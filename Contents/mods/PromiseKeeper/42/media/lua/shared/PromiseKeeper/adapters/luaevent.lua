-- adapters/luaevent.lua -- situationStream builder for Starlit LuaEvent sources.
local Events = require("DREAMBase/events")

local moduleName = ...
local LuaEventAdapter = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		LuaEventAdapter = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = LuaEventAdapter
	end
end

if LuaEventAdapter.fromEvent == nil then
	--- Build a situationStream from a LuaEvent source (addListener/removeListener).
	---@param eventSource table
	---@param mapEventToCandidate function
	function LuaEventAdapter.fromEvent(eventSource, mapEventToCandidate)
		return Events.fromLuaEvent(eventSource, mapEventToCandidate)
	end
end

return LuaEventAdapter
