-- update.lua
-- Manual GitHub updater for CC:Tweaked

local USER = "draleksei1-cmyk"
local REPO = "cc-scripts"
local BRANCH = "main"

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. BRANCH .. "/"
local MANIFEST_URL = BASE .. "manifest.lua"

local args = { ... }
local onlyName = args[1]

local function fail(msg)
  print("ERROR: " .. tostring(msg))
end

local function download(url)
  if not http then
    return nil, "HTTP API is disabled"
  end

  local response, err = http.get(url, {
    ["Cache-Control"] = "no-cache"
  })

  if not response then
    return nil, err or "download failed"
  end

  local data = response.readAll()
  response.close()

  if not data or data == "" then
    return nil, "empty response"
  end

  return data
end

local function loadManifest()
  local data, err = download(MANIFEST_URL)
  if not data then
    return nil, "cannot download manifest: " .. tostring(err)
  end

  local fn, loadErr = load(data, "manifest", "t", {})
  if not fn then
    return nil, "cannot parse manifest: " .. tostring(loadErr)
  end

  local ok, manifest = pcall(fn)
  if not ok then
    return nil, "manifest error: " .. tostring(manifest)
  end

  if type(manifest) ~= "table" then
    return nil, "manifest must return table"
  end

  return manifest
end

local function saveFile(path, content)
  local dir = fs.getDir(path)

  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end

  if fs.exists(path) then
    fs.delete(path)
  end

  local file = fs.open(path, "w")
  if not file then
    return false, "cannot write file: " .. path
  end

  file.write(content)
  file.close()

  return true
end

local function getSortedNames(manifest)
  local names = {}

  for name in pairs(manifest) do
    table.insert(names, name)
  end

  table.sort(names)
  return names
end

local function updateOne(name, item)
  if type(item) ~= "table" then
    print(name .. ": FAILED")
    print("  manifest item is not table")
    return false
  end

  if not item.path then
    print(name .. ": FAILED")
    print("  no path in manifest")
    return false
  end

  local target = item.target or name
  local url = BASE .. item.path

  write(name .. " -> " .. target .. "... ")

  local data, err = download(url)
  if not data then
    print("FAILED")
    print("  " .. tostring(err))
    return false
  end

  local ok, saveErr = saveFile(target, data)
  if not ok then
    print("FAILED")
    print("  " .. tostring(saveErr))
    return false
  end

  print("OK")
  return true
end

print("GitHub updater")
print("Repo: " .. USER .. "/" .. REPO)
print("")

local manifest, err = loadManifest()
if not manifest then
  fail(err)
  return
end

if onlyName then
  local item = manifest[onlyName]
  if not item then
    fail("unknown program: " .. onlyName)
    return
  end

  updateOne(onlyName, item)
  return
end

local okCount = 0
local failCount = 0

for _, name in ipairs(getSortedNames(manifest)) do
  local ok = updateOne(name, manifest[name])
  if ok then
    okCount = okCount + 1
  else
    failCount = failCount + 1
  end
end

print("")
print("Done. Updated: " .. okCount .. ", failed: " .. failCount)
