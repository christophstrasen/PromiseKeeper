local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")

local MOD_ID = "MyMod"
local pk = PromiseKeeper.namespace(MOD_ID)
pk.situations.searchIn(WorldObserver)
local situations = WorldObserver.situations.namespace(MOD_ID)

-- Define the WorldObserver situation once (typically at load time).
-- PromiseKeeper does not hide this step: WO remains the source of truth for situation definitions.
situations.define("nearSquares", function()
	return WorldObserver.observations:squares()
end)

pk.actions.define("markSquare", function(subject, args, promiseCtx)
	print(
		("[PK] %s mark square tag=%s"):format(
			tostring(promiseCtx.occurranceKey),
			tostring(args.tag)
		)
	)
end)

pk.promise({
	promiseId = "markNearSquares",
	situationKey = "nearSquares",
	situationArgs = nil,
	actionId = "markSquare",
	actionArgs = { tag = "seen" },
	policy = { maxRuns = 1, chance = 1 },
})

pk.remember()
