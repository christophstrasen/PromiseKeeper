-- core/pacemaker.lua -- OnTick retry scheduler.
local U = require("PromiseKeeper/util")
local Time = require("PromiseKeeper/time")
local Router = require("PromiseKeeper/core/router")

local LOG_TAG = "[PromiseKeeper pacemaker]"

local moduleName = ...
local Pacemaker = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Pacemaker = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Pacemaker
	end
end

Pacemaker._internal = Pacemaker._internal or {
	started = false,
	unsubscribe = nil,
}

local function logInfo(msg)
	U.log(LOG_TAG, msg)
end

if Pacemaker.tick == nil then
	function Pacemaker.tick()
		local nowMs = Time.gameMillis()
		Router.processRetries(nowMs)
	end
end

if Pacemaker.start == nil then
	function Pacemaker.start()
		local state = Pacemaker._internal
		if state.started then
			return
		end
		if _G.Events == nil or _G.Events.OnTick == nil then
			logInfo("OnTick not available; pacemaker inactive")
			return
		end
		local handler = function()
			Pacemaker.tick()
		end
		local unsubscribe = U.subscribeEvent(_G.Events.OnTick, handler)
		if unsubscribe then
			state.started = true
			state.unsubscribe = unsubscribe
		end
	end
end

if Pacemaker.stop == nil then
	function Pacemaker.stop()
		local state = Pacemaker._internal
		if state.unsubscribe then
			pcall(state.unsubscribe)
		end
		state.started = false
		state.unsubscribe = nil
	end
end

return Pacemaker
