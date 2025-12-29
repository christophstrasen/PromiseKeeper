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

		pk.actions.define("act", function(subject, args, promiseCtx)
			received[#received + 1] = {
				subject = subject,
				note = args.note,
				promiseId = promiseCtx.promiseId,
			}
		end)

		pk.situationMaps.define("stream", function()
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

	it("accepts a spec table and returns a promise handle", function()
		local pk = PromiseKeeper.namespace("tests")
		local stream = makeStream()

		pk.actions.define("act", function() end)
		pk.situationMaps.define("stream", function()
			return stream
		end)

		local promise = pk.promise({
			promiseId = "p2",
			situationMapId = "stream",
			actionId = "act",
			actionArgs = {},
			policy = { maxRuns = 1, chance = 1 },
		})

		assert.equals("tests", promise.namespace)
		assert.equals("p2", promise.promiseId)
		assert.is_true(promise.started)
		assert.is_function(promise.stop)
		assert.is_function(promise.forget)
		assert.is_function(promise.status)
		assert.is_function(promise.whyNot)

		assert.is_table(pk.factories)
		assert.is_table(pk.adapters)
		assert.is_table(pk.actions)
		assert.is_table(pk.situationMaps)

		assert.is_table(promise.status())

		promise.stop()
		assert.is_nil(stream.handler)

		stream:emit({ occurrenceId = "o1", subject = "square" })
		promise.forget()
		assert.equals(0, promise.status().totalRuns)
	end)
end)
