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
	local situationKey = "onTickPlayer"
	local actionId = "logPlayerTick"
	local promiseId = "logPlayerTickOnce"

	-- WHY: PZ's built-in Events.* don't carry a stable occurranceKey for idempotence,
	-- so we shape the event into `{ occurranceKey, subject }` ourselves.
	pk.situations.defineFromPZEvent(situationKey, Events.OnTick, function(args)
		local player = getPlayer()
		if not player then
			return nil
		end
		return {
			occurranceKey = tostring(args.keyPrefix or "player:")
				.. tostring(player:getPlayerNum() or 0),
			subject = player,
		}
	end)

	pk.actions.define(actionId, function(subject, args, promiseCtx)
		print(
			("[PK] tick subject=%s note=%s occurranceKey=%s"):format(
				tostring(subject),
				tostring(args.note),
				tostring(promiseCtx.occurranceKey)
			)
		)
	end)

	local promise = pk.promise({
		promiseId = promiseId,
		situationKey = situationKey,
		situationArgs = { keyPrefix = "player:" },
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
