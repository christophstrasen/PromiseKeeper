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

	local namespace = "PKSmokeWO"
	local pk = PromiseKeeper.namespace(namespace)
	local wo = {
		situations = WorldObserver.situations.namespace(namespace),
	}
	local mapWO = pk.adapters.worldobserver.mapFrom(wo.situations)

	-- Define the WorldObserver situation explicitly (no hiding/wrapping).
	-- WHY: WO is the source of truth for situations; PromiseKeeper only maps WO emissions into actionable candidates.
	wo.situations.define("corpseSquares", function()
		return WorldObserver.observations:squares():squareHasCorpse()
	end)

	local opts = {
		interest = {
			modId = namespace,
			key = "corpseSquares",
			spec = { type = "squares", scope = "near", radius = 3, staleness = 3, highlight = true },
		},
	}

	pk.situationMaps.define("corpseSquares", mapWO(
		"corpseSquares",
		function(observation)
			local square = observation.square
			return {
				occurrenceId = square.squareId,
				subject = square.IsoGridSquare,
			}
		end,
		opts
	))

	pk.actions.define("markSquare", function(subject, args, promiseCtx)
		print(
			("[PK] square observed occurrenceId=%s tag=%s subject=%s"):format(
				tostring(promiseCtx.occurrenceId),
				tostring(args.tag),
				tostring(subject)
			)
		)
	end)

	local promise = pk.promise({
		promiseId = "markCorpseSquares",
		situationFactoryId = "corpseSquares",
		situationArgs = nil,
		actionId = "markSquare",
		actionArgs = { tag = "seen" },
		policy = { maxRuns = 1, chance = 1 },
	})

	return {
		stop = function()
			promise.forget()
		end,
		promise = promise,
	}
end

return Smoke
