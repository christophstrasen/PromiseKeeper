require("Movement/MovePlayer") --Dependency to from TchernoLib mod. used to identify clear spaces
if MovePlayer then MovePlayer.Verbose = true end

StoryModeMod.WorldFinder = {}
StoryModeMod.WorldFinder.verbose = false
StoryModeMod.WorldFinder.uniqueRoomNames = {}


function StoryModeMod.WorldFinder.getRandFreeSquareInRoomDef(roomDef)
    if not instanceof(roomDef, "RoomDef") then return false end
    return getCell():getFreeTile(roomDef)
end

--- Returns true if the given position corresponds to a residential BuildingDef.
-- @param pos {x=number, y=number, z=number}
-- @return boolean
function StoryModeMod.WorldFinder.positionHasResidentialBuilding(pos)
    if not pos or not pos.x or not pos.y then return false end
    local metaBuilding = getWorld():getMetaGrid():getBuildingAt(pos.x, pos.y)
    return metaBuilding and metaBuilding:isResidential() or false
end

--- Find all nearby doors within a given radius
-- @param searchSquare IsoGridSquare
-- @param onFinished function -- callback with result table of IsoGridSquare
function StoryModeMod.WorldFinder.getSquaresOfNearbyDoorsAsync(searchSquare, onFinished)
    local matcher = StoryModeMod.WorldFinder.makeDoorMatcher()

    StoryModeMod.WorldFinder.searchAroundSquareAsync(
        searchSquare,
        10,
        matcher,
        function(squares)
            print("🔍 Matcher returned " .. tostring(#squares) .. " squares of doors.")
            -- pass the result to the callback
            onFinished(squares)
        end
    )
end

-- Updated to accept a starting room and iterate over its squares to find doors with keys (exterior doors prioritized)
-- TODO: We can explore option of getWorld():getMetaGrid():getAssociatedBuildingAt(sq):getRooms() but that is much more expensive
function StoryModeMod.WorldFinder.getSquaresOfDoorsWithinRoom(room)
    local doors = {}
    local squares = room:getSquares()
    for j = 0, squares:size() - 1 do
        local sq = squares:get(j)
        local objects = sq:getObjects()
        for k = 0, objects:size() - 1 do
            local obj = objects:get(k)
            if instanceof(obj, "IsoDoor") then
                table.insert(doors, sq)
            end
        end
    end
    return doors
end

function StoryModeMod.WorldFinder.getFilteredRoomAsync(opts, limiter)
    limiter = limiter or 1
    if limiter > 10 then
        opts.onFinished(nil)
        return
    end
    assert(opts and opts.name and opts.from and opts.onFinished,
        "findFilteredRoomAsync requires { name, from, onFinished }")

    local minDist = opts.minDistance or 0
    local maxDist = opts.maxDistance or 999999
    local predicate = opts.predicateFn or function(_) return true end

    print(string.format("📍 RoomQuery: name='%s', dist=[%d,%d]", opts.name, minDist, maxDist))

    StoryModeMod.WorldFinder.getRoomDefinitionsAsync(opts.name, function(allRooms)
        print("📦 Total rooms with name:", #allRooms)

        local distances = NCgetDistances(opts.from, allRooms)
        local inRange = {}
        for k, dist in pairs(distances) do
            if dist >= minDist and dist <= maxDist then
                inRange[k] = allRooms[k]
            end
        end


        -- Inline batch filter
        local keys = {}
        local filtered = {}
        local roomKeys = {}
        for k, _ in pairs(inRange) do table.insert(roomKeys, k) end
        local index = 1

        local function processNextBatch()
            local batchSize = 100 * GetDynamicBatchSize()
            local processed = 0

            while index <= #roomKeys and processed < batchSize do
                local k = roomKeys[index]
                local room = inRange[k]
                index = index + 1
                processed = processed + 1

                local ok = predicate(room)
                if ok then
                    filtered[k] = room
                    table.insert(keys, k)
                end
            end

            if index > #roomKeys then
                Events.OnTick.Remove(processNextBatch)
                print("✅ Predicate-filtered rooms: " .. tostring(#keys))

                if #keys == 0 then
                    if opts.fallbackMaxMultiplier and opts.fallbackMaxMultiplier > 1 then
                        limiter = limiter + 1 or 1
                        print("Oh oh. found no rooms so using fallbackMaxMultiplier maximum 10 times to expand search radius and try again. Currently run number was: ", limiter)
                        opts.maxDistance = opts.maxDistance * opts.fallbackMaxMultiplier         
                        StoryModeMod.WorldFinder.getFilteredRoomAsync(opts, limiter)
                        return
                    else
                        print("❌ No suitable room found.")
                        opts.onFinished(nil)
                        return
                    end
                end

                local randomKey = keys[ZombRand(#keys) + 1]
                local selected = filtered[randomKey]

                if not selected then
                    print("❌ Failed to resolve selected room key.")
                    opts.onFinished(nil)
                    return
                end

                print(string.format("🎯 Room selected at (%d, %d, %d)",
                    selected:getX(), selected:getY(), selected:getZ()))
                opts.onFinished(selected)
            end
        end

        Events.OnTick.Add(processNextBatch)
    end)
end


--- Asynchronously finds a random room matching name, distance range, and optional predicate.
-- 
-- Filters rooms in batches by name, 2D distance from a given origin, and custom predicate.
-- When done, calls `opts.onFinished(roomDef)` with a selected match or `nil` if none found.
--
-- @param opts table A table of parameters:
--   @field name string The name of the room to match (e.g., "kitchen")
--   @field from table|IsoObject An object or table with :getX(), :getY() or .x, .y fields
--   @field minDistance number? Optional minimum 2D distance (inclusive), default = 0
--   @field maxDistance number? Optional maximum 2D distance (inclusive), default = 999999
--   @field predicateFn fun(room: RoomDef): boolean Optional function to further filter results
--   @field onFinished fun(room: RoomDef|nil) Callback invoked with one matching room or nil
--
-- @usage
-- StoryModeMod.WorldFinder.getFilteredRoomAsync({
--     name = "kitchen",
--     from = getPlayer(),
--     minDistance = 20,
--     maxDistance = 1000,
--     predicateFn = function(room) return room:getArea() >= 5 end,
--     onFinished = function(room)
--         if room then
--             print("Room at", room:getX(), room:getY())
--         else
--             print("No room found.")
--         end
--     end
-- })
function StoryModeMod.WorldFinder.getRoomDefinitionsAsync(filterByName, onFinished, printUniqueNames)
    local buildings = getWorld():getMetaGrid():getBuildings()
    local matchedRooms = {}
    local uniqueNames = StoryModeMod.WorldFinder.uniqueRoomNames or {}
    StoryModeMod.WorldFinder.uniqueRoomNames = uniqueNames

    if not buildings then
        print("⚠️ MetaGrid:getBuildings() returned nil!")
        onFinished(matchedRooms)
        return
    end

    print("📍 Starting getRoomDefinitionsAsync scan... total buildings:", buildings:size())

    local total = buildings:size()
    local index = 0

    local function processNextBatch()
        local batchSize = 10 * GetDynamicBatchSize()
        local processed = 0

        while index < total and processed < batchSize do
            local building = buildings:get(index)
            index = index + 1
            processed = processed + 1

            if building then
                local rooms = building:getRooms()
                if rooms then
                    for j = 0, rooms:size() - 1 do
                        local room = rooms:get(j)
                        if room and room:getName() then
                            local name = room:getName()
                            if printUniqueNames and not uniqueNames[name] then
                                print("🔠 Found room name:", name)
                                uniqueNames[name] = true
                            else
                                uniqueNames[name] = true
                            end

                            if not filterByName or filterByName == name then
                                table.insert(matchedRooms, room)
                            end
                        end
                    end
                else
                    print(string.format("⚠️ Building ID %s has no rooms", tostring(building:getID())))
                end
            else
                print(string.format("⚠️ Building at index %d was nil", index - 1))
            end
        end

        if index >= total then
            Events.OnTick.Remove(processNextBatch)
            print("✅ Finished room scan. Total matched:", #matchedRooms)
            onFinished(matchedRooms)
        end
    end

    Events.OnTick.Add(processNextBatch)
end

--factory function that returns a closure
function StoryModeMod.WorldFinder.makeDoorMatcher()
    print("🛠️ Creating door matcher.")
    return function(square)
        local results = {}
        print(string.format("🧪 Scanning square (%d, %d, %d)...", square:getX(), square:getY(), square:getZ()))
        for i = 0, square:getObjects():size() - 1 do
            local obj = square:getObjects():get(i)
            if instanceof(obj, "IsoDoor") or (instanceof(obj, "IsoThumpable") and obj:isDoor()) then
                print(string.format("🚪 Door at (%d, %d, %d): keyId = %d", square:getX(), square:getY(), square:getZ(),
                    obj:getKeyId()))
                print("✅ Match found! Adding square to results.")
                table.insert(results, square)
            end
        end
        if #results == 0 then
            print("❌ No doors found on this square.")
        end
        return results
    end
end

-- Updated to use dynamic batch size and harmonized naming
function StoryModeMod.WorldFinder.searchAroundSquareAsync(anchorSquare, radius, filterFunction, onFinished)
    local matchedSquares = {}

    if not anchorSquare then
        print("❌ search square is not valid.")
        onFinished(matchedSquares)
        return
    end

    local cell = getCell()
    local positionsToCheck = {}
    local z = anchorSquare:getZ()
    local anchorX, anchorY = anchorSquare:getX(), anchorSquare:getY()

    -- Build list of positions to scan
    for dy = -radius, radius do
        for dx = -radius, radius do
            table.insert(positionsToCheck, { x = anchorX + dx, y = anchorY + dy, z = z })
        end
    end

    local currentIndex = 1
    local function processNextBatch()
        local batchSize = 1 * GetDynamicBatchSize()
        local processed = 0

        while currentIndex <= #positionsToCheck and processed < batchSize do
            local coord = positionsToCheck[currentIndex]
            currentIndex = currentIndex + 1
            processed = processed + 1

            local square = cell:getGridSquare(coord.x, coord.y, coord.z)
            print(string.format("🔎 Searching (%d, %d, %d):", coord.x, coord.y, coord.z))
            if square then
                local results = filterFunction(square)
                table.append(matchedSquares, results)
            end
        end

        if currentIndex > #positionsToCheck then
            Events.OnTick.Remove(processNextBatch)
            print("✅ Finished scanning. Total matched squares:", #matchedSquares)
            onFinished(matchedSquares)
        end
    end

    print("DEBUG: Starting async square scan. Total squares:", #positionsToCheck)
    Events.OnTick.Add(processNextBatch)
end


--- Return a list of 3x3 square blocks around a center that are suitable to spawn vehicles.
-- Each block is scored or discarded based on hard checks and soft scoring.
-- @param centerPos position
-- @param radius number
-- @param filterFunction function(square: IsoGridSquare): integer|false (optional)
-- @param onFinished function(sectionTable: {score: integer|false, squares: IsoGridSquare[]})
-- example: StoryModeMod.WorldFinder.findVehicleSpawnSectionsAsync({y=10,x=20,z=0}, 10, nil, function(res) _vehicleSpawnScanResult = res end)

function StoryModeMod.WorldFinder.findVehicleSpawnSectionsAsync(centerPos, radius, filterFunction, onFinished)
    local v = StoryModeMod.WorldFinder.verbose
    assert(StoryModeMod.ServerUtils.isValidPosition(centerPos),
        "centerPos must be a valid position and have centerPos.x or centerPos:getX() etc.")
    assert(type(radius) == "number" and radius > 0, "radius must be a positive number")
    assert(type(onFinished) == "function", "onFinished callback must be provided")
    if filterFunction ~= nil and filterFunction ~= false then
        assert(type(filterFunction) == "function", "filterFunction must be a function or nil")
    end

    print(string.format("[VehicleSpawn] Starting search from (%d, %d, %d) with radius %d", centerPos.x, centerPos.y,
        centerPos.z, radius))

    -- Define scanning bounds adjusted to nearest multiple of 3 to fit 3x3 sections
    local side = (radius * 2) + 1
    local size = side - (side % 3)
    local offset = math.floor(size / 2)
    local startX = centerPos.x - offset
    local startY = centerPos.y - offset
    local maxX = startX + size
    local maxY = startY + size

    -- Collect top-left coordinates of all 3x3 sections to evaluate
    local sectionCoords = {}
    for x = startX, maxX - 2, 3 do
        for y = startY, maxY - 2, 3 do
            table.insert(sectionCoords, { x = x, y = y })
        end
    end

    print("[VehicleSpawn] Total candidate sections:", #sectionCoords)

    local normSections = {}
    local index = 1
    local allSections = {}
    local minScore, maxScore = math.huge, -math.huge

    local function normalizeBatch()
        if minScore == math.huge or maxScore == -math.huge then
            minScore = 0
            maxScore = 1
        end
        local batchSize = 10 * GetDynamicBatchSize()
        local processed = 0
    
        while index <= #allSections and processed < batchSize do
            local s = allSections[index]
            index = index + 1
            processed = processed + 1
    
            if s.score and type(s.score) == "number" then
                local normVal = s
                normVal.score = (s.score - minScore) / (maxScore - minScore + 0.0001)
                table.insert(normSections, normVal)
    
                if StoryModeMod.verbose == true then
                    for _, sq in ipairs(normVal.squares) do
                        local floor = sq and sq:getFloor()
                        if floor then
                            floor:setHighlightColor(0.2, 0.5, 1.0, normVal.score)
                            floor:setHighlighted(true, false)
                        end
                    end
                end
            end
        end
    
        if index > #allSections then
            print("[VehicleSpawn] Finished normalizing ")
            Events.OnTick.Remove(normalizeBatch)

            local highestScoredSection = false
            for i, localSection in ipairs(normSections) do
                if StoryModeMod.WorldFinder.verbose then print(string.format("  • Section %d ", i)) end
                --ncdump(section)
                if not highestScoredSection or (highestScoredSection.score and highestScoredSection.score < localSection.score) then
                    --print("found higher score ", section.score)
                    highestScoredSection = localSection
                end
            end

            onFinished(normSections, highestScoredSection)
        end
    end



    -- Process candidate sections incrementally across frames
    local function processNextBatch()
        local batchSize = 1 * GetDynamicBatchSize()
        local processed = 0

        while index <= #sectionCoords and processed < batchSize do
            local coord = sectionCoords[index]
            index = index + 1
            processed = processed + 1

            local section = {
                squares = {},
                strips = {},
                score = 0
            }

            --print(string.format("[VehicleSpawn] Evaluating section origin: (%d, %d, %d)", coord.x, coord.y, centerPos.z))
            local disqualify = false

            -- Iterate over all 9 squares in the 3x3 section
            for dx = 0, 2 do
                for dy = 0, 2 do
                    local sq = getCell():getGridSquare(coord.x + dx, coord.y + dy, centerPos.z)
                    if not sq then
                        --print("[VehicleSpawn] Missing square in section. Disqualified.")
                        disqualify = true
                        break
                    end
                    table.insert(section.squares, sq)

                    if sq:isInARoom() then
                        --print(string.format("[VehicleSpawn] Square at (%d, %d, %d) is indoors. Disqualified.", sq:getX(), sq:getY(), sq:getZ()))
                        disqualify = true
                        if StoryModeMod.verbose == true then
                            local floor = sq:getFloor()
                            if floor then
                                floor:setHighlightColor(1, 0, 0, 1)
                                floor:setHighlighted(true, false)
                            end
                        end
                        break
                    end

                    if sq:getVehicleContainer() then
                        --print(string.format("[VehicleSpawn] Square at (%d, %d, %d) contains a vehicle. Disqualified.", sq:getX(), sq:getY(), sq:getZ()))
                        disqualify = true
                        break
                    end

                    if sq:hasNaturalFloor() then
                        section.score = section.score - 3
                        --print("[Score] -1 natural floor")
                    else
                        section.score = section.score + 3
                        --print("[Score] +1 non-natural floor")
                    end

                    if sq:HasTree() then
                        section.score = section.score - 7
                        --print("[Score] -4 has tree")
                    end

                    -- checking the floor more thoroughly
                    local floor = sq:getFloor()
                    if floor then
                        local tex = floor:getTextureName()
                        if tex and tex:contains("blends_street") then
                            section.score = section.score + 10
                        end
                        local material = GetFloorFootstepMaterial(floor)
                        if material then
                            if material:contains("asphalt") then
                                section.score = section.score + 10
                            elseif material:contains("gravel") or material:contains("concrete") then
                                section.score = section.score + 3
                            end
                        end
                    end

                    local special = sq:getSpecialObjects():size()
                    if special > 0 then
                        section.score = section.score - (10 * special)
                    end

                    local objects = sq:getObjects():size()
                    if objects > 0 then
                        section.score = section.score - (2 * objects)
                    end

                    if sq:hasFarmingPlant() or sq:hasLitCampfire() or sq:hasFireplace() then
                        section.score = section.score - 7
                        --print("[Score] -5 for dangerous or active square")
                    end

                    if sq:isAdjacentToWindow() or sq:isAdjacentToHoppable() then
                        section.score = section.score - 3
                        --print("[Score] -3 for adjacency to window/hoppable")
                    end

                    if filterFunction then
                        local extra = filterFunction(sq)
                        if extra == false then
                            --print(string.format("[VehicleSpawn] Square at (%d, %d, %d) failed custom filter.", sq:getX(), sq:getY(), sq:getZ()))
                            disqualify = true
                            if StoryModeMod.verbose == true then
                                local floor = sq:getFloor()
                                if floor then
                                    floor:setHighlightColor(1, 0, 0, 1)
                                    floor:setHighlighted(true, false)
                                end
                            end
                        elseif type(extra) == "number" then
                            section.score = section.score + extra
                            --print("[Score] +" .. extra .. " from custom filter")
                        end
                    end
                end
                if disqualify then break end
            end

            -- Evaluate directional strips for physical blockages using MovePlayer
            if not disqualify then
                section.strips = {
                    { getCell():getGridSquare(coord.x, coord.y, centerPos.z),     getCell():getGridSquare(coord.x + 2, coord.y, centerPos.z) },
                    { getCell():getGridSquare(coord.x, coord.y + 1, centerPos.z), getCell():getGridSquare(coord.x + 2, coord.y + 1, centerPos.z) },
                    { getCell():getGridSquare(coord.x, coord.y + 2, centerPos.z), getCell():getGridSquare(coord.x + 2, coord.y + 2, centerPos.z) },
                }
                for i, pair in ipairs(section.strips) do
                    if not pair[1] or not pair[2] or MovePlayer.isBlockedTo(pair[1], pair[2]) then
                        --print(string.format("[VehicleSpawn] Strip %d is blocked or incomplete. Section disqualified.", i))
                        section.score = false
                        if StoryModeMod.verbose == true then
                            for _, sq in ipairs(pair) do
                                local floor = sq and sq:getFloor()
                                if floor then
                                    floor:setHighlightColor(1, 0, 0, 1)
                                    floor:setHighlighted(true, false)
                                end
                            end
                        end
                        break
                    end
                end
            else
                section.score = false
            end

            --keeping track of scores min/max
            if section.score and section.score < minScore then
                minScore = section.score
            end
            if section.score and section.score > maxScore then
                maxScore = section.score
            end

            table.insert(allSections, section)
        end

        if index > #sectionCoords then
            print("[VehicleSpawn] Finished evaluating all sections. Will now normalize scores")
            index = 1
            Events.OnTick.Remove(processNextBatch)
            Events.OnTick.Add(normalizeBatch)
        end
    end

    Events.OnTick.Add(processNextBatch)
end

_vehicleSpawnLoop = _vehicleSpawnLoop or {
    active = false,

    tick = function()
        local player = getPlayer()
        if not player then return end

        local square = player:getCurrentSquare()
        if not square then return end

        _vehicleSpawnLoop.active = true

        StoryModeMod.WorldFinder.findVehicleSpawnSectionsAsync(
            StoryModeMod.ServerUtils.expandPosition(player, square),
            20, nil,
            function(results, highestScoredSection)
                _vehicleSpawnLoop.active = false
                if not results or #results == 0 then
                    if StoryModeMod.WorldFinder.verbose then print("🚫 No vehicle spawn sections found.") end
                    return
                end

                if StoryModeMod.WorldFinder.verbose then print("🔍 Found vehicle spawn sections:") end

                if highestScoredSection and highestScoredSection.squares and highestScoredSection.squares[5] then
                    local winnerSQ = highestScoredSection.squares[5] --in a 3x3 the 5 is the middle
                    print("winning square is ", winnerSQ)
                    local floor = winnerSQ:getFloor()
                    if floor and StoryModeMod.verbose then
                        floor:setHighlightColor(1, 1, 0, 1)
                        floor:setHighlighted(true, false)
                        floor:setBlink(true)
                    end
                end
            end
        )
    end
}