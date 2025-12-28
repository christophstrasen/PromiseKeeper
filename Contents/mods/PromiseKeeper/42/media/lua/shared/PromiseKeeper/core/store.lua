-- core/store.lua -- ModData persistence for PromiseKeeper v2.
local U = require("PromiseKeeper/util")
local Time = require("PromiseKeeper/time")
local LOG_TAG = "[PromiseKeeper store]"

local moduleName = ...
local Store = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Store = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Store
	end
end

Store._internal = Store._internal or {}

local ROOT_KEY = "PromiseKeeperV2"
local root

local function nowMs()
	return Time.gameMillis()
end

local function ensureRoot()
	if root ~= nil then
		return root
	end
	-- In Project Zomboid, `ModData` is the persistence layer for shared save data.
	-- In busted/headless runs we don't have it, so we fall back to an in-memory table.
	-- WHY: PromiseKeeper's logic and tests should still run outside the engine without requiring
	-- a full ModData stub everywhere.
	if _G.ModData and _G.ModData.getOrCreate then
		root = _G.ModData.getOrCreate(ROOT_KEY)
	else
		root = {}
	end
	root.version = root.version or 2
	root.namespaces = root.namespaces or {}
	return root
end

local function ensureNamespace(namespace)
	U.assertf(type(namespace) == "string" and namespace ~= "", "namespace must be a non-empty string")
	local r = ensureRoot()
	local bucket = r.namespaces[namespace]
	if bucket == nil then
		bucket = { promises = {} }
		r.namespaces[namespace] = bucket
	end
	bucket.promises = bucket.promises or {}
	return bucket
end

local function ensurePromise(namespace, promiseId)
	U.assertf(type(promiseId) == "string" and promiseId ~= "", "promiseId must be a non-empty string")
	local bucket = ensureNamespace(namespace)
	local entry = bucket.promises[promiseId]
	if entry == nil then
		entry = { definition = {}, progress = {} }
		bucket.promises[promiseId] = entry
	end
	entry.definition = entry.definition or {}
	entry.progress = entry.progress or {}
	if entry.progress.status == nil then
		entry.progress.status = "active"
	end
	if entry.progress.occurrences == nil then
		entry.progress.occurrences = {}
	end
	if entry.progress.totalRuns == nil then
		entry.progress.totalRuns = 0
	end
	if entry.progress.cooldownUntilMs == nil then
		entry.progress.cooldownUntilMs = 0
	end
	if entry.progress.createdAtMs == nil then
		entry.progress.createdAtMs = nowMs() or 0
	end
	return entry
end

if Store.upsertDefinition == nil then
	function Store.upsertDefinition(namespace, promiseId, definition)
		local entry = ensurePromise(namespace, promiseId)
		entry.definition = U.shallowCopy(definition or {})
		entry.definition.promiseId = promiseId
		return entry
	end
end

if Store.getPromise == nil then
	function Store.getPromise(namespace, promiseId)
		local bucket = ensureNamespace(namespace)
		return bucket.promises[promiseId]
	end
end

if Store.listPromises == nil then
	function Store.listPromises(namespace)
		local bucket = ensureNamespace(namespace)
		local out = {}
		for promiseId, entry in pairs(bucket.promises or {}) do
			out[#out + 1] = {
				promiseId = promiseId,
				definition = U.shallowCopy(entry.definition or {}),
				progress = U.shallowCopy(entry.progress or {}),
			}
		end
		return out
	end
end

if Store.listNamespaces == nil then
	function Store.listNamespaces()
		local r = ensureRoot()
		local out = {}
		for ns in pairs(r.namespaces or {}) do
			out[#out + 1] = ns
		end
		table.sort(out)
		return out
	end
end

if Store.forgetPromise == nil then
	function Store.forgetPromise(namespace, promiseId)
		local bucket = ensureNamespace(namespace)
		bucket.promises[promiseId] = nil
	end
end

if Store.forgetAll == nil then
	function Store.forgetAll(namespace)
		local bucket = ensureNamespace(namespace)
		bucket.promises = {}
	end
end

if Store.markBroken == nil then
	function Store.markBroken(namespace, promiseId, reasonCode, message)
		local entry = ensurePromise(namespace, promiseId)
		entry.progress.status = "broken"
		entry.progress.brokenReason = { code = reasonCode, message = message }
	end
end

if Store.clearBroken == nil then
	function Store.clearBroken(namespace, promiseId)
		local entry = ensurePromise(namespace, promiseId)
		entry.progress.status = "active"
		entry.progress.brokenReason = nil
	end
end

if Store.getOccurrence == nil then
	function Store.getOccurrence(namespace, promiseId, occurrenceId, create)
		local entry = ensurePromise(namespace, promiseId)
		local key = tostring(occurrenceId)
		local occ = entry.progress.occurrences[key]
		if occ == nil and create == true then
			occ = {
				state = "pending",
				retryCounter = 0,
				nextRetryAtMs = 0,
				createdAtMs = nowMs() or 0,
			}
			entry.progress.occurrences[key] = occ
		end
		return occ
	end
end

if Store.markDone == nil then
	function Store.markDone(namespace, promiseId, occurrenceId)
		local entry = ensurePromise(namespace, promiseId)
		local occ = Store.getOccurrence(namespace, promiseId, occurrenceId, true)
		occ.state = "done"
		occ.lastWhyNot = nil
		occ.retryCounter = 0
		occ.nextRetryAtMs = 0
		occ.lastError = nil
		entry.progress.totalRuns = (entry.progress.totalRuns or 0) + 1
	end
end

if Store.markWhyNot == nil then
	function Store.markWhyNot(namespace, promiseId, occurrenceId, code)
		local occ = Store.getOccurrence(namespace, promiseId, occurrenceId, true)
		occ.lastWhyNot = code
	end
end

if Store.markAttemptFailed == nil then
	function Store.markAttemptFailed(namespace, promiseId, occurrenceId, nextRetryAtMs, err)
		local occ = Store.getOccurrence(namespace, promiseId, occurrenceId, true)
		occ.retryCounter = (occ.retryCounter or 0) + 1
		occ.nextRetryAtMs = tonumber(nextRetryAtMs) or 0
		occ.lastError = err
	end
end

if Store.resetRetry == nil then
	function Store.resetRetry(namespace, promiseId, occurrenceId)
		local occ = Store.getOccurrence(namespace, promiseId, occurrenceId, true)
		occ.retryCounter = 0
		occ.nextRetryAtMs = 0
		occ.lastError = nil
	end
end

if Store.setCooldownUntil == nil then
	function Store.setCooldownUntil(namespace, promiseId, cooldownUntilMs)
		local entry = ensurePromise(namespace, promiseId)
		entry.progress.cooldownUntilMs = tonumber(cooldownUntilMs) or 0
	end
end

Store._internal.ensureRoot = ensureRoot
Store._internal.ensureNamespace = ensureNamespace
Store._internal.ensurePromise = ensurePromise

return Store
