-- ANDESITE ALLOY FACTORY UI
-- CC:Tweaked + Create Item Vaults + optional Redstone Relay
-- Minecraft 1.21.1 friendly. English labels only to avoid terminal encoding issues.

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local CONFIG = {
  monitor = "monitor_1",
  monitorScale = 0.5,
  updateInterval = 2,

  -- Optional. If connected, this reads real stop signals from Create Redstone Link receivers.
  -- Put duplicated Create Redstone Link receivers near the relay with the same frequencies as your line stops.
  redstoneRelay = "redstone_relay_0",
  useRelayInputs = true,

  -- Create Item Vault capacity. Default Create value: 1 vault block = 20 stacks = 1280 items.
  itemsPerVaultBlock = 1280,

  -- Rates are calculated from storage changes over this window.
  rateWindowSeconds = 60,
  showDebugExtraItems = true,
}

local VAULTS = {
  rawCobble = {
    name = "create:item_vault_4",
    label = "Raw Cobble Vault",
    blocks = 6 * 2 * 2,
  },
  craftBuffer = {
    name = "create:item_vault_2",
    label = "Craft Buffer",
    blocks = 3 * 3 * 4,
  },
  diorite = {
    name = "create:item_vault_3",
    label = "Diorite Vault",
    blocks = 1,
  },
  alloy = {
    name = "create:item_vault_1",
    label = "Alloy Output",
    blocks = 1 * 3,
  },
}

local ID = {
  cobble = "minecraft:cobblestone",
  quartz = "minecraft:quartz",
  ironNugget = "minecraft:iron_nugget",
  diorite = "minecraft:diorite",
  alloy = "create:andesite_alloy",
}

-- Recipe chain:
-- 1 Andesite Alloy = 2 Andesite + 2 Iron Nuggets
-- 2 Andesite      = 1 Cobblestone + 1 Diorite
-- 1 Diorite       = 2 Cobblestone + 2 Quartz
-- Full chain: 1 Alloy = 3 Cobble + 2 Quartz + 2 Iron Nuggets
local LIMITS = {
  alloyStop = 1088,

  -- Raw cobble vault is 30720 items. 70% = 21504 items = 336 stacks.
  cobbleGeneratorStopRatio = 0.70,

  -- Craft buffer balance. Ratio 3 : 2 : 2.
  bufferCobbleMax = 18000,
  bufferQuartzMax = 12000,
  bufferIronMax = 12000,

  dioriteMax = 1280,
}

-- Mapping for Redstone Relay inputs.
-- If a side receives redstone, the line is displayed as STOPPED.
-- Edit these sides to match how you wire your Redstone Relay.
local LINE_INPUTS = {
  alloy = "right",
  cobbleGenerator = "left",
  cobbleLine = "front",
  quartzLine = "back",
  ironLine = "top",
  dioriteLine = "bottom",
}

local KNOWN_ITEMS = {
  [ID.cobble] = true,
  [ID.quartz] = true,
  [ID.ironNugget] = true,
  [ID.diorite] = true,
  [ID.alloy] = true,
}

------------------------------------------------------------
-- DERIVED VALUES
------------------------------------------------------------

for _, vault in pairs(VAULTS) do
  vault.capacity = vault.blocks * CONFIG.itemsPerVaultBlock
  vault.stacks = vault.capacity / 64
end

local RAW_COBBLE_STOP_LIMIT = math.floor(
  VAULTS.rawCobble.capacity * LIMITS.cobbleGeneratorStopRatio + 0.5
)

------------------------------------------------------------
-- SCREEN HELPERS
------------------------------------------------------------

local screen = term
local screenName = "terminal"

local function setupScreen()
  if CONFIG.monitor and peripheral.isPresent(CONFIG.monitor) then
    screen = peripheral.wrap(CONFIG.monitor)
    if screen.setTextScale then screen.setTextScale(CONFIG.monitorScale) end
    screenName = CONFIG.monitor
  else
    screen = term
    screenName = "terminal"
  end
end

local function clearScreen()
  screen.setBackgroundColor(colors.black)
  screen.setTextColor(colors.white)
  screen.clear()
  screen.setCursorPos(1, 1)
end

local function clearLine(y)
  local w, _ = screen.getSize()
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
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 10000 then
    return string.format("%.1fk", n / 1000)
  else
    return tostring(math.floor(n + 0.5))
  end
end

local function fmtValue(value, maxValue)
  return fmt(value) .. "/" .. fmt(maxValue)
end

local function nowSeconds()
  if os.epoch then
    return os.epoch("utc") / 1000
  end
  return os.clock()
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
  if maxValue and maxValue > 0 then
    ratio = math.min(value / maxValue, 1)
  end

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

local function drawMeterLine(y, label, status, value, maxValue, barColor, rightText)
  local w, _ = screen.getSize()

  local labelX = 2
  local statusX = 26
  local barX = 37
  local valueX = math.max(62, w - 24)
  local barW = valueX - barX - 2
  if barW < 8 then barW = 8 end

  local color = colorForStatus(status)

  clearLine(y)
  writeAt(labelX, y, string.sub(label, 1, 22), colors.white)
  writeAt(statusX, y, string.format("%-8s", status), color)
  drawSolidBar(barX, y, barW, value, maxValue, barColor or color)
  writeAt(valueX, y, string.format("%-14s", fmtValue(value, maxValue)), color)

  if rightText then
    writeAt(math.min(w - #rightText + 1, valueX + 15), y, rightText, colors.gray)
  end
end

local function drawSmallBox(x, y, text, status)
  local bg = colorForStatus(status)
  local fg = colors.black
  local label = " " .. text .. " "
  writeAt(x, y, label, fg, bg)
end

------------------------------------------------------------
-- VAULT READING
------------------------------------------------------------

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

------------------------------------------------------------
-- RATES
------------------------------------------------------------

local rateHistory = {}

local function updateRate(key, value)
  local t = nowSeconds()
  local hist = rateHistory[key]
  if not hist then
    hist = {}
    rateHistory[key] = hist
  end

  table.insert(hist, { t = t, v = value })

  while #hist > 2 and (t - hist[1].t) > CONFIG.rateWindowSeconds do
    table.remove(hist, 1)
  end

  if #hist < 2 then return nil end

  local first = hist[1]
  local last = hist[#hist]
  local dt = last.t - first.t
  if dt < 10 then return nil end

  return (last.v - first.v) / dt * 60
end

local function fmtRate(rate)
  if rate == nil then return "--/min" end
  local sign = ""
  if rate > 0.49 then sign = "+" end

  local absRate = math.abs(rate)
  if absRate >= 1000 then
    return sign .. string.format("%.1fk/min", rate / 1000)
  end
  return sign .. string.format("%.0f/min", rate)
end

------------------------------------------------------------
-- RELAY INPUTS
------------------------------------------------------------

local relay = nil

local function setupRelay()
  relay = nil
  if CONFIG.useRelayInputs and CONFIG.redstoneRelay and peripheral.isPresent(CONFIG.redstoneRelay) then
    relay = peripheral.wrap(CONFIG.redstoneRelay)
  end
end

local function isRelayStopped(key)
  if not relay then return false end
  local side = LINE_INPUTS[key]
  if not side then return false end

  local ok, value = pcall(function()
    return relay.getInput(side)
  end)

  if not ok then return false end
  return value == true
end

------------------------------------------------------------
-- FACTORY LOGIC
------------------------------------------------------------

local function possibleReadyAlloy(bufferCobble, diorite, ironNugget)
  -- 1 Alloy = 1 Cobble + 1 Diorite + 2 Iron Nuggets
  return math.min(math.floor(bufferCobble), math.floor(diorite), math.floor(ironNugget / 2))
end

local function possibleFullChainAlloy(bufferCobble, quartz, ironNugget)
  -- 1 Alloy = 3 Cobble + 2 Quartz + 2 Iron Nuggets
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

local function statusLine(key, computedStatus)
  if isRelayStopped(key) then return "STOPPED" end
  return computedStatus
end

local function getOverall(alloyLine, genLine, cobbleLine, quartzLine, ironLine, need)
  if alloyLine == "STOPPED" then return "ALLOY OUTPUT FULL" end
  if genLine == "STOPPED" then return "COBBLE GENERATOR FULL" end
  if ironLine == "LOW" or need == "IRON NUGGET" then return "WAITING FOR IRON" end
  if quartzLine == "LOW" or need == "QUARTZ" then return "WAITING FOR QUARTZ" end
  if cobbleLine == "LOW" or need == "COBBLE" then return "WAITING FOR COBBLE" end
  return "RUNNING"
end

------------------------------------------------------------
-- FLOW MAP AND DEBUG
------------------------------------------------------------

local function drawFlowMap(y, statuses)
  clearLine(y)
  drawSmallBox(2, y, "COBBLE GEN", statuses.generator)
  writeAt(17, y, "->", colors.gray)
  drawSmallBox(21, y, "RAW COBBLE", statusByFill(statuses.rawCobbleValue, RAW_COBBLE_STOP_LIMIT))

  clearLine(y + 1)
  writeAt(7, y + 1, "|", colors.gray)
  writeAt(17, y + 1, "+->", colors.gray)
  drawSmallBox(21, y + 1, "COBBLE", statuses.cobble)
  writeAt(36, y + 1, "-----+", colors.gray)

  clearLine(y + 2)
  writeAt(7, y + 2, "|", colors.gray)
  writeAt(17, y + 2, "+->", colors.gray)
  drawSmallBox(21, y + 2, "QUARTZ", statuses.quartz)
  writeAt(36, y + 2, "->", colors.gray)
  drawSmallBox(40, y + 2, "DIORITE", statuses.diorite)
  writeAt(54, y + 2, "->", colors.gray)
  drawSmallBox(58, y + 2, "ALLOY", statuses.alloy)
  writeAt(70, y + 2, "->", colors.gray)
  drawSmallBox(74, y + 2, "OUTPUT", statuses.output)

  clearLine(y + 3)
  writeAt(7, y + 3, "|", colors.gray)
  writeAt(17, y + 3, "+->", colors.gray)
  drawSmallBox(21, y + 3, "IRON", statuses.iron)
  writeAt(36, y + 3, "-----+", colors.gray)

  return y + 4
end

local function drawDebugVault(y, vault)
  local _, h = screen.getSize()
  if y > h then return y end

  local extras = {}
  for id, count in pairs(vault.items or {}) do
    if not KNOWN_ITEMS[id] then
      table.insert(extras, { id = id, count = count })
    end
  end

  table.sort(extras, function(a, b) return a.count > b.count end)

  clearLine(y)
  if #extras == 0 then
    writeAt(2, y, vault.label .. ": clean", colors.gray)
    return y + 1
  end

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

------------------------------------------------------------
-- MAIN DASHBOARD
------------------------------------------------------------

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

  local alloyLine = statusLine("alloy", alloy >= LIMITS.alloyStop and "STOPPED" or (readyAlloy <= 0 and "WAITING" or "RUNNING"))
  local generatorLine = statusLine("cobbleGenerator", rawCobble >= RAW_COBBLE_STOP_LIMIT and "STOPPED" or "RUNNING")
  local cobbleLine = statusLine("cobbleLine", bufferCobble >= LIMITS.bufferCobbleMax and "STOPPED" or statusByFill(bufferCobble, LIMITS.bufferCobbleMax))
  local quartzLine = statusLine("quartzLine", bufferQuartz >= LIMITS.bufferQuartzMax and "STOPPED" or statusByFill(bufferQuartz, LIMITS.bufferQuartzMax))
  local ironLine = statusLine("ironLine", bufferIron >= LIMITS.bufferIronMax and "STOPPED" or statusByFill(bufferIron, LIMITS.bufferIronMax))
  local dioriteLine = statusLine("dioriteLine", diorite >= LIMITS.dioriteMax and "STOPPED" or statusByFill(diorite, LIMITS.dioriteMax))

  local state = getOverall(alloyLine, generatorLine, cobbleLine, quartzLine, ironLine, need)

  local rateRawCobble = updateRate("rawCobble", rawCobble)
  local rateBufferCobble = updateRate("bufferCobble", bufferCobble)
  local rateQuartz = updateRate("bufferQuartz", bufferQuartz)
  local rateIron = updateRate("bufferIron", bufferIron)
  local rateDiorite = updateRate("diorite", diorite)
  local rateAlloy = updateRate("alloy", alloy)

  clearScreen()

  local w, h = screen.getSize()
  local timeText = textutils.formatTime(os.time(), true)

  writeAt(2, 1, "ANDESITE ALLOY FACTORY", colors.cyan)
  writeAt(math.max(2, w - #timeText - 1), 1, timeText, colors.gray)

  writeAt(2, 2, "Status:", colors.white)
  local stateColor = colors.orange
  if state == "RUNNING" then stateColor = colors.lime end
  if state == "ALLOY OUTPUT FULL" then stateColor = colors.red end
  writeAt(11, 2, state, stateColor)

  writeAt(2, 3, "Recipe: 3 Cobble + 2 Quartz + 2 Iron Nugget = 1 Alloy", colors.gray)
  writeAt(2, 4, "Relay: " .. (relay and CONFIG.redstoneRelay or "not connected / disabled"), relay and colors.green or colors.gray)

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
    output = alloy >= LIMITS.alloyStop and "FULL" or "OK",
    rawCobbleValue = rawCobble,
  })
  y = y + 1

  drawTitle(y, "PRODUCTION LINES")
  y = y + 1
  drawMeterLine(y, "Andesite Alloy", alloyLine, alloy, LIMITS.alloyStop, colorForStatus(alloyLine), fmtRate(rateAlloy)); y = y + 1
  drawMeterLine(y, "Cobblestone Generator", generatorLine, rawCobble, RAW_COBBLE_STOP_LIMIT, colorForStatus(generatorLine), fmtRate(rateRawCobble)); y = y + 1
  drawMeterLine(y, "Cobble Line", cobbleLine, bufferCobble, LIMITS.bufferCobbleMax, colorForStatus(cobbleLine), fmtRate(rateBufferCobble)); y = y + 1
  drawMeterLine(y, "Quartz Line", quartzLine, bufferQuartz, LIMITS.bufferQuartzMax, colorForStatus(quartzLine), fmtRate(rateQuartz)); y = y + 1
  drawMeterLine(y, "Iron Line", ironLine, bufferIron, LIMITS.bufferIronMax, colorForStatus(ironLine), fmtRate(rateIron)); y = y + 1
  drawMeterLine(y, "Diorite Line", dioriteLine, diorite, LIMITS.dioriteMax, colorForStatus(dioriteLine), fmtRate(rateDiorite)); y = y + 2

  drawTitle(y, "MAIN PRODUCT")
  y = y + 1
  drawMeterLine(y, "Alloy Ready", statusByFill(alloy, LIMITS.alloyStop), alloy, LIMITS.alloyStop, colors.cyan, fmtRate(rateAlloy)); y = y + 1
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
  drawMeterLine(y, VAULTS.rawCobble.label, statusByFill(raw.total, raw.capacity), raw.total, raw.capacity, colors.lightBlue); y = y + 1
  drawMeterLine(y, VAULTS.craftBuffer.label, statusByFill(buffer.total, buffer.capacity), buffer.total, buffer.capacity, colors.lime); y = y + 1
  drawMeterLine(y, VAULTS.diorite.label, statusByFill(dioriteVault.total, dioriteVault.capacity), dioriteVault.total, dioriteVault.capacity, colors.orange); y = y + 1
  drawMeterLine(y, VAULTS.alloy.label, statusByFill(alloyVault.total, alloyVault.capacity), alloyVault.total, alloyVault.capacity, colors.cyan); y = y + 2

  drawTitle(y, "BUFFER CONTENT")
  y = y + 1
  drawMeterLine(y, "Cobble", statusByFill(bufferCobble, LIMITS.bufferCobbleMax), bufferCobble, LIMITS.bufferCobbleMax, colors.lightBlue); y = y + 1
  drawMeterLine(y, "Quartz", statusByFill(bufferQuartz, LIMITS.bufferQuartzMax), bufferQuartz, LIMITS.bufferQuartzMax, colors.purple); y = y + 1
  drawMeterLine(y, "Iron Nugget", statusByFill(bufferIron, LIMITS.bufferIronMax), bufferIron, LIMITS.bufferIronMax, colors.orange); y = y + 2

  if CONFIG.showDebugExtraItems and y <= h - 2 then
    drawTitle(y, "DEBUG: EXTRA ITEMS")
    y = y + 1
    y = drawDebugVault(y, raw)
    y = drawDebugVault(y, buffer)
    y = drawDebugVault(y, dioriteVault)
    y = drawDebugVault(y, alloyVault)
  end

  local errors = {}
  if not raw.ok then table.insert(errors, raw.name .. " " .. tostring(raw.error)) end
  if not buffer.ok then table.insert(errors, buffer.name .. " " .. tostring(buffer.error)) end
  if not dioriteVault.ok then table.insert(errors, dioriteVault.name .. " " .. tostring(dioriteVault.error)) end
  if not alloyVault.ok then table.insert(errors, alloyVault.name .. " " .. tostring(alloyVault.error)) end

  clearLine(h)
  if #errors > 0 then
    writeAt(2, h, "ERROR: " .. errors[1], colors.red)
  else
    writeAt(2, h, "All vaults connected | Rates are 1 min average | Limits display current line logic", colors.green)
  end
end

------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

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
