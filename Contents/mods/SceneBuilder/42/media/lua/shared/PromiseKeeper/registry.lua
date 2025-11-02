-- registry.lua — name -> { fn, tag }
local M = {}
local map = {}

---@param name string
---@param fn   function
---@param tag? string
---@return boolean replaced
function M.put(name, fn, tag)
	local replaced = map[name] ~= nil
	map[name] = { fn = fn, tag = tag }
	return replaced
end

---@param name string
---@return function|nil fn
function M.get(name)
	local r = map[name]
	return r and r.fn or nil
end

function M.list()
	return map
end

return M
