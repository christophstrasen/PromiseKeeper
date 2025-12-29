--[[
PZ console:
smoke = require("examples/smoke_pk_pz_events")
handle = smoke.start()
handle.stop()
]]

local Smoke = {}

function Smoke.start()
	local PromiseKeeper = require("PromiseKeeper")
	local namespace = "PKSmokePZ"
	local pk = PromiseKeeper.namespace(namespace)
	local situationId = "onTickPlayer"
	local actionId = "logPlayerTick"
	local promiseId = "logPlayerTickOnce"

	pk.situationMaps.define(situationId, function()
		-- WHY: PZ's built-in Events.* don't carry a stable "occurrence id" for idempotence,
		-- so we shape the event into `{ occurrenceId, subject }` ourselves.
		return pk.factories.fromPZEvent(Events.OnTick, function()
			return {
				occurrenceId = "player:" .. tostring(getPlayer():getPlayerNum()),
				subject = getPlayer(),
			}
		end)
	end)

	pk.actions.define(actionId, function(subject, args, promiseCtx)
		print(
			("[PK] tick subject=%s note=%s occurrenceId=%s"):format(
				tostring(subject),
				tostring(args.note),
				tostring(promiseCtx.occurrenceId)
			)
		)
	end)

	local promise = pk.promise({
		promiseId = promiseId,
		situationMapId = situationId,
		situationArgs = nil, -- Events are rarely if ever parameterized.
		actionId = actionId,
		actionArgs = { note = "once" },
		policy = { maxRuns = 1, chance = 1 },
	})

	return {
		stop = function()
			-- Stop + forget to keep smoke testing iterative (no persisted state surprise).
			promise.forget()
		end,
		promise = promise,
	}
end

return Smoke
