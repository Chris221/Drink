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
  return {
    instance = instance,
    raid = IsInRaid() and true or false,
    party = IsInGroup() and true or false,
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
