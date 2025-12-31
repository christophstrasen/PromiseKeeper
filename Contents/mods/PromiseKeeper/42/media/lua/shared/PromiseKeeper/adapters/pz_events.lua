-- adapters/pz_events.lua -- situationStream builder for PZ native Events.* sources.
local Events = require("DREAMBase/events")

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

if PZEvents.fromEvent == nil then
	--- Build a situationStream from a PZ event source (Add/Remove).
	---@param eventSource table
	---@param mapEventToCandidate function
	function PZEvents.fromEvent(eventSource, mapEventToCandidate)
		return Events.fromPZEvent(eventSource, mapEventToCandidate)
	end
end

return PZEvents
