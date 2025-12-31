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
		reload("PromiseKeeper/registries/actions")
		reload("PromiseKeeper/registries/situations")
		reload("PromiseKeeper/core/store")
		reload("PromiseKeeper/core/router")
		reload("PromiseKeeper/debug/status")
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

		pk.situations.define("stream", function()
			return stream
		end)

		pk.promise("p1", "stream", nil, "act", { note = "ok" }, { maxRuns = 1, chance = 1 })

		stream:emit({ occurranceKey = "o1", subject = "square" })
		stream:emit({ occurranceKey = "o1", subject = "square" })

		assert.equals(1, #received)
		assert.equals("square", received[1].subject)
		assert.equals("ok", received[1].note)
		assert.equals("p1", received[1].promiseId)
	end)

	it("accepts a spec table and returns a promise handle", function()
		local pk = PromiseKeeper.namespace("tests")
		local stream = makeStream()

		pk.actions.define("act", function() end)
		pk.situations.define("stream", function()
			return stream
		end)

		local promise = pk.promise({
			promiseId = "p2",
			situationKey = "stream",
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
		assert.is_table(pk.situations)

		assert.is_table(promise.status())

		promise.stop()
		assert.is_nil(stream.handler)

		stream:emit({ occurranceKey = "o1", subject = "square" })
		promise.forget()
		assert.equals(0, promise.status().totalRuns)
	end)

	it("defines situations from PZ events", function()
		local pk = PromiseKeeper.namespace("tests")
		local event = { handlers = {} }
		function event.Add(fn)
			event.handlers[fn] = true
		end
		function event.Remove(fn)
			event.handlers[fn] = nil
		end
		function event.fire(payload)
			for fn in pairs(event.handlers) do
				fn(payload)
			end
		end

		local received = {}
		pk.actions.define("act", function(_subject, _args, promiseCtx)
			received[#received + 1] = promiseCtx.occurranceKey
		end)

		pk.situations.defineFromPZEvent("tick", event, function(args, payload)
			return { occurranceKey = tostring(args.keyPrefix or "") .. tostring(payload), subject = payload }
		end)

		pk.promise("p1", "tick", { keyPrefix = "k:" }, "act", {}, { maxRuns = 1, chance = 1 })
		event.fire("hello")

		assert.equals(1, #received)
		assert.equals("k:hello", received[1])
	end)

	it("defines situations from LuaEvent sources", function()
		local pk = PromiseKeeper.namespace("tests")
		local event = { listeners = {} }
		function event:addListener(fn)
			self.listeners[fn] = true
			return fn
		end
		function event:removeListener(fn)
			self.listeners[fn] = nil
		end
		function event:emit(payload)
			for fn in pairs(self.listeners) do
				fn(payload)
			end
		end

		local received = {}
		pk.actions.define("act", function(_subject, _args, promiseCtx)
			received[#received + 1] = promiseCtx.occurranceKey
		end)

		pk.situations.defineFromLuaEvent("evt", event, function(args, payload)
			return { occurranceKey = tostring(args.keyPrefix or "") .. tostring(payload), subject = payload }
		end)

		pk.promise("p2", "evt", { keyPrefix = "k:" }, "act", {}, { maxRuns = 1, chance = 1 })
		event:emit("hello")

		assert.equals(1, #received)
		assert.equals("k:hello", received[1])
	end)

	it("resolves WorldObserver situations via searchIn when not defined in PK", function()
		local pk = PromiseKeeper.namespace("tests")
		local stream = makeStream()
		local registry = {
			situations = {
				namespace = function()
					return {
						get = function(key)
							if key == "wo" then
								return stream
							end
							return nil
						end,
					}
				end,
			},
		}

		pk.situations.searchIn(registry)
		local received = {}
		pk.actions.define("act", function(_subject, _args, promiseCtx)
			received[#received + 1] = promiseCtx.occurranceKey
		end)

		pk.promise("p3", "wo", nil, "act", {}, { maxRuns = 1, chance = 1 })
		stream:emit({ WoMeta = { occurranceKey = "k1" }, value = "obs" })

		assert.equals(1, #received)
		assert.equals("k1", received[1])
	end)
end)
