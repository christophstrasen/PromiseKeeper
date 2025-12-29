-- adapters/worldobserver.lua -- helpers for WorldObserver situation streams.
local U = require("PromiseKeeper/util")

local LOG_TAG = "[PromiseKeeper WOAdapter]"

local moduleName = ...
local WOAdapter = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		WOAdapter = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = WOAdapter
	end
end

local function logInfo(msg)
	U.log(LOG_TAG, msg)
end

local function resolveFactInterest(opts)
	if opts and opts.factInterest then
		return opts.factInterest
	end
	local ok, wo = pcall(require, "WorldObserver")
	if ok and type(wo) == "table" then
		return wo.factInterest
	end
	return nil
end

local function declareInterest(spec, opts)
	if type(spec) ~= "table" then
		return nil
	end
	local factInterest = resolveFactInterest(opts)
	if type(factInterest) ~= "table" or type(factInterest.declare) ~= "function" then
		logInfo("interest requested but WorldObserver.factInterest missing")
		return nil
	end
	local modId = spec.modId
	local key = spec.key
	local interestSpec = spec.spec
	local interestOpts = spec.opts
	local ok, err = pcall(factInterest.declare, factInterest, modId, key, interestSpec, interestOpts)
	if not ok then
		error("interest_failed:" .. tostring(err))
	end
	return function()
		if type(factInterest.revoke) == "function" then
			pcall(factInterest.revoke, factInterest, modId, key)
		end
	end
end

local function withInterest(stream, interestSpec, opts)
	return {
		subscribe = function(_, onNext)
			-- Declare interest *only* when someone actually subscribes to the situation stream.
			-- WHY: interest leases drive WorldObserver probing/listeners. We don't want PromiseKeeper
			-- to enable upstream work globally just because a promise definition exists on disk.
			-- Tying it to subscribe/unsubscribe keeps resource usage proportional to active promises.
			local release = declareInterest(interestSpec, opts)
			local subscription = stream:subscribe(onNext)
			return {
				unsubscribe = function()
					if subscription and type(subscription.unsubscribe) == "function" then
						subscription:unsubscribe()
					elseif type(subscription) == "table" and type(subscription.dispose) == "function" then
						subscription:dispose()
					end
					if release then
						release()
					end
				end,
			}
		end,
	}
end

local function buildFactory(situations, situationKey, mapSituationToCandidate, opts)
	return function(args)
		local base = situations.get(situationKey, args)
		assert(
			type(base) == "table" and type(base.asRx) == "function",
			"WorldObserver situation stream missing :asRx()"
		)
		-- We deliberately use WorldObserver's Rx bridge here (asRx + map) instead of re-implementing
		-- mapping in PromiseKeeper core.
		-- WHY: the adapter is where we can assume the WO + Rx dependency set, keeping the v2 core
		-- usable with plain PZ events and LuaEvent sources without pulling in reactive plumbing.
		local stream = base:asRx():map(mapSituationToCandidate)
		if opts and opts.interest then
			return withInterest(stream, opts.interest, opts)
		end
		return stream
	end
end

if WOAdapter.mapFrom == nil then
	--- Return a mapper for a WorldObserver situation namespace.
	---@param situations table
	---@return function
	function WOAdapter.mapFrom(situations)
		return function(situationKey, mapSituationToCandidate, opts)
			return buildFactory(situations, situationKey, mapSituationToCandidate, opts)
		end
	end
end

return WOAdapter
