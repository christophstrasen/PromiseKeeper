package.path = table.concat({
	"Contents/mods/PromiseKeeper/42/media/lua/shared/?.lua",
	"Contents/mods/PromiseKeeper/42/media/lua/shared/?/init.lua",
	package.path,
}, ";")

_G.getDebug = function()
	return false
end

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("PromiseKeeper policies", function()
	local Chance
	local RunCount

	before_each(function()
		Chance = reload("PromiseKeeper/policies/chance")
		RunCount = reload("PromiseKeeper/policies/run_count")
	end)

	it("applies deterministic chance", function()
		local ok = Chance.shouldRun("ns", "p1", "occ", { chance = 1 })
		assert.is_true(ok)

		local ok2 = Chance.shouldRun("ns", "p1", "occ", { chance = 0 })
		assert.is_false(ok2)
	end)

	it("honors maxRuns", function()
		local ok = RunCount.shouldRun({ totalRuns = 0 }, { maxRuns = 1 })
		assert.is_true(ok)

		local ok2 = RunCount.shouldRun({ totalRuns = 1 }, { maxRuns = 1 })
		assert.is_false(ok2)
	end)
end)
