-- PromiseKeeper.lua -- v2 public API (namespaced, resumable promises).
local U = require("PromiseKeeper/util")
local Store = require("PromiseKeeper/core/store")
local Router = require("PromiseKeeper/core/router")
local Pacemaker = require("PromiseKeeper/core/pacemaker")
local Actions = require("PromiseKeeper/registries/actions")
local Situations = require("PromiseKeeper/registries/situations")
local Factories = require("PromiseKeeper/factories")
local WOAdapter = require("PromiseKeeper/adapters/worldobserver")
local PZEventsAdapter = require("PromiseKeeper/adapters/pz_events")
local LuaEventAdapter = require("PromiseKeeper/adapters/luaevent")
local Status = require("PromiseKeeper/debug/status")

local LOG_TAG = "[PromiseKeeper]"

local PromiseKeeper = {}

PromiseKeeper.factories = Factories
PromiseKeeper.adapters = {
	worldobserver = WOAdapter,
	pz_events = PZEventsAdapter,
	luaevent = LuaEventAdapter,
}

local function logInfo(msg)
	U.log(LOG_TAG, msg)
end

local function assertNonEmptyString(value, name)
	U.assertf(type(value) == "string" and value ~= "", ("%s must be a non-empty string"):format(tostring(name)))
end

local function normalizeArgs(args, name)
	if args == nil then
		return {}
	end
	U.assertf(type(args) == "table", ("%s must be a table or nil"):format(tostring(name)))
	return args
end

local function normalizePolicy(policy)
	if policy == nil then
		policy = {}
	end
	U.assertf(type(policy) == "table", "policy must be a table or nil")

	local retry = policy.retry
	if retry == nil then
		retry = {}
	end
	U.assertf(type(retry) == "table", "policy.retry must be a table or nil")

	local expiry = policy.expiry
	if expiry == nil then
		expiry = {}
	end
	U.assertf(type(expiry) == "table", "policy.expiry must be a table or nil")

	local maxRuns = tonumber(policy.maxRuns)
	if maxRuns == nil then
		maxRuns = 1
	end

	local chance = tonumber(policy.chance)
	if chance == nil then
		chance = 1
	end

	local cooldownSeconds = tonumber(policy.cooldownSeconds) or 0
	if cooldownSeconds < 0 then
		cooldownSeconds = 0
	end

	local maxRetries = tonumber(retry.maxRetries)
	if maxRetries == nil then
		maxRetries = 3
	end

	local delaySeconds = tonumber(retry.delaySeconds)
	if delaySeconds == nil then
		delaySeconds = 10
	end
	if delaySeconds < 0 then
		delaySeconds = 0
	end

	-- PromiseKeeper persists policies; keep them scalar-only and fully expanded with defaults.
	-- WHY: relying on implicit defaults after reload makes debugging harder and can create
	-- surprising behavior drift when the library evolves.
	return {
		maxRuns = maxRuns,
		chance = chance,
		cooldownSeconds = cooldownSeconds,
		retry = {
			maxRetries = maxRetries,
			delaySeconds = delaySeconds,
		},
		expiry = {
			-- Enabled by default; pruning only triggers when there are > 1000 unfulfilled occurrences.
			enabled = expiry.enabled ~= false,
			ttlSeconds = tonumber(expiry.ttlSeconds) or (60 * 60 * 24),
		},
	}
end

if PromiseKeeper.namespace == nil then
	--- Return a namespaced PromiseKeeper handle.
	---@param namespace string
	function PromiseKeeper.namespace(namespace)
		assertNonEmptyString(namespace, "namespace")

		local pk = {}

		---@param actionId string
		---@param actionFn function
		function pk.defineAction(actionId, actionFn)
			return Actions.define(namespace, actionId, actionFn)
		end

		---@param actionId string
		function pk.hasAction(actionId)
			return Actions.has(namespace, actionId)
		end

		function pk.listActions()
			return Actions.list(namespace)
		end

		---@param situationFactoryId string
		---@param buildSituationStreamFn function
		function pk.defineSituationFactory(situationFactoryId, buildSituationStreamFn)
			return Situations.define(namespace, situationFactoryId, buildSituationStreamFn)
		end

		---@param promiseId string
		---@param situationFactoryId string
		---@param situationArgs table|nil
		---@param actionId string
		---@param actionArgs table|nil
		---@param policy table|nil
		function pk.promise(promiseId, situationFactoryId, situationArgs, actionId, actionArgs, policy)
			assertNonEmptyString(promiseId, "promiseId")
			assertNonEmptyString(situationFactoryId, "situationFactoryId")
			assertNonEmptyString(actionId, "actionId")

			local def = {
				situationFactoryId = situationFactoryId,
				situationArgs = U.shallowCopy(normalizeArgs(situationArgs, "situationArgs")),
				actionId = actionId,
				actionArgs = U.shallowCopy(normalizeArgs(actionArgs, "actionArgs")),
				policy = U.shallowCopy(normalizePolicy(policy)),
			}

			local existed = Store.getPromise(namespace, promiseId) ~= nil
			Store.upsertDefinition(namespace, promiseId, def)
			if existed then
				logInfo(("promise overwritten namespace=%s promiseId=%s"):format(tostring(namespace), tostring(promiseId)))
			end

			Pacemaker.start()
			local debugEnabled = type(_G.getDebug) == "function" and _G.getDebug() == true
			return Router.startPromise(namespace, promiseId, { throwOnError = debugEnabled })
		end

		function pk.remember()
			Pacemaker.start()
			local debugEnabled = type(_G.getDebug) == "function" and _G.getDebug() == true
			return Router.startAll(namespace, { throwOnError = debugEnabled })
		end

		function pk.rememberAll()
			Pacemaker.start()
			local debugEnabled = type(_G.getDebug) == "function" and _G.getDebug() == true
			return Router.startAllNamespaces({ throwOnError = debugEnabled })
		end

		---@param promiseId string
		function pk.forget(promiseId)
			assertNonEmptyString(promiseId, "promiseId")
			return Router.forgetPromise(namespace, promiseId)
		end

		function pk.forgetAll()
			return Router.forgetAll(namespace)
		end

		function pk.listPromises()
			return Store.listPromises(namespace)
		end

		---@param promiseId string
		function pk.getStatus(promiseId)
			assertNonEmptyString(promiseId, "promiseId")
			return Status.getStatus(namespace, promiseId)
		end

		function pk.debugDump()
			return Status.debugDump(namespace)
		end

		---@param promiseId string
		---@param occurrenceId string
		function pk.whyNot(promiseId, occurrenceId)
			assertNonEmptyString(promiseId, "promiseId")
			return Status.whyNot(namespace, promiseId, occurrenceId)
		end

		return pk
	end
end

return PromiseKeeper
