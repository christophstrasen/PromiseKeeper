local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")
local WOAdapter = require("PromiseKeeper/adapters/worldobserver")

local MOD_ID = "MyMod"
local pk = PromiseKeeper.namespace(MOD_ID)
local situations = WorldObserver.situations.namespace(MOD_ID)

-- Define the WorldObserver situation once (typically at load time).
situations.define("nearSquares", function(_args)
	return WorldObserver.observations:squares()
end)

pk.defineAction("markSquare", function(subject, args, promiseCtx)
	print(("[PK] %s mark square tag=%s"):format(tostring(promiseCtx.occurrenceId), tostring(args.tag)))
end)

local opts = {
	interest = {
		modId = MOD_ID,
		key = "nearSquares",
		spec = { type = "squares", scope = "near" },
	},
}

WOAdapter.defineSituationFactory(pk, situations, "nearSquares", "nearSquares", function(observation)
	local square = observation.square
	return {
		occurrenceId = square.squareId,
		subject = square.IsoGridSquare,
	}
end, opts)

pk.promise("markNearSquares", "nearSquares", nil, "markSquare", { tag = "seen" }, { maxRuns = 1, chance = 1 })

pk.remember()
