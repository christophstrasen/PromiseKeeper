-- policies/chance.lua -- deterministic chance per occurrenceId.
local U = require("PromiseKeeper/util")
local M = {}

local MODULUS = 4294967296 -- 2^32

function M.shouldRun(namespace, promiseId, occurrenceId, policy)
	local chance = tonumber(policy and policy.chance)
	if chance == nil then
		chance = 1
	end
	if chance >= 1 then
		return true, nil
	end
	if chance <= 0 then
		return false, "policy_skip_chance"
	end
	local key = U.buildKey(namespace, promiseId, occurrenceId)
	local h = U.hash32(key)
	local roll = h / MODULUS
	if roll < chance then
		return true, nil
	end
	return false, "policy_skip_chance"
end

return M
