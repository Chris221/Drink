local NAMES = { "Enum", "UnitPower", "UnitPowerMax", "issecretvalue", "C_UnitAuras", "UnitBuff",
  "C_ChatInfo", "SendChatMessage", "IsInGroup", "IsInRaid", "LE_PARTY_CATEGORY_INSTANCE", "LE_PARTY_CATEGORY_HOME",
  "UnitAffectingCombat", "GetNumGroupMembers",
  "C_Container", "GetContainerNumSlots", "GetContainerItemID", "GetContainerItemInfo", "C_Item", "GetItemInfo",
  "C_TooltipInfo", "CreateFrame", "WorldFrame", "UnitLevel", "IsUsableItem", "GetItemCooldown",
  "DrinkScanTooltipTextLeft1", "DrinkScanTooltipTextLeft2", "DrinkScanTooltipTextLeft3",
  "C_RestrictedActions", "InCombatLockdown", "C_CurveUtil", "UnitPowerPercent", "CurveConstants", "C_SpellBook", "C_Spell",
  "GetManaRegen", "UnitClass", "UnitName", "UnitIsUnit" }

-- Run fn with the given WoW globals installed (all others in NAMES cleared), then restore.
local function with_globals(g, fn)
  local saved = {}
  for _, n in ipairs(NAMES) do saved[n] = _G[n]; _G[n] = g[n] end
  local ns = {}
  local ok, err = pcall(function()
    load_addon(ns, "Drink/Logic.lua")
    load_addon(ns, "Drink/Drinks.lua")
    load_addon(ns, "Drink/Compat.lua")
    fn(ns.Compat, ns)
  end)
  for _, n in ipairs(NAMES) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end

local function power(manaCur, manaMax, otherCur)
  return function(unit, ptype)
    assert(unit == "player")
    if ptype == 0 then return manaCur end
    return otherCur
  end, function(unit, ptype)
    if ptype == 0 then return manaMax end
    return 100
  end
end

test("compat: mana uses the mana power type (druid forms)", function()
  local up, upm = power(30, 100, 100)
  with_globals({ Enum = { PowerType = { Mana = 0 } }, UnitPower = up, UnitPowerMax = upm }, function(C)
    eq(C.GetManaPercent(), 30)
    eq(C.HasMana(), true)
  end)
  with_globals({ UnitPower = up, UnitPowerMax = upm }, function(C)
    eq(C.GetManaPercent(), 30, "without Enum global")
  end)
end)

test("compat: secret mana returns nil but still counts as having mana", function()
  local up, upm = power(30, 100, 100)
  with_globals({ UnitPower = up, UnitPowerMax = upm, issecretvalue = function() return true end }, function(C)
    eq(C.GetManaPercent(), nil)
    eq(C.HasMana(), true)
  end)
end)

test("compat: no mana pool", function()
  local up, upm = power(0, 0, 50)
  with_globals({ UnitPower = up, UnitPowerMax = upm }, function(C)
    eq(C.HasMana(), false)
    eq(C.GetManaPercent(), nil)
  end)
end)

test("compat: drink detection with modern aura API", function()
  local auras = { { name = "Well Fed" }, { name = "Refreshment" } }
  with_globals({
    C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
      assert(unit == "player" and filter == "HELPFUL"); return auras[i] end },
    UnitBuff = function() error("legacy UnitBuff must not be called") end,
  }, function(C, ns)
    local set = ns.Logic.ParseNames("Drink\nRefreshment")
    eq(C.IsDrinking(set), true)
    auras[2] = nil
    eq(C.IsDrinking(set), false)
  end)
end)

test("compat: drink detection with legacy UnitBuff", function()
  with_globals({ UnitBuff = function(unit, i) if i == 1 then return "Drink" end end }, function(C, ns)
    eq(C.IsDrinking(ns.Logic.ParseNames("Drink")), true)
    eq(C.IsDrinking(ns.Logic.ParseNames("Food & Drink")), false)
  end)
end)

test("compat: secret aura names are skipped", function()
  with_globals({
    C_UnitAuras = { GetAuraDataByIndex = function(_, i) if i == 1 then return { name = "Drink" } end end },
    issecretvalue = function() return true end,
  }, function(C, ns)
    eq(C.IsDrinking(ns.Logic.ParseNames("Drink")), false)
  end)
end)

test("compat: chat send and lockdown fallbacks", function()
  local got
  with_globals({ SendChatMessage = function(m, c) got = { m, c } end }, function(C)
    C.SendChat("hi", "PARTY")
    eq(got, { "hi", "PARTY" })
    eq(C.ChatLocked(), false)
  end)
  got = nil
  with_globals({
    C_ChatInfo = { SendChatMessage = function(m, c) got = { "modern", m, c } end,
                   InChatMessagingLockdown = function() return true end },
    SendChatMessage = function() error("legacy send must not be called") end,
  }, function(C)
    C.SendChat("hi", "RAID")
    eq(got, { "modern", "hi", "RAID" })
    eq(C.ChatLocked(), true)
  end)
end)

test("compat: group state", function()
  with_globals({
    IsInGroup = function(cat) if cat == 2 then return true end return true end,
    IsInRaid = function() return false end,
    LE_PARTY_CATEGORY_INSTANCE = 2,
  }, function(C)
    eq(C.GroupState(), { instance = true, raid = false, party = true })
  end)
  with_globals({ IsInGroup = function() return false end, IsInRaid = function() return false end },
    function(C)
      eq(C.GroupState(), { instance = false, raid = false, party = false })
    end)
end)

test("compat: group in combat checks party and raid units", function()
  local fighting = {}
  local g = {
    IsInGroup = function() return true end,
    IsInRaid = function() return false end,
    GetNumGroupMembers = function() return 3 end,
    UnitAffectingCombat = function(u) return fighting[u] == true end,
  }
  with_globals(g, function(C)
    eq(C.GroupInCombat(), false)
    fighting.party2 = true
    eq(C.GroupInCombat(), true)
  end)
  fighting = { raid5 = true }
  g.IsInRaid = function() return true end
  g.GetNumGroupMembers = function() return 10 end
  with_globals(g, function(C)
    eq(C.GroupInCombat(), true)
  end)
end)

test("compat: LFG-only group is not a home party/raid (fixed channels)", function()
  -- Dungeon finder group: in an instance group, not in a home party.
  local inCat = { [1] = false, [2] = true }
  with_globals({
    IsInGroup = function(cat) if cat == nil then return true end return inCat[cat] end,
    IsInRaid = function(cat) if cat == nil then return true end return false end,
    LE_PARTY_CATEGORY_HOME = 1,
    LE_PARTY_CATEGORY_INSTANCE = 2,
  }, function(C, ns)
    local s = C.GroupState()
    eq(s, { instance = true, raid = false, party = false })
    eq(ns.Logic.PickChannel("PARTY", s), nil, "fixed PARTY must not send in an LFG-only group")
    eq(ns.Logic.PickChannel("AUTO", s), "INSTANCE_CHAT")
  end)
end)

-- A secret value: any arithmetic or comparison on it errors, like the real thing.
local SECRET = setmetatable({}, { __index = function() error("secret value used") end,
  __lt = function() error("compared a secret") end, __le = function() error("compared a secret") end,
  __div = function() error("math on a secret") end, __tostring = function() error("tostring of a secret") end })

test("compat: debug line on a client with secret mana and restrictions", function()
  with_globals({
    Enum = { PowerType = { Mana = 0 }, AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 } },
    UnitPower = function() return SECRET end, UnitPowerMax = function() return SECRET end,
    issecretvalue = function(v) return v == SECRET end,
    InCombatLockdown = function() return false end,
    C_RestrictedActions = { GetAddOnRestrictionState = function(t) return t == 4 and 2 or 0 end },
  }, function(C)
    eq(C.ManaDebugLine(), "mana=secret max=secret lockdown=no restrictions: Combat=0 Encounter=0 ChallengeMode=0 PvPMatch=0 Map=2")
  end)
end)

test("compat: debug line with readable mana and no restriction API (Classic)", function()
  local up, upm = power(615, 1445, 0)
  with_globals({ UnitPower = up, UnitPowerMax = upm, InCombatLockdown = function() return true end }, function(C)
    eq(C.ManaDebugLine(), "mana=615/1445 (43%) lockdown=yes restrictions: n/a")
  end)
end)

-- _forever_ hidden mana -----------------------------------------------------------

-- Fake curve API: curves record their points; UnitPowerPercent returns a tagged "secret".
local function curveWorld(extra)
  local g = {
    Enum = { PowerType = { Mana = 0 }, LuaCurveType = { Step = 1 } },
    UnitPower = function() return SECRET end, UnitPowerMax = function() return 1445 end,
    issecretvalue = function(v) return v == SECRET or (type(v) == "table" and v.secret == true) end,
    C_CurveUtil = { CreateCurve = function()
      local c = { points = {} }
      function c:SetType(t) self.type = t end
      function c:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
      return c
    end },
    UnitPowerPercent = function(unit, ptype, predicted, curve)
      assert(unit == "player" and ptype == 0 and predicted == false)
      return { secret = true, curve = curve }
    end,
  }
  for k, v in pairs(extra or {}) do g[k] = v end
  return g
end

test("compat: hidden mana detected only when the game can draw it", function()
  with_globals(curveWorld(), function(C) eq(C.ManaHidden(), true) end)
  with_globals(curveWorld({ UnitPowerPercent = false }), function(C) eq(C.ManaHidden(), false, "no curve API") end)
  local up, upm = power(615, 1445, 0)
  with_globals(curveWorld({ UnitPower = up, UnitPowerMax = upm }), function(C) eq(C.ManaHidden(), false, "readable") end)
end)

test("compat: hidden view gives the game a band curve per tier and a 0-100 percent", function()
  local scale = { name = "ScaleTo100" }
  with_globals(curveWorld({ CurveConstants = { ScaleTo100 = scale } }), function(C)
    local view = C.HiddenManaView({ { tier = "critical", from = 0, to = 0.2 }, { tier = "fyi", from = 0.8 } })
    eq(view.percent.curve, scale)
    eq(view.alpha.critical.curve.points, { { 0, 1 }, { 0.2, 0 } })
    eq(view.alpha.fyi.curve.points, { { 0, 0 }, { 0.8, 1 } })
    eq(view.alpha.critical.curve.type, 1)
    eq(view.alpha.heads, nil, "disabled tier gets nothing")
    eq(view.has, { critical = true, fyi = true }, "plain flags for what the game returned")
    eq(view.hasPercent, true)
  end)
end)

test("compat: hidden view flags a refused curve without touching the value", function()
  with_globals(curveWorld({ UnitPowerPercent = function() error("refused") end, CurveConstants = { ScaleTo100 = {} } }), function(C)
    local view = C.HiddenManaView({ { tier = "critical", from = 0, to = 0.2 } })
    eq(view.has, {}); eq(view.hasPercent, false)
  end)
end)

test("compat: hidden message formats the template with the game's percent", function()
  with_globals(curveWorld({ UnitPowerPercent = function() return 57 end, CurveConstants = { ScaleTo100 = {} } }), function(C)
    eq(C.HiddenMessage("Drinking — %m% mana"), "[Drink] Drinking — 57% mana")
  end)
end)

local function spellWorld(insufficient)
  return curveWorld({
    Enum = { PowerType = { Mana = 0 }, LuaCurveType = { Step = 1 }, SpellBookSpellBank = { Player = 0 },
             SpellBookItemType = { Spell = 1 } },
    C_SpellBook = {
      GetNumSpellBookSkillLines = function() return 1 end,
      GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 3 } end,
      GetSpellBookItemInfo = function(slot)
        return ({ { spellID = 10, itemType = 1 }, { spellID = 20, itemType = 1 }, { spellID = 30, itemType = 1, isPassive = true } })[slot]
      end,
    },
    C_Spell = {
      GetSpellPowerCost = function(id)
        return ({ [10] = { { type = 0, cost = 125 } }, [20] = { { type = 0, cost = 255 } }, [30] = { { type = 0, cost = 999 } } })[id]
      end,
      IsSpellUsable = function(id) assert(id == 20, "asks about the costliest active spell"); return not insufficient, insufficient end,
    },
  })
end

test("compat: low mana confirmed when the costliest spell is unaffordable", function()
  with_globals(spellWorld(true), function(C) eq(C.LowManaConfirmed(), true) end)
  with_globals(spellWorld(false), function(C) eq(C.LowManaConfirmed(), false) end)
  with_globals(curveWorld(), function(C) eq(C.LowManaConfirmed(), false, "no spellbook API") end)
end)

-- Extras ------------------------------------------------------------------------

test("compat: mana regen per second, nil when missing, secret or zero", function()
  with_globals({ GetManaRegen = function() return 7.5, 2 end }, function(C) eq(C.GetManaRegen(), 7.5) end)
  with_globals({}, function(C) eq(C.GetManaRegen(), nil) end)
  with_globals({ GetManaRegen = function() return 0, 0 end }, function(C) eq(C.GetManaRegen(), nil) end)
  with_globals({ GetManaRegen = function() return SECRET end, issecretvalue = function(v) return v == SECRET end },
    function(C) eq(C.GetManaRegen(), nil) end)
end)

local function groupWorld(units, raid, extra)
  local g = {
    IsInGroup = function() return true end,
    IsInRaid = function() return raid end,
    GetNumGroupMembers = function() return raid and #units or #units + 1 end,
    UnitClass = function(unit) local u = units[unit]; if u then return u.class, u.file end end,
    UnitName = function(unit) local u = units[unit]; if u then return u.name, u.realm end end,
    UnitIsUnit = function(unit, other) return units[unit] and units[unit].me == true and other == "player" end,
  }
  for k, v in pairs(extra or {}) do g[k] = v end
  return g
end

test("compat: finds a mage in the party or raid, never me", function()
  local party = { party1 = { name = "Anduin", file = "PRIEST" }, party2 = { name = "Jaina", file = "MAGE" } }
  party[1], party[2] = true, true
  with_globals(groupWorld(party, false), function(C) eq(C.FindMage(), "Jaina") end)
  local raid = { raid1 = { name = "Me", file = "MAGE", me = true }, raid2 = { name = "Khadgar", realm = "Dalaran", file = "MAGE" } }
  raid[1], raid[2] = true, true
  with_globals(groupWorld(raid, true), function(C) eq(C.FindMage(), "Khadgar-Dalaran") end)
  local none = { party1 = { name = "Anduin", file = "PRIEST" } }
  none[1] = true
  with_globals(groupWorld(none, false), function(C) eq(C.FindMage(), nil) end)
  with_globals({ IsInGroup = function() return false end }, function(C) eq(C.FindMage(), nil) end)
end)

test("compat: a secret class or name is skipped, not compared", function()
  local party = { party1 = { name = "Jaina", file = SECRET }, party2 = { name = SECRET, file = "MAGE" } }
  party[1], party[2] = true, true
  with_globals(groupWorld(party, false, { issecretvalue = function(v) return v == SECRET end }),
    function(C) eq(C.FindMage(), nil) end)
end)

test("compat: whisper uses the modern or legacy send", function()
  local calls = {}
  with_globals({ C_ChatInfo = { SendChatMessage = function(...) calls[#calls + 1] = { "new", ... } end } },
    function(C) C.SendWhisper("hi", "Jaina") end)
  with_globals({ SendChatMessage = function(...) calls[#calls + 1] = { "old", ... } end },
    function(C) C.SendWhisper("hi", "Jaina") end)
  eq(calls, { { "new", "hi", "WHISPER", nil, "Jaina" }, { "old", "hi", "WHISPER", nil, "Jaina" } })
end)

test("compat: hidden drink stats are evaluated by the game and formatted", function()
  local made = {}
  local world = curveWorld({
    Enum = { PowerType = { Mana = 0 }, LuaCurveType = { Step = 1, Linear = 0 } },
    UnitPowerPercent = function(unit, ptype, predicted, curve)
      made[#made + 1] = curve
      return curve.type == 0 and 18 or 2
    end,
  })
  with_globals(world, function(C)
    local drink = { itemID = 1205, name = "Melon Juice", mana = 450, seconds = 30 }
    eq(C.HiddenStatsMessage(drink, 1000, 0), "[Drink] Melon Juice x2: ~18s to full")
    local linear, step
    for _, c in ipairs(made) do if c.type == 0 then linear = c else step = c end end
    eq(linear.points, { { 0, 67 }, { 1, 0 } })
    eq(#step.points, 4)
    eq(step.points[1], { 0, 3 })
  end)
end)

test("compat: hidden drink stats give nothing when curves are unsupported or refused", function()
  local drink = { itemID = 1205, name = "Melon Juice", mana = 450, seconds = 30 }
  with_globals(curveWorld(), function(C) eq(C.HiddenStatsMessage(drink, 1000, 0), nil, "no linear curves") end)
  with_globals(curveWorld({
    Enum = { PowerType = { Mana = 0 }, LuaCurveType = { Step = 1, Linear = 0 } },
    UnitPowerPercent = function() error("refused") end,
  }), function(C) eq(C.HiddenStatsMessage(drink, 1000, 0), nil) end)
end)
