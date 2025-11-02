-- square_events.lua — square-first evaluation (Build 42)
-- Listens to Events.LoadGridsquare; fulfills "at" requests and runs square matchers once per square.
-- Context: shared. No colons in logs.

local U = require("PromiseKeeper/util")
local LOG_TAG = "[PromiseKeeper square_events]"
local log = U.makeLogger(LOG_TAG)

local M = {}

-- Injected dependencies from PromiseKeeper.lua:
-- deps = { store, registry, config, U, LOG_TAG }
local deps
local running = false

-- Process each loaded square at most once per session.
local seenSquares = {} -- [squareId:number] = true
---@type table<string, { id:string, fulfiller:string, tag:string|nil, matchFn:fun(squareCtx:PKSquareCtx, matchParams:any):(PKTargetSquare|PKTargetRoom)[], matchParams:any }>
local squareMatchers = {} -- id -> { id, fulfiller, tag, matchFn, matchParams }
local erroredFulfillments = {} -- fulfillmentKey -> true

-- ---------- helpers ----------

--- Build the lightweight context for a loaded square.
--- Guarantees that `sq` is a valid IsoGridSquare with basic methods available.
---@param sq IsoGridSquare
---@return PKSquareCtx
local function buildSquareCtx(sq)
	U.assertf(sq and sq.getX and sq.getY and sq.getZ, "squareCtx requires a valid IsoGridSquare")
	local x, y, z = sq:getX(), sq:getY(), sq:getZ()

	-- Prefer chunk coords from the engine if available; fallback to math division.
	local cx, cy = nil, nil
	--- @todo research e.g. https://projectzomboid.com/modding/zombie/iso/IsoChunk.html if we can load chunk coords
	if cx == nil or cy == nil then -- If chunk API is unavailable, fall back to deriving cx,cy from coords (10x10 tiles in PZ).
		cx, cy = math.floor(x / 10), math.floor(y / 10)
	end

	local room = sq.getRoom and sq:getRoom() or nil
	local roomDef = (room and room.getRoomDef) and room:getRoomDef() or nil
	local roomId = (roomDef and roomDef.getID) and roomDef:getID() or nil

	return {
		sq = sq,
		x = x,
		y = y,
		z = z,
		cx = cx,
		cy = cy, -- exposed if authors want chunk info
		roomDef = roomDef,
		roomId = roomId,
	}
end

--- Call a fulfiller with a consistent context.
--- `request` is informational (not a live store record).
---@param fulfillerName string
---@param id string
---@param tag string|nil
---@param targetRef IsoGridSquare|RoomDef
---@param fulfillmentKey string|nil
---@return boolean ok
local function callFulfiller(fulfillerName, id, tag, targetRef, fulfillmentKey)
	local fn = deps.registry.get(fulfillerName)
	if not fn or not targetRef then
		return false
	end
	local ctx = {
		request = { id = id, fulfiller = fulfillerName, tag = tag },
		target = targetRef,
		meta = { id = id, fulfiller = fulfillerName, tag = tag },
	}

	-- call in a robust fashion but handle errors
	local ok, err = pcall(fn, ctx)
	if ok then
		return true
	end

	local key = fulfillmentKey or (id .. "|fallback")
	if not erroredFulfillments[key] then --throw once
		erroredFulfillments[key] = true
		U.logCtx(LOG_TAG, "fulfiller error", { id = id, fulfiller = fulfillerName, key = key, err = err })
		if getDebug() then
			error("Fulfiller error while in debug mode enforces strict assert. See log")
		end
	end
	return false
end

-- ---------- core handler ----------

local function onSquareLoaded(sq)
	if not sq then
		return
	end

	local x, y, z = sq:getX(), sq:getY(), sq:getZ()
	-- Gate: run at most once per exact square this session.
	local sqId = sq:getID()
	if seenSquares[sqId] then
		return
	end
	seenSquares[sqId] = true

	local sctx = buildSquareCtx(sq)
	local deliveredCount = 0

	-- 1) ensureAt path — deliver when this exact square or its room appears.
	-- Iterate requested entries via the store
	deps.store.eachRequested(function(fKey, entry)
		local t = entry.target
		if t.type == "IsoSquare" then
			-- Fast path: compare square IDs
			if t.squareId and t.squareId == sq:getID() and deps.store.isEligible(fKey) then
				if callFulfiller(entry.fulfiller, entry.id, entry.tag, sq, fKey) then
					deps.store.markFulfilled(fKey)
					deliveredCount = deliveredCount + 1
				end
			end
		elseif t.type == "roomDef" and sctx.roomId then
			-- Fast path: compare room IDs
			if t.roomId and t.roomId == sctx.roomId and deps.store.isEligible(fKey) then
				if callFulfiller(entry.fulfiller, entry.id, entry.tag, sctx.roomDef, fKey) then
					deps.store.markFulfilled(fKey)
					deliveredCount = deliveredCount + 1
				end
			end
		end
	end)

	if deliveredCount > 0 then
		U.logCtx(LOG_TAG, "delivered via ensureAt", { x = x, y = y, z = z, count = deliveredCount })
	end

	-- 2) square matchers — run once per square
	local matchedCount = 0
	-- Outer loop: each registered matcher runs once for this square.
	for _, rec in pairs(squareMatchers) do
		local results = rec.matchFn(sctx, rec.matchParams) or {}
		-- Inner loop: each returned target (must provide a stable key) is considered once.
		for i = 1, #results do
			local t = results[i]
			if t and t.key and t.type then
				-- Ensure numeric IDs are present to avoid any string parsing on the hot path.
				if t.type == "IsoSquare" then
					if (not t.squareId) and t.ref and t.ref.getID then
						t.squareId = t.ref:getID()
					end
				elseif t.type == "roomDef" then
					if (not t.roomId) and t.ref and t.ref.getID then
						t.roomId = t.ref:getID()
					end
				end
				local fKey = deps.store.fulfillmentKey(rec.id, t.key)
				if deps.store.isEligible(fKey) then
					local ref = t.ref
					if not ref then
						-- Resolve by ID only (no strings, no coords)
						if t.type == "IsoSquare" and t.squareId then
							-- We only resolve the *current* square cheaply; for foreign squares, ask matchers to pass ref.
							if t.squareId == sctx.sq:getID() then
								ref = sctx.sq
							end
						elseif t.type == "roomDef" and t.roomId then
							if sctx.roomId and t.roomId == sctx.roomId then
								ref = sctx.roomDef
							end
						end
					end

					if ref and callFulfiller(rec.fulfiller, rec.id, rec.tag, ref, fKey) then
						deps.store.markFulfilled(fKey)
						matchedCount = matchedCount + 1
					end
				end
			end
		end
	end

	if matchedCount > 0 then
		U.logCtx(LOG_TAG, "matched via square matchers", { x = x, y = y, z = z, count = matchedCount })
	end
end

-- ---------- subscriptions ----------

-- We subscribe to the engine's "square loaded" event because it's present across B42 builds.
-- This keeps v1 simple, deterministic, and avoids chunk API variability.
local subscribed = false
local function subscribe()
	if subscribed then
		return
	end
	if Events and Events.LoadGridsquare and Events.LoadGridsquare.Add then
		Events.LoadGridsquare.Add(onSquareLoaded)
		subscribed = true
		log("subscribed Events.LoadGridsquare")
	elseif Events and Events.OnLoadGridsquare and Events.OnLoadGridsquare.Add then
		-- Some builds expose this name instead; handle both.
		Events.OnLoadGridsquare.Add(onSquareLoaded)
		subscribed = true
		log("subscribed Events.OnLoadGridsquare")
	else
		log("warning no square-load event found")
	end
end

-- ---------- public API ----------

function M.start(d)
	if running then
		return
	end
	deps = d or {}
	running = true
	subscribe()
	log("square events started")
end

---@param req PKRequest  -- persisted marker already added by Store
function M.attachSquareMatcher(req)
	if not req or type(req.id) ~= "string" or type(req.matchFn) ~= "function" then
		log("attachSquareMatcher ignored (invalid req)")
		return
	end
	squareMatchers[req.id] = {
		id = req.id,
		fulfiller = req.fulfiller,
		tag = req.tag,
		matchFn = req.matchFn,
		matchParams = req.matchParams,
	}
	U.logCtx(LOG_TAG, "square matcher attached", { id = req.id })
end

return M
