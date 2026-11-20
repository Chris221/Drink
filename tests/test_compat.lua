local NAMES = { "Enum", "UnitPower", "UnitPowerMax", "issecretvalue", "C_UnitAuras", "UnitBuff",
  "C_ChatInfo", "SendChatMessage", "IsInGroup", "IsInRaid", "LE_PARTY_CATEGORY_INSTANCE",
  "UnitAffectingCombat", "GetNumGroupMembers" }

-- Run fn with the given WoW globals installed (all others in NAMES cleared), then restore.
local function with_globals(g, fn)
  local saved = {}
  for _, n in ipairs(NAMES) do saved[n] = _G[n]; _G[n] = g[n] end
  local ns = {}
  local ok, err = pcall(function()
    load_addon(ns, "Drink/Logic.lua")
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
