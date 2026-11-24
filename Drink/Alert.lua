-- On-screen "time to drink" alert: one movable text frame plus a full-screen red edge flash.
local ADDON, ns = ...

local Alert = {}
ns.Alert = Alert

local function sound(name, fallback)
  return function()
    local id = (SOUNDKIT and SOUNDKIT[name]) or fallback
    if id then PlaySound(id, "Master") end
  end
end

local STYLE = {
  fyi      = { size = 18, r = 0.6, g = 1.0, b = 0.6 },
  heads    = { size = 24, r = 1.0, g = 0.9, b = 0.2, play = sound("TELL_MESSAGE", 3081) },
  low      = { size = 32, r = 1.0, g = 0.55, b = 0.1, play = sound("READY_CHECK", 8960) },
  critical = { size = 44, r = 1.0, g = 0.15, b = 0.15, play = sound("RAID_WARNING", 8959), pulse = true },
  unknown  = { size = 24, r = 1.0, g = 0.9, b = 0.2, play = sound("TELL_MESSAGE", 3081) },
}
local UNKNOWN_DURATION = 3
local FADE = 0.6

local profile, frame, text, flash, layer, critHolder, mage
local PULL_DURATION = 3
local editUnlocked = false -- unlocked by the game's Edit Mode rather than by hand
local HIDDEN_DURATION = 4 -- hidden mana: the addon can't tell which tier the game showed
local HIDDEN_TIERS = { "fyi", "heads", "low", "critical" }

-- Alert text per tier (profile.tiers[tier].text): "%m" is the mana %, like the chat templates.
local FALLBACK_TEXT = "DRINK!  %m% mana"

local function tierText(tier)
  local cfg = profile.tiers[tier]
  local t = cfg and cfg.text
  if type(t) == "string" and t:find("%S") then return t end
  local d = ns.defaults and ns.defaults.profile.tiers[tier]
  return d and d.text or FALLBACK_TEXT
end

local function withPercent(t, pct)
  return (t:gsub("%%m", function() return tostring(pct) end))
end

-- No readable %: drop the "%m% mana" part of the usual shape, put a ? in place of any other %m.
local function withoutPercent(t)
  local s = t:gsub("%s*%%m%%?%s*mana", ""):gsub("%%m", "?")
  s = s:match("^%s*(.-)%s*$")
  return s ~= "" and s or "DRINK!"
end

-- printf format for a secret %: literal % doubled, each %m -> %d. Returns the format and how many.
local function secretFormat(t)
  return t:gsub("%%", "%%%%"):gsub("%%%%m", "%%d")
end

local function rep(v, n)
  if n <= 0 then return end
  return v, rep(v, n - 1)
end

-- Offsets are stored in screen (UIParent) units so changing the scale doesn't move the alert;
-- SetPoint/GetPoint offsets on a scaled frame are in the frame's own units.
local function savePoint()
  local p, _, rp, x, y = frame:GetPoint()
  local s = frame:GetScale()
  profile.alert.point = { p, rp, x * s, y * s }
end

local function onUpdate(self, elapsed)
  self.t = self.t + elapsed
  local remaining = self.duration - self.t
  if remaining <= 0 then
    Alert.Hide()
    return
  end
  local fade = remaining < FADE and remaining / FADE or 1
  local pulse = 0.55 + 0.45 * math.abs(math.sin(self.t * 5))
  if self.hiddenMode then
    -- Each tier text's own alpha is the game's secret 0/1; fade and pulse go on the parents.
    layer:SetAlpha(fade)
    critHolder:SetAlpha(pulse)
    if flash:IsShown() then flash:SetAlpha(fade * 0.8) end
    return
  end
  local alpha = self.pulse and pulse or 1
  alpha = alpha * fade
  text:SetAlpha(alpha)
  if flash:IsShown() then flash:SetAlpha(alpha * 0.8) end
end

local function create()
  frame = CreateFrame("Frame", "DrinkAlertFrame", UIParent)
  frame:SetSize(700, 70)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
  frame:Hide()

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(0, 0.6, 1, 0.25)
  frame.bg:Hide()

  text = frame:CreateFontString(nil, "OVERLAY")
  text:SetPoint("CENTER")
  text:SetFont(STANDARD_TEXT_FONT, 24, "THICKOUTLINE")

  -- Hidden-mana layer: one text per tier stacked on top of each other; the game sets which
  -- one is visible (alpha from a curve on the secret mana value).
  layer = CreateFrame("Frame", "DrinkAlertHidden", frame)
  layer:SetAllPoints()
  critHolder = CreateFrame("Frame", nil, layer)
  critHolder:SetAllPoints()
  layer.texts = {}
  for _, tier in ipairs(HIDDEN_TIERS) do
    local style = STYLE[tier]
    local fs = (tier == "critical" and critHolder or layer):CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetFont(STANDARD_TEXT_FONT, style.size, "THICKOUTLINE")
    fs:SetTextColor(style.r, style.g, style.b)
    layer.texts[tier] = fs
  end
  layer:Hide()

  flash = CreateFrame("Frame", "DrinkAlertFlash", UIParent)
  flash:SetAllPoints(UIParent)
  flash:SetFrameStrata("BACKGROUND")
  local tex = flash:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
  tex:SetBlendMode("ADD")
  flash.tex = tex
  flash:Hide()

  -- "Ask <mage> for water": an ordinary click button. It only asks the controller to send;
  -- nothing goes out unless the user clicks it.
  mage = CreateFrame("Button", "DrinkMageButton", UIParent)
  mage:SetSize(240, 26)
  mage:SetFrameStrata("HIGH")
  mage:SetPoint("TOP", frame, "BOTTOM", 0, -80)
  local mbg = mage:CreateTexture(nil, "BACKGROUND")
  mbg:SetAllPoints()
  mbg:SetColorTexture(0.1, 0.35, 0.8, 0.75)
  mage.label = mage:CreateFontString(nil, "OVERLAY")
  mage.label:SetPoint("CENTER")
  mage.label:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  mage:SetScript("OnClick", function()
    local ctrl = ns.ctrl and ns.ctrl()
    if ctrl then ctrl:RequestWater() end
  end)
  mage:Hide()
end

function Alert.ApplyLayout()
  if not frame then return end
  local p, s = profile.alert.point, profile.alert.scale
  frame:SetScale(s)
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[2], p[3] / s, p[4] / s)
end

function Alert.Init(p)
  profile = p
  if not frame then create() end
  Alert.ApplyLayout()
  Alert.SetLocked(profile.alert.locked)
end

function Alert.Show(tier, pct)
  if not frame then return end
  local style = STYLE[tier] or STYLE.unknown
  local cfg = profile.tiers[tier]
  frame.bg:Hide()
  frame.hiddenMode = false
  layer:Hide()
  flash.tex:SetAlpha(1)
  text:SetFont(STANDARD_TEXT_FONT, style.size, "THICKOUTLINE")
  text:SetTextColor(style.r, style.g, style.b)
  local t = tierText(tier)
  if pct then
    text:SetText(withPercent(t, pct))
  else
    text:SetText(withoutPercent(t) .. "  (mana unknown)")
  end
  text:SetAlpha(1)

  frame.t = 0
  frame.duration = cfg and cfg.duration or UNKNOWN_DURATION
  frame.pulse = style.pulse
  frame:SetScript("OnUpdate", onUpdate)
  frame:Show()

  if tier == "critical" and cfg and cfg.flash then
    flash:SetAlpha(0.8)
    flash:Show()
  else
    flash:Hide()
  end
  if style.play and not (cfg and cfg.sound == false) then style.play() end
end

-- The group pulled while I'm sitting.
function Alert.ShowPull()
  if not frame then return end
  local style, crit = STYLE.critical, profile.tiers.critical
  frame.bg:Hide()
  frame.hiddenMode = false
  layer:Hide()
  text:SetFont(STANDARD_TEXT_FONT, style.size, "THICKOUTLINE")
  text:SetTextColor(style.r, style.g, style.b)
  text:SetText("PULL - stand up!")
  text:SetAlpha(1)
  frame.t = 0
  frame.duration = PULL_DURATION
  frame.pulse = true
  frame:SetScript("OnUpdate", onUpdate)
  frame:Show()
  flash:Hide()
  if crit.sound ~= false then style.play() end
end

function Alert.ShowMage(name)
  if not mage then return end
  mage.label:SetText("Ask " .. name .. " for water")
  mage:Show()
end

function Alert.HideMage()
  if mage then mage:Hide() end
end

-- Stock check line: green when you're good, orange when you should restock. Silent, no flash.
local STOCK_DURATION = 6
function Alert.ShowStock(summary)
  if not frame then return end
  frame.bg:Hide()
  frame.hiddenMode = false
  layer:Hide()
  text:SetFont(STANDARD_TEXT_FONT, 24, "THICKOUTLINE")
  -- summary.need: set in a dungeon I've run before (what it's likely to take from here).
  local detail
  if summary.need then
    detail = string.format(" (~%d needed)", summary.need)
  elseif summary.total == 0 then
    detail = ""
  elseif summary.refills < 1 then
    detail = " (<1 refill)"
  elseif summary.refills == 1 then
    detail = " (~1 refill)"
  else
    detail = string.format(" (~%d refills)", summary.refills)
  end
  if summary.low then
    text:SetTextColor(1.0, 0.6, 0.1)
    text:SetText(string.format("Drinks: %d%s - STOCK UP", summary.total, detail))
  else
    text:SetTextColor(0.4, 1.0, 0.4)
    text:SetText(string.format("Drinks: %d%s - you're good", summary.total, detail))
  end
  text:SetAlpha(1)
  frame.t = 0
  frame.duration = STOCK_DURATION
  frame.pulse = false
  frame:SetScript("OnUpdate", onUpdate)
  frame:Show()
  flash:Hide()
end

-- Hidden mana (_forever_): view = { percent, hasPercent, alpha = { [tier] = v }, has = { [tier] = true } }.
-- percent and alpha values are secret: never test or compare them, only pass them to widgets
-- (decide from the plain has/hasPercent flags).
-- sound: the controller confirmed low mana (can't afford a spell costing about the Critical cutoff).
function Alert.ShowHidden(view, sound)
  if not frame then return end
  frame.bg:Hide()
  text:SetText("")
  for _, tier in ipairs(HIDDEN_TIERS) do
    local fs = layer.texts[tier]
    local t = tierText(tier)
    local fmt, n = secretFormat(t)
    if n == 0 then
      fs:SetText(t)
    elseif not (view.hasPercent and pcall(fs.SetFormattedText, fs, fmt, rep(view.percent, n))) then
      fs:SetText(withoutPercent(t))
    end
    if not (view.has[tier] and pcall(fs.SetAlpha, fs, view.alpha[tier])) then fs:SetAlpha(0) end
  end
  layer:SetAlpha(1)
  layer:Show()

  frame.t = 0
  frame.duration = HIDDEN_DURATION
  frame.hiddenMode = true
  frame:SetScript("OnUpdate", onUpdate)
  frame:Show()

  local crit = profile.tiers.critical
  if crit.enabled and crit.flash and view.has.critical then
    if not pcall(flash.tex.SetAlpha, flash.tex, view.alpha.critical) then flash.tex:SetAlpha(0) end
    flash:SetAlpha(0.8)
    flash:Show()
  else
    flash:Hide()
  end
  if sound and crit.enabled and crit.sound ~= false then STYLE.critical.play() end
end

function Alert.Hide()
  if not frame then return end
  if not profile.alert.locked then
    Alert.SetLocked(false) -- back to the drag handle
    return
  end
  frame:SetScript("OnUpdate", nil)
  frame:Hide()
  flash:Hide()
  layer:Hide()
end

function Alert.SetLocked(locked)
  profile.alert.locked = locked
  if ns.DrinkButton and ns.DrinkButton.SetLocked then ns.DrinkButton.SetLocked(locked) end
  if not frame then return end
  frame:SetScript("OnUpdate", nil)
  flash:Hide()
  layer:Hide()
  frame.hiddenMode = false
  if locked then
    frame:EnableMouse(false)
    frame.bg:Hide()
    frame:Hide()
  else
    frame:EnableMouse(true)
    frame.bg:Show()
    text:SetFont(STANDARD_TEXT_FONT, 24, "THICKOUTLINE")
    text:SetTextColor(1, 1, 1)
    text:SetAlpha(1)
    text:SetText(editUnlocked and "Drink alert  -  drag me" or "Drag me  -  /drink lock when done")
    frame:Show()
  end
end

-- The game's Edit Mode opened or closed. Unlock while it's open; lock again afterwards only
-- if Edit Mode did the unlocking (an unlock made by hand stays as it was).
function Alert.EditMode(open)
  if not profile then return end
  if open then
    if profile.alert.locked then
      editUnlocked = true
      Alert.SetLocked(false)
    end
  elseif editUnlocked then
    editUnlocked = false
    Alert.SetLocked(true)
  end
end
