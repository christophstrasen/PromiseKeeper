--[[
PZ console:
smoke = require("examples/smoke_pk_worldobserver")
handle = smoke.start()
handle.stop()
]]

local Smoke = {}

local INTEREST_NEAR = {
	type = "squares",
	scope = "near",
	staleness = { desired = 3, tolerable = 6 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = true,
}

local LEASE_OPTS = {
	ttlSeconds = 60 * 60, -- smoke tests can run longer than the default 10 minutes
}

function Smoke.start()
	local PromiseKeeper = require("PromiseKeeper")
	local WorldObserver = require("WorldObserver")

	-- One-off explicit interest for squares so WO has something to observe.
	local interest = WorldObserver.factInterest:declare(
		"examples/smoke_pk_worldobserver",
		"near",
		INTEREST_NEAR,
		LEASE_OPTS
	)

	local namespace = "PKSmokeWO"
	-- PromiseKeeper state is namespaced so multiple mods can use it without collisions.
	local pk = PromiseKeeper.namespace(namespace)
	-- Convention: use the same namespace for WorldObserver situations and PromiseKeeper promises.
	local situations = WorldObserver.situations.namespace(namespace)
	-- One-time bridge: PromiseKeeper can search WorldObserver situations by situationKey.
	pk.situations.searchIn(WorldObserver)

	-- WHY: WO is the source of truth for situations; Here we define one in-situ
	situations.define("corpseSquares", function()
		-- This returns a WorldObserver squares observation stream, filtered to squares where `square.hasCorpse == true`.
		return WorldObserver.observations:squares():squareHasCorpse()
	end)

	-- Define the action (side effect). It is looked up by `actionId` at runtime (resumable promises).
	pk.actions.define("markSquare", function(subject, args, promiseCtx)
		local square = subject.square
		print(
			("[PK] square observed occurranceKey=%s tag=%s subject=%s"):format(
				tostring(promiseCtx.occurranceKey),
				tostring(args.tag),
				tostring(square and square.IsoGridSquare or subject)
			)
		)
	end)

	local promise = pk.promise({
		-- This creates a durable promise: “when the situation stream emits candidates, run my action”.
		promiseId = "markCorpseSquares",
		situationKey = "corpseSquares",
		situationArgs = nil,
		actionId = "markSquare",
		actionArgs = { tag = "seen" },
		-- `maxRuns` is counted per promiseId (not per occurranceKey). With 1, the smoke will act once and then stop.
		policy = { maxRuns = 1, chance = 1 },
	})

	return {
		stop = function()
			-- Stop + forget to keep smoke testing iterative (no persisted state surprise).
			promise.forget()
			if interest and interest.stop then
				pcall(function()
					interest:stop()
				end)
			end
		end,
		promise = promise,
	}
end

return Smoke
