-- policies/run_count.lua -- maxRuns gate per promiseId.
local M = {}

function M.shouldRun(progress, policy)
	local maxRuns = tonumber(policy and policy.maxRuns) or 1
	local totalRuns = tonumber(progress and progress.totalRuns) or 0
	if maxRuns >= 0 and totalRuns >= maxRuns then
		return false, "max_runs_reached"
	end
	return true, nil
end

return M
