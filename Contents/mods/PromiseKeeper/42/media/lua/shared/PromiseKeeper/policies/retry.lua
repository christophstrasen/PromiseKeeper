-- policies/retry.lua -- retry gating per occurrence.
local M = {}

function M.shouldAttempt(occurrence, policy, nowMs)
	local retry = policy and policy.retry or nil
	local maxRetries = tonumber(retry and retry.maxRetries)
	local delaySeconds = tonumber(retry and retry.delaySeconds) or 0

	if maxRetries == nil then
		maxRetries = 3
	end

	local retryCounter = tonumber(occurrence and occurrence.retryCounter) or 0
	local nextRetryAtMs = tonumber(occurrence and occurrence.nextRetryAtMs) or 0
	local info = {
		retryCounter = retryCounter,
		maxRetries = maxRetries,
		delaySeconds = delaySeconds,
		nextRetryAtMs = nextRetryAtMs,
		nowMs = nowMs,
	}

	-- `retryCounter` counts *failures*, so `maxRetries = 0` still allows the first attempt
	-- (it just disables any retry after the first failure).
	if maxRetries >= 0 and retryCounter > maxRetries then
		return false, "retries_exhausted", info
	end

	if delaySeconds > 0 and nextRetryAtMs > 0 and nowMs and nextRetryAtMs > nowMs then
		return false, "retry_waiting", info
	end

	return true, nil, info
end

function M.nextRetryAt(nowMs, policy)
	local retry = policy and policy.retry or nil
	local delaySeconds = tonumber(retry and retry.delaySeconds) or 0
	if delaySeconds <= 0 then
		return 0
	end
	local base = tonumber(nowMs) or 0
	return base + math.floor(delaySeconds * 1000)
end

return M
