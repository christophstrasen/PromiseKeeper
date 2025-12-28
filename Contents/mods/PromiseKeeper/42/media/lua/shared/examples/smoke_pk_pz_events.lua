--[[
PZ console:
smoke = require("examples/smoke_pk_pz_events")
handle = smoke.start()
handle.stop()
]]

local Smoke = {}

function Smoke.start()
	local PromiseKeeper = require("PromiseKeeper")

	local modId = "PKSmokePZ"
	local promiseId = "logPlayerTickOnce"
	local pk = PromiseKeeper.namespace(modId)

	pk.defineAction("logPlayerTick", function(subject, args, promiseCtx)
		print(
			("[PK] tick subject=%s note=%s occurrenceId=%s"):format(
				tostring(subject),
				tostring(args.note),
				tostring(promiseCtx.occurrenceId)
			)
		)
	end)

	pk.defineSituationFactory("onTickPlayer", function()
		return PromiseKeeper.factories.fromPZEvent(Events.OnTick, function()
			local player = getPlayer()
			if not player then
				return nil
			end
			local id = nil
			if player.getOnlineID then
				id = player:getOnlineID()
			elseif player.getPlayerNum then
				id = player:getPlayerNum()
			end
			return {
				occurrenceId = "player:" .. tostring(id or 0),
				subject = player,
			}
		end)
	end)

	pk.promise(promiseId, "onTickPlayer", nil, "logPlayerTick", { note = "once" }, { maxRuns = 1, chance = 1 })

	return {
		stop = function()
			pk.forget(promiseId)
		end,
	}
end

return Smoke
