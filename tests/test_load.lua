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
  eq(meta["Title"], "|cff33ccffDrink|r")
  -- The icon path must point at a file that ships in the addon folder.
  local icon = meta["IconTexture"]:match("^Interface\\AddOns\\Drink\\(.+)$")
  truthy(icon, "IconTexture should live under Interface\\AddOns\\Drink")
  truthy(exists("Drink/" .. icon:gsub("\\", "/") .. ".tga"), "IconTexture file missing")
end)

test("load: toc file order and existence", function()
  local files = tocFiles()
  eq(files, { "embeds.xml", "Logic.lua", "Drinks.lua", "Tally.lua", "Defaults.lua", "Compat.lua", "Controller.lua",
    "Alert.lua", "DrinkButton.lua", "Options.lua", "Drink.lua" })
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
    for _, f in ipairs({ "Logic", "Drinks", "Defaults", "Compat", "Controller", "Drink" }) do
      load_addon(ns, "Drink/" .. f .. ".lua")
    end
    addon:OnInitialize()
    local realEnv = ns.ctrl().env
    eq(_G["BINDING_NAME_CLICK DrinkUseButton:LeftButton"], "Use recommended drink")
    eq(_G.BINDING_HEADER_DRINK, "Drink")
    for k, v in pairs(FakeEnv.New()) do
      if type(v) == "function" and k ~= "advance" then
        truthy(type(realEnv[k]) == "function", "real env missing " .. k)
      end
    end
    for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_AURA", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
      truthy(type(addon[ev]) == "function", "missing handler " .. ev)
    end
  end)
  _G.LibStub = saved.LibStub
  if not ok then error(err, 0) end
end)

test("load: glue passes Edit Mode opening and closing on to the alert", function()
  local addon
  local saved = { LibStub = _G.LibStub, EditModeManagerFrame = _G.EditModeManagerFrame, EventRegistry = _G.EventRegistry }
  local callbacks = {}
  _G.EditModeManagerFrame = {}
  _G.EventRegistry = { RegisterCallback = function(_, event, fn) callbacks[event] = fn end }
  _G.LibStub = function(name)
    if name == "AceAddon-3.0" then
      return { NewAddon = function(_, n) addon = { name = n, RegisterEvent = function() end }; return addon end }
    elseif name == "AceDB-3.0" then
      return { New = function(_, _, defaults)
        return { profile = deepcopy(defaults.profile), RegisterCallback = function() end }
      end }
    end
    error("unexpected lib " .. tostring(name))
  end
  local ok, err = pcall(function()
    local ns = {}
    for _, f in ipairs({ "Logic", "Drinks", "Defaults", "Compat", "Controller", "Drink" }) do
      load_addon(ns, "Drink/" .. f .. ".lua")
    end
    addon:OnInitialize()
    local got = {}
    ns.Alert = { EditMode = function(open) got[#got + 1] = open end }
    addon:OnEnable()
    truthy(callbacks["EditMode.Enter"] and callbacks["EditMode.Exit"], "watching Edit Mode")
    callbacks["EditMode.Enter"](); callbacks["EditMode.Exit"]()
    eq(got, { true, false })
  end)
  for k in pairs({ LibStub = true, EditModeManagerFrame = true, EventRegistry = true }) do _G[k] = saved[k] end
  if not ok then error(err, 0) end
end)

test("load: glue gives the controller this character's saved runs and the dungeon's name", function()
  local addon, db
  local names = { "LibStub", "IsInInstance", "GetInstanceInfo", "time", "C_Timer", "InCombatLockdown", "UnitBuff",
    "C_UnitAuras", "GetTime" }
  local saved = {}
  for _, n in ipairs(names) do saved[n] = _G[n] end
  _G.IsInInstance = function() return true, "party" end
  _G.GetInstanceInfo = function() return "Deadmines", "party" end
  _G.time = function() return 12345 end
  _G.GetTime = function() return 50 end
  _G.C_Timer = { After = function() end }
  _G.InCombatLockdown = function() return false end
  _G.UnitBuff = function() return nil end
  _G.C_UnitAuras = nil
  _G.LibStub = function(name)
    if name == "AceAddon-3.0" then
      return { NewAddon = function(_, n) addon = { name = n }; return addon end }
    elseif name == "AceDB-3.0" then
      return { New = function(_, _, defaults)
        db = { profile = deepcopy(defaults.profile), char = deepcopy(defaults.char), RegisterCallback = function() end }
        return db
      end }
    end
    error("unexpected lib " .. tostring(name))
  end
  local ok, err = pcall(function()
    local ns = {}
    for _, f in ipairs({ "Logic", "Drinks", "Tally", "Defaults", "Compat", "Controller", "Drink" }) do
      load_addon(ns, "Drink/" .. f .. ".lua")
    end
    eq(ns.defaults.char, { runs = {} }, "saved per character")
    addon:OnInitialize()
    truthy(ns.ctrl().store == db.char, "the controller works on the saved table itself")
    addon:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", false, false)
    eq(db.char.run.name, "Deadmines")
    eq(db.char.run.seen, 12345, "stamped with the real-world clock")
  end)
  for _, n in ipairs(names) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end)

test("load: key binding file binds the drink button", function()
  local f = assert(io.open("Drink/Bindings.xml", "r"))
  local xml = f:read("a"); f:close()
  truthy(xml:find('name="CLICK DrinkUseButton:LeftButton"', 1, true), "click binding")
  truthy(xml:find('header="DRINK"', 1, true), "header")
end)
