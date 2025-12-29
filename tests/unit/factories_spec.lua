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

describe("PromiseKeeper factories", function()
	local Factories

	before_each(function()
		Factories = reload("PromiseKeeper/factories")
	end)

	it("builds {occurranceKey, subject} mappers via makeCandidate", function()
		local map = Factories.makeCandidate(function(payload)
			return "id:" .. tostring(payload)
		end)
		local candidate = map("hello")
		assert.equals("id:hello", candidate.occurranceKey)
		assert.equals("hello", candidate.subject)
	end)

	it("passes through already-shaped candidates via candidateOr", function()
		local called = 0
		local map = Factories.candidateOr(function(payload)
			called = called + 1
			return { occurranceKey = "id:" .. tostring(payload), subject = payload }
		end)

		local pass = { occurranceKey = "o1", subject = "square" }
		assert.equals(pass, map(pass))
		assert.equals(0, called)

		local out = map("x")
		assert.equals("id:x", out.occurranceKey)
		assert.equals(1, called)
	end)
end)
