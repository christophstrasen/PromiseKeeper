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

describe("PromiseKeeper adapters", function()
	local PZEvents
	local LuaEventAdapter
	local WOAdapter

	before_each(function()
		PZEvents = reload("PromiseKeeper/adapters/pz_events")
		LuaEventAdapter = reload("PromiseKeeper/adapters/luaevent")
		WOAdapter = reload("PromiseKeeper/adapters/worldobserver")
	end)

	it("subscribes to PZ events via Add/Remove", function()
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
		local stream = PZEvents.fromEvent(event, function(payload)
			return { occurrenceId = payload, subject = payload }
		end)

		local sub = stream:subscribe(function(candidate)
			received[#received + 1] = candidate.subject
		end)

		event.fire("hello")
		assert.equals(1, #received)
		assert.equals("hello", received[1])

		sub:unsubscribe()
		event.fire("again")
		assert.equals(1, #received)
	end)

	it("subscribes to LuaEvent via addListener/removeListener", function()
		local event = { listeners = {} }
		function event:addListener(fn)
			local token = {}
			self.listeners[token] = fn
			return token
		end
		function event:removeListener(token)
			if type(token) ~= "table" then
				error("token required")
			end
			self.listeners[token] = nil
		end
		function event:emit(payload)
			for _, fn in pairs(self.listeners) do
				fn(payload)
			end
		end

		local received = {}
		local stream = LuaEventAdapter.fromEvent(event, function(payload)
			return { occurrenceId = payload, subject = payload }
		end)

		local sub = stream:subscribe(function(candidate)
			received[#received + 1] = candidate.subject
		end)

		event:emit("hello")
		assert.equals(1, #received)
		assert.equals("hello", received[1])

		sub:unsubscribe()
		event:emit("again")
		assert.equals(1, #received)
	end)

	it("defines a PK situation factory backed by a WO situation", function()
		local base = { handler = nil }
		function base:subscribe(onNext)
			self.handler = onNext
			return {
				unsubscribe = function()
					base.handler = nil
				end,
			}
		end
		function base:emit(value)
			if self.handler then
				self.handler(value)
			end
		end
		function base:asRx()
			local rx = {}
			function rx:map(mapFn)
				return {
					subscribe = function(_, onNext)
						return base:subscribe(function(item)
							onNext(mapFn(item))
						end)
					end,
				}
			end
			return rx
		end

		local pk = { factories = {}, situationMaps = {} }
		function pk.situationMaps.define(id, factoryFn)
			pk.factories[id] = factoryFn
		end

		local situations = { defs = {} }
		function situations.define(id, fn)
			situations.defs[id] = fn
		end
		function situations.get(id, args)
			return situations.defs[id](args)
		end

		situations.define("s1", function()
			return base
		end)

		local factoryFn = WOAdapter.mapFrom(situations)("s1", function(obs)
			return { occurrenceId = obs.id, subject = obs.subject }
		end)
		pk.situationMaps.define("f1", factoryFn)

		local stream = pk.factories.f1({})
		local received = {}
		local sub = stream:subscribe(function(candidate)
			received[#received + 1] = candidate.subject
		end)

		base:emit({ id = "o1", subject = "square" })
		assert.equals(1, #received)
		assert.equals("square", received[1])

		sub:unsubscribe()
	end)
end)
