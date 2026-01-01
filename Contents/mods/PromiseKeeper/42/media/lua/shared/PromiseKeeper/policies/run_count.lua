-- policies/run_count.lua -- maxRuns gate per promiseId.
local M = {}

function M.shouldRun(progress, policy)
	local maxRuns = tonumber(policy and policy.maxRuns) or 1
	local totalRuns = tonumber(progress and progress.totalRuns) or 0
	local info = { maxRuns = maxRuns, totalRuns = totalRuns }
	if maxRuns >= 0 and totalRuns >= maxRuns then
		return false, "max_runs_reached", info
	end
	return true, nil, info
end

return M
