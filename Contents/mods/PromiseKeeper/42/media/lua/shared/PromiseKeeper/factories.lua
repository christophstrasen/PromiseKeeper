-- factories.lua -- small situationStream helpers.
local U = require("PromiseKeeper/util")
local PZEvents = require("PromiseKeeper/adapters/pz_events")
local LuaEventAdapter = require("PromiseKeeper/adapters/luaevent")

local moduleName = ...
local Factories = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Factories = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Factories
	end
end

if Factories.fromPZEvent == nil then
	--- Build a situationStream from a PZ event source (Add/Remove).
	---@param eventSource table
	---@param mapEventToCandidate function
	function Factories.fromPZEvent(eventSource, mapEventToCandidate)
		return PZEvents.fromEvent(eventSource, mapEventToCandidate)
	end
end

if Factories.fromLuaEvent == nil then
	--- Build a situationStream from a LuaEvent source (addListener/removeListener).
	---@param eventSource table
	---@param mapEventToCandidate function
	function Factories.fromLuaEvent(eventSource, mapEventToCandidate)
		return LuaEventAdapter.fromEvent(eventSource, mapEventToCandidate)
	end
end

if Factories.fromEvent == nil then
	--- Build a situationStream from a generic event source (auto-detect).
	---@param eventSource table
	---@param mapEventToCandidate function
	function Factories.fromEvent(eventSource, mapEventToCandidate)
		if type(eventSource) == "table" and type(eventSource.Add) == "function" then
			return Factories.fromPZEvent(eventSource, mapEventToCandidate)
		end
		if type(eventSource) == "table" and type(eventSource.addListener) == "function" then
			return Factories.fromLuaEvent(eventSource, mapEventToCandidate)
		end
		error("event source missing Add/Remove or addListener/removeListener", 2)
	end
end

if Factories.isCandidate == nil then
	--- Check whether a value looks like a PromiseKeeper candidate.
	---@param value any
	---@return boolean
	function Factories.isCandidate(value)
		return type(value) == "table" and value.occurranceKey ~= nil and value.subject ~= nil
	end
end

if Factories.candidateOr == nil then
	--- Wrap a mapper to accept already-shaped candidates as pass-through.
	---@param mapEventToCandidate function
	---@return function
	function Factories.candidateOr(mapEventToCandidate)
		U.assertf(type(mapEventToCandidate) == "function", "mapEventToCandidate must be a function")
		return function(...)
			local first = select(1, ...)
			if Factories.isCandidate(first) then
				return first
			end
			return mapEventToCandidate(...)
		end
	end
end

if Factories.makeCandidate == nil then
	--- Build a mapper that returns `{ occurranceKey = ..., subject = ... }`.
	---@param occurranceKeyFn function
	---@param subjectFn function|nil Defaults to the first event argument.
	---@return function
	function Factories.makeCandidate(occurranceKeyFn, subjectFn)
		U.assertf(type(occurranceKeyFn) == "function", "occurranceKeyFn must be a function")
		if subjectFn == nil then
			subjectFn = function(...)
				return select(1, ...)
			end
		end
		U.assertf(type(subjectFn) == "function", "subjectFn must be a function or nil")
		return function(...)
			return {
				occurranceKey = occurranceKeyFn(...),
				subject = subjectFn(...),
			}
		end
	end
end

return Factories
