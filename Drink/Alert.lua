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

local profile, frame, text, flash

local function savePoint()
  local p, _, rp, x, y = frame:GetPoint()
  profile.alert.point = { p, rp, x, y }
end

local function onUpdate(self, elapsed)
  self.t = self.t + elapsed
  local remaining = self.duration - self.t
  if remaining <= 0 then
    Alert.Hide()
    return
  end
  local alpha = 1
  if self.pulse then alpha = 0.55 + 0.45 * math.abs(math.sin(self.t * 5)) end
  if remaining < FADE then alpha = alpha * remaining / FADE end
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

  flash = CreateFrame("Frame", "DrinkAlertFlash", UIParent)
  flash:SetAllPoints(UIParent)
  flash:SetFrameStrata("BACKGROUND")
  local tex = flash:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
  tex:SetBlendMode("ADD")
  flash:Hide()
end

function Alert.ApplyLayout()
  if not frame then return end
  local p = profile.alert.point
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  frame:SetScale(profile.alert.scale)
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
  if style.play then style.play() end
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
end

function Alert.SetLocked(locked)
  profile.alert.locked = locked
  if not frame then return end
  frame:SetScript("OnUpdate", nil)
  flash:Hide()
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
