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

-- Returns whether a drink buff is up and, where the game says, when it runs out (GetTime
-- seconds; nil if hidden).
function Compat.IsDrinking(nameSet)
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for i = 1, 255 do
    local name, ends, _
    if getAura then
      local aura = getAura("player", i, "HELPFUL")
      if not aura then return false end
      name, ends = aura.name, aura.expirationTime
    else
      name, _, _, _, _, ends = UnitBuff("player", i)
      if not name then return false end
    end
    if not isSecret(name) and Logic.IsDrinkAura(name, nameSet) then
      if isSecret(ends) or type(ends) ~= "number" then ends = nil end
      return true, ends
    end
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
-- true / false, or nil when the game hides the answer (a secret value): callers must treat
-- nil as "unknown". Secret values are never tested here.
function Compat.GroupInCombat()
  if not IsInGroup() then return false end
  local n = GetNumGroupMembers() or 0
  local raid = IsInRaid()
  for i = 1, raid and n or n - 1 do
    local unit = (raid and "raid" or "party") .. i
    local me = false
    if raid and UnitIsUnit then
      me = UnitIsUnit(unit, "player")
      if isSecret(me) then return nil end
    end
    if not me then
      local fighting = UnitAffectingCombat(unit)
      if isSecret(fighting) then return nil end
      if fighting then return true end
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

-- Diagnostics -----------------------------------------------------------------

local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }

local function describe(v)
  if isSecret(v) then return "secret" end
  if v == nil then return "nil" end
  return tostring(v)
end

-- One line describing whether mana is readable and which addon restrictions are active.
-- Never does math or comparisons on a value that might be secret.
function Compat.ManaDebugLine()
  local t = manaType()
  local cur, max = UnitPower("player", t), UnitPowerMax("player", t)
  local mana
  if isSecret(cur) or isSecret(max) then
    mana = "mana=" .. describe(cur) .. " max=" .. describe(max)
  else
    local pct = Logic.ManaPercent(cur, max)
    mana = "mana=" .. describe(cur) .. "/" .. describe(max) .. (pct and (" (" .. pct .. "%)") or "")
  end
  local lockdown = (InCombatLockdown and InCombatLockdown()) and "yes" or "no"
  local parts = {}
  local types = Enum and Enum.AddOnRestrictionType
  local get = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
  if types and get then
    for _, name in ipairs(RESTRICTIONS) do
      if types[name] ~= nil then parts[#parts + 1] = name .. "=" .. describe(get(types[name])) end
    end
  end
  return mana .. " lockdown=" .. lockdown .. " restrictions: " .. (#parts > 0 and table.concat(parts, " ") or "n/a")
end

-- Hidden mana (_forever_) -----------------------------------------------------------
-- Current mana is a secret value there: no comparing or math. The game can still evaluate
-- curves on it (UnitPowerPercent) and widgets can display the result. Same approach as
-- HealerTrafficLight / HealthBarTextForever.

local function curvesSupported()
  return C_CurveUtil and C_CurveUtil.CreateCurve and UnitPowerPercent
    and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and true or false
end

function Compat.ManaHidden()
  if not curvesSupported() then return false end
  return isSecret(UnitPower("player", manaType()))
end

local curveCache, percentCurve = {}, nil

-- Step curve over 0..1 of max mana: 1 inside [from, to), 0 elsewhere (to = nil: up to 100%).
local function bandCurve(from, to)
  local key = tostring(from) .. ":" .. tostring(to)
  if curveCache[key] then return curveCache[key] end
  local c = C_CurveUtil.CreateCurve()
  c:SetType(Enum.LuaCurveType.Step)
  if from > 0 then c:AddPoint(0, 0) end
  c:AddPoint(from, 1)
  if to then c:AddPoint(to, 0) end
  curveCache[key] = c
  return c
end

local function pctCurve()
  if CurveConstants and CurveConstants.ScaleTo100 then return CurveConstants.ScaleTo100 end
  if not percentCurve then
    percentCurve = C_CurveUtil.CreateCurve()
    percentCurve:SetType(Enum.LuaCurveType.Step)
    for i = 0, 100 do percentCurve:AddPoint(i / 100, i) end
  end
  return percentCurve
end

-- Returns ok, value. The value may be secret: callers must not test or compare it, only
-- pass it on to a widget. `ok` is a plain boolean.
local function gamePercent(curve)
  return pcall(UnitPowerPercent, "player", manaType(), false, curve)
end

-- For the alert to display:
--   percent = <secret 0-100>, hasPercent = bool
--   alpha = { [tier] = <secret 0 or 1> }, has = { [tier] = true }
-- The has/hasPercent flags are plain, so nothing ever has to test a secret value.
function Compat.HiddenManaView(bands)
  local view = { alpha = {}, has = {} }
  local ok, pct = gamePercent(pctCurve())
  if ok then view.percent = pct end
  view.hasPercent = ok
  for _, b in ipairs(bands) do
    local okBand, a = gamePercent(bandCurve(b.from, b.to))
    if okBand then
      view.alpha[b.tier] = a
      view.has[b.tier] = true
    end
  end
  return view
end

-- "[Drink] <template with the real %>", for printing to my own chat (it can't be sent).
function Compat.HiddenMessage(template)
  local okPct, pct = gamePercent(pctCurve())
  if okPct then
    local ok, msg = pcall(string.format, "[Drink] " .. Logic.TemplateFormat(template), pct)
    if ok then return msg end
  end
  return "[Drink] " .. Logic.WithoutNumber(template, "Drinking")
end

-- True when the game says I can't afford a yardstick spell: a real, comparable answer about
-- low mana even while the amount itself is hidden. The yardstick is the active mana spell
-- whose cost is nearest targetPct of my max mana (HealerProtection's approach), so true
-- means roughly "below targetPct". A spell that takes the whole pool (Lay on Hands) is never
-- the yardstick. With max mana unreadable it falls back to the costliest spell.
function Compat.LowManaConfirmed(targetPct)
  local book, spell = C_SpellBook, C_Spell
  local types = Enum and Enum.SpellBookItemType
  local bank = Enum and Enum.SpellBookSpellBank
  if not (book and book.GetNumSpellBookSkillLines and spell and spell.GetSpellPowerCost
          and spell.IsSpellUsable and types and bank) then return false end
  local max = Compat.GetMaxMana()
  local target = max and targetPct and max * targetPct / 100
  local best, bestScore
  for i = 1, book.GetNumSpellBookSkillLines() do
    local line = book.GetSpellBookSkillLineInfo(i)
    if line and not line.offSpecID then
      for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
        local item = book.GetSpellBookItemInfo(slot, bank.Player)
        if item and item.itemType == types.Spell and not item.isPassive and item.spellID then
          local ok, costs = pcall(spell.GetSpellPowerCost, item.spellID)
          if ok and type(costs) == "table" and not isSecret(costs) then
            for _, c in ipairs(costs) do
              local cost = c.cost
              if not isSecret(c.type) and c.type == manaType()
                  and not isSecret(cost) and type(cost) == "number" and cost > 0 then
                local score -- higher is better
                if not target then
                  score = cost
                elseif cost < max then
                  score = -math.abs(cost - target)
                end
                if score and (not bestScore or score > bestScore) then
                  best, bestScore = item.spellID, score
                end
              end
            end
          end
        end
      end
    end
  end
  if not best then return false end
  local ok, _, insufficient = pcall(spell.IsSpellUsable, best)
  if not ok or isSecret(insufficient) then return false end
  return insufficient == true
end

-- False when I'm fighting on another resource (bear or cat form, shadow, elemental...): the
-- mana pool is there but isn't what I'm spending. Unknown counts as mana.
function Compat.ManaIsActive()
  if not UnitPowerType then return true end
  local ok, powerType = pcall(UnitPowerType, "player")
  if not ok or isSecret(powerType) or powerType == nil then return true end
  return powerType == manaType()
end

-- The game's Edit Mode (its HUD layout editor), on clients that have one: onChange(true) when
-- it opens, onChange(false) when it closes. Returns whether there was anything to watch.
function Compat.WatchEditMode(onChange)
  if not (EditModeManagerFrame and EventRegistry and EventRegistry.RegisterCallback) then return false end
  EventRegistry:RegisterCallback("EditMode.Enter", function() onChange(true) end)
  EventRegistry:RegisterCallback("EditMode.Exit", function() onChange(false) end)
  return true
end

-- Name of the dungeon or raid I'm in (plain string), or nil if the game won't say.
function Compat.InstanceName()
  if not GetInstanceInfo then return nil end
  local ok, name = pcall(GetInstanceInfo)
  if not ok or isSecret(name) or type(name) ~= "string" or name == "" then return nil end
  return name
end

-- Extras ------------------------------------------------------------------------

-- Out-of-combat mana regen per second, or nil when the game doesn't give a usable number.
function Compat.GetManaRegen()
  if not GetManaRegen then return nil end
  local ok, base = pcall(GetManaRegen)
  if not ok or isSecret(base) or type(base) ~= "number" or base <= 0 then return nil end
  return base
end

-- Name of a mage in my group (not me), or nil. Secret class/name values are skipped untested.
function Compat.FindMage()
  if not (IsInGroup and IsInGroup()) or not UnitClass or not UnitName then return nil end
  -- A mage makes their own water: never offer to ask another mage.
  local _, myClass = UnitClass("player")
  if not isSecret(myClass) and myClass == "MAGE" then return nil end
  local raid = IsInRaid and IsInRaid()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local count = raid and n or n - 1
  for i = 1, count do
    local unit = (raid and "raid" or "party") .. i
    local isMe = raid and UnitIsUnit and UnitIsUnit(unit, "player")
    if isSecret(isMe) then isMe = true end
    if not isMe then
      local _, file = UnitClass(unit)
      if not isSecret(file) and file == "MAGE" then
        local name, realm = UnitName(unit)
        if not isSecret(name) and type(name) == "string" then
          if not isSecret(realm) and type(realm) == "string" and realm ~= "" then
            return name .. "-" .. realm
          end
          return name
        end
      end
    end
  end
  return nil
end

function Compat.SendWhisper(msg, name)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, name)
  else
    SendChatMessage(msg, "WHISPER", nil, name)
  end
end

local function curveFrom(points, curveType)
  local c = C_CurveUtil.CreateCurve()
  c:SetType(curveType)
  for _, pt in ipairs(points) do c:AddPoint(pt[1], pt[2]) end
  return c
end

local statsCurves = {} -- "itemID:max:regen" -> { seconds = curve, drinks = curve }

-- Hidden mana: "[Drink] <name> x<drinks>: ~<seconds>s to full", with both numbers worked out
-- by the game from curves (the addon can't do maths on the hidden amount).
-- Returns ok, message. `ok` is a plain boolean; the message is a SECRET string when ok, so
-- callers must only pass it on (print), never test it. false when linear curves aren't
-- available or the game refuses. Decides only from pcall results.
function Compat.HiddenStatsMessage(drink, maxMana, regen)
  if not curvesSupported() or Enum.LuaCurveType.Linear == nil then return false end
  local key = tostring(drink.itemID) .. ":" .. tostring(maxMana) .. ":" .. tostring(regen or 0)
  local curves = statsCurves[key]
  if not curves then
    local points = Drinks.FillCurves(drink, maxMana, regen)
    if not points then return false end
    local ok, built = pcall(function()
      return { seconds = curveFrom(points.seconds, Enum.LuaCurveType.Linear),
               drinks = curveFrom(points.drinks, Enum.LuaCurveType.Step) }
    end)
    if not ok then return false end
    curves = built
    statsCurves[key] = curves
  end
  local okS, seconds = gamePercent(curves.seconds)
  local okD, count = gamePercent(curves.drinks)
  if not (okS and okD) then return false end
  local okF, msg = pcall(string.format, "[Drink] %s x%d: ~%ds to full", drink.name, count, seconds)
  if not okF then return false end
  return true, msg
end
