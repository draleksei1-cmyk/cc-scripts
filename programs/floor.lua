-- floor.lua
-- CC:Tweaked turtle floor replacer
-- Turtle starts on floor level.
-- Start position is included in the area.
-- First row goes forward. Next rows shift to the right.
-- Chest with stone bricks must be behind the turtle at the start position.

local TARGET_BLOCK = "minecraft:stone_bricks"

local x = 0      -- forward from start
local z = 0      -- right from start
local dir = 0    -- 0 forward, 1 right, 2 back, 3 left

local function askNumber(text)
    while true do
        write(text .. ": ")
        local n = tonumber(read())
        if n and n > 0 and math.floor(n) == n then
            return n
        end
        print("Enter a positive whole number.")
    end
end

local length = askNumber("Length forward")
local width = askNumber("Width to the right")

local function turnLeft()
    turtle.turnLeft()
    dir = (dir + 3) % 4
end

local function turnRight()
    turtle.turnRight()
    dir = (dir + 1) % 4
end

local function turnTo(targetDir)
    while dir ~= targetDir do
        local diff = (targetDir - dir) % 4
        if diff == 1 then
            turnRight()
        elseif diff == 3 then
            turnLeft()
        else
            turnRight()
            turnRight()
        end
    end
end

local function updatePosForward()
    if dir == 0 then
        x = x + 1
    elseif dir == 1 then
        z = z + 1
    elseif dir == 2 then
        x = x - 1
    elseif dir == 3 then
        z = z - 1
    end
end

local function digForwardIfNeeded()
    while turtle.detect() do
        turtle.dig()
        sleep(0.2)
    end
end

local function moveForward()
    digForwardIfNeeded()

    while not turtle.forward() do
        turtle.dig()
        turtle.attack()
        sleep(0.2)
    end

    updatePosForward()
end

local function findTargetBlock()
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == TARGET_BLOCK then
            turtle.select(i)
            return true
        end
    end
    return false
end

local function dumpTrashToChest()
    -- Call only at start. Chest is behind the original start direction.
    turnTo(2)

    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail(i)
        if item and item.name ~= TARGET_BLOCK then
            turtle.drop()
        end
    end

    turnTo(0)
end

local function suckStoneBricksFromChest()
    -- Call only at start. Chest is behind the original start direction.
    turnTo(2)

    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail(i)
        if not item or item.name == TARGET_BLOCK then
            turtle.suck()
        end
    end

    turnTo(0)
end

local function goToStart()
    if z > 0 then
        turnTo(3)
        while z > 0 do
            moveForward()
        end
    elseif z < 0 then
        turnTo(1)
        while z < 0 do
            moveForward()
        end
    end

    if x > 0 then
        turnTo(2)
        while x > 0 do
            moveForward()
        end
    elseif x < 0 then
        turnTo(0)
        while x < 0 do
            moveForward()
        end
    end

    turnTo(0)
end

local function goToPosition(targetX, targetZ, targetDir)
    if z < targetZ then
        turnTo(1)
        while z < targetZ do
            moveForward()
        end
    elseif z > targetZ then
        turnTo(3)
        while z > targetZ do
            moveForward()
        end
    end

    if x < targetX then
        turnTo(0)
        while x < targetX do
            moveForward()
        end
    elseif x > targetX then
        turnTo(2)
        while x > targetX do
            moveForward()
        end
    end

    turnTo(targetDir)
end

local function ensureBlocks()
    if findTargetBlock() then
        return true
    end

    print("No stone bricks. Returning to chest...")

    local savedX = x
    local savedZ = z
    local savedDir = dir

    goToStart()
    dumpTrashToChest()
    suckStoneBricksFromChest()

    if not findTargetBlock() then
        print("Chest has no stone bricks.")
        print("Add stone bricks to the chest behind the start.")
        return false
    end

    print("Refilled. Returning to work...")
    goToPosition(savedX, savedZ, savedDir)

    return true
end

local function replaceBlockDown()
    local ok, data = turtle.inspectDown()

    if ok then
        -- Keep existing stone bricks. Replacing them would waste blocks.
        if data.name == TARGET_BLOCK then
            return true
        end

        turtle.digDown()
        sleep(0.1)
    end

    if not ensureBlocks() then
        error("No stone bricks available.")
    end

    while not turtle.placeDown() do
        turtle.digDown()
        sleep(0.2)

        if not ensureBlocks() then
            error("No stone bricks available.")
        end
    end

    return true
end

local function placeCurrentCell()
    replaceBlockDown()

    local freeSlots = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            freeSlots = freeSlots + 1
        end
    end

    if freeSlots <= 1 then
        local savedX = x
        local savedZ = z
        local savedDir = dir

        print("Inventory almost full. Dumping trash...")
        goToStart()
        dumpTrashToChest()
        suckStoneBricksFromChest()
        goToPosition(savedX, savedZ, savedDir)
    end
end

print("Floor replacer")
print("Length forward: " .. length)
print("Width right: " .. width)
print("Chest must be behind the start position.")
print("Press Enter to start.")
read()

for row = 1, width do
    for col = 1, length do
        placeCurrentCell()

        if col < length then
            moveForward()
        end
    end

    if row < width then
        if row % 2 == 1 then
            -- At far end, shift right, then face back.
            turnRight()
            moveForward()
            turnRight()
        else
            -- At near end, shift right, then face forward.
            turnLeft()
            moveForward()
            turnLeft()
        end
    end
end

goToStart()
print("Done. Returned to start.")
