-- debug/status.lua -- diagnostic helpers and reason codes.
local Store = require("PromiseKeeper/core/store")

local moduleName = ...
local Status = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Status = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Status
	end
end

Status.brokenCodes = Status.brokenCodes or {
	"missing_action_id",
	"missing_situation_map_id",
	"invalid_situation_stream",
	"subscribe_failed",
	"invalid_policy",
	"moddata_corrupt",
	"interest_failed",
	"remember_failed",
}

Status.whyNotCodes = Status.whyNotCodes or {
	"missing_occurrence_id",
	"missing_subject",
	"already_fulfilled",
	"max_runs_reached",
	"policy_skip_chance",
	"policy_skip_cooldown",
	"retry_waiting",
	"retries_exhausted",
	"action_error",
}

if Status.getStatus == nil then
	function Status.getStatus(namespace, promiseId)
		local entry = Store.getPromise(namespace, promiseId)
		return entry and entry.progress or nil
	end
end

if Status.whyNot == nil then
	function Status.whyNot(namespace, promiseId, occurrenceId)
		local occ = Store.getOccurrence(namespace, promiseId, occurrenceId, false)
		return occ and occ.lastWhyNot or nil
	end
end

if Status.debugDump == nil then
	function Status.debugDump(namespace)
		return Store.listPromises(namespace)
	end
end

return Status
