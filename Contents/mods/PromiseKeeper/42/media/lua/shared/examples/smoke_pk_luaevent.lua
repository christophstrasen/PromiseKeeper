--[[
PZ console:
smoke = require("examples/smoke_pk_luaevent")
handle = smoke.start()
handle.fire("hello")
handle.stop()
]]

local Smoke = {}

function Smoke.start()
	local PromiseKeeper = require("PromiseKeeper")
	local LuaEvent = require("Starlit/LuaEvent")
	local event = LuaEvent.new()

	local namespace = "PKSmokeLuaEvent"
	local pk = PromiseKeeper.namespace(namespace)
	local situationId = "luaEventStream"
	local actionId = "logEvent"
	local promiseId = "logLuaEventOnce"

	pk.situationMaps.define(situationId, function()
		-- WHY: Starlit LuaEvent is an event emitter; PromiseKeeper wants a stable id + subject.
		-- Here we treat the payload itself as the subject, and use `tostring(payload)` as a stable id.
		-- It could be any better id extracted from the event too.
		return pk.factories.fromLuaEvent(event, function(payload)
			return {
				occurrenceId = tostring(payload or "none"),
				subject = payload,
			}
		end)
	end)

	pk.actions.define(actionId, function(subject, args, promiseCtx)
		print(
			("[PK] luaevent subject=%s note=%s occurrenceId=%s"):format(
				tostring(subject),
				tostring(args.note),
				tostring(promiseCtx.occurrenceId)
			)
		)
	end)

	local promise = pk.promise({
		promiseId = promiseId,
		situationFactoryId = situationId,
		situationArgs = nil,
		actionId = actionId,
		actionArgs = { note = "hello" },
		policy = { maxRuns = 1, chance = 1 },
	})

	return {
		fire = function(payload)
			return event:trigger(payload)
		end,
		stop = function()
			promise.forget()
		end,
		promise = promise,
	}
end

return Smoke
