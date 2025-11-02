-- requests_store.lua — ModData persistence, normalization, idempotence, indexes
-- v1 scope: no fulfiller execution here; just data + helpers.
-- Conventions: no colons in logs; use U.assertf for contract checks; serialize-safe only.

local U = require("PromiseKeeper/util")
local LOG_TAG = "[PromiseKeeper requests_store]"
local log = U.makeLogger(LOG_TAG)

local M = {}

-- ======== Types (EmmyLua) ========

---@class PKStoredEntry
---@field id               string
---@field fulfiller        string
---@field tag?             string
---@field createdAtDays    number
---@field cleanAfterDays   number
---@field status           '"Requested"'|'"Evaluating"'|'"Fulfilled"'
---@field maxFulfillments  number
---@field fulfillments     number
---@field target           PKRequestTarget

---@class PKStoredIdBucket
---@field id string
---@field entries table<string, PKStoredEntry>  -- fulfillmentKey -> entry
---@field delivered string[]                    -- list of fulfillmentKeys (append-only view)

---@class PKRequestsRoot
---@field byId table<string, PKStoredIdBucket>
---@field byTarget table<string, true>         -- quick dup guard

-- ======== Module locals ========

local ROOT_KEY = "PromiseKeeper"
local REQ_KEY = "requests"

local md ---@type table
local requestsRoot ---@type PKRequestsRoot
-- Module-wide config + deps set by loadOrInit
local CURRENT_CONFIG = { cleanAfterDays = 30, maxFulfillments = 1 } ---@type {cleanAfterDays:number, maxFulfillments:number}

-- ======== Utilities ========

---@return number worldDays
local function worldDays()
	-- Build 42: GameTime:getInstance():getWorldAgeHours() is available → normalize to days
	local gt = GameTime and GameTime:getInstance() or nil
	if gt and gt.getWorldAgeHours then
		return gt:getWorldAgeHours() / 24
	end
	log("Warning world age not available; cleanup scheduling may be off")
	return 0
end

--- Turn author-provided target (roomDef or IsoSquare) into a stable key.
--- Uses native method presence instead of separate helpers.
---@param target any
---@return PKRequestTarget normTarget, string targetKey
local function normalizeTarget(target)
	U.assertf(target ~= nil, "target required")

	-- roomDef: has getID/getName
	if type(target) == "table" and target.getID and target.getName then
		local id = target:getID()
		U.assertf(type(id) == "number", "roomDef:getID must return number")
		local key = tostring(id) -- idempotence key
		return { type = "roomDef", key = key, roomId = id }, key
	end

	-- IsoSquare: has getID/getX (getX just to sanity-check it's a square)
	if type(target) == "table" and target.getID and target.getX then
		local id = target:getID()
		U.assertf(type(id) == "number", "IsoSquare:getID must return number")
		local key = tostring(id) -- idempotence key
		return { type = "IsoSquare", key = key, squareId = id }, key
	end

	U.assertf(false, "unsupported target type; expected roomDef or IsoSquare")
	-- unreachable, but keeps Lua happy
	return { type = "IsoSquare", key = "0", squareId = 0 }, "0"
end

---@param id string
---@param targetKey string
---@return string
local function fulfillmentKey(id, targetKey)
	return tostring(id) .. "|" .. tostring(targetKey)
end

---@param target PKRequestTarget|nil
---@return table
local function cloneStoredTarget(target)
	if type(target) ~= "table" then
		return {}
	end
	return {
		type = target.type,
		key = target.key,
		squareId = target.squareId,
		roomId = target.roomId,
	}
end

-- ======== Public init ========

---@param config table
function M.loadOrInit(config)
	-- snapshot config so inner functions don't need it as a param
	if type(config) == "table" then
		if type(config.cleanAfterDays) == "number" then
			CURRENT_CONFIG.cleanAfterDays = config.cleanAfterDays
		end
		if type(config.maxFulfillments) == "number" then
			CURRENT_CONFIG.maxFulfillments = config.maxFulfillments
		end
	end

	local all = ModData.getOrCreate(ROOT_KEY)
	md = all

	if type(md[REQ_KEY]) ~= "table" then
		md[REQ_KEY] = {}
	end

	local root = md[REQ_KEY]
	root.byId = root.byId or {}
	root.byTarget = root.byTarget or {}

	requestsRoot = root
	log("store ready")
end

-- ======== Idempotence / read-side ========

--- Returns true only when this fulfillmentKey has not yet reached its maxFulfillments.
--- Pure read: no side effects. The store stays passive.
--- key format: "<id>|<targetKey>" e.g. "intro-lab|room:12345"
---@param key string
---@return boolean
function M.isEligible(key)
	if not key or key == "" then
		return false
	end
	local sep = key:find("|", 1, true)
	if not sep then
		return true
	end

	local id = key:sub(1, sep - 1)
	local bucket = requestsRoot.byId[id]
	if not bucket then
		return true
	end

	local entry = bucket.entries and bucket.entries[key] or nil
	if not entry then
		return true -- first time seeing this key
	end
	return entry.fulfillments < entry.maxFulfillments
end

---@param key string  -- fulfillmentKey
function M.markFulfilled(key)
	if not key or key == "" then
		return
	end
	local sep = key:find("|", 1, true)
	if not sep then
		return
	end
	local id = key:sub(1, sep - 1)

	local bucket = requestsRoot.byId[id]
	if not bucket or not bucket.entries then
		return
	end

	local entry = bucket.entries[key]
	if not entry then
		return
	end

	entry.fulfillments = (entry.fulfillments or 0) + 1
	if entry.fulfillments >= entry.maxFulfillments then
		entry.status = "Fulfilled"
	end

	bucket.delivered[#bucket.delivered + 1] = key
end

-- Expose for other modules (diagnostics / composition)
M.fulfillmentKey = fulfillmentKey
M.normalizeTarget = normalizeTarget

-- ======== Persistence entry points (internal intent) ========

---- Upsert a concrete single-target request into ModData (no evaluation, no side effects beyond persistence).
--- Responsibilities:
---   1) Normalize author target (roomDef / IsoSquare → {type,key})
---   2) Compute stable fulfillmentKey = "<id>|<targetKey>"
---   3) Create or merge a serialize-safe entry:
---        - keep earliest createdAtDays
---        - raise maxFulfillments if caller provided a higher cap
---   4) Never persist functions or refs (ModData must stay serializable)
---@param req table  -- PKRequest from public API
local function upsertAtRequest(req)
	U.assertf(type(req) == "table", "ensureAt requires table")
	U.assertf(type(req.id) == "string" and req.id ~= "", "ensureAt requires id")
	U.assertf(type(req.fulfiller) == "string" and req.fulfiller ~= "", "ensureAt requires fulfiller")
	U.assertf(req.target ~= nil, "ensureAt requires target (roomDef or IsoSquare)")

	local normTarget, tKey = normalizeTarget(req.target)
	local fKey = fulfillmentKey(req.id, tKey)

	local bucket = requestsRoot.byId[req.id]
	if not bucket then
		bucket = { id = req.id, entries = {}, delivered = {} }
		requestsRoot.byId[req.id] = bucket
	end

	local now = worldDays()
	local cleanAfterDays = tonumber(req.cleanAfterDays) or CURRENT_CONFIG.cleanAfterDays
	local maxFulfillments = tonumber(req.maxFulfillments) or CURRENT_CONFIG.maxFulfillments

	local existing = bucket.entries[fKey]
	if existing then
		if (existing.createdAtDays or now) > now then
			existing.createdAtDays = now
		end
		if maxFulfillments > (existing.maxFulfillments or 1) then
			existing.maxFulfillments = maxFulfillments
		end
		if U and U.log then
			U.log(LOG_TAG, "ensureAt merge id " .. req.id .. " key " .. fKey)
		end
	else
		bucket.entries[fKey] = {
			id = req.id,
			fulfiller = req.fulfiller,
			tag = req.tag,
			createdAtDays = now,
			cleanAfterDays = cleanAfterDays,
			status = "Requested",
			maxFulfillments = maxFulfillments,
			fulfillments = 0,
			target = normTarget,
		}
		requestsRoot.byTarget[fKey] = true
		if U and U.log then
			U.log(LOG_TAG, "ensureAt queued id " .. req.id .. " key " .. fKey)
		end
	end
end

--- Upsert a matcher definition record under the id (functions are NOT persisted).
--- Purpose:
---   - Make the matcher visible in ModData/status tools
---   - Centralize metadata for the id, without storing any function
---@param req table  -- PKRequest from public API (matchFn omitted)
local function upsertMatcherRecord(req)
	U.assertf(type(req) == "table", "ensureMatcher requires table")
	U.assertf(type(req.id) == "string" and req.id ~= "", "ensureMatcher requires id")
	U.assertf(type(req.fulfiller) == "string" and req.fulfiller ~= "", "ensureMatcher requires fulfiller")

	local bucket = requestsRoot.byId[req.id]
	if not bucket then
		bucket = { id = req.id, entries = {}, delivered = {} }
		requestsRoot.byId[req.id] = bucket
	end

	local markerKey = fulfillmentKey(req.id, "matcher:square")
	if not bucket.entries[markerKey] then
		bucket.entries[markerKey] = {
			id = req.id,
			fulfiller = req.fulfiller,
			tag = req.tag,
			createdAtDays = worldDays(),
			cleanAfterDays = tonumber(req.cleanAfterDays) or CURRENT_CONFIG.cleanAfterDays,
			status = "Requested",
			maxFulfillments = tonumber(req.maxFulfillments) or CURRENT_CONFIG.maxFulfillments,
			fulfillments = 0,
			target = { type = "IsoSquare", key = "matcher:square" }, -- placeholder key, schema-stable
		}
	end
	if U and U.log then
		U.log(LOG_TAG, "ensureMatcher queued id " .. req.id)
	end
end

-- Expose for other modules (diagnostics / composition)
M.upsertAtRequest = upsertAtRequest
M.upsertMatcherRecord = upsertMatcherRecord

-- ======== Read side ========

---@param id string
---@return table|nil
function M.getStatus(id)
	local bucket = requestsRoot.byId[id]
	if not bucket then
		return nil
	end

	-- Return a serialize-safe shallow copy without internal tables being exposed by reference.
	local out = { id = bucket.id, entries = {}, delivered = {} }
	for k, v in pairs(bucket.entries) do
		out.entries[k] = {
			id = v.id,
			fulfiller = v.fulfiller,
			tag = v.tag,
			createdAtDays = v.createdAtDays,
			cleanAfterDays = v.cleanAfterDays,
			status = v.status,
			maxFulfillments = v.maxFulfillments,
			fulfillments = v.fulfillments,
			target = cloneStoredTarget(v.target),
		}
	end
	for i = 1, #bucket.delivered do
		out.delivered[i] = bucket.delivered[i]
	end
	return out
end

---@param id string
---@return string[]
function M.listDelivered(id)
	local bucket = requestsRoot.byId[id]
	if not bucket then
		return {}
	end
	-- Return a copy
	local out = {}
	for i = 1, #bucket.delivered do
		out[i] = bucket.delivered[i]
	end
	return out
end

---@return string[]
function M.listAllIds()
	local out = {}
	local byId = requestsRoot and requestsRoot.byId
	if not byId then
		return out
	end
	for id, _ in pairs(byId) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

-- ======= Iterators ======

--- Call `visitor(fulfillmentKey, entry)` for each entry with status "Requested".
---@param visitor fun(key:string, entry:PKStoredEntry)
function M.eachRequested(visitor)
	if type(visitor) ~= "function" then
		return
	end
	local byId = requestsRoot and requestsRoot.byId
	if not byId then
		return
	end
	for _, bucket in pairs(byId) do
		local entries = bucket.entries
		if entries then
			for fKey, e in pairs(entries) do
				if e.status == "Requested" then
					visitor(fKey, e)
				end
			end
		end
	end
end

---@param limit number|nil  -- max entries to copy per id (nil/<=0 for all)
---@return table
function M.debugDump(limit)
	local clamp = tonumber(limit)
	if clamp and clamp > 0 then
		clamp = math.floor(clamp)
	else
		clamp = nil
	end

	local summary = { totalIds = 0, pending = 0, delivered = 0 }
	local dump = { summary = summary, ids = {} }

	local byId = requestsRoot and requestsRoot.byId
	if not byId then
		return dump
	end

	for id, bucket in pairs(byId) do
		local info = {
			id = id,
			pending = 0,
			entries = {},
			delivered = {},
		}

		local added = 0
		for fKey, entry in pairs(bucket.entries or {}) do
			if entry.status == "Requested" then
				info.pending = info.pending + 1
				summary.pending = summary.pending + 1
			end
			if not clamp or added < clamp then
				info.entries[#info.entries + 1] = {
					key = fKey,
					status = entry.status,
					fulfillments = entry.fulfillments,
					maxFulfillments = entry.maxFulfillments,
					createdAtDays = entry.createdAtDays,
					cleanAfterDays = entry.cleanAfterDays,
					tag = entry.tag,
					target = cloneStoredTarget(entry.target),
				}
				added = added + 1
			end
		end

		if #info.entries > 1 then
			table.sort(info.entries, function(a, b)
				return tostring(a.key or "") < tostring(b.key or "")
			end)
		end

		local delivered = bucket.delivered or {}
		for i = 1, #delivered do
			info.delivered[i] = delivered[i]
		end
		summary.delivered = summary.delivered + #info.delivered

		dump.ids[#dump.ids + 1] = info
	end

	table.sort(dump.ids, function(a, b)
		return tostring(a.id or "") < tostring(b.id or "")
	end)
	summary.totalIds = #dump.ids
	return dump
end

return M
