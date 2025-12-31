-- adapters/pz_events.lua -- situationStream builder for PZ native Events.* sources.
local U = require("PromiseKeeper/util")

local moduleName = ...
local PZEvents = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		PZEvents = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = PZEvents
	end
end

local function assertEvent(eventSource)
	U.assertf(type(eventSource) == "table", "eventSource must be a table")
	U.assertf(type(eventSource.Add) == "function", "eventSource.Add must be a function")
	U.assertf(type(eventSource.Remove) == "function", "eventSource.Remove must be a function")
end

if PZEvents.fromEvent == nil then
	--- Build a situationStream from a PZ event source (Add/Remove).
	---@param eventSource table
	---@param mapEventToCandidate function
	function PZEvents.fromEvent(eventSource, mapEventToCandidate)
		-- Prefer DREAMBase when available (workspace/in-game); fall back to local implementation
		-- so PromiseKeeper stays fully standalone for CI/tests.
		local okBase, BaseEvents = pcall(require, "DREAMBase/events")
		if okBase and type(BaseEvents) == "table" and type(BaseEvents.fromPZEvent) == "function" then
			return BaseEvents.fromPZEvent(eventSource, mapEventToCandidate)
		end

		assertEvent(eventSource)
		return {
			subscribe = function(_, onNext)
				local handler = function(...)
					if not onNext then
						return
					end
					local candidate = mapEventToCandidate(...)
					if candidate ~= nil then
						onNext(candidate)
					end
				end

				local ok = pcall(eventSource.Add, handler)
				if not ok then
					ok = pcall(eventSource.Add, eventSource, handler)
				end
				if not ok then
					error("pz_event_subscribe_failed", 2)
				end

				return {
					unsubscribe = function()
						local okRemove = pcall(eventSource.Remove, handler)
						if not okRemove then
							pcall(eventSource.Remove, eventSource, handler)
						end
					end,
				}
			end,
		}
	end
end

return PZEvents
