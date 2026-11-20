-- Smoke test for the UI module with stub WoW frames: exercises every code path for nil/typo errors.
local function stubObject(log)
  local o = { shown = false, scripts = {}, alpha = 1, scale = 1 }
  local methods = {
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetScript = function(self, k, f) self.scripts[k] = f end,
    SetAlpha = function(self, a) self.alpha = a end,
    SetText = function(self, t) self.text = t; log[#log + 1] = t end,
    GetPoint = function() return "TOP", nil, "TOP", 5, -40 end,
    SetPoint = function(self, ...) self.point = { ... } end,
    SetScale = function(self, s) self.scale = s end,
    GetScale = function(self) return self.scale end,
    CreateTexture = function() return stubObject(log) end,
    CreateFontString = function() return stubObject(log) end,
  }
  -- Real WoW widget methods Alert.lua may call; anything else capitalized is a typo.
  local NOOP = { "SetSize", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "ClearAllPoints", "EnableMouse", "SetAllPoints",
    "SetColorTexture", "SetTexture", "SetBlendMode", "SetFont", "SetTextColor" }
  for _, m in ipairs(NOOP) do methods[m] = methods[m] or function() end end
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then error("unknown WoW widget method: " .. k, 2) end
    return nil
  end })
end

local G = { "CreateFrame", "UIParent", "STANDARD_TEXT_FONT", "SOUNDKIT", "PlaySound" }

test("alert: show, fade, lock and drag paths run without errors", function()
  local saved = {}
  for _, n in ipairs(G) do saved[n] = _G[n] end
  local log, frames, sounds = {}, {}, {}
  _G.CreateFrame = function(_, name) local f = stubObject(log); frames[name] = f; return f end
  _G.UIParent = stubObject(log)
  _G.STANDARD_TEXT_FONT = "font"
  _G.SOUNDKIT = { RAID_WARNING = 8959 }
  _G.PlaySound = function(id) sounds[#sounds + 1] = id end

  local ok, err = pcall(function()
    local ns = {}
    load_addon(ns, "Drink/Defaults.lua")
    load_addon(ns, "Drink/Alert.lua")
    local profile = deepcopy(ns.defaults.profile)
    local A = ns.Alert
    A.Init(profile)
    local f, flash = frames.DrinkAlertFrame, frames.DrinkAlertFlash
    truthy(f and flash, "frames created")
    eq(f.shown, false, "locked + idle = hidden")

    A.Show("critical", 12)
    eq(f.shown, true); eq(flash.shown, true)
    truthy(log[#log]:find("12%% mana"), "critical text: " .. tostring(log[#log]))
    eq(sounds, { 8959 })
    f.scripts.OnUpdate(f, 3)            -- mid-pulse
    eq(f.shown, true)
    f.scripts.OnUpdate(f, 3.5)          -- past 6s duration
    eq(f.shown, false); eq(flash.shown, false)

    A.Show("fyi", 90)
    eq(flash.shown, false, "no flash for fyi")
    eq(#sounds, 1, "fyi is silent")
    A.Hide()
    eq(f.shown, false)

    A.Show("unknown", nil)
    truthy(log[#log]:find("unknown"), "unknown text")
    A.Show("heads", 65); A.Show("low", 35)
    eq(#sounds, 4, "heads, low and unknown play sounds (fallback ids)")

    A.SetLocked(false)
    eq(profile.alert.locked, false)
    eq(f.shown, true, "drag handle visible")
    f.scripts.OnDragStart(f); f.scripts.OnDragStop(f)
    eq(profile.alert.point, { "TOP", "TOP", 5, -40 })
    A.Show("low", 35)
    A.Hide()
    eq(f.shown, true, "unlocked hide returns to drag handle")
    truthy(log[#log]:find("Drag me"), "drag text restored")

    A.SetLocked(true)
    eq(f.shown, false)
    local n = #sounds
    profile.tiers.low.sound = false
    A.Show("low", 35)
    eq(#sounds, n, "low tier sound toggled off")
    profile.tiers.low.sound = true
    A.Show("low", 35)
    eq(#sounds, n + 1, "low tier sound back on")
    profile.alert.scale = 1.5
    A.ApplyLayout()
  end)
  for _, n in ipairs(G) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end)

test("alert: changing scale keeps the dragged position on screen", function()
  local saved = {}
  for _, n in ipairs(G) do saved[n] = _G[n] end
  local log, frames = {}, {}
  _G.CreateFrame = function(_, name) local f = stubObject(log); frames[name] = f; return f end
  _G.UIParent = stubObject(log)
  _G.STANDARD_TEXT_FONT = "font"
  _G.SOUNDKIT = {}
  _G.PlaySound = function() end
  local ok, err = pcall(function()
    local ns = {}
    load_addon(ns, "Drink/Defaults.lua")
    load_addon(ns, "Drink/Alert.lua")
    local profile = deepcopy(ns.defaults.profile)
    profile.alert.scale = 2
    ns.Alert.Init(profile)
    local f = frames.DrinkAlertFrame
    f.scripts.OnDragStop(f)                       -- GetPoint reports 5, -40 in frame (x2) units
    eq(profile.alert.point, { "TOP", "TOP", 10, -80 }, "saved in screen units")
    ns.Alert.ApplyLayout()
    eq({ f.point[1], f.point[3], f.point[4], f.point[5] }, { "TOP", "TOP", 5, -40 })
    profile.alert.scale = 1
    ns.Alert.ApplyLayout()
    eq({ f.point[4], f.point[5] }, { 10, -80 }, "same screen position at scale 1")
  end)
  for _, n in ipairs(G) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end)

test("alert: stock line, good vs low, silent", function()
  local saved = {}
  for _, n in ipairs(G) do saved[n] = _G[n] end
  local log, frames, sounds = {}, {}, {}
  _G.CreateFrame = function(_, name) local f = stubObject(log); frames[name] = f; return f end
  _G.UIParent = stubObject(log)
  _G.STANDARD_TEXT_FONT = "font"
  _G.SOUNDKIT = {}
  _G.PlaySound = function(id) sounds[#sounds + 1] = id end
  local ok, err = pcall(function()
    local ns = {}
    load_addon(ns, "Drink/Defaults.lua")
    load_addon(ns, "Drink/Alert.lua")
    local profile = deepcopy(ns.defaults.profile)
    ns.Alert.Init(profile)
    local f, flash = frames.DrinkAlertFrame, frames.DrinkAlertFlash
    ns.Alert.ShowStock({ total = 34, refills = 21, low = false })
    eq(log[#log], "Drinks: 34 (~21 refills) - you're good")
    eq(f.shown, true); eq(flash.shown, false); eq(#sounds, 0)
    ns.Alert.ShowStock({ total = 6, refills = 3, low = true })
    eq(log[#log], "Drinks: 6 (~3 refills) - STOCK UP")
    f.scripts.OnUpdate(f, 6.1)
    eq(f.shown, false, "gone after 6s")
  end)
  for _, n in ipairs(G) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end)
