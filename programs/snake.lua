-- snake.lua
-- CC:Tweaked Mining Turtle
-- Snake tunnel miner: 3 blocks high, 1 block wide.
-- English-only terminal text.
--
-- Recommended slots:
-- 1  = fuel
-- 2  = torches
-- 3  = chests
-- 4  = filler blocks for water/lava: cobblestone/dirt/stone
-- 5-16 = loot
--
-- Place the turtle in the middle height of the future tunnel.
-- It mines forward, up and down, but never moves down.

local STATE_FILE = ".snake_tunnel_state"

local SLOT_FUEL  = 1
local SLOT_TORCH = 2
local SLOT_CHEST = 3
local SLOT_FILL  = 4

local LOOT_FIRST = 5

local RIGHT = 1
local LEFT  = -1

local MAX_DIG_RETRIES = 14
local DEFAULT_UNLOAD_EMPTY = 4
local DEFAULT_SIDE_GAP = 3
local DEFAULT_TORCH_EVERY = 8

local state = nil
local isUnloading = false

local function save()
    if not state then return end

    local h = fs.open(STATE_FILE, "w")
    h.write(textutils.serialize(state))
    h.close()
end

local function loadState()
    if not fs.exists(STATE_FILE) then
        return nil
    end

    local h = fs.open(STATE_FILE, "r")
    local data = h.readAll()
    h.close()

    return textutils.unserialize(data)
end

local function stop(msg)
    save()
    error("\nSTOP: " .. tostring(msg), 0)
end

local function askNumber(label, default, minValue)
    while true do
        write(label .. " [" .. tostring(default) .. "]: ")
        local s = read()

        if s == "" then
            return default
        end

        local n = tonumber(s)

        if n and n >= minValue then
            return math.floor(n)
        end

        print("Enter a number >= " .. tostring(minValue))
    end
end

local function askDirection()
    while true do
        write("First side turn: R = right, L = left [R]: ")
        local s = read()
        s = string.lower(s or "")

        if s == "" or s == "r" or s == "right" then
            return RIGHT
        end

        if s == "l" or s == "left" then
            return LEFT
        end

        print("Enter R or L")
    end
end

local function nameContains(name, part)
    if not name then
        return false
    end

    return string.find(name, part, 1, true) ~= nil
end

local function getItemName(slot)
    local detail = turtle.getItemDetail(slot)
    if detail then
        return detail.name
    end

    return nil
end

local function isFluidName(name)
    return nameContains(name, "water") or nameContains(name, "lava")
end

local function isLavaName(name)
    return nameContains(name, "lava")
end

local function isChestItem(name)
    return nameContains(name, "chest")
end

local function isTorchItem(name)
    return nameContains(name, "torch")
end

local function isUtilityBlockName(name)
    return isChestItem(name) or isTorchItem(name)
end

local function findItemSlot(checkFn, preferredSlot)
    if preferredSlot and turtle.getItemCount(preferredSlot) > 0 then
        local name = getItemName(preferredSlot)

        if checkFn(name) then
            return preferredSlot
        end
    end

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local name = getItemName(slot)

            if checkFn(name) then
                return slot
            end
        end
    end

    return nil
end

local function isProtectedSlot(slot)
    if slot == SLOT_FUEL then
        return true
    end

    if slot == SLOT_FILL and turtle.getItemCount(slot) > 0 then
        return true
    end

    local name = getItemName(slot)

    if isChestItem(name) then
        return true
    end

    if isTorchItem(name) then
        return true
    end

    return false
end

local function countEmptyLootSlots()
    local empty = 0

    for slot = LOOT_FIRST, 16 do
        if not isProtectedSlot(slot) then
            if turtle.getItemCount(slot) == 0 then
                empty = empty + 1
            end
        end
    end

    return empty
end

local function initState()
    print("=== Snake Tunnel 3H ===")
    print("")
    print("Recommended slots:")
    print("1  = fuel")
    print("2  = torches")
    print("3  = chests")
    print("4  = filler blocks")
    print("5-16 = loot")
    print("")
    print("Turtle must stand at the middle height of tunnel.")
    print("")

    local len = askNumber("Length of one straight tunnel", 10, 1)
    local lanes = askNumber("How many straight lanes? 0 = infinite", 0, 0)
    local sideGap = askNumber("Side connector length between lanes", DEFAULT_SIDE_GAP, 1)
    local torchEvery = askNumber("Place torch every N blocks? 0 = disabled", DEFAULT_TORCH_EVERY, 0)
    local unloadEmpty = askNumber("Unload when empty loot slots are <= N", DEFAULT_UNLOAD_EMPTY, 1)
    local firstSide = askDirection()

    state = {
        len = len,
        lanes = lanes,
        sideGap = sideGap,
        torchEvery = torchEvery,
        unloadEmpty = unloadEmpty,

        row = 1,
        phase = "long",
        step = 0,

        side = firstSide,

        totalMoves = 0
    }

    save()
end

local function normalizeState()
    if not state.unloadEmpty then
        state.unloadEmpty = DEFAULT_UNLOAD_EMPTY
    end

    if not state.sideGap then
        state.sideGap = DEFAULT_SIDE_GAP
    end

    if not state.torchEvery then
        state.torchEvery = DEFAULT_TORCH_EVERY
    end

    if not state.totalMoves then
        state.totalMoves = 0
    end

    save()
end

local function isFuelUnlimited()
    return turtle.getFuelLevel() == "unlimited"
end

local function tryRefuelFromSlot(slot)
    if turtle.getItemCount(slot) <= 0 then
        return false
    end

    turtle.select(slot)

    if not turtle.refuel(0) then
        return false
    end

    turtle.refuel(1)
    return true
end

local function ensureFuel(need)
    if isFuelUnlimited() then
        return
    end

    if turtle.getFuelLevel() >= need then
        return
    end

    while turtle.getFuelLevel() < need do
        local didFuel = false

        if tryRefuelFromSlot(SLOT_FUEL) then
            didFuel = true
        else
            for slot = 1, 16 do
                if tryRefuelFromSlot(slot) then
                    didFuel = true
                    break
                end
            end
        end

        if not didFuel then
            stop("Not enough fuel. Put fuel in slot 1.")
        end
    end
end

local function turnSide(side)
    local ok, err

    if side == RIGHT then
        ok, err = turtle.turnRight()
    else
        ok, err = turtle.turnLeft()
    end

    if not ok then
        stop("Cannot turn: " .. tostring(err))
    end
end

local function needsUnload()
    local empty = countEmptyLootSlots()
    return empty <= state.unloadEmpty
end

local unloadToChest

local function ensureInventoryRoom()
    if needsUnload() and not isUnloading then
        unloadToChest()
    end
end

local function selectFillOrStop(reason)
    if turtle.getItemCount(SLOT_FILL) <= 0 then
        stop(reason .. ". No filler blocks in slot 4.")
    end

    turtle.select(SLOT_FILL)
end

local function sealFront(name)
    selectFillOrStop("Fluid detected in front: " .. tostring(name))

    local ok, err = turtle.place()

    if not ok then
        if isLavaName(name) then
            stop("Lava in front and cannot seal it: " .. tostring(err))
        else
            stop("Fluid in front and cannot seal it: " .. tostring(err))
        end
    end

    sleep(0.15)
end

local function sealUp(name)
    selectFillOrStop("Fluid detected above: " .. tostring(name))

    local ok, err = turtle.placeUp()

    if not ok then
        stop("Fluid above and cannot seal it: " .. tostring(err))
    end

    sleep(0.15)
end

local function sealDown(name)
    selectFillOrStop("Fluid detected below: " .. tostring(name))

    local ok, err = turtle.placeDown()

    if not ok then
        stop("Fluid below and cannot seal it: " .. tostring(err))
    end

    sleep(0.15)
end

local function clearFront()
    for _ = 1, MAX_DIG_RETRIES do
        local has, data = turtle.inspect()

        if not has then
            return
        end

        local name = data.name

        if isFluidName(name) then
            print("Fluid in front. Quick seal and pass...")

            selectFillOrStop("Fluid detected in front: " .. tostring(name))

            local placed, placeErr = turtle.place()
            if not placed then
                stop("Cannot place filler into fluid: " .. tostring(placeErr))
            end

            local dug, digErr = turtle.dig()
            if not dug then
                stop("Cannot dig temporary filler block: " .. tostring(digErr))
            end

            return
        end

        ensureInventoryRoom()

        local ok, err = turtle.dig()

        if not ok then
            turtle.attack()
            sleep(0.10)

            ok, err = turtle.dig()

            if not ok then
                stop("Cannot dig block in front: " .. tostring(name) .. " / " .. tostring(err))
            end
        end

        sleep(0.10)
    end

    stop("Too many blocks in front. Sand, gravel or fluid may be endless.")
end

local function clearUp()
    for _ = 1, MAX_DIG_RETRIES do
        local has, data = turtle.inspectUp()

        if not has then
            return
        end

        local name = data.name

        if isFluidName(name) then
            sealUp(name)
            return
        end

        ensureInventoryRoom()

        local ok, err = turtle.digUp()

        if not ok then
            turtle.attackUp()
            sleep(0.10)

            ok, err = turtle.digUp()

            if not ok then
                stop("Cannot dig block above: " .. tostring(name) .. " / " .. tostring(err))
            end
        end

        sleep(0.10)
    end

    stop("Too many falling blocks above.")
end

local function clearDown()
    for _ = 1, MAX_DIG_RETRIES do
        local has, data = turtle.inspectDown()

        if not has then
            return
        end

        local name = data.name

        if isFluidName(name) then
            sealDown(name)
            return
        end

        ensureInventoryRoom()

        local ok, err = turtle.digDown()

        if not ok then
            turtle.attackDown()
            sleep(0.10)

            ok, err = turtle.digDown()

            if not ok then
                stop("Cannot dig block below: " .. tostring(name) .. " / " .. tostring(err))
            end
        end

        sleep(0.10)
    end

    stop("Too many falling blocks below.")
end

local function clearColumn()
    clearUp()
    clearDown()
end

local function getTorchSide()
    if state.phase == "long" then
        return -state.side
    end

    return LEFT
end

local function getChestSide()
    if state.phase == "long" then
        return state.side
    end

    return RIGHT
end

local function carveSideNiche()
    for _ = 1, MAX_DIG_RETRIES do
        local has, data = turtle.inspect()

        if not has then
            return true
        end

        local name = data.name

        if isUtilityBlockName(name) then
            return false, "Niche already contains utility block"
        end

        if isFluidName(name) then
            sealFront(name)
            return false, "Fluid sealed, niche skipped"
        end

        local ok, err = turtle.dig()

        if not ok then
            return false, "Cannot dig side niche: " .. tostring(err)
        end

        sleep(0.10)
    end

    return false, "Too many falling blocks in side niche"
end

local function placeTorchInNiche()
    if state.torchEvery <= 0 then
        return
    end

    local torchSlot = findItemSlot(isTorchItem, SLOT_TORCH)

    if not torchSlot then
        return
    end

    local side = getTorchSide()

    turnSide(side)

    local ok = carveSideNiche()

    if ok then
        turtle.select(torchSlot)
        turtle.place()
    end

    turnSide(-side)
end

local function dropLootIntoChest()
    for slot = 1, 16 do
        if not isProtectedSlot(slot) then
            turtle.select(slot)

            if turtle.getItemCount(slot) > 0 then
                turtle.drop()
            end
        end
    end

    turtle.select(SLOT_FUEL)
end

local function selectChestOrStop()
    local chestSlot = findItemSlot(isChestItem, SLOT_CHEST)

    if not chestSlot then
        stop("No chests found. Put chests in slot 3.")
    end

    turtle.select(chestSlot)
end

local function tryUnloadOnSide(side)
    turnSide(side)

    local done = false
    local has, data = turtle.inspect()

    if has and isChestItem(data.name) then
        dropLootIntoChest()
        done = true

    elseif has and isUtilityBlockName(data.name) then
        done = false

    else
        local nicheOk = carveSideNiche()

        if nicheOk then
            selectChestOrStop()

            local placed, err = turtle.place()

            if placed then
                dropLootIntoChest()
                done = true
            else
                print("Chest place failed: " .. tostring(err))
                done = false
            end
        end
    end

    turnSide(-side)

    return done
end

unloadToChest = function()
    isUnloading = true

    print("Inventory is getting full.")
    print("Empty loot slots: " .. tostring(countEmptyLootSlots()))
    print("Trying to place chest...")

    local side = getChestSide()
    local ok = tryUnloadOnSide(side)

    if not ok then
        ok = tryUnloadOnSide(-side)
    end

    isUnloading = false

    if not ok then
        stop("Cannot place chest on either side. Check chests and side space.")
    end

    print("Unload complete.")
end

local function moveForwardOne()
    ensureFuel(2)

    if needsUnload() then
        unloadToChest()
    end

    clearFront()

    for _ = 1, 8 do
        local ok, err = turtle.forward()

        if ok then
            state.totalMoves = state.totalMoves + 1
            state.step = state.step + 1
            save()

            clearColumn()

            if needsUnload() then
                unloadToChest()
            end

            return
        end

        turtle.attack()
        clearFront()
        sleep(0.15)
    end

    stop("Cannot move forward. There may be a mob, fluid, bedrock or protected block.")
end

local function mineStep(allowTorch)
    moveForwardOne()

    if allowTorch and state.torchEvery > 0 then
        if state.step % state.torchEvery == 0 and state.step < state.len then
            placeTorchInNiche()
            save()
        end
    end
end

local function startConnector()
    print("Side connector: " .. tostring(state.sideGap) .. " blocks")

    turnSide(state.side)

    state.phase = "connector"
    state.step = 0

    save()
end

local function finishConnector()
    turnSide(state.side)

    state.side = -state.side
    state.row = state.row + 1
    state.phase = "long"
    state.step = 0

    save()

    print("New straight lane: " .. tostring(state.row))
end

local function printStatus()
    print("Saved progress found.")
    print("Continuing:")
    print("Lane: " .. tostring(state.row))
    print("Phase: " .. tostring(state.phase))
    print("Step: " .. tostring(state.step))
    print("Side connector length: " .. tostring(state.sideGap))
    print("Empty loot slots: " .. tostring(countEmptyLootSlots()))
    print("")
    print("To restart, stop with Ctrl+T and delete:")
    print("delete " .. STATE_FILE)
    print("")
end

local function main()
    state = loadState()

    if state then
        normalizeState()
        printStatus()
        sleep(2)
    else
        initState()
    end

    clearColumn()
    save()

    while true do
        if state.lanes > 0 and state.row > state.lanes then
            print("Done. All lanes mined.")
            fs.delete(STATE_FILE)
            return
        end

        if state.phase == "long" then
            if state.step < state.len then
                mineStep(true)
            else
                if state.lanes > 0 and state.row >= state.lanes then
                    print("Done. Last straight lane mined.")
                    fs.delete(STATE_FILE)
                    return
                end

                startConnector()
            end

        elseif state.phase == "connector" then
            if state.step < state.sideGap then
                mineStep(false)
            else
                finishConnector()
            end

        else
            stop("Unknown state phase: " .. tostring(state.phase))
        end
    end
end

main()
