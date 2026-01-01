-- policies/expiry.lua -- per-promise expiry (pruning), optional.
local M = {}

function M.isExpired(progress, policy, nowMs)
	local expiry = policy and policy.expiry or nil
	if expiry and expiry.enabled == false then
		return false
	end
	local ttlSeconds = tonumber(expiry and expiry.ttlSeconds) or 0
	if ttlSeconds <= 0 then
		return false
	end
	local createdAtMs = tonumber(progress and progress.createdAtMs) or 0
	if createdAtMs <= 0 or not nowMs then
		return false
	end
	return (createdAtMs + math.floor(ttlSeconds * 1000)) <= nowMs
end

return M
