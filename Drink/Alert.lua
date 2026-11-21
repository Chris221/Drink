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

local profile, frame, text, flash, layer, critHolder
local HIDDEN_DURATION = 4 -- hidden mana: the addon can't tell which tier the game showed
local HIDDEN_TIERS = { "fyi", "heads", "low", "critical" }

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
  if pct then
    text:SetText(string.format("DRINK!  %d%% mana", pct))
  else
    text:SetText("DRINK!  (mana unknown)")
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

-- Stock check line: green when you're good, orange when you should restock. Silent, no flash.
local STOCK_DURATION = 6
function Alert.ShowStock(summary)
  if not frame then return end
  frame.bg:Hide()
  frame.hiddenMode = false
  layer:Hide()
  text:SetFont(STANDARD_TEXT_FONT, 24, "THICKOUTLINE")
  if summary.low then
    text:SetTextColor(1.0, 0.6, 0.1)
    text:SetText(string.format("Drinks: %d (~%d refills) - STOCK UP", summary.total, summary.refills))
  else
    text:SetTextColor(0.4, 1.0, 0.4)
    text:SetText(string.format("Drinks: %d (~%d refills) - you're good", summary.total, summary.refills))
  end
  text:SetAlpha(1)
  frame.t = 0
  frame.duration = STOCK_DURATION
  frame.pulse = false
  frame:SetScript("OnUpdate", onUpdate)
  frame:Show()
  flash:Hide()
end

-- Hidden mana (_forever_): view = { percent = <secret>, alpha = { [tier] = <secret 0/1> } }.
-- sound: the controller confirmed low mana (can't afford the costliest spell).
function Alert.ShowHidden(view, sound)
  if not frame then return end
  frame.bg:Hide()
  text:SetText("")
  for _, tier in ipairs(HIDDEN_TIERS) do
    local fs = layer.texts[tier]
    if not pcall(fs.SetFormattedText, fs, "DRINK!  %d%% mana", view.percent) then
      fs:SetText("DRINK!")
    end
    if not pcall(fs.SetAlpha, fs, view.alpha[tier] or 0) then fs:SetAlpha(0) end
  end
  layer:SetAlpha(1)
  layer:Show()

  frame.t = 0
  frame.duration = HIDDEN_DURATION
  frame.hiddenMode = true
  frame:SetScript("OnUpdate", onUpdate)
  frame:Show()

  local crit = profile.tiers.critical
  if crit.enabled and crit.flash and view.alpha.critical ~= nil then
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
    text:SetText("Drag me  -  /drink lock when done")
    frame:Show()
  end
end
