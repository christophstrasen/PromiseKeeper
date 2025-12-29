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
	-- PromiseKeeper state is namespaced so multiple mods can use it without collisions.
	local pk = PromiseKeeper.namespace(namespace)
	local wo = {
		-- Convention: use the same namespace for WorldObserver situations and PromiseKeeper promises.
		situations = WorldObserver.situations.namespace(namespace),
	}
	-- `mapWO` builds PromiseKeeper situation maps from existing WorldObserver situations.
	local mapWO = pk.adapters.worldobserver.mapFrom(wo.situations)

	-- WHY: WO is the source of truth for situations; Here we define one in-situ
	wo.situations.define("corpseSquares", function()
		-- This returns a WorldObserver squares observation stream, filtered to squares where `square.hasCorpse == true`.
		return WorldObserver.observations:squares():squareHasCorpse()
	end)

	local opts = {
		interest = {
			-- Interest is optional: it tells WorldObserver what to pay attention to upstream.
			modId = namespace,
			key = "corpseSquares",
			spec = { type = "squares", scope = "near", radius = 3, staleness = 3, highlight = true },
		},
	}

	local situationMapId = "corpseSquares"
	-- Map a WO observation into a PromiseKeeper situation candidate.
	-- PromiseKeeper only *requires*:
	-- - `occurrenceId`: stable id for idempotence (“did we already act on this?” stable across reloads)
	-- - `subject`: the live, safe-to-mutate world object handed to the action
	local mapCorpseSquares = mapWO(situationMapId, function(observation)
		local square = observation.square
		return {
			occurrenceId = square.squareId,
			subject = square.IsoGridSquare,
		}
	end, opts)

	-- Register the situation map under a stable id so PromiseKeeper can resume after reload.
	pk.situationMaps.define(situationMapId, mapCorpseSquares)

	-- Define the action (side effect). It is looked up by `actionId` at runtime (resumable promises).
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
		-- This creates a durable promise: “when the situation stream emits candidates, run my action”.
		promiseId = "markCorpseSquares",
		situationMapId = situationMapId,
		situationArgs = nil,
		actionId = "markSquare",
		actionArgs = { tag = "seen" },
		-- `maxRuns` is counted per promiseId (not per occurrenceId). With 1, the smoke will act once and then stop.
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
