-- WoW API feature detection. Looks up globals at call time so it works on
-- _forever_ (16001), MoP Classic (50504) and Retail/Midnight (12.x).
local ADDON, ns = ...
local Logic = ns.Logic

local Compat = {}
ns.Compat = Compat

local function isSecret(v)
  local f = issecretvalue
  return f ~= nil and f(v) and true or false
end

local function manaType()
  return Enum and Enum.PowerType and Enum.PowerType.Mana or 0
end

function Compat.HasMana()
  local max = UnitPowerMax("player", manaType())
  if isSecret(max) then return true end
  return (max or 0) > 0
end

function Compat.GetManaPercent()
  local t = manaType()
  local cur, max = UnitPower("player", t), UnitPowerMax("player", t)
  if isSecret(cur) or isSecret(max) then return nil end
  return Logic.ManaPercent(cur, max)
end

function Compat.IsDrinking(nameSet)
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for i = 1, 255 do
    local name
    if getAura then
      local aura = getAura("player", i, "HELPFUL")
      if not aura then return false end
      name = aura.name
    else
      name = UnitBuff("player", i)
      if not name then return false end
    end
    if not isSecret(name) and Logic.IsDrinkAura(name, nameSet) then return true end
  end
  return false
end

function Compat.SendChat(msg, channel)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    C_ChatInfo.SendChatMessage(msg, channel)
  else
    SendChatMessage(msg, channel)
  end
end

function Compat.ChatLocked()
  local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  return f ~= nil and f() and true or false
end

function Compat.GroupState()
  local instance = false
  if LE_PARTY_CATEGORY_INSTANCE then
    instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false
  end
  -- party/raid mean the *home* group: an LFD/LFR-only group can only use INSTANCE_CHAT.
  local home = LE_PARTY_CATEGORY_HOME
  return {
    instance = instance,
    raid = IsInRaid(home) and true or false,
    party = IsInGroup(home) and true or false,
  }
end

-- Any group member (other than the player) still in combat?
function Compat.GroupInCombat()
  if not IsInGroup() then return false end
  local n = GetNumGroupMembers() or 0
  if IsInRaid() then
    for i = 1, n do
      local unit = "raid" .. i
      if not (UnitIsUnit and UnitIsUnit(unit, "player")) and UnitAffectingCombat(unit) then return true end
    end
  else
    for i = 1, n - 1 do
      if UnitAffectingCombat("party" .. i) then return true end
    end
  end
  return false
end

-- Drinks in bags ------------------------------------------------------------

local Drinks = ns.Drinks
-- Backpack + equipped bags (+ Retail/_forever_ reagent bag). Never NUM_BAG_SLOTS + 1 on Classic:
-- there that index is the first bank bag.
local function lastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end
local COOLDOWN_GCD = 1.5
local parseCache = {}                -- itemID -> { parsed = table|false, conjured = bool }

function Compat.GetMaxMana()
  local max = UnitPowerMax("player", manaType())
  if isSecret(max) or not max or max <= 0 then return nil end
  return max
end

local function numSlots(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return f and f(bag) or 0
end

-- itemID, count, icon for a bag slot (or nil when empty)
local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount, info.iconFileID end
    return nil
  end
  local id = GetContainerItemID(bag, slot)
  if not id then return nil end
  local icon, count = GetContainerItemInfo(bag, slot)
  return id, count, icon
end

local function itemInfo(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, _, _, minLevel = f(id)
  return name, minLevel
end

local scanTip
local function tooltipLines(id)
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local data = C_TooltipInfo.GetItemByID(id)
    for i, line in ipairs(data and data.lines or {}) do lines[i] = line.leftText end
    return lines
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "DrinkScanTooltip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetItemByID(id)
  for i = 1, scanTip:NumLines() do
    local fs = _G["DrinkScanTooltipTextLeft" .. i]
    lines[i] = fs and fs:GetText()
  end
  return lines
end

local function isUsable(id, minLevel)
  if minLevel and UnitLevel and minLevel > UnitLevel("player") then return false end
  local usable = (C_Item and C_Item.IsUsableItem) or IsUsableItem
  if usable and not usable(id) then return false end
  local cooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if cooldown then
    local start, duration = cooldown(id)
    if start and start > 0 and duration and duration > COOLDOWN_GCD then return false end
  end
  return true
end

local function parsedFor(id, name)
  local cached = parseCache[id]
  if cached == nil then
    local lines = tooltipLines(id)
    cached = { parsed = Drinks.ParseTooltip(lines) or false, conjured = Drinks.IsConjured(name, lines) }
    -- A 0-1 line tooltip means item data hadn't loaded yet: don't remember it as "not a drink".
    if cached.parsed or #lines >= 2 then parseCache[id] = cached end
  end
  return cached
end

-- Usable drinks in bags, one entry per itemID:
-- { itemID, name, icon, count, mana, seconds, conjured }
function Compat.ScanDrinks(overrides)
  overrides = overrides or {}
  local counts, icons, order = {}, {}, {}
  for bag = 0, lastBag() do
    for slot = 1, numSlots(bag) do
      local id, count, icon = slotItem(bag, slot)
      if id then
        if not counts[id] then order[#order + 1] = id; counts[id] = 0; icons[id] = icon end
        counts[id] = counts[id] + (count or 1)
      end
    end
  end

  local maxMana = Compat.GetMaxMana() or 0
  local out = {}
  for _, id in ipairs(order) do
    local name, minLevel = itemInfo(id)
    if name then
      local override = overrides[string.lower(name)] or overrides[tostring(id)]
      local info = parsedFor(id, name)
      local mana, seconds
      if override then
        mana, seconds = override.mana, override.seconds
      elseif info.parsed then
        mana, seconds = Drinks.Resolve(info.parsed, maxMana)
      end
      if mana and mana > 0 and isUsable(id, minLevel) then
        out[#out + 1] = { itemID = id, name = name, icon = icons[id], count = counts[id],
                          mana = mana, seconds = seconds, conjured = info.conjured }
      end
    end
  end
  return out
end
