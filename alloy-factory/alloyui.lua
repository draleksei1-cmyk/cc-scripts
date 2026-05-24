-- ANDESITE ALLOY FACTORY UI
-- CC:Tweaked + Create Item Vaults + Redstone Relay line statuses
-- Dual monitor layout:
--   monitor_6 = FLOW MAP
--   monitor_5 = MAIN DASHBOARD
-- Storage nodes are neutral. Only production lines are colored by relay status.

local CONFIG = {
  mapMonitor = "monitor_6",
  mainMonitor = "monitor_5",
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

local mainScreen = term
local mapScreen = nil
local screen = term
local relay = nil

------------------------------------------------------------
-- SCREEN SETUP
------------------------------------------------------------

local function wrapMonitor(name)
  if name and peripheral.isPresent(name) then
    local p = peripheral.wrap(name)
    if p and p.setTextScale then p.setTextScale(CONFIG.monitorScale) end
    return p
  end
  return nil
end

local function setupScreens()
  mainScreen = wrapMonitor(CONFIG.mainMonitor) or term
  mapScreen = wrapMonitor(CONFIG.mapMonitor)
  screen = mainScreen
end

local function useScreen(target)
  screen = target or mainScreen or term
end

local function setupRelay()
  if CONFIG.redstoneRelay and peripheral.isPresent(CONFIG.redstoneRelay) then
    relay = peripheral.wrap(CONFIG.redstoneRelay)
  else
    relay = nil
  end
end

local function size()
  return screen.getSize()
end

local function clearScreen()
  screen.setBackgroundColor(colors.black)
  screen.setTextColor(colors.white)
  screen.clear()
  screen.setCursorPos(1, 1)
end

local function clearLine(y)
  local w = ({ size() })[1]
  screen.setBackgroundColor(colors.black)
  screen.setCursorPos(1, y)
  screen.write(string.rep(" ", w))
end

local function writeAt(x, y, text, fg, bg)
  local w, h = size()
  if x < 1 or y < 1 or x > w or y > h then return end
  local s = tostring(text)
  if x + #s - 1 > w then s = string.sub(s, 1, w - x + 1) end
  screen.setBackgroundColor(bg or colors.black)
  screen.setTextColor(fg or colors.white)
  screen.setCursorPos(x, y)
  screen.write(s)
  screen.setBackgroundColor(colors.black)
end

------------------------------------------------------------
-- FORMAT / COLORS
------------------------------------------------------------

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

------------------------------------------------------------
-- DATA
------------------------------------------------------------

local function readVault(vault)
  local data = { ok = false, name = vault.name, label = vault.label, capacity = vault.capacity, total = 0, items = {}, error = nil }

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

local function buildData()
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

  local lines = {
    alloy = lineStatus("alloy"),
    generator = lineStatus("cobbleGenerator"),
    cobble = lineStatus("cobbleLine"),
    quartz = lineStatus("quartzLine"),
    iron = lineStatus("ironLine"),
    diorite = lineStatus("dioriteLine"),
  }

  local need = bottleneck(bufferCobble, bufferQuartz, bufferIron)

  return {
    raw = raw,
    buffer = buffer,
    dioriteVault = dioriteVault,
    alloyVault = alloyVault,
    rawCobble = rawCobble,
    bufferCobble = bufferCobble,
    bufferQuartz = bufferQuartz,
    bufferIron = bufferIron,
    diorite = diorite,
    alloy = alloy,
    readyAlloy = possibleReadyAlloy(bufferCobble, diorite, bufferIron),
    fullChainAlloy = possibleFullChainAlloy(bufferCobble, bufferQuartz, bufferIron),
    bottleneck = need,
    lines = lines,
    state = getOverall(lines.alloy, lines.generator, lines.cobble, lines.quartz, lines.iron, need),
  }
end

------------------------------------------------------------
-- MAP SCREEN
------------------------------------------------------------

local function fillRect(x, y, w, h, bg)
  local sw, sh = size()
  if w <= 0 or h <= 0 then return end
  local line = string.rep(" ", w)
  screen.setBackgroundColor(bg)
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= sh and x <= sw then
      screen.setCursorPos(math.max(1, x), yy)
      screen.write(string.sub(line, 1, math.min(w, sw - x + 1)))
    end
  end
  screen.setBackgroundColor(colors.black)
end

local function centerInBox(x, y, w, text, fg, bg)
  local s = tostring(text)
  if #s > w then s = string.sub(s, 1, w) end
  local tx = x + math.floor((w - #s) / 2)
  writeAt(tx, y, s, fg, bg)
end

local function drawCard(x, y, w, h, title, subtitle, isLine, status)
  local bg = isLine and colorForStatus(status) or colors.gray
  local fg = colors.black
  fillRect(x, y, w, h, bg)
  centerInBox(x, y + 1, w, title, fg, bg)
  if subtitle and h >= 4 then
    centerInBox(x, y + 2, w, subtitle, fg, bg)
  elseif subtitle and h >= 3 then
    centerInBox(x, y + 2, w, subtitle, fg, bg)
  end
end

local function hLine(x1, x2, y)
  if x2 < x1 then x1, x2 = x2, x1 end
  for x = x1, x2 do writeAt(x, y, "-", colors.gray) end
end

local function vLine(x, y1, y2)
  if y2 < y1 then y1, y2 = y2, y1 end
  for y = y1, y2 do writeAt(x, y, "|", colors.gray) end
end

local function nodeCenter(x, w)
  return x + math.floor(w / 2)
end

local function drawMapScreen(d)
  if not mapScreen then return end
  useScreen(mapScreen)
  clearScreen()

  local w, h = size()
  local cardW = math.max(12, math.min(20, math.floor(w / 5)))
  local cardH = 3
  local cx = math.floor(w / 2)

  writeAt(2, 1, "FLOW MAP", colors.yellow)
  writeAt(math.max(2, w - #d.state - 1), 1, d.state, d.state == "RUNNING" and colors.lime or colors.orange)

  local topY = math.max(3, math.floor((h - 25) / 2) + 2)
  local yGen = topY
  local yRaw = topY + 5
  local yLines = topY + 10
  local yBuffer = topY + 15
  local yFinal = topY + 20

  local xGen = cx - math.floor(cardW / 2)
  local xRaw = xGen
  local xIron = 4
  local xQuartz = cx - math.floor(cardW / 2)
  local xCobble = w - cardW - 4
  local xBuffer = xRaw
  local xDiorite = math.max(4, cx - cardW - 14)
  local xAlloy = math.min(w - cardW - 18, cx + 5)
  local xOutput = w - cardW - 4

  local cGen = nodeCenter(xGen, cardW)
  local cRaw = nodeCenter(xRaw, cardW)
  local cIron = nodeCenter(xIron, cardW)
  local cQuartz = nodeCenter(xQuartz, cardW)
  local cCobble = nodeCenter(xCobble, cardW)
  local cBuffer = nodeCenter(xBuffer, cardW)
  local cDiorite = nodeCenter(xDiorite, cardW)
  local cAlloy = nodeCenter(xAlloy, cardW)
  local cOutput = nodeCenter(xOutput, cardW)

  drawCard(xGen, yGen, cardW, cardH, "COBBLE", "GENERATOR", true, d.lines.generator)
  vLine(cGen, yGen + cardH, yRaw - 1)
  writeAt(cRaw, yRaw - 1, "v", colors.gray)
  drawCard(xRaw, yRaw, cardW, cardH, "RAW", "COBBLE", false)

  local busY1 = yRaw + cardH + 1
  vLine(cRaw, yRaw + cardH, busY1)
  hLine(cIron, cCobble, busY1)
  vLine(cIron, busY1, yLines - 1)
  vLine(cQuartz, busY1, yLines - 1)
  vLine(cCobble, busY1, yLines - 1)
  writeAt(cIron, yLines - 1, "v", colors.gray)
  writeAt(cQuartz, yLines - 1, "v", colors.gray)
  writeAt(cCobble, yLines - 1, "v", colors.gray)

  drawCard(xIron, yLines, cardW, cardH, "IRON", "NUGGETS", true, d.lines.iron)
  drawCard(xQuartz, yLines, cardW, cardH, "QUARTZ", "LINE", true, d.lines.quartz)
  drawCard(xCobble, yLines, cardW, cardH, "COBBLE", "FEED", true, d.lines.cobble)

  local busY2 = yLines + cardH + 1
  vLine(cIron, yLines + cardH, busY2)
  vLine(cQuartz, yLines + cardH, busY2)
  vLine(cCobble, yLines + cardH, busY2)
  hLine(cIron, cCobble, busY2)
  vLine(cBuffer, busY2, yBuffer - 1)
  writeAt(cBuffer, yBuffer - 1, "v", colors.gray)
  drawCard(xBuffer, yBuffer, cardW, cardH, "MAIN", "BUFFER", false)

  local busY3 = yBuffer + cardH + 1
  vLine(cBuffer, yBuffer + cardH, busY3)
  hLine(cDiorite, cAlloy, busY3)
  vLine(cDiorite, busY3, yFinal - 1)
  vLine(cAlloy, busY3, yFinal - 1)
  writeAt(cDiorite, yFinal - 1, "v", colors.gray)
  writeAt(cAlloy, yFinal - 1, "v", colors.gray)

  drawCard(xDiorite, yFinal, cardW, cardH, "DIORITE", "LINE", true, d.lines.diorite)
  drawCard(xAlloy, yFinal, cardW, cardH, "ALLOY", "LINE", true, d.lines.alloy)
  drawCard(xOutput, yFinal, cardW, cardH, "OUTPUT", "VAULT", false)

  hLine(xDiorite + cardW, xAlloy - 1, yFinal + 1)
  writeAt(xAlloy - 1, yFinal + 1, ">", colors.gray)
  hLine(xAlloy + cardW, xOutput - 1, yFinal + 1)
  writeAt(xOutput - 1, yFinal + 1, ">", colors.gray)

  local legendY = h - 3
  if legendY > yFinal + cardH + 1 then
    drawCard(2, legendY, 11, 2, "RUN", nil, true, "RUNNING")
    drawCard(16, legendY, 12, 2, "STOP", nil, true, "STOPPED")
    drawCard(31, legendY, 14, 2, "STORAGE", nil, false)
  end
end

------------------------------------------------------------
-- MAIN DASHBOARD SCREEN
------------------------------------------------------------

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

local function drawMainScreen(d)
  useScreen(mainScreen)
  clearScreen()
  local w, h = size()
  local timeText = textutils.formatTime(os.time(), true)

  writeAt(2, 1, "ANDESITE ALLOY FACTORY", colors.cyan)
  writeAt(math.max(2, w - #timeText - 1), 1, timeText, colors.gray)
  writeAt(2, 2, "Status:", colors.white)
  writeAt(11, 2, d.state, d.state == "RUNNING" and colors.lime or colors.orange)
  writeAt(2, 3, "Recipe: 3 Cobble + 2 Quartz + 2 Iron Nugget = 1 Alloy", colors.gray)
  writeAt(2, 4, "Relay: " .. (relay and CONFIG.redstoneRelay or "not connected"), relay and colors.green or colors.red)

  local y = 6

  drawTitle(y, "PRODUCTION LINES - RELAY SIGNALS")
  y = y + 1
  drawLineMeter(y, "Andesite Alloy", d.lines.alloy, d.alloy, LIMITS.alloyStop); y = y + 1
  drawLineMeter(y, "Cobblestone Generator", d.lines.generator, d.rawCobble, RAW_COBBLE_STOP_LIMIT); y = y + 1
  drawLineMeter(y, "Cobble Line", d.lines.cobble, d.bufferCobble, LIMITS.bufferCobbleMax); y = y + 1
  drawLineMeter(y, "Quartz Line", d.lines.quartz, d.bufferQuartz, LIMITS.bufferQuartzMax); y = y + 1
  drawLineMeter(y, "Iron Line", d.lines.iron, d.bufferIron, LIMITS.bufferIronMax); y = y + 1
  drawLineMeter(y, "Diorite Line", d.lines.diorite, d.diorite, LIMITS.dioriteMax); y = y + 2

  drawTitle(y, "MAIN PRODUCT")
  y = y + 1
  drawStorageMeter(y, "Alloy Ready", d.alloy, LIMITS.alloyStop, colors.cyan); y = y + 1
  clearLine(y)
  writeAt(2, y, "Can craft now:", colors.white)
  writeAt(18, y, fmt(d.readyAlloy), colors.lime)
  writeAt(32, y, "Full chain:", colors.white)
  writeAt(45, y, fmt(d.fullChainAlloy), colors.lightBlue)
  writeAt(58, y, "Bottleneck:", colors.white)
  writeAt(70, y, d.bottleneck, colors.orange)
  y = y + 2

  drawTitle(y, "VAULTS")
  y = y + 1
  drawStorageMeter(y, VAULTS.rawCobble.label, d.raw.total, d.raw.capacity, colors.lightGray); y = y + 1
  drawStorageMeter(y, VAULTS.craftBuffer.label, d.buffer.total, d.buffer.capacity, colors.lightGray); y = y + 1
  drawStorageMeter(y, VAULTS.diorite.label, d.dioriteVault.total, d.dioriteVault.capacity, colors.lightGray); y = y + 1
  drawStorageMeter(y, VAULTS.alloy.label, d.alloyVault.total, d.alloyVault.capacity, colors.lightGray); y = y + 2

  drawTitle(y, "BUFFER CONTENT")
  y = y + 1
  drawStorageMeter(y, "Cobble", d.bufferCobble, LIMITS.bufferCobbleMax, colors.lightBlue); y = y + 1
  drawStorageMeter(y, "Quartz", d.bufferQuartz, LIMITS.bufferQuartzMax, colors.purple); y = y + 1
  drawStorageMeter(y, "Iron Nugget", d.bufferIron, LIMITS.bufferIronMax, colors.orange); y = y + 2

  if CONFIG.showDebugExtraItems and y <= h - 2 then
    local oldY = y
    y = drawDebugVault(y, d.raw)
    y = drawDebugVault(y, d.buffer)
    y = drawDebugVault(y, d.dioriteVault)
    y = drawDebugVault(y, d.alloyVault)
    if y ~= oldY then writeAt(2, oldY - 1, "DEBUG: EXTRA ITEMS", colors.yellow) end
  end

  local errors = {}
  if not d.raw.ok then table.insert(errors, d.raw.name .. " " .. tostring(d.raw.error)) end
  if not d.buffer.ok then table.insert(errors, d.buffer.name .. " " .. tostring(d.buffer.error)) end
  if not d.dioriteVault.ok then table.insert(errors, d.dioriteVault.name .. " " .. tostring(d.dioriteVault.error)) end
  if not d.alloyVault.ok then table.insert(errors, d.alloyVault.name .. " " .. tostring(d.alloyVault.error)) end

  clearLine(h)
  if #errors > 0 then
    writeAt(2, h, "ERROR: " .. errors[1], colors.red)
  elseif not relay then
    writeAt(2, h, "ERROR: Relay not connected. Expected " .. CONFIG.redstoneRelay, colors.red)
  else
    writeAt(2, h, "All vaults connected | Main: " .. CONFIG.mainMonitor .. " | Map: " .. CONFIG.mapMonitor, colors.green)
  end
end

------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

setupScreens()

while true do
  local ok, err = pcall(function()
    local d = buildData()
    drawMapScreen(d)
    drawMainScreen(d)
  end)

  if not ok then
    useScreen(mainScreen)
    clearScreen()
    writeAt(2, 1, "DASHBOARD ERROR", colors.red)
    writeAt(2, 3, tostring(err), colors.white)
  end

  sleep(CONFIG.updateInterval)
end
