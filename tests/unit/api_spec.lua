package.path = table.concat({
	"Contents/mods/PromiseKeeper/42/media/lua/shared/?.lua",
	"Contents/mods/PromiseKeeper/42/media/lua/shared/?/init.lua",
	package.path,
}, ";")

_G.getDebug = function()
	return false
end

local function resetModData()
	local data = {}
	_G.ModData = {
		getOrCreate = function(key)
			if data[key] == nil then
				data[key] = {}
			end
			return data[key]
		end,
	}
end

local function resetEvents()
	_G.Events = {
		OnTick = {
			Add = function() end,
			Remove = function() end,
		},
	}
end

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

local function makeStream()
	local stream = { handler = nil }
	function stream:subscribe(onNext)
		self.handler = onNext
		return {
			unsubscribe = function()
				stream.handler = nil
			end,
		}
	end
	function stream:emit(candidate)
		if self.handler then
			self.handler(candidate)
		end
	end
	return stream
end

describe("PromiseKeeper API", function()
	local PromiseKeeper

	before_each(function()
		resetModData()
		resetEvents()
		PromiseKeeper = reload("PromiseKeeper")
	end)

	it("runs an action for a situation candidate", function()
		local pk = PromiseKeeper.namespace("tests")
		local stream = makeStream()
		local received = {}

		pk.defineAction("act", function(subject, args, promiseCtx)
			received[#received + 1] = {
				subject = subject,
				note = args.note,
				promiseId = promiseCtx.promiseId,
			}
		end)

		pk.defineSituationFactory("stream", function()
			return stream
		end)

		pk.promise("p1", "stream", nil, "act", { note = "ok" }, { maxRuns = 1, chance = 1 })

		stream:emit({ occurrenceId = "o1", subject = "square" })
		stream:emit({ occurrenceId = "o1", subject = "square" })

		assert.equals(1, #received)
		assert.equals("square", received[1].subject)
		assert.equals("ok", received[1].note)
		assert.equals("p1", received[1].promiseId)
	end)
end)
