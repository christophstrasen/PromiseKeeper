-- adapters/luaevent.lua -- situationStream builder for Starlit LuaEvent sources.
local U = require("PromiseKeeper/util")

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

local function assertEvent(eventSource)
	U.assertf(type(eventSource) == "table", "eventSource must be a table")
	U.assertf(type(eventSource.addListener) == "function", "eventSource.addListener must be a function")
	U.assertf(type(eventSource.removeListener) == "function", "eventSource.removeListener must be a function")
end

local function subscribe(eventSource, handler)
	local ok, token = pcall(eventSource.addListener, eventSource, handler)
	if not ok then
		ok, token = pcall(eventSource.addListener, handler)
	end
	if not ok then
		return nil
	end
	return function()
		local removeArg = token ~= nil and token or handler
		local okRemove = pcall(eventSource.removeListener, eventSource, removeArg)
		if not okRemove then
			pcall(eventSource.removeListener, removeArg)
		end
	end
end

if LuaEventAdapter.fromEvent == nil then
	--- Build a situationStream from a LuaEvent source (addListener/removeListener).
	---@param eventSource table
	---@param mapEventToCandidate function
	function LuaEventAdapter.fromEvent(eventSource, mapEventToCandidate)
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
				local unsubscribe = subscribe(eventSource, handler)
				if not unsubscribe then
					error("luaevent_subscribe_failed", 2)
				end
				return {
					unsubscribe = function()
						unsubscribe()
					end,
				}
			end,
		}
	end
end

return LuaEventAdapter
