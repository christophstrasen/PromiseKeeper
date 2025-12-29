local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")

local MOD_ID = "MyMod"
local pk = PromiseKeeper.namespace(MOD_ID)
local wo = {
	situations = WorldObserver.situations.namespace(MOD_ID),
}
local mapWO = pk.adapters.worldobserver.mapFrom(wo.situations)

-- Define the WorldObserver situation once (typically at load time).
-- PromiseKeeper does not hide this step: WO remains the source of truth for situation definitions.
wo.situations.define("nearSquares", function()
	return WorldObserver.observations:squares()
end)

pk.actions.define("markSquare", function(subject, args, promiseCtx)
	print(("[PK] %s mark square tag=%s"):format(tostring(promiseCtx.occurrenceId), tostring(args.tag)))
end)

local opts = {
	interest = {
		modId = MOD_ID,
		key = "nearSquares",
		spec = { type = "squares", scope = "near" },
	},
}

pk.situationMaps.define("nearSquares", mapWO(
	"nearSquares",
	function(observation)
		local square = observation.square
		return {
			occurrenceId = square.squareId,
			subject = square.IsoGridSquare,
		}
	end,
	opts
))

pk.promise({
	promiseId = "markNearSquares",
	situationMapId = "nearSquares",
	situationArgs = nil,
	actionId = "markSquare",
	actionArgs = { tag = "seen" },
	policy = { maxRuns = 1, chance = 1 },
})

pk.remember()
