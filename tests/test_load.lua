-- Static checks: every addon file parses, the toc and embeds point at real files.
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local function exists(path) return read(path) ~= nil end

local function tocFiles()
  local toc = read("Drink/Drink.toc")
  truthy(toc, "Drink/Drink.toc missing")
  local files, meta = {}, {}
  for line in toc:gmatch("[^\r\n]+") do
    local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if k then meta[k] = v
    elseif not line:match("^#") and line:match("%S") then
      files[#files + 1] = (line:gsub("\\", "/"):match("^%s*(.-)%s*$"))
    end
  end
  return files, meta
end

test("load: toc metadata", function()
  local _, meta = tocFiles()
  eq(meta["Interface"], "16001, 50504, 120105, 120107")
  eq(meta["SavedVariables"], "DrinkDB")
  eq(meta["Title"], "Drink")
end)

test("load: toc file order and existence", function()
  local files = tocFiles()
  eq(files, { "embeds.xml", "Logic.lua", "Defaults.lua", "Compat.lua", "Controller.lua",
    "Alert.lua", "Options.lua", "Drink.lua" })
  for _, f in ipairs(files) do truthy(exists("Drink/" .. f), "missing Drink/" .. f) end
end)

test("load: every addon lua file parses", function()
  local files = tocFiles()
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      local chunk, err = loadfile("Drink/" .. f)
      truthy(chunk, err)
    end
  end
end)

test("load: addon files avoid Lua 5.2+ only syntax", function()
  local files = tocFiles()
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      local src = read("Drink/" .. f):gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')
      truthy(not src:find("//", 1, true), f .. " uses //")
      truthy(not src:find("goto ", 1, true), f .. " uses goto")
      truthy(not src:find("::", 1, true), f .. " uses labels")
      truthy(not src:find("[^~<>=]~[^=]") , f .. " uses bitwise ~")
      truthy(not src:find("<<", 1, true) and not src:find(">>", 1, true), f .. " uses shifts")
    end
  end
end)

test("load: embeds.xml references existing files", function()
  local xml = read("Drink/embeds.xml")
  truthy(xml, "Drink/embeds.xml missing")
  local n = 0
  for path in xml:gmatch('file="([^"]+)"') do
    n = n + 1
    truthy(exists("Drink/" .. path:gsub("\\", "/")), "embeds.xml -> missing " .. path)
  end
  truthy(n >= 9, "expected at least 9 library includes, got " .. n)
end)

test("load: glue env implements the full controller env contract", function()
  local FakeEnv = require("fake_env")
  local addon
  local fakeDB = function(defaults)
    return { profile = deepcopy(defaults.profile), RegisterCallback = function() end }
  end
  local saved = { LibStub = _G.LibStub }
  _G.LibStub = function(name)
    if name == "AceAddon-3.0" then
      return { NewAddon = function(_, n) addon = { name = n }; return addon end }
    elseif name == "AceDB-3.0" then
      return { New = function(_, _, defaults) return fakeDB(defaults) end }
    end
    error("unexpected lib " .. tostring(name))
  end
  local ok, err = pcall(function()
    local ns = {}
    for _, f in ipairs({ "Logic", "Defaults", "Compat", "Controller", "Drink" }) do
      load_addon(ns, "Drink/" .. f .. ".lua")
    end
    addon:OnInitialize()
    local realEnv = ns.ctrl().env
    for k, v in pairs(FakeEnv.New()) do
      if type(v) == "function" and k ~= "advance" then
        truthy(type(realEnv[k]) == "function", "real env missing " .. k)
      end
    end
    for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_AURA" }) do
      truthy(type(addon[ev]) == "function", "missing handler " .. ev)
    end
  end)
  _G.LibStub = saved.LibStub
  if not ok then error(err, 0) end
end)
