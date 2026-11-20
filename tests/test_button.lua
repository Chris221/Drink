-- Smoke test for the secure drink button with whitelisted stub frames (typos in WoW method names fail).
local function stubObject(kind, name, parent, template, registry)
  local o = { kind = kind, name = name, parent = parent, template = template, shown = true,
              scripts = {}, hooks = {}, attrs = {}, w = 0, h = 0, mouse = false }
  local methods = {
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetScript = function(self, k, f) self.scripts[k] = f end,
    HookScript = function(self, k, f) self.hooks[k] = f end,
    SetAttribute = function(self, k, v) self.attrs[k] = v end,
    GetAttribute = function(self, k) return self.attrs[k] end,
    SetPoint = function(self, ...) self.point = { ... } end,
    GetPoint = function(self) return "LEFT", nil, "LEFT", 300, -20 end,
    SetSize = function(self, w, h) self.w, self.h = w, h end,
    GetSize = function(self) return self.w, self.h end,
    EnableMouse = function(self, v) self.mouse = v end,
    SetText = function(self, t) self.text = t end,
    SetTexture = function(self, t) self.texture = t end,
    CreateTexture = function(self) return stubObject("Texture", nil, self, nil, registry) end,
    CreateFontString = function(self) return stubObject("FontString", nil, self, nil, registry) end,
  }
  local NOOP = { "SetMovable", "SetResizable", "SetResizeBounds", "SetClampedToScreen", "RegisterForDrag",
    "RegisterForClicks", "StartMoving", "StartSizing", "StopMovingOrSizing", "ClearAllPoints", "SetAllPoints",
    "SetUserPlaced", "SetFrameStrata", "SetColorTexture", "SetTextColor", "SetFont", "SetAlpha", "SetVertexColor" }
  for _, m in ipairs(NOOP) do methods[m] = methods[m] or function() end end
  local obj = setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then error("unknown WoW widget method: " .. k, 2) end
    return nil
  end })
  if name then registry[name] = obj end
  registry[#registry + 1] = obj
  return obj
end

local G = { "CreateFrame", "UIParent", "RegisterStateDriver", "InCombatLockdown", "GameTooltip", "STANDARD_TEXT_FONT" }

local function with_button(fn)
  local saved = {}
  for _, n in ipairs(G) do saved[n] = _G[n] end
  local reg, drivers, combat = {}, {}, { on = false }
  _G.UIParent = stubObject("Frame", "UIParent", nil, nil, reg)
  _G.CreateFrame = function(kind, name, parent, template) return stubObject(kind, name, parent, template, reg) end
  _G.RegisterStateDriver = function(f, state, cond) drivers[#drivers + 1] = { f, state, cond } end
  _G.InCombatLockdown = function() return combat.on end
  _G.GameTooltip = stubObject("GameTooltip", "GameTooltip", nil, nil, reg)
  _G.STANDARD_TEXT_FONT = "font"
  local ok, err = pcall(function()
    local ns = {}
    load_addon(ns, "Drink/Defaults.lua")
    load_addon(ns, "Drink/DrinkButton.lua")
    local profile = deepcopy(ns.defaults.profile)
    ns.DrinkButton.Init(profile)
    fn(ns.DrinkButton, reg, drivers, combat, profile)
  end)
  for _, n in ipairs(G) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end

local DRINK = { itemID = 8079, name = "Conjured Crystal Water", icon = 5555, count = 14, mana = 4200, seconds = 30 }

test("button: secure holder with combat state driver, anchored to UIParent", function()
  with_button(function(B, reg, drivers)
    local holder, button = reg.DrinkButtonHolder, reg.DrinkUseButton
    truthy(holder and button, "frames created")
    eq(holder.template, "SecureHandlerStateTemplate")
    eq(button.template, "SecureActionButtonTemplate")
    eq(button.parent, holder)
    eq(drivers, { { holder, "visibility", "[combat] hide; show" } })
    eq(holder.point[2], reg.UIParent, "anchored to UIParent, never the alert frame")
    eq({ holder.point[1], holder.point[3], holder.point[4], holder.point[5] }, { "CENTER", "CENTER", 0, 110 })
    eq({ holder.w, holder.h }, { 40, 40 })
    eq(button.attrs.type, "item")
    eq(button.shown, false, "hidden until there is a recommendation")
  end)
end)

test("button: show sets the item and shows; click hides", function()
  with_button(function(B, reg)
    local button = reg.DrinkUseButton
    eq(B.Show(DRINK), true)
    eq(button.attrs.item, "item:8079")
    eq(button.shown, true)
    button.hooks.PostClick(button)
    eq(button.shown, false)
  end)
end)

test("button: nothing changes in combat; deferred hide applied after combat", function()
  with_button(function(B, reg, _, combat)
    local button = reg.DrinkUseButton
    B.Show(DRINK)
    combat.on = true
    eq(B.Show({ itemID = 1, name = "x", icon = 1, count = 1 }), false)
    eq(button.attrs.item, "item:8079", "attribute untouched in combat")
    B.Hide()
    eq(button.shown, true, "hide deferred in combat")
    combat.on = false
    B.FlushPending()
    eq(button.shown, false)
  end)
end)

test("button: unlock shows a draggable placeholder; drag and resize are saved", function()
  with_button(function(B, reg, _, _, profile)
    local holder = reg.DrinkButtonHolder
    eq(holder.mouse, false, "locked by default")
    B.SetLocked(false)
    eq(holder.mouse, true)
    holder.scripts.OnDragStart(holder)
    holder.scripts.OnDragStop(holder)
    eq(profile.button.point, { "LEFT", "LEFT", 300, -20 })
    -- resize via the grip: user drags to 70x55 -> square, clamped
    local grip
    for _, o in ipairs(reg) do if o.parent == holder and o.scripts.OnMouseDown then grip = o end end
    truthy(grip, "resize grip exists")
    grip.scripts.OnMouseDown(grip)
    holder.w, holder.h = 70, 55
    grip.scripts.OnMouseUp(grip)
    eq(profile.button.size, 70)
    eq({ holder.w, holder.h }, { 70, 70 })
    grip.scripts.OnMouseDown(grip); holder.w, holder.h = 500, 500; grip.scripts.OnMouseUp(grip)
    eq(profile.button.size, 96, "clamped to max")
    B.SetLocked(true)
    eq(holder.mouse, false)
    eq(grip.shown, false)
  end)
end)

test("button: lock and layout requested in combat are applied afterwards", function()
  with_button(function(B, reg, _, combat, profile)
    local holder = reg.DrinkButtonHolder
    combat.on = true
    B.SetLocked(false)
    profile.button.size = 60
    B.ApplyLayout()
    eq(holder.mouse, false)
    eq(holder.w, 40)
    combat.on = false
    B.FlushPending()
    eq(holder.mouse, true)
    eq(holder.w, 60)
  end)
end)

-- Final-review fixes -------------------------------------------------------

test("button: uses the item on release; the ignored key-down click doesn't hide it", function()
  with_button(function(B, reg)
    local button = reg.DrinkUseButton
    eq(button.attrs.useOnKeyDown, false)
    B.Show(DRINK)
    button.hooks.PostClick(button, "LeftButton", true)
    eq(button.shown, true, "still there for the release that actually drinks")
    button.hooks.PostClick(button, "LeftButton", false)
    eq(button.shown, false)
  end)
end)

test("button: shows a count of 1 so you can see it's your last drink", function()
  with_button(function(B, reg)
    local one = {}
    for k, v in pairs(DRINK) do one[k] = v end
    one.count = 1
    B.Show(one)
    eq(reg.DrinkUseButton.count.text, "1")
  end)
end)

local function gripOf(reg, holder)
  for _, o in ipairs(reg) do if o.parent == holder and o.scripts.OnMouseDown then return o end end
end

test("button: resizing keeps the corner where it was dropped (point saved too)", function()
  with_button(function(B, reg, _, _, profile)
    local holder = reg.DrinkButtonHolder
    B.SetLocked(false)
    local grip = gripOf(reg, holder)
    grip.scripts.OnMouseDown(grip); holder.w, holder.h = 60, 60; grip.scripts.OnMouseUp(grip)
    eq(profile.button.point, { "LEFT", "LEFT", 300, -20 }, "point re-read after sizing")
  end)
end)

test("button: combat starting mid-drag never touches the protected holder until it ends", function()
  with_button(function(B, reg, _, combat)
    local holder = reg.DrinkButtonHolder
    local stops = 0
    holder.StopMovingOrSizing = function() if combat.on then error("ADDON_ACTION_BLOCKED") end; stops = stops + 1 end
    B.SetLocked(false)
    holder.scripts.OnDragStart(holder)
    combat.on = true
    holder.scripts.OnDragStop(holder)
    local grip = gripOf(reg, holder)
    grip.scripts.OnMouseUp(grip)
    eq(stops, 0)
    combat.on = false
    B.FlushPending()
    eq(stops, 1, "stopped once after combat")
  end)
end)
