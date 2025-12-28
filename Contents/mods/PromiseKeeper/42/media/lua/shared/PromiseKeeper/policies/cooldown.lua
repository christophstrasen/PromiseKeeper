-- policies/cooldown.lua -- per-promise cooldown.
local M = {}

function M.shouldRun(progress, policy, nowMs)
	local cooldownSeconds = tonumber(policy and policy.cooldownSeconds) or 0
	if cooldownSeconds <= 0 then
		return true, nil
	end
	local untilMs = tonumber(progress and progress.cooldownUntilMs) or 0
	if nowMs and untilMs > nowMs then
		return false, "policy_skip_cooldown"
	end
	return true, nil
end

function M.nextCooldownUntil(nowMs, policy)
	local cooldownSeconds = tonumber(policy and policy.cooldownSeconds) or 0
	if cooldownSeconds <= 0 then
		return 0
	end
	local base = tonumber(nowMs) or 0
	return base + math.floor(cooldownSeconds * 1000)
end

return M
