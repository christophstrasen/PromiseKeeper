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

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("PromiseKeeper store", function()
	local Store

	before_each(function()
		resetModData()
		Store = reload("PromiseKeeper/core/store")
	end)

	it("persists definitions and progress", function()
		Store.upsertDefinition("ns", "promiseA", {
			actionId = "actionA",
			situationKey = "factoryA",
			actionArgs = { note = "hello" },
		})

		local entry = Store.getPromise("ns", "promiseA")
		assert.equals("actionA", entry.definition.actionId)
		assert.equals("factoryA", entry.definition.situationKey)

		Store.markDone("ns", "promiseA", "occ1")
		local progress = Store.getPromise("ns", "promiseA").progress
		assert.equals(1, progress.totalRuns)
		assert.equals("done", progress.occurrences["occ1"].state)
	end)

	it("tracks retry attempts", function()
		Store.upsertDefinition("ns", "promiseB", {
			actionId = "actionB",
			situationKey = "factoryB",
		})
		Store.markAttemptFailed("ns", "promiseB", "occ9", 1000, "boom")
		local occ = Store.getOccurrence("ns", "promiseB", "occ9", false)
		assert.equals(1, occ.retryCounter)
		assert.equals(1000, occ.nextRetryAtMs)
		assert.equals("boom", occ.lastError)
	end)

	it("drops legacy situationMapId definitions", function()
		local root = _G.ModData.getOrCreate("PromiseKeeper")
		root.namespaces = {
			ns = {
				promises = {
					legacy = {
						definition = { situationMapId = "old", actionId = "act" },
						progress = {},
					},
				},
			},
		}

		local entry = Store.getPromise("ns", "legacy")
		assert.is_nil(entry.definition.situationMapId)
	end)
end)
