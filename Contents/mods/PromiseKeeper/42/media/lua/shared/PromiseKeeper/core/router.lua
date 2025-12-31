-- core/router.lua -- situationStream ingress, policy gating, action execution.
local U = require("PromiseKeeper/util")
local Store = require("PromiseKeeper/core/store")
local Time = require("PromiseKeeper/time")
local Actions = require("PromiseKeeper/registries/actions")
local Situations = require("PromiseKeeper/registries/situations")
local RunCount = require("PromiseKeeper/policies/run_count")
local Chance = require("PromiseKeeper/policies/chance")
local Cooldown = require("PromiseKeeper/policies/cooldown")
local Retry = require("PromiseKeeper/policies/retry")

local LOG_TAG = "PromiseKeeper router"

local okLog, Log = pcall(require, "DREAMBase/log")
local log = nil
if okLog and type(Log) == "table" and type(Log.withTag) == "function" then
	log = Log.withTag(LOG_TAG)
end

local moduleName = ...
local Router = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Router = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Router
	end
end

Router._internal = Router._internal or {}
Router._runtime = Router._runtime or {
	subscriptions = {},
	candidates = {},
	pendingRetries = {},
	nextRetryDueMs = nil,
}

local function logInfo(msg)
	if log and type(log.info) == "function" then
		log:info("%s", tostring(msg or ""))
		return
	end
	U.log(LOG_TAG, msg)
end

local function listSize(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
end

local function ensureRuntimeBucket(root, namespace, promiseId)
	local nsBucket = root[namespace]
	if nsBucket == nil then
		nsBucket = {}
		root[namespace] = nsBucket
	end
	local bucket = nsBucket[promiseId]
	if bucket == nil then
		bucket = {}
		nsBucket[promiseId] = bucket
	end
	return bucket
end

local function clearRuntimeBucket(root, namespace, promiseId)
	local nsBucket = root[namespace]
	if not nsBucket then
		return
	end
	nsBucket[promiseId] = nil
end

local function normalizeUnsubscribe(subscription)
	if type(subscription) == "function" then
		return subscription
	end
	if type(subscription) ~= "table" then
		return nil
	end
	if type(subscription.unsubscribe) == "function" then
		return function()
			subscription:unsubscribe()
		end
	end
	if type(subscription.dispose) == "function" then
		return function()
			subscription:dispose()
		end
	end
	return nil
end

local function subscribeToStream(stream, onNext)
	if type(stream) ~= "table" then
		return nil, "invalid_situation_stream"
	end

	-- PromiseKeeper supports two ingress shapes:
	-- 1) situationStream: `{ subscribe = function(self, onNext) ... end }` returning a subscription with `:unsubscribe()`.
	-- 2) event source: PZ Events.* (`Add/Remove`) or Starlit LuaEvent (`addListener/removeListener`).
	--
	-- We prefer `subscribe` when present (even if the object *also* looks like an event source),
	-- because that is the more precise contract (explicit unsubscribe + composition via adapters).
	if type(stream.subscribe) == "function" then
		local ok, subscriptionOrErr = pcall(stream.subscribe, stream, onNext)
		if not ok then
			local err = tostring(subscriptionOrErr)
			if err:find("interest_failed", 1, true) then
				return nil, "interest_failed"
			end
			return nil, "subscribe_failed"
		end
		local unsubscribe = normalizeUnsubscribe(subscriptionOrErr)
		if unsubscribe then
			return unsubscribe, nil
		end
		return nil, "subscribe_failed"
	end

	local unsubscribe = U.subscribeEvent(stream, onNext)
	if unsubscribe then
		return unsubscribe, nil
	end
	return nil, "invalid_situation_stream"
end

local function scheduleRetry(namespace, promiseId, occurranceKey, nextRetryAtMs)
	local runtime = Router._runtime
	local pending = ensureRuntimeBucket(runtime.pendingRetries, namespace, promiseId)
	pending[tostring(occurranceKey)] = true
	if nextRetryAtMs and nextRetryAtMs > 0 then
		local current = runtime.nextRetryDueMs
		if current == nil or nextRetryAtMs < current then
			runtime.nextRetryDueMs = nextRetryAtMs
		end
	end
end

local function clearRetry(namespace, promiseId, occurranceKey)
	local pending = Router._runtime.pendingRetries
	local bucket = pending[namespace]
	if bucket and bucket[promiseId] then
		bucket[promiseId][tostring(occurranceKey)] = nil
	end
end

local function recordCandidate(namespace, promiseId, occurranceKey, candidate)
	local bucket = ensureRuntimeBucket(Router._runtime.candidates, namespace, promiseId)
	bucket[tostring(occurranceKey)] = candidate
end

local function clearCandidate(namespace, promiseId, occurranceKey)
	local bucket = Router._runtime.candidates
	local nsBucket = bucket[namespace]
	if nsBucket and nsBucket[promiseId] then
		nsBucket[promiseId][tostring(occurranceKey)] = nil
	end
end

local function getCandidate(namespace, promiseId, occurranceKey)
	local bucket = Router._runtime.candidates
	local nsBucket = bucket[namespace]
	if nsBucket and nsBucket[promiseId] then
		return nsBucket[promiseId][tostring(occurranceKey)]
	end
	return nil
end

local function handlePolicySkip(namespace, promiseId, occurranceKey, code)
	Store.markWhyNot(namespace, promiseId, occurranceKey, code)
	logInfo(("policy skip %s promiseId=%s occurranceKey=%s"):format(tostring(code), tostring(promiseId), tostring(occurranceKey)))
end

local function handleMissing(namespace, promiseId, occurranceKey, code, note)
	if occurranceKey ~= nil then
		Store.markWhyNot(namespace, promiseId, occurranceKey, code)
	end
	if note then
		logInfo(("drop %s promiseId=%s occurranceKey=%s %s"):format(
			tostring(code),
			tostring(promiseId),
			tostring(occurranceKey),
			tostring(note)
		))
	else
		logInfo(("drop %s promiseId=%s occurranceKey=%s"):format(
			tostring(code),
			tostring(promiseId),
			tostring(occurranceKey)
		))
	end
end

local function shouldPrune(progress, policy)
	local expiry = policy and policy.expiry or nil
	if expiry and expiry.enabled == false then
		return false
	end
	local ttlSeconds = tonumber(expiry and expiry.ttlSeconds) or 0
	if ttlSeconds <= 0 then
		return false
	end
	local occurrences = progress and progress.occurrences or nil
	if type(occurrences) ~= "table" then
		return false
	end
	-- Only prune when there are *many still-unfulfilled* occurrences.
	-- WHY: fulfilled occurrences are the useful idempotence history; we only need pruning as a safety valve
	-- for long-lived promises that never become eligible (or where the upstream stream is too chatty).
	local unfulfilled = 0
	for _, occ in pairs(occurrences) do
		if type(occ) == "table" and occ.state ~= "done" then
			unfulfilled = unfulfilled + 1
		end
	end
	return unfulfilled > 1000
end

local function pruneExpiredOccurrences(progress, policy, nowMs)
	if not shouldPrune(progress, policy) then
		return
	end
	local expiry = policy and policy.expiry or nil
	local ttlSeconds = tonumber(expiry and expiry.ttlSeconds) or 0
	local ttlMs = math.floor(ttlSeconds * 1000)
	if ttlMs <= 0 then
		return
	end
	local occurrences = progress and progress.occurrences or nil
	if type(occurrences) ~= "table" then
		return
	end
	for key, occ in pairs(occurrences) do
		local state = type(occ) == "table" and occ.state or nil
		if state ~= "done" then
			local createdAtMs = tonumber(occ and occ.createdAtMs) or 0
			if createdAtMs > 0 and nowMs and (createdAtMs + ttlMs) <= nowMs then
				occurrences[key] = nil
			end
		end
	end
end

local function tryAction(namespace, promiseId, definition, progress, occurranceKey, candidate)
	local subject = candidate.subject
	if subject == nil then
		handleMissing(namespace, promiseId, occurranceKey, "missing_subject")
		return false
	end

	local policy = definition.policy or {}
	local nowMs = Time.gameMillis()

	pruneExpiredOccurrences(progress, policy, nowMs)

	local okRun, reason = RunCount.shouldRun(progress, policy)
	if not okRun then
		handlePolicySkip(namespace, promiseId, occurranceKey, reason)
		return false
	end

	local okCooldown, cooldownReason = Cooldown.shouldRun(progress, policy, nowMs)
	if not okCooldown then
		handlePolicySkip(namespace, promiseId, occurranceKey, cooldownReason)
		return false
	end

	local okChance, chanceReason = Chance.shouldRun(namespace, promiseId, occurranceKey, policy)
	if not okChance then
		handlePolicySkip(namespace, promiseId, occurranceKey, chanceReason)
		return false
	end

	local occ = Store.getOccurrence(namespace, promiseId, occurranceKey, true)
	local okRetry, retryReason = Retry.shouldAttempt(occ, policy, nowMs)
	if not okRetry then
		handlePolicySkip(namespace, promiseId, occurranceKey, retryReason)
		if retryReason == "retries_exhausted" then
			occ.state = "done"
			clearCandidate(namespace, promiseId, occurranceKey)
			clearRetry(namespace, promiseId, occurranceKey)
		end
		return false
	end

	local actionFn = Actions.get(namespace, definition.actionId)
	if type(actionFn) ~= "function" then
		Store.markBroken(namespace, promiseId, "missing_action_id", "actionId missing at execution")
		return false
	end

	local promiseCtx = {
		promiseId = promiseId,
		occurranceKey = occurranceKey,
		actionId = definition.actionId,
		situationKey = definition.situationKey,
		retryCounter = occ and occ.retryCounter or 0,
		policy = policy,
		situation = candidate,
	}

	local ok, err = pcall(actionFn, subject, definition.actionArgs or {}, promiseCtx)
	if ok then
		Store.resetRetry(namespace, promiseId, occurranceKey)
		Store.markDone(namespace, promiseId, occurranceKey)
		clearRetry(namespace, promiseId, occurranceKey)
		clearCandidate(namespace, promiseId, occurranceKey)

		local cooldownUntil = Cooldown.nextCooldownUntil(nowMs, policy)
		if cooldownUntil > 0 then
			Store.setCooldownUntil(namespace, promiseId, cooldownUntil)
		end

		-- If the promise has reached its max run count, stop listening immediately.
		-- WHY: once satisfied, continuing to subscribe wastes upstream work (especially WorldObserver probes)
		-- and keeps interest leases alive even though we will never act again.
		local shouldContinue, stopReason = RunCount.shouldRun(progress, policy)
		if not shouldContinue and stopReason == "max_runs_reached" then
			progress.status = "stopped"
			Router.stopPromise(namespace, promiseId)
		end
		return true
	end

	Store.markWhyNot(namespace, promiseId, occurranceKey, "action_error")
	logInfo(("action error promiseId=%s occurranceKey=%s err=%s"):format(
		tostring(promiseId),
		tostring(occurranceKey),
		tostring(err)
	))

	local nextRetryAtMs = Retry.nextRetryAt(nowMs, policy)
	if nextRetryAtMs <= 0 then
		nextRetryAtMs = nowMs or 0
	end
	Store.markAttemptFailed(namespace, promiseId, occurranceKey, nextRetryAtMs, err)

	local retryState = Store.getOccurrence(namespace, promiseId, occurranceKey, false)
	local retryCounter = retryState and retryState.retryCounter or 0
	local maxRetries = tonumber(policy and policy.retry and policy.retry.maxRetries) or 3
	if maxRetries >= 0 and retryCounter > maxRetries then
		Store.markWhyNot(namespace, promiseId, occurranceKey, "retries_exhausted")
		retryState.state = "done"
		clearCandidate(namespace, promiseId, occurranceKey)
		clearRetry(namespace, promiseId, occurranceKey)
		return false
	end

	scheduleRetry(namespace, promiseId, occurranceKey, nextRetryAtMs)
	return false
end

if Router.handleCandidate == nil then
	function Router.handleCandidate(namespace, promiseId, candidate)
		if candidate == nil then
			return
		end
		if type(candidate) ~= "table" then
			handleMissing(namespace, promiseId, nil, "missing_occurrance_key", "candidate not a table")
			return
		end

		local occurranceKey = candidate.occurranceKey
		if occurranceKey == nil then
			handleMissing(namespace, promiseId, nil, "missing_occurrance_key")
			return
		end

		if candidate.subject == nil then
			handleMissing(namespace, promiseId, occurranceKey, "missing_subject")
			return
		end

		local entry = Store.getPromise(namespace, promiseId)
		if entry == nil then
			logInfo(("drop candidate promise missing promiseId=%s occurranceKey=%s"):format(
				tostring(promiseId),
				tostring(occurranceKey)
			))
			return
		end

		local progress = entry.progress or {}
		if progress.status == "broken" or progress.status == "stopped" then
			logInfo(("drop candidate promise %s promiseId=%s occurranceKey=%s"):format(
				tostring(progress.status),
				tostring(promiseId),
				tostring(occurranceKey)
			))
			return
		end

		local occ = Store.getOccurrence(namespace, promiseId, occurranceKey, true)
		if occ and occ.state == "done" then
			Store.markWhyNot(namespace, promiseId, occurranceKey, "already_fulfilled")
			return
		end

		recordCandidate(namespace, promiseId, occurranceKey, candidate)
		tryAction(namespace, promiseId, entry.definition or {}, progress, occurranceKey, candidate)
	end
end

local function rememberOne(namespace, promiseId, entry, opts)
	if type(entry) ~= "table" then
		return false
	end

	local def = entry.definition or {}
	local progress = entry.progress or {}

	-- If a promise is already satisfied (maxRuns reached), avoid re-subscribing during remember().
	-- WHY: this prevents PromiseKeeper from keeping upstream subscriptions (and WO interest leases)
	-- alive forever, only to spam "max_runs_reached" skips.
	local policy = def.policy
	if policy == nil then
		policy = {}
	end
	if type(policy) == "table" then
		local shouldContinue, stopReason = RunCount.shouldRun(progress, policy)
		if not shouldContinue and stopReason == "max_runs_reached" then
			progress.status = "stopped"
			progress.brokenReason = nil
			Router.stopPromise(namespace, promiseId)
			return true
		end
	end

	if progress.status == "stopped" then
		progress.status = "active"
	end

	local situationKey = def.situationKey
	local actionId = def.actionId

	if type(situationKey) ~= "string" or situationKey == "" then
		Store.markBroken(namespace, promiseId, "missing_situation_key", "situationKey missing")
		logInfo(("broken missing situationKey promiseId=%s"):format(tostring(promiseId)))
		if opts and opts.throwOnError then
			error("missing_situation_key", 2)
		end
		return false
	end
	if type(actionId) ~= "string" or actionId == "" then
		Store.markBroken(namespace, promiseId, "missing_action_id", "actionId missing")
		logInfo(("broken missing actionId promiseId=%s"):format(tostring(promiseId)))
		if opts and opts.throwOnError then
			error("missing_action_id", 2)
		end
		return false
	end

	if def.policy ~= nil and type(def.policy) ~= "table" then
		Store.markBroken(namespace, promiseId, "invalid_policy", "policy must be a table or nil")
		logInfo(("broken invalid policy promiseId=%s"):format(tostring(promiseId)))
		if opts and opts.throwOnError then
			error("invalid_policy", 2)
		end
		return false
	end

	local actionFn = Actions.get(namespace, actionId)
	if type(actionFn) ~= "function" then
		Store.markBroken(namespace, promiseId, "missing_action_id", "actionId not registered")
		logInfo(("broken missing action registration promiseId=%s actionId=%s"):format(
			tostring(promiseId),
			tostring(actionId)
		))
		if opts and opts.throwOnError then
			error("missing_action_id", 2)
		end
		return false
	end

	local factoryFn = Situations.resolve(namespace, situationKey)
	if type(factoryFn) ~= "function" then
		Store.markBroken(namespace, promiseId, "missing_situation_key", "situationKey not registered")
		logInfo(("broken missing situation registration promiseId=%s situationKey=%s"):format(
			tostring(promiseId),
			tostring(situationKey)
		))
		if opts and opts.throwOnError then
			error("missing_situation_key", 2)
		end
		return false
	end

	local ok, streamOrErr = pcall(factoryFn, def.situationArgs or {})
	if not ok then
		local errMsg = tostring(streamOrErr)
		local reason = "remember_failed"
		if errMsg:find("interest_failed", 1, true) then
			reason = "interest_failed"
		elseif errMsg:find("missing_situation_key", 1, true) then
			reason = "missing_situation_key"
		end
		Store.markBroken(namespace, promiseId, reason, errMsg)
		logInfo(("broken remember failed promiseId=%s reason=%s"):format(tostring(promiseId), tostring(reason)))
		if opts and opts.throwOnError then
			error(errMsg, 2)
		end
		return false
	end

	local stream = streamOrErr
	local unsubscribe, reason = subscribeToStream(stream, function(item)
		local candidate = item
		if candidate == nil then
			return
		end
		Router.handleCandidate(namespace, promiseId, candidate)
	end)

	if not unsubscribe then
		Store.markBroken(namespace, promiseId, reason or "invalid_situation_stream", "subscribe failed")
		logInfo(("broken subscribe failed promiseId=%s reason=%s"):format(
			tostring(promiseId),
			tostring(reason or "invalid_situation_stream")
		))
		if opts and opts.throwOnError then
			error(reason or "subscribe_failed", 2)
		end
		return false
	end

	Store.clearBroken(namespace, promiseId)

	local runtime = Router._runtime
	local bucket = ensureRuntimeBucket(runtime.subscriptions, namespace, promiseId)
	if bucket.unsubscribe then
		pcall(bucket.unsubscribe)
	end
	bucket.unsubscribe = unsubscribe

	return true
end

if Router.startPromise == nil then
	---@param namespace string
	---@param promiseId string
	function Router.startPromise(namespace, promiseId, opts)
		local entry = Store.getPromise(namespace, promiseId)
		if entry == nil then
			return false
		end
		return rememberOne(namespace, promiseId, entry, opts)
	end
end

if Router.startAll == nil then
	function Router.startAll(namespace, opts)
		local entries = Store.listPromises(namespace)
		for _, item in ipairs(entries or {}) do
			Router.startPromise(namespace, item.promiseId, opts)
		end
	end
end

if Router.startAllNamespaces == nil then
	function Router.startAllNamespaces(opts)
		local namespaces = Store.listNamespaces()
		for _, namespace in ipairs(namespaces or {}) do
			Router.startAll(namespace, opts)
		end
	end
end

if Router.stopPromise == nil then
	function Router.stopPromise(namespace, promiseId)
		local bucket = Router._runtime.subscriptions[namespace]
		if bucket and bucket[promiseId] and bucket[promiseId].unsubscribe then
			pcall(bucket[promiseId].unsubscribe)
		end
		clearRuntimeBucket(Router._runtime.subscriptions, namespace, promiseId)
		clearRuntimeBucket(Router._runtime.candidates, namespace, promiseId)
		clearRuntimeBucket(Router._runtime.pendingRetries, namespace, promiseId)
	end
end

	if Router.forgetPromise == nil then
		function Router.forgetPromise(namespace, promiseId)
			Router.stopPromise(namespace, promiseId)
			Store.clearBroken(namespace, promiseId)
			local entry = Store.getPromise(namespace, promiseId)
			if entry then
				entry.progress = {
					status = "active",
					occurrences = {},
					totalRuns = 0,
					cooldownUntilMs = 0,
					createdAtMs = Time.gameMillis() or 0,
				}
			end
		end
	end

if Router.forgetAll == nil then
	function Router.forgetAll(namespace)
		local entries = Store.listPromises(namespace)
		for _, item in ipairs(entries or {}) do
			Router.forgetPromise(namespace, item.promiseId)
		end
	end
end

if Router.processRetries == nil then
	function Router.processRetries(nowMs)
		-- Retries re-use the last seen candidate; PromiseKeeper does not resense the world.
		local runtime = Router._runtime
		if runtime.nextRetryDueMs ~= nil and nowMs and nowMs < runtime.nextRetryDueMs then
			return
		end

		local minNext = nil
		for namespace, bucket in pairs(runtime.pendingRetries or {}) do
			for promiseId, occurrences in pairs(bucket or {}) do
				for occurranceKey in pairs(occurrences or {}) do
					local occ = Store.getOccurrence(namespace, promiseId, occurranceKey, false)
					local nextRetryAtMs = tonumber(occ and occ.nextRetryAtMs) or 0
					if nextRetryAtMs > 0 then
						if nowMs and nextRetryAtMs <= nowMs then
							local candidate = getCandidate(namespace, promiseId, occurranceKey)
							if candidate then
								Router.handleCandidate(namespace, promiseId, candidate)
								local updated = Store.getOccurrence(namespace, promiseId, occurranceKey, false)
								local rescheduled = tonumber(updated and updated.nextRetryAtMs) or 0
								if rescheduled > nowMs then
									if minNext == nil or rescheduled < minNext then
										minNext = rescheduled
									end
								end
							end
						elseif nowMs and nextRetryAtMs > nowMs then
							if minNext == nil or nextRetryAtMs < minNext then
								minNext = nextRetryAtMs
							end
						end
					end
				end
			end
		end
		runtime.nextRetryDueMs = minNext
	end
end

Router._internal.subscribeToStream = subscribeToStream
Router._internal.tryAction = tryAction

return Router
