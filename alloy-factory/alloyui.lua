-- ANDESITE ALLOY FACTORY UI
-- CC:Tweaked + Create Item Vaults + Redstone Relay line statuses
-- Storage nodes are neutral. Only production lines are colored by relay status.

local CONFIG = {
  monitor = "monitor_1",
  monitorScale = 0.5,
  updateInterval = 2,
  redstoneRelay = "redstone_relay_1",
  itemsPerVaultBlock = 1280,
  showDebugExtraItems = true,
}

local VAULTS = {
  rawCobble = { name = "create:item_vault_4", label = "Raw Cobble Vault", blocks = 6 * 2 * 2 },
  craftBuffer = { name = "create:item_vault_2", label = "Craft Buffer", blocks = 3 * 3 * 4 },
  diorite = { name = "create:item_vault_3", label = "Diorite Vault", blocks = 1 },
  alloy = { name = "create:item_vault_1", label = "Alloy Output", blocks = 1 * 3 },
}

local ID = {
  cobble = "minecraft:cobblestone",
  quartz = "minecraft:quartz",
  ironNugget = "minecraft:iron_nugget",
  diorite = "minecraft:diorite",
  alloy = "create:andesite_alloy",
}

-- Recipe chain:
-- 1 Alloy = 2 Andesite + 2 Iron Nuggets
-- 2 Andesite = 1 Cobblestone + 1 Diorite
-- 1 Diorite = 2 Cobblestone + 2 Quartz
-- Full chain: 1 Alloy = 3 Cobble + 2 Quartz + 2 Iron Nuggets
local LIMITS = {
  alloyStop = 1088,
  cobbleGeneratorStopRatio = 0.70,
  bufferCobbleMax = 18000,
  bufferQuartzMax = 12000,
  bufferIronMax = 12000,
  dioriteMax = 1280,
}

-- Redstone signal ON on this relay side means line is STOPPED.
-- Current wiring:
-- front = cobble line to main buffer
-- right = cobblestone generator / drills for raw cobble
-- top   = diorite + andesite alloy assembly after main buffer
-- back  = quartz generation line
-- left  = iron nuggets line
local LINE_INPUTS = {
  cobbleLine = "front",
  cobbleGenerator = "right",
  alloy = "top",
  dioriteLine = "top",
  quartzLine = "back",
  ironLine = "left",
}

local KNOWN_ITEMS = {
  [ID.cobble] = true,
  [ID.quartz] = true,
  [ID.ironNugget] = true,
  [ID.diorite] = true,
  [ID.alloy] = true,
}

for _, vault in pairs(VAULTS) do
  vault.capacity = vault.blocks * CONFIG.itemsPerVaultBlock
end

local RAW_COBBLE_STOP_LIMIT = math.floor(VAULTS.rawCobble.capacity * LIMITS.cobbleGeneratorStopRatio + 0.5)

local screen = term
local relay = nil

local function setupScreen()
  if CONFIG.monitor and peripheral.isPresent(CONFIG.monitor) then
    screen = peripheral.wrap(CONFIG.monitor)
    if screen.setTextScale then screen.setTextScale(CONFIG.monitorScale) end
  else
    screen = term
  end
end

local function setupRelay()
  if CONFIG.redstoneRelay and peripheral.isPresent(CONFIG.redstoneRelay) then
    relay = peripheral.wrap(CONFIG.redstoneRelay)
  else
    relay = nil
  end
end

local function clearScreen()
  screen.setBackgroundColor(colors.black)
  screen.setTextColor(colors.white)
  screen.clear()
  screen.setCursorPos(1, 1)
end

local function size()
  return screen.getSize()
end

local function clearLine(y)
  local w = ({ size() })[1]
  screen.setBackgroundColor(colors.black)
  screen.setCursorPos(1, y)
  screen.write(string.rep(" ", w))
end

local function writeAt(x, y, text, fg, bg)
  screen.setBackgroundColor(bg or colors.black)
  screen.setTextColor(fg or colors.white)
  screen.setCursorPos(x, y)
  screen.write(tostring(text))
  screen.setBackgroundColor(colors.black)
end

local function fmt(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

local function pct(value, maxValue)
  if not maxValue or maxValue <= 0 then return 0 end
  return math.floor(value / maxValue * 100 + 0.5)
end

local function fmtValue(value, maxValue)
  return fmt(value) .. "/" .. fmt(maxValue)
end

local function colorForStatus(status)
  if status == "RUNNING" then return colors.lime end
  if status == "STOPPED" then return colors.red end
  if status == "FULL" then return colors.red end
  if status == "HIGH" then return colors.orange end
  if status == "LOW" then return colors.lightBlue end
  if status == "WAITING" then return colors.orange end
  if status == "OFFLINE" then return colors.gray end
  if status == "OK" then return colors.lime end
  return colors.white
end

local function statusByFill(value, maxValue)
  if not maxValue or maxValue <= 0 then return "OK" end
  local r = value / maxValue
  if r >= 1.00 then return "FULL" end
  if r >= 0.85 then return "HIGH" end
  if r <= 0.15 then return "LOW" end
  return "OK"
end

local function drawSolidBar(x, y, width, value, maxValue, fillColor)
  if width <= 0 then return end
  local ratio = 0
  if maxValue and maxValue > 0 then ratio = math.min(value / maxValue, 1) end
  local filled = math.floor(width * ratio + 0.5)
  local empty = width - filled

  screen.setCursorPos(x, y)
  screen.setBackgroundColor(fillColor or colors.green)
  screen.write(string.rep(" ", filled))
  screen.setBackgroundColor(colors.gray)
  screen.write(string.rep(" ", empty))
  screen.setBackgroundColor(colors.black)
end

local function drawTitle(y, title)
  clearLine(y)
  writeAt(2, y, title, colors.yellow)
end

local function drawLineMeter(y, label, status, value, maxValue)
  local w = ({ size() })[1]
  local statusColor = colorForStatus(status)
  local valueX = math.max(62, w - 17)
  local barX = 37
  local barW = valueX - barX - 2
  if barW < 8 then barW = 8 end

  clearLine(y)
  writeAt(2, y, string.sub(label, 1, 22), colors.white)
  writeAt(26, y, string.format("%-8s", status), statusColor)
  drawSolidBar(barX, y, barW, value, maxValue, statusColor)
  writeAt(valueX, y, fmtValue(value, maxValue), statusColor)
end

local function drawStorageMeter(y, label, value, maxValue, fillColor)
  local w = ({ size() })[1]
  local valueX = math.max(62, w - 17)
  local barX = 37
  local barW = valueX - barX - 2
  if barW < 8 then barW = 8 end

  clearLine(y)
  writeAt(2, y, string.sub(label, 1, 22), colors.white)
  writeAt(26, y, string.format("%3d%%", pct(value, maxValue)), colors.lightGray)
  drawSolidBar(barX, y, barW, value, maxValue, fillColor or colors.lightGray)
  writeAt(valueX, y, fmtValue(value, maxValue), colors.lightGray)
end

local function drawStorageBox(x, y, text)
  writeAt(x, y, " " .. text .. " ", colors.black, colors.lightGray)
end

local function drawLineBox(x, y, text, status)
  writeAt(x, y, " " .. text .. " ", colors.black, colorForStatus(status))
end

local function readVault(vault)
  local data = {
    ok = false,
    name = vault.name,
    label = vault.label,
    capacity = vault.capacity,
    total = 0,
    items = {},
    error = nil,
  }

  if not peripheral.isPresent(vault.name) then
    data.error = "not connected"
    return data
  end

  local inv = peripheral.wrap(vault.name)
  if not inv or not inv.list then
    data.error = "not inventory"
    return data
  end

  local ok, list = pcall(function() return inv.list() end)
  if not ok or not list then
    data.error = "cannot read"
    return data
  end

  for _, item in pairs(list) do
    local id = item.name
    local count = item.count or 0
    data.items[id] = (data.items[id] or 0) + count
    data.total = data.total + count
  end

  data.ok = true
  return data
end

local function countItem(vaultData, itemId)
  if not vaultData or not vaultData.items then return 0 end
  return vaultData.items[itemId] or 0
end

local function relaySignal(side)
  if not relay or not side then return false end
  local ok, value = pcall(function() return relay.getInput(side) end)
  return ok and value == true
end

local function lineStatus(key)
  if not relay then return "OFFLINE" end
  local side = LINE_INPUTS[key]
  if not side then return "OFFLINE" end
  if relaySignal(side) then return "STOPPED" end
  return "RUNNING"
end

local function possibleReadyAlloy(bufferCobble, diorite, ironNugget)
  return math.min(math.floor(bufferCobble), math.floor(diorite), math.floor(ironNugget / 2))
end

local function possibleFullChainAlloy(bufferCobble, quartz, ironNugget)
  return math.min(math.floor(bufferCobble / 3), math.floor(quartz / 2), math.floor(ironNugget / 2))
end

local function bottleneck(bufferCobble, quartz, ironNugget)
  local byCobble = math.floor(bufferCobble / 3)
  local byQuartz = math.floor(quartz / 2)
  local byIron = math.floor(ironNugget / 2)
  local m = math.min(byCobble, byQuartz, byIron)
  if m == byCobble then return "COBBLE" end
  if m == byQuartz then return "QUARTZ" end
  return "IRON NUGGET"
end

local function getOverall(alloyLine, genLine, cobbleLine, quartzLine, ironLine, need)
  if not relay then return "RELAY OFFLINE" end
  if alloyLine == "STOPPED" then return "ALLOY / DIORITE STOPPED" end
  if genLine == "STOPPED" then return "COBBLE GENERATOR STOPPED" end
  if cobbleLine == "STOPPED" then return "COBBLE LINE STOPPED" end
  if quartzLine == "STOPPED" then return "QUARTZ LINE STOPPED" end
  if ironLine == "STOPPED" then return "IRON LINE STOPPED" end
  if need == "IRON NUGGET" then return "NEEDS IRON" end
  if need == "QUARTZ" then return "NEEDS QUARTZ" end
  if need == "COBBLE" then return "NEEDS COBBLE" end
  return "RUNNING"
end

local function drawFlowMap(y, s)
  for i = 0, 8 do clearLine(y + i) end

  drawLineBox(37, y, "COBBLE GENERATOR", s.generator)
  writeAt(46, y + 1, "v", colors.gray)
  drawStorageBox(39, y + 2, "RAW COBBLE")

  writeAt(18, y + 3, "/", colors.gray)
  writeAt(47, y + 3, "|", colors.gray)
  writeAt(75, y + 3, "\\", colors.gray)

  drawLineBox(3, y + 4, "IRON NUGGETS LINE", s.iron)
  drawLineBox(35, y + 4, "QUARTZ GENERATION", s.quartz)
  drawLineBox(66, y + 4, "COBBLE TO BUFFER", s.cobble)

  writeAt(22, y + 5, "\\", colors.gray)
  writeAt(47, y + 5, "|", colors.gray)
  writeAt(73, y + 5, "/", colors.gray)

  drawStorageBox(35, y + 6, "MAIN BUFFER")

  writeAt(37, y + 7, "/", colors.gray)
  writeAt(57, y + 7, "\\", colors.gray)

  drawLineBox(14, y + 8, "DIORITE LINE", s.diorite)
  writeAt(31, y + 8, "---------->", colors.gray)
  drawLineBox(45, y + 8, "ANDESITE ALLOY", s.alloy)
  writeAt(64, y + 8, "->", colors.gray)
  drawStorageBox(68, y + 8, "OUTPUT")

  return y + 9
end

local function drawDebugVault(y, vault)
  local h = ({ size() })[2]
  if y > h then return y end

  local extras = {}
  for id, count in pairs(vault.items or {}) do
    if not KNOWN_ITEMS[id] then table.insert(extras, { id = id, count = count }) end
  end
  if #extras == 0 then return y end
  table.sort(extras, function(a, b) return a.count > b.count end)

  clearLine(y)
  writeAt(2, y, vault.label .. ": extra items", colors.orange)
  y = y + 1
  for i = 1, math.min(#extras, 4) do
    if y > h then break end
    clearLine(y)
    writeAt(4, y, string.sub(extras[i].id, 1, 42), colors.gray)
    writeAt(50, y, fmt(extras[i].count), colors.lightBlue)
    y = y + 1
  end
  return y
end

local function drawDashboard()
  setupRelay()

  local raw = readVault(VAULTS.rawCobble)
  local buffer = readVault(VAULTS.craftBuffer)
  local dioriteVault = readVault(VAULTS.diorite)
  local alloyVault = readVault(VAULTS.alloy)

  local rawCobble = countItem(raw, ID.cobble)
  local bufferCobble = countItem(buffer, ID.cobble)
  local bufferQuartz = countItem(buffer, ID.quartz)
  local bufferIron = countItem(buffer, ID.ironNugget)
  local diorite = countItem(dioriteVault, ID.diorite)
  local alloy = countItem(alloyVault, ID.alloy)

  local readyAlloy = possibleReadyAlloy(bufferCobble, diorite, bufferIron)
  local fullChainAlloy = possibleFullChainAlloy(bufferCobble, bufferQuartz, bufferIron)
  local need = bottleneck(bufferCobble, bufferQuartz, bufferIron)

  local alloyLine = lineStatus("alloy")
  local generatorLine = lineStatus("cobbleGenerator")
  local cobbleLine = lineStatus("cobbleLine")
  local quartzLine = lineStatus("quartzLine")
  local ironLine = lineStatus("ironLine")
  local dioriteLine = lineStatus("dioriteLine")

  local state = getOverall(alloyLine, generatorLine, cobbleLine, quartzLine, ironLine, need)

  clearScreen()
  local w, h = size()
  local timeText = textutils.formatTime(os.time(), true)

  writeAt(2, 1, "ANDESITE ALLOY FACTORY", colors.cyan)
  writeAt(math.max(2, w - #timeText - 1), 1, timeText, colors.gray)
  writeAt(2, 2, "Status:", colors.white)
  writeAt(11, 2, state, state == "RUNNING" and colors.lime or colors.orange)
  writeAt(2, 3, "Recipe: 3 Cobble + 2 Quartz + 2 Iron Nugget = 1 Alloy", colors.gray)
  writeAt(2, 4, "Relay: " .. (relay and CONFIG.redstoneRelay or "not connected"), relay and colors.green or colors.red)

  local y = 6
  drawTitle(y, "FLOW MAP")
  y = y + 1
  y = drawFlowMap(y, {
    generator = generatorLine,
    cobble = cobbleLine,
    quartz = quartzLine,
    iron = ironLine,
    diorite = dioriteLine,
    alloy = alloyLine,
  })
  y = y + 1

  drawTitle(y, "PRODUCTION LINES - REAL RELAY SIGNALS")
  y = y + 1
  drawLineMeter(y, "Andesite Alloy", alloyLine, alloy, LIMITS.alloyStop); y = y + 1
  drawLineMeter(y, "Cobblestone Generator", generatorLine, rawCobble, RAW_COBBLE_STOP_LIMIT); y = y + 1
  drawLineMeter(y, "Cobble Line", cobbleLine, bufferCobble, LIMITS.bufferCobbleMax); y = y + 1
  drawLineMeter(y, "Quartz Line", quartzLine, bufferQuartz, LIMITS.bufferQuartzMax); y = y + 1
  drawLineMeter(y, "Iron Line", ironLine, bufferIron, LIMITS.bufferIronMax); y = y + 1
  drawLineMeter(y, "Diorite Line", dioriteLine, diorite, LIMITS.dioriteMax); y = y + 2

  drawTitle(y, "MAIN PRODUCT")
  y = y + 1
  drawStorageMeter(y, "Alloy Ready", alloy, LIMITS.alloyStop, colors.cyan); y = y + 1
  clearLine(y)
  writeAt(2, y, "Can craft now:", colors.white)
  writeAt(18, y, fmt(readyAlloy), colors.lime)
  writeAt(32, y, "Full chain:", colors.white)
  writeAt(45, y, fmt(fullChainAlloy), colors.lightBlue)
  writeAt(58, y, "Bottleneck:", colors.white)
  writeAt(70, y, need, colors.orange)
  y = y + 2

  drawTitle(y, "VAULTS")
  y = y + 1
  drawStorageMeter(y, VAULTS.rawCobble.label, raw.total, raw.capacity, colors.lightGray); y = y + 1
  drawStorageMeter(y, VAULTS.craftBuffer.label, buffer.total, buffer.capacity, colors.lightGray); y = y + 1
  drawStorageMeter(y, VAULTS.diorite.label, dioriteVault.total, dioriteVault.capacity, colors.lightGray); y = y + 1
  drawStorageMeter(y, VAULTS.alloy.label, alloyVault.total, alloyVault.capacity, colors.lightGray); y = y + 2

  drawTitle(y, "BUFFER CONTENT")
  y = y + 1
  drawStorageMeter(y, "Cobble", bufferCobble, LIMITS.bufferCobbleMax, colors.lightBlue); y = y + 1
  drawStorageMeter(y, "Quartz", bufferQuartz, LIMITS.bufferQuartzMax, colors.purple); y = y + 1
  drawStorageMeter(y, "Iron Nugget", bufferIron, LIMITS.bufferIronMax, colors.orange); y = y + 2

  if CONFIG.showDebugExtraItems and y <= h - 2 then
    local oldY = y
    y = drawDebugVault(y, raw)
    y = drawDebugVault(y, buffer)
    y = drawDebugVault(y, dioriteVault)
    y = drawDebugVault(y, alloyVault)
    if y ~= oldY then
      writeAt(2, oldY - 1, "DEBUG: EXTRA ITEMS", colors.yellow)
    end
  end

  local errors = {}
  if not raw.ok then table.insert(errors, raw.name .. " " .. tostring(raw.error)) end
  if not buffer.ok then table.insert(errors, buffer.name .. " " .. tostring(buffer.error)) end
  if not dioriteVault.ok then table.insert(errors, dioriteVault.name .. " " .. tostring(dioriteVault.error)) end
  if not alloyVault.ok then table.insert(errors, alloyVault.name .. " " .. tostring(alloyVault.error)) end

  clearLine(h)
  if #errors > 0 then
    writeAt(2, h, "ERROR: " .. errors[1], colors.red)
  elseif not relay then
    writeAt(2, h, "ERROR: Relay not connected. Expected " .. CONFIG.redstoneRelay, colors.red)
  else
    writeAt(2, h, "All vaults connected | Storages neutral | Line status = relay signals", colors.green)
  end
end

setupScreen()

while true do
  local ok, err = pcall(drawDashboard)
  if not ok then
    clearScreen()
    writeAt(2, 1, "DASHBOARD ERROR", colors.red)
    writeAt(2, 3, tostring(err), colors.white)
  end
  sleep(CONFIG.updateInterval)
end
