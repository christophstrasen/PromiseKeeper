-- test.lua — lightweight helper to exercise PromiseKeeper with SceneBuilder's full demo.

local PromiseKeeper = require("PromiseKeeper")
local fulldemo = require("SceneBuilder/prefabs/demo_full")

local U = require("PromiseKeeper/util")
local LOG_TAG = "[PromiseKeeper Test]"
local log = U.makeLogger(LOG_TAG)

local Test = {}

local function ensureDemoFulfiller()
	PromiseKeeper.registerFulfiller("pk_demo_full_room", function(ctx)
		fulldemo.makeForRoomDef(ctx.target)
	end, "Scene")
end

local function currentRoomDef()
	local player = getSpecificPlayer(0) or getPlayer()
	if not player then
		return nil, "no player found"
	end
	local sq = player:getSquare()
	if not sq then
		return nil, "player has no square yet"
	end
	local room = sq:getRoom()
	if not room then
		return nil, "player is not inside a room"
	end
	local roomDef = room:getRoomDef()
	if not roomDef then
		return nil, "room has no roomDef"
	end
	return roomDef
end

--- Queue the full demo scene for the player's current room.
function Test.ensureDemoForPlayerRoom()
	local roomDef, err = currentRoomDef()
	if not roomDef then
		log("aborted: " .. tostring(err))
		return false
	end

	ensureDemoFulfiller()

	local roomId = roomDef:getID()
	PromiseKeeper.ensureAt({
		id = "pk-demo-full-room",
		fulfiller = "pk_demo_full_room",
		tag = "Test",
		target = roomDef,
		cleanAfterDays = 1,
	})

	log("queued demo for room " .. tostring(roomId))
	return true
end

return Test
