-- policies/chance.lua -- deterministic chance per occurranceKey.
local U = require("DREAMBase/util")
local M = {}

local MODULUS = 4294967296 -- 2^32

function M.shouldRun(namespace, promiseId, occurranceKey, policy)
	local chance = tonumber(policy and policy.chance)
	if chance == nil then
		chance = 1
	end
	local info = { chance = chance }
	if chance >= 1 then
		return true, nil, info
	end
	if chance <= 0 then
		return false, "policy_skip_chance", info
	end
	local key = U.buildKey(namespace, promiseId, occurranceKey)
	-- Use Murmur32 for stronger avalanche so nearby keys do not correlate.
	local h = U.murmur32(key)
	local roll = h / MODULUS
	info.hash = h
	info.roll = roll
	if roll < chance then
		return true, nil, info
	end
	return false, "policy_skip_chance", info
end

return M
