-- PromiseKeeper.lua — Public API for deferred spawning (v1, square-first)
-- Conventions: no colons in logs; EmmyLua on public functions; Build 42 require paths.

local Config = require("PromiseKeeper/config")
local Registry = require("PromiseKeeper/registry")
local Store = require("PromiseKeeper/requests_store")
local SquareWires = require("PromiseKeeper/square_events")
require("PromiseKeeper/types") -- load type annotations for IDEs

local U = require("PromiseKeeper/util")
local LOG_TAG = "[PromiseKeeper Main]"
local log = U.makeLogger(LOG_TAG)

local PromiseKeeper = {}

--- Live, writable config (authors may tweak after require)
PromiseKeeper.config = {
	cleanAfterDays = Config.cleanAfterDays or 30,
	maxFulfillments = Config.maxFulfillments or 1,
}

-- One-time start guard (square wiring & initial sweep)
local started = false
local function startOnce()
	if started then
		return
	end
	started = true
	Store.loadOrInit(PromiseKeeper.config)
	SquareWires.start({
		store = Store,
		registry = Registry,
		config = PromiseKeeper.config,
		U = U,
		LOG_TAG = LOG_TAG,
	})
	log("initialized")
end

--- Register a named fulfiller (builder function).
---@param name string
---@param fn   fun(ctx: table)  -- ctx: { request, target, meta }
---@param tag? string
function PromiseKeeper.registerFulfiller(name, fn, tag)
	U.assertf(type(name) == "string" and name ~= "", "registerFulfiller name required")
	U.assertf(type(fn) == "function", "registerFulfiller fn must be function")
	local replaced = Registry.put(name, fn, tag)
	if replaced then
		U.log(LOG_TAG, "registerFulfiller overwrite " .. name)
	end
	startOnce()
end

--- Ensure a specific target will be fulfilled once its square is ready.
---@param req PKRequest
function PromiseKeeper.ensureAt(req)
	U.assertf(type(req) == "table", "ensureAt requires a request table")
	U.assertf(type(req.id) == "string" and req.id ~= "", "ensureAt requires id")
	U.assertf(type(req.fulfiller) == "string" and req.fulfiller ~= "", "ensureAt requires fulfiller")
	U.assertf(Registry.get(req.fulfiller) ~= nil, "ensureAt fulfiller not registered " .. tostring(req.fulfiller))

	startOnce() -- ✅ init storage/wiring before writing
	Store.upsertAtRequest(req)
end

--- Ensure matching targets evaluated on every loaded square.
--- The matcher is kept in memory only; it MUST return stable keys for idempotence.
---@param req PKRequest
function PromiseKeeper.ensureMatchingForSquare(req)
	U.assertf(type(req) == "table", "ensureMatchingForSquare requires a request table")
	U.assertf(type(req.id) == "string" and req.id ~= "", "ensureMatchingForSquare requires id")
	U.assertf(type(req.fulfiller) == "string" and req.fulfiller ~= "", "ensureMatchingForSquare requires fulfiller")
	U.assertf(
		Registry.get(req.fulfiller) ~= nil,
		"ensureMatchingForSquare fulfiller not registered " .. tostring(req.fulfiller)
	)
	U.assertf(type(req.matchFn) == "function", "ensureMatchingForSquare requires matchFn(squareCtx, matchParams)")

	req.mode = "square"

	startOnce() -- ✅ ensure events are live
	Store.upsertMatcherRecord(req) -- persist status marker
	SquareWires.attachSquareMatcher(req)
end

--- Optional: read-side status helpers (debug)
---@param id string
---@return table|nil
function PromiseKeeper.getStatus(id)
	return Store.getStatus(id)
end

---@param id string
---@return string[]  -- fulfillmentKeys
function PromiseKeeper.listDelivered(id)
	return Store.listDelivered(id)
end

---@return string[]
function PromiseKeeper.listAllIds()
	return Store.listAllIds()
end

---@param limit number|nil
---@return table
function PromiseKeeper.debugDump(limit)
	return Store.debugDump(limit)
end

return PromiseKeeper
