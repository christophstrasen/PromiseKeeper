-- registries/situations.lua -- situationFactoryId -> buildSituationStreamFn (namespaced).
local U = require("PromiseKeeper/util")
local LOG_TAG = "[PromiseKeeper situations]"

local moduleName = ...
local Situations = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Situations = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Situations
	end
end

Situations._internal = Situations._internal or {}
Situations._definitions = Situations._definitions or {}

local function assertNonEmptyString(value, name)
	U.assertf(type(value) == "string" and value ~= "", ("%s must be a non-empty string"):format(tostring(name)))
end

local function getBucket(namespace, create)
	local bucket = Situations._definitions[namespace]
	if bucket == nil and create == true then
		bucket = {}
		Situations._definitions[namespace] = bucket
	end
	return bucket
end

if Situations.define == nil then
	function Situations.define(namespace, situationFactoryId, factoryFn)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(situationFactoryId, "situationFactoryId")
		U.assertf(type(factoryFn) == "function", "factoryFn must be a function")

		local bucket = getBucket(namespace, true)
		local existed = bucket[situationFactoryId] ~= nil
		bucket[situationFactoryId] = factoryFn

		if existed then
			U.log(LOG_TAG, "situation overwritten namespace=" .. namespace .. " id=" .. situationFactoryId)
		end
	end
end

if Situations.get == nil then
	function Situations.get(namespace, situationFactoryId)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(situationFactoryId, "situationFactoryId")
		local bucket = getBucket(namespace, false)
		return bucket and bucket[situationFactoryId] or nil
	end
end

if Situations.has == nil then
	function Situations.has(namespace, situationFactoryId)
		return Situations.get(namespace, situationFactoryId) ~= nil
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

if Situations.list == nil then
	function Situations.list(namespace)
		assertNonEmptyString(namespace, "namespace")
		local bucket = getBucket(namespace, false)
		return listSortedKeys(bucket)
	end
end

Situations._internal.getBucket = getBucket

return Situations
