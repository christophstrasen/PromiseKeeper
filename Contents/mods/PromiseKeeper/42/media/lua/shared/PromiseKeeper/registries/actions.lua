-- registries/actions.lua -- actionId -> actionFn (namespaced).
local U = require("DREAMBase/util")
local LOG_TAG = "PromiseKeeper actions"

local Log = require("DREAMBase/log")
local log = Log.withTag(LOG_TAG)

local moduleName = ...
local Actions = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Actions = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Actions
	end
end

Actions._internal = Actions._internal or {}
Actions._definitions = Actions._definitions or {}

local function assertNonEmptyString(value, name)
	U.assertf(type(value) == "string" and value ~= "", ("%s must be a non-empty string"):format(tostring(name)))
end

local function getBucket(namespace, create)
	local bucket = Actions._definitions[namespace]
	if bucket == nil and create == true then
		bucket = {}
		Actions._definitions[namespace] = bucket
	end
	return bucket
end

if Actions.define == nil then
	function Actions.define(namespace, actionId, actionFn)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(actionId, "actionId")
		U.assertf(type(actionFn) == "function", "actionFn must be a function")

		local bucket = getBucket(namespace, true)
		local existed = bucket[actionId] ~= nil
		bucket[actionId] = actionFn

		if existed then
			local msg = "action overwritten namespace=" .. namespace .. " id=" .. actionId
			log:warn("%s", msg)
		end
	end
end

if Actions.get == nil then
	function Actions.get(namespace, actionId)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(actionId, "actionId")
		local bucket = getBucket(namespace, false)
		return bucket and bucket[actionId] or nil
	end
end

if Actions.has == nil then
	function Actions.has(namespace, actionId)
		return Actions.get(namespace, actionId) ~= nil
	end
end

local function listSortedKeys(tbl)
	local keys = {}
	for key in pairs(tbl or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

if Actions.list == nil then
	function Actions.list(namespace)
		assertNonEmptyString(namespace, "namespace")
		local bucket = getBucket(namespace, false)
		return listSortedKeys(bucket)
	end
end

Actions._internal.getBucket = getBucket

return Actions
