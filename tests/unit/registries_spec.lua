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

describe("PromiseKeeper registries", function()
	local Actions
	local Situations

	before_each(function()
		Actions = reload("PromiseKeeper/registries/actions")
		Situations = reload("PromiseKeeper/registries/situations")
	end)

	it("stores and lists actions per namespace", function()
		Actions.define("ns", "a1", function() end)
		Actions.define("ns", "a2", function() end)

		local list = Actions.list("ns")
		assert.equals(2, #list)
		assert.is_true(Actions.has("ns", "a1"))
		assert.is_false(Actions.has("ns", "missing"))
	end)

	it("stores situation factories per namespace", function()
		Situations.define("ns", "s1", function() end)
		assert.is_true(Situations.has("ns", "s1"))
		assert.is_nil(Situations.get("ns", "missing"))
	end)
end)
