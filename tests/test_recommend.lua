local FakeEnv = require("fake_env")
local ns = {}
load_addon(ns, "Drink/Logic.lua")
load_addon(ns, "Drink/Drinks.lua")
load_addon(ns, "Drink/Tally.lua")
load_addon(ns, "Drink/Defaults.lua")
load_addon(ns, "Drink/Controller.lua")

local function d(name, mana, seconds, conjured, count)
  return { itemID = #name, name = name, icon = 1, mana = mana, seconds = seconds or 30,
           conjured = conjured or false, count = count or 5 }
end
local THREE = { d("Big", 800), d("Mid", 450), d("Small", 300) }

local function setup(o, tweak)
  local profile = deepcopy(ns.defaults.profile)
  if tweak then tweak(profile) end
  local env = FakeEnv.New(o)
  local ctrl = ns.Controller.New(profile, env)
  ctrl:SyncDrinking()
  return ctrl, env, profile
end

local function fight(ctrl, env, len)
  ctrl:OnCombatStart(); env:advance(len); ctrl:OnCombatEnd(); env:advance(0)
end

test("recommend: shows smallest covering drink on combat end", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Mid" })
end)

test("recommend: respects the below threshold", function()
  local ctrl, env = setup({ mana = 85, drinks = THREE })
  fight(ctrl, env, 10)
  eq(#env.buttonShows, 0)
  ctrl, env = setup({ mana = 85, drinks = THREE }, function(p) p.recommend.below = 100 end)
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Small" }, "deficit 150 -> smallest covering is 300")
end)

test("recommend: disabled, drinking, no drinks, unknown mana, dead", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE }, function(p) p.recommend.enabled = false end)
  fight(ctrl, env, 10); eq(#env.buttonShows, 0, "disabled")
  ctrl, env = setup({ mana = 60, drinks = {} })
  fight(ctrl, env, 10); eq(#env.buttonShows, 0, "no drinks")
  ctrl, env = setup({ unknownMana = true, drinks = THREE })
  fight(ctrl, env, 10); eq(#env.buttonShows, 0, "unknown mana")
  ctrl, env = setup({ mana = 60, drinks = THREE, dead = true })
  fight(ctrl, env, 10); eq(#env.buttonShows, 0, "dead")
  ctrl, env = setup({ mana = 60, drinks = THREE, group = { party = true }, groupCombat = true },
    function(p) p.alert.waitForGroup = true end)
  fight(ctrl, env, 10)
  env:advance(1)
  env.drinking = true; ctrl:OnAuraChanged()
  env.groupCombat = false; env:advance(1)
  eq(#env.buttonShows, 0, "already drinking")
end)

test("recommend: works even when the alert tier is disabled", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE }, function(p) p.tiers.heads.enabled = false; p.alert.enabled = false end)
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Mid" })
end)

test("recommend: button hidden when a pull starts", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  fight(ctrl, env, 10)
  local before = env.buttonHides
  ctrl:OnCombatStart()
  eq(env.buttonHides, before + 1)
  eq(env.buttonShown, nil)
end)

test("recommend: button hides after its seconds", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  fight(ctrl, env, 10)
  local before = env.buttonHides
  env:advance(4.9)
  eq(env.buttonHides, before, "still visible")
  env:advance(0.2)
  eq(env.buttonHides, before + 1)
end)

test("recommend: stale timer from an earlier fight does nothing", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  fight(ctrl, env, 10)                    -- hides: start, end -> 2; then shown
  env:advance(2)
  ctrl:OnCombatStart()                    -- 3
  env:advance(2)
  env.mana = 100
  ctrl:OnCombatEnd(); env:advance(0)      -- 4 (no new recommendation at 100%)
  env:advance(5)
  eq(env.buttonHides, 4)
end)

test("recommend: learned downtime changes the pick", function()
  local ctrl, env = setup({ mana = 60, drinks = { d("Big", 800, 30), d("Mid", 450, 30) } })
  for _ = 1, 3 do fight(ctrl, env, 10); env:advance(15) end   -- three 15s gaps (+0 from advance(0))
  env.buttonShows = {}
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Big" }, "450 only yields 225 in 15s; 800 yields 400")
end)

test("recommend: downtime factor can be turned off", function()
  local ctrl, env = setup({ mana = 60, drinks = { d("Big", 800, 30), d("Mid", 450, 30) } },
    function(p) p.recommend.useDowntime = false end)
  for _ = 1, 3 do fight(ctrl, env, 10); env:advance(15) end
  env.buttonShows = {}
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Mid" })
end)

test("recommend: zone change resets downtime", function()
  local ctrl, env = setup({ mana = 60, drinks = { d("Big", 800, 30), d("Mid", 450, 30) } })
  for _ = 1, 3 do fight(ctrl, env, 10); env:advance(15) end
  ctrl:OnZoneChanged()
  env.buttonShows = {}
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Mid" })
  eq(ctrl:DowntimeInfo(), { estimate = nil, count = 0 })
end)

test("recommend: prefer mage water", function()
  local list = { d("Vendor", 450), d("Conjured Water", 300, 30, true) }
  local ctrl, env = setup({ mana = 60, drinks = list })
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Conjured Water" })
  ctrl, env = setup({ mana = 60, drinks = list }, function(p) p.recommend.preferConjured = false end)
  fight(ctrl, env, 10)
  eq(env.buttonShows, { "Vendor" })
end)

test("stock: check on entering a dungeon or raid", function()
  local ctrl, env = setup({ drinks = { d("A", 800, 30, false, 10), d("B", 450, 30, false, 4) } })
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  eq(#env.stocks, 1)
  eq(env.stocks[1].total, 14)
  eq(env.stocks[1].low, true)
  eq(env.printed[#env.printed], "[Drink] In your bags: A x10, B x4")
  ctrl:OnEnteringWorld(false, "raid"); env:advance(3)
  eq(#env.stocks, 2)
end)

test("stock: not on reload, not outside instances, not when disabled", function()
  local ctrl, env = setup({ drinks = { d("A", 800) } })
  ctrl:OnEnteringWorld(true, "party"); env:advance(3)
  ctrl:OnEnteringWorld(false, "none"); env:advance(3)
  ctrl:OnEnteringWorld(false, "pvp")
  ctrl:OnEnteringWorld(false, nil)
  eq(#env.stocks, 0)
  ctrl, env = setup({ drinks = { d("A", 800) } }, function(p) p.stock.enabled = false end)
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  eq(#env.stocks, 0)
end)

test("stock: silent without a mana pool; empty bags print a note", function()
  local ctrl, env = setup({ noMana = true, drinks = { d("A", 800) } })
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  eq(#env.stocks, 0)
  ctrl, env = setup({ drinks = {} })
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  eq(#env.stocks, 1)
  eq(env.printed[#env.printed], "[Drink] No drinks in your bags.")
end)

test("stock: entering world (not reload) resets downtime", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  for _ = 1, 3 do fight(ctrl, env, 10); env:advance(15) end
  ctrl:OnEnteringWorld(true, "party"); env:advance(3)
  eq(ctrl:DowntimeInfo().count, 2, "reload keeps it (3 fights = 2 gaps)")
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  eq(ctrl:DowntimeInfo().count, 0)
end)

test("recommend: previews", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  eq(ctrl:Preview("drink"), true)
  eq(env.buttonShows, { "Mid" })
  ctrl:Preview("stock")
  eq(#env.stocks, 1)
  ctrl, env = setup({ mana = 60, drinks = {} })
  ctrl:Preview("drink")
  eq(env.printed[#env.printed], "[Drink] No usable drink to recommend.")
end)

test("stock: check waits 3s after the loading screen (item data settles)", function()
  local ctrl, env = setup({ drinks = { d("A", 800, 30, false, 10) } })
  ctrl:OnEnteringWorld(false, "party")
  env:advance(2.9)
  eq(#env.stocks, 0, "not immediately")
  env:advance(0.1)
  eq(#env.stocks, 1)
end)

test("recommend: drinking from the action bar closes the button", function()
  local ctrl, env = setup({ mana = 60, drinks = THREE })
  fight(ctrl, env, 10)
  eq(env.buttonShown and env.buttonShown.name, "Mid")
  env.drinking = true; ctrl:OnAuraChanged()
  eq(env.buttonShown, nil)
end)

test("stock: skipped while dead or a ghost (corpse run)", function()
  local ctrl, env = setup({ dead = true, drinks = { d("A", 800) } })
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  eq(#env.stocks, 0)
end)

-- _forever_: missing mana is unknown, so the button offers a full refill after every fight.
test("hidden: button after every fight with the smallest drink that refills the whole bar", function()
  local ctrl, env = setup({ hiddenMana = true, maxMana = 400, drinks = THREE })
  fight(ctrl, env, 10)
  eq(env.buttonShown and env.buttonShown.name, "Mid")
end)

test("hidden: nothing covers a full bar -> biggest drink", function()
  local ctrl, env = setup({ hiddenMana = true, maxMana = 5000, drinks = THREE })
  fight(ctrl, env, 10)
  eq(env.buttonShown and env.buttonShown.name, "Big")
end)
