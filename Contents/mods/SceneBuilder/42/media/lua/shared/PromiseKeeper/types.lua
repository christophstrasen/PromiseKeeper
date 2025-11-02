-- PromiseKeeper/types.lua — shared EmmyLua surface for IDEs.

---@class PKSquareCtx
---@field sq IsoGridSquare
---@field x integer
---@field y integer
---@field z integer
---@field cx integer
---@field cy integer
---@field roomDef RoomDef|nil
---@field roomId integer|nil

---@class PKTargetSquare
---@field type '"IsoSquare"'
---@field key string
---@field squareId number
---@field ref IsoGridSquare|nil

---@class PKTargetRoom
---@field type '"roomDef"'
---@field key string
---@field roomId number
---@field ref RoomDef|nil

---@class PKRequest
---@field id string
---@field fulfiller string
---@field tag? string
---@field cleanAfterDays? number
---@field maxFulfillments? number
---@field target? PKTargetSquare|PKTargetRoom
---@field mode? '"square"'
---@field matchFn? fun(squareCtx:PKSquareCtx, matchParams:any): (PKTargetSquare|PKTargetRoom)[]
---@field matchParams? table|nil

---@alias PKRequestTarget PKTargetSquare|PKTargetRoom

local Types = {}

---@return PKSquareCtx
function Types.newSquareCtx()
	return {
		sq = nil,
		x = 0,
		y = 0,
		z = 0,
		cx = 0,
		cy = 0,
		roomDef = nil,
		roomId = nil,
	}
end

return Types
