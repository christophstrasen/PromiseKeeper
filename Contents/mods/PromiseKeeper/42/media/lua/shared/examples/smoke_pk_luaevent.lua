--[[
PZ console:
smoke = require("examples/smoke_pk_luaevent")
handle = smoke.start()
handle.fire("hello")
handle.stop()
]]

local Smoke = {}

local function fireEvent(event, payload)
	if type(event.trigger) == "function" then
		return event:trigger(payload)
	end
	if type(event.fire) == "function" then
		return event:fire(payload)
	end
	if type(event.emit) == "function" then
		return event:emit(payload)
	end
	if type(event.dispatch) == "function" then
		return event:dispatch(payload)
	end
	if type(event.invoke) == "function" then
		return event:invoke(payload)
	end
	print("[PK] LuaEvent fire method not found; manual trigger required")
end

function Smoke.start()
	local PromiseKeeper = require("PromiseKeeper")

	local okEvent, LuaEvent = pcall(require, "Starlit/LuaEvent")
	if not okEvent then
		print("[PK] Starlit LuaEvent not available; skipping smoke")
		return {
			stop = function() end,
			fire = function() end,
		}
	end

	local event = nil
	if type(LuaEvent) == "table" and type(LuaEvent.new) == "function" then
		event = LuaEvent.new()
	elseif type(LuaEvent) == "function" then
		event = LuaEvent()
	elseif type(LuaEvent) == "table" and type(LuaEvent.create) == "function" then
		event = LuaEvent.create()
	end

	if not event then
		print("[PK] LuaEvent constructor not found; skipping smoke")
		return {
			stop = function() end,
			fire = function() end,
		}
	end

	local modId = "PKSmokeLuaEvent"
	local promiseId = "logLuaEventOnce"
	local pk = PromiseKeeper.namespace(modId)

	pk.defineAction("logEvent", function(subject, args, promiseCtx)
		print(("[PK] luaevent subject=%s note=%s occurrenceId=%s"):format(
			tostring(subject),
			tostring(args.note),
			tostring(promiseCtx.occurrenceId)
		))
	end)

	pk.defineSituationFactory("luaEventStream", function()
		return PromiseKeeper.factories.fromLuaEvent(event, function(payload)
			return {
				occurrenceId = tostring(payload or "none"),
				subject = payload,
			}
		end)
	end)

	pk.promise(promiseId, "luaEventStream", nil, "logEvent", { note = "hello" }, { maxRuns = 1, chance = 1 })

	return {
		fire = function(payload)
			return fireEvent(event, payload)
		end,
		stop = function()
			pk.forget(promiseId)
		end,
	}
end

return Smoke
