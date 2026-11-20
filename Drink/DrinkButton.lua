-- Clickable "drink this" button. A SecureActionButtonTemplate is required to use an item
-- from addon UI; secure frames can't be shown/hidden/moved/changed in combat, so:
--   * the holder has a secure state driver that hides it in combat (backstop),
--   * every change is skipped in combat and re-applied by FlushPending() afterwards,
--   * the holder is anchored to UIParent, never to the (insecure) alert frame.
local ADDON, ns = ...

local Btn = {}
ns.DrinkButton = Btn

local MIN_SIZE, MAX_SIZE = 24, 96

local profile, holder, button, placeholder, placeholderLabel, grip
local pendingHide, pendingLayout, pendingLock, pendingStop = false, false, nil, false

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function clampSize(n)
  return math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(n + 0.5)))
end

local function savePoint()
  local p, _, rp, x, y = holder:GetPoint()
  profile.button.point = { p, rp, x, y }
end

-- Mouse released after combat began mid-drag: the holder is protected now, so leave it alone
-- and let FlushPending stop the move and restore the saved layout.
local function deferStop()
  if not inCombat() then return false end
  pendingStop, pendingLayout = true, true
  return true
end

local function saveSize()
  local w, h = holder:GetSize()
  profile.button.size = clampSize(math.max(w or 0, h or 0))
  Btn.ApplyLayout()
end

local function create()
  holder = CreateFrame("Frame", "DrinkButtonHolder", UIParent, "SecureHandlerStateTemplate")
  holder:SetFrameStrata("HIGH")
  holder:SetClampedToScreen(true)
  holder:SetMovable(true)
  holder:SetResizable(true)
  if holder.SetResizeBounds then holder:SetResizeBounds(MIN_SIZE, MIN_SIZE, MAX_SIZE, MAX_SIZE) end
  holder:RegisterForDrag("LeftButton")
  holder:SetScript("OnDragStart", function(self) if not inCombat() then self:StartMoving() end end)
  holder:SetScript("OnDragStop", function(self)
    if deferStop() then return end
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    savePoint()
  end)
  RegisterStateDriver(holder, "visibility", "[combat] hide; show")

  -- Placeholder shown only while unlocked, so there is something to drag/resize.
  placeholder = holder:CreateTexture(nil, "BACKGROUND")
  placeholder:SetAllPoints()
  placeholder:SetColorTexture(0, 0.6, 1, 0.35)
  placeholderLabel = holder:CreateFontString(nil, "OVERLAY")
  placeholderLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  placeholderLabel:SetPoint("TOP", holder, "BOTTOM", 0, -2)
  placeholderLabel:SetText("Drink button")

  grip = CreateFrame("Button", nil, holder)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
  local gt = grip:CreateTexture(nil, "OVERLAY")
  gt:SetAllPoints()
  gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function() if not inCombat() then holder:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    if deferStop() then return end
    holder:StopMovingOrSizing()
    if holder.SetUserPlaced then holder:SetUserPlaced(false) end
    savePoint() -- sizing moves the anchor; re-read it so the button doesn't jump
    saveSize()
  end)

  button = CreateFrame("Button", "DrinkUseButton", holder, "SecureActionButtonTemplate")
  button:SetAllPoints(holder)
  button:RegisterForClicks("AnyUp") -- release only: one click can never use two drinks
  button:SetAttribute("type", "item")
  -- Always use the item on release, whatever the "cast on key down" setting is; PostClick below
  -- hides only on that release, so the ignored key-down click can't hide the button undrunk.
  button:SetAttribute("useOnKeyDown", false)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.count = button:CreateFontString(nil, "OVERLAY")
  button.count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  button.label = button:CreateFontString(nil, "OVERLAY")
  button.label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  button.label:SetPoint("TOP", button, "BOTTOM", 0, -2)
  button:SetScript("OnEnter", function(self)
    if self.itemID and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(self.itemID)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  button:HookScript("PostClick", function(_, _, down) if not down then Btn.Hide() end end)
  button:Hide()
end

function Btn.Init(p)
  profile = p
  if not holder then create() end
  Btn.ApplyLayout()
  Btn.SetLocked(profile.alert.locked)
end

function Btn.ApplyLayout()
  if not holder then return end
  if inCombat() then pendingLayout = true; return end
  pendingLayout = false
  local pt, size = profile.button.point, clampSize(profile.button.size)
  holder:ClearAllPoints()
  holder:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  holder:SetSize(size, size)
end

function Btn.SetLocked(locked)
  if not holder then return end
  if inCombat() then pendingLock = locked; return end
  pendingLock = nil
  holder:EnableMouse(not locked)
  if locked then
    placeholder:Hide(); placeholderLabel:Hide(); grip:Hide()
  else
    placeholder:Show(); placeholderLabel:Show(); grip:Show()
  end
end

-- Returns true if the button is now showing `drink`.
function Btn.Show(drink)
  if not button or inCombat() then return false end
  pendingHide = false
  button.itemID = drink.itemID
  button:SetAttribute("item", "item:" .. drink.itemID)
  button.icon:SetTexture(drink.icon)
  button.count:SetText((drink.count or 0) >= 1 and tostring(drink.count) or "")
  button.label:SetText(drink.name)
  button:Show()
  return true
end

function Btn.Hide()
  if not button then return end
  if inCombat() then pendingHide = true; return end
  pendingHide = false
  button:Hide()
end

-- Re-apply anything that was requested during combat (call on PLAYER_REGEN_ENABLED).
function Btn.FlushPending()
  if inCombat() then return end
  if pendingStop then
    pendingStop = false
    holder:StopMovingOrSizing()
    if holder.SetUserPlaced then holder:SetUserPlaced(false) end
  end
  if pendingHide then Btn.Hide() end
  if pendingLayout then Btn.ApplyLayout() end
  if pendingLock ~= nil then Btn.SetLocked(pendingLock) end
end
