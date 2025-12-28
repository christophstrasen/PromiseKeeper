--[[
PZ console:
smoke = require("examples/smoke_pk_worldobserver")
handle = smoke.start()
handle.stop()
]]

local Smoke = {}

function Smoke.start()
	local PromiseKeeper = require("PromiseKeeper")
	local WorldObserver = require("WorldObserver")
	local WOAdapter = require("PromiseKeeper/adapters/worldobserver")

	local modId = "PKSmokeWO"
	local promiseId = "markNearSquares"
	local pk = PromiseKeeper.namespace(modId)
	local situations = WorldObserver.situations.namespace(modId)

	situations.define("nearSquares", function(_args)
		return WorldObserver.observations:squares()
	end)

	pk.defineAction("markSquare", function(subject, args, promiseCtx)
		print(("[PK] square observed occurrenceId=%s tag=%s subject=%s"):format(
			tostring(promiseCtx.occurrenceId),
			tostring(args.tag),
			tostring(subject)
		))
	end)

	local opts = {
		interest = {
			modId = modId,
			key = "nearSquares",
			spec = { type = "squares", scope = "near", radius = 3, staleness = 3, highlight = true },
		},
	}

	WOAdapter.defineSituationFactory(pk, situations, "nearSquares", "nearSquares", function(observation)
		local square = observation.square
		return {
			occurrenceId = square.squareId,
			subject = square.IsoGridSquare,
		}
	end, opts)

	pk.promise(promiseId, "nearSquares", nil, "markSquare", { tag = "seen" }, { maxRuns = 1, chance = 1 })

	return {
		stop = function()
			pk.forget(promiseId)
		end,
	}
end

return Smoke
