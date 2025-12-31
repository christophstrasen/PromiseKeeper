-- adapters/worldobserver.lua -- helpers for WorldObserver situation streams.
local U = require("DREAMBase/util")

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

local function toCandidate(observation)
	local woMeta = type(observation) == "table" and observation.WoMeta or nil
	local key = woMeta and (woMeta.occurranceKey or woMeta.key) or nil
	return {
		occurranceKey = key,
		subject = observation,
	}
end

if WOAdapter.isWorldObserver == nil then
	---@param registry table
	---@return boolean
	function WOAdapter.isWorldObserver(registry)
		return type(registry) == "table"
			and type(registry.situations) == "table"
			and type(registry.situations.namespace) == "function"
	end
end

if WOAdapter.wrapSituationStream == nil then
	--- Wrap a WorldObserver situation stream as PromiseKeeper candidates.
	---@param stream table
	---@return table
	function WOAdapter.wrapSituationStream(stream)
		U.assertf(type(stream) == "table", "situation stream must be a table")
		if type(stream.asRx) == "function" then
			local rx = stream:asRx():map(toCandidate)
			return {
				subscribe = function(_, onNext)
					return rx:subscribe(onNext)
				end,
			}
		end
		if type(stream.subscribe) == "function" then
			return {
				subscribe = function(_, onNext)
					return stream:subscribe(function(observation)
						if onNext then
							onNext(toCandidate(observation))
						end
					end)
				end,
			}
		end
		error("worldobserver_stream_missing_subscribe", 2)
	end
end

return WOAdapter
