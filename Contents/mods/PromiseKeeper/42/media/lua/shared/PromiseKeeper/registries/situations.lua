-- registries/situations.lua -- situationKey -> buildSituationStreamFn (namespaced).
local U = require("PromiseKeeper/util")
local WOAdapter = require("PromiseKeeper/adapters/worldobserver")
local LOG_TAG = "PromiseKeeper situations"

local okLog, Log = pcall(require, "DREAMBase/log")
local log = nil
if okLog and type(Log) == "table" and type(Log.withTag) == "function" then
	log = Log.withTag(LOG_TAG)
end

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
Situations._search = Situations._search or {}

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
	function Situations.define(namespace, situationKey, factoryFn)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(situationKey, "situationKey")
		U.assertf(type(factoryFn) == "function", "factoryFn must be a function")

		local bucket = getBucket(namespace, true)
		local existed = bucket[situationKey] ~= nil
		bucket[situationKey] = factoryFn

		if existed then
			local msg = "situation overwritten namespace=" .. namespace .. " situationKey=" .. situationKey
			if log and type(log.warn) == "function" then
				log:warn("%s", msg)
			else
				U.log(LOG_TAG, msg)
			end
		end
	end
end

if Situations.get == nil then
	function Situations.get(namespace, situationKey)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(situationKey, "situationKey")
		local bucket = getBucket(namespace, false)
		return bucket and bucket[situationKey] or nil
	end
end

if Situations.has == nil then
	function Situations.has(namespace, situationKey)
		return Situations.get(namespace, situationKey) ~= nil
	end
end

if Situations.searchIn == nil then
	--- Register a search registry for situations not defined in PromiseKeeper.
	---@param namespace string
	---@param registry table
	function Situations.searchIn(namespace, registry)
		assertNonEmptyString(namespace, "namespace")
		U.assertf(type(registry) == "table", "registry must be a table")

		local isWO = type(WOAdapter.isWorldObserver) == "function" and WOAdapter.isWorldObserver(registry)
		U.assertf(isWO == true, "search registry not supported")

		Situations._search[namespace] = {
			kind = "worldobserver",
			registry = registry,
		}
	end
end

local function resolveSearch(namespace, situationKey)
	local search = Situations._search[namespace]
	if not search then
		return nil
	end
	if search.kind == "worldobserver" then
		local registry = search.registry
		return function(args)
			local situations = registry.situations.namespace(namespace)
			local stream = situations.get(situationKey, args)
			if stream == nil then
				error("missing_situation_key", 2)
			end
			return WOAdapter.wrapSituationStream(stream)
		end
	end
	return nil
end

if Situations.resolve == nil then
	function Situations.resolve(namespace, situationKey)
		local factoryFn = Situations.get(namespace, situationKey)
		if type(factoryFn) == "function" then
			return factoryFn
		end
		return resolveSearch(namespace, situationKey)
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
