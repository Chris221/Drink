-- Extras: drink stats, once-per-break announce, Ready, pull alert, mid-run stock, mage request.
local FakeEnv = require("fake_env")
local ns = {}
load_addon(ns, "Drink/Logic.lua")
load_addon(ns, "Drink/Drinks.lua")
load_addon(ns, "Drink/Defaults.lua")
load_addon(ns, "Drink/Controller.lua")

local function d(name, mana, seconds, conjured, count)
  return { itemID = #name, name = name, icon = 1, mana = mana, seconds = seconds or 30,
           conjured = conjured or false, count = count or 5 }
end
local THREE = { d("Big", 800), d("Mid", 450), d("Small", 300) }
local PARTY = { party = true }

local function setup(o, tweak)
  local profile = deepcopy(ns.defaults.profile)
  if tweak then tweak(profile) end
  local env = FakeEnv.New(o)
  local ctrl = ns.Controller.New(profile, env)
  ctrl:SyncDrinking()
  return ctrl, env, profile
end

local function fight(ctrl, env, len)
  ctrl:OnCombatStart(); env:advance(len or 10); ctrl:OnCombatEnd(); env:advance(0)
end
local function sit(ctrl, env) env.drinking = true; ctrl:OnAuraChanged() end
local function standNow(ctrl, env) env.drinking = false; ctrl:OnAuraChanged() end
-- Stand up and let the 2s "really done drinking" grace pass.
local function stand(ctrl, env) standNow(ctrl, env); env:advance(2) end

-- Once per break -------------------------------------------------------------

test("break: a second drink before the next fight is not announced again", function()
  local ctrl, env = setup({ mana = 30, group = PARTY, drinks = THREE })
  fight(ctrl, env)
  sit(ctrl, env); env:advance(20); stand(ctrl, env)
  env.mana = 60
  sit(ctrl, env)
  eq(env.sent, { { "Drinking — 30% mana", "PARTY" } })
  env:advance(20); stand(ctrl, env)
  env.mana = 40
  fight(ctrl, env)
  sit(ctrl, env)
  eq(#env.sent, 2, "a new fight starts a new break")
  eq(env.sent[2], { "Drinking — 40% mana", "PARTY" })
end)

-- Stats ----------------------------------------------------------------------

test("stats: one drink is enough -> seconds to full, printed just to me", function()
  local ctrl, env = setup({ mana = 60, maxMana = 1000, group = PARTY, drinks = THREE })
  fight(ctrl, env)                      -- recommends Mid (450 over 30s)
  sit(ctrl, env)
  eq(env.printed, { "[Drink] Mid: full in ~27s" })
  eq(#env.sent, 1, "only the Drinking announcement is sent")
end)

test("stats: natural regen is counted", function()
  local ctrl, env = setup({ mana = 60, maxMana = 1000, regen = 5, group = PARTY, drinks = THREE })
  fight(ctrl, env)
  sit(ctrl, env)
  eq(env.printed, { "[Drink] Mid: full in ~20s" })
end)

test("stats: more than one drink needed", function()
  local ctrl, env = setup({ mana = 10, maxMana = 1000, group = PARTY, drinks = { d("Small", 300) } })
  fight(ctrl, env)
  sit(ctrl, env)
  eq(env.printed, { "[Drink] Small: 3 drinks to fill (~90s)" })
end)

test("stats: printed again for the second drink, updated", function()
  local ctrl, env = setup({ mana = 10, maxMana = 1000, group = PARTY, drinks = { d("Small", 300) } })
  fight(ctrl, env)
  sit(ctrl, env); env:advance(30); stand(ctrl, env)
  env.mana = 40
  sit(ctrl, env)
  eq(env.printed[2], "[Drink] Small: 2 drinks to fill (~60s)")
  eq(#env.sent, 1)
end)

test("stats: nothing without a recommendation, at full mana, or when turned off", function()
  local ctrl, env = setup({ mana = 60, group = PARTY, drinks = THREE })
  sit(ctrl, env)
  eq(#env.printed, 0, "no recommendation yet")
  ctrl, env = setup({ mana = 60, group = PARTY, drinks = THREE }, function(p) p.recommend.stats = false end)
  fight(ctrl, env); sit(ctrl, env)
  eq(#env.printed, 0, "off")
  ctrl, env = setup({ mana = 60, group = PARTY, drinks = THREE })
  fight(ctrl, env); env.mana = 100; sit(ctrl, env)
  eq(#env.printed, 0, "full")
end)

test("stats: hidden mana hands the maths to the game", function()
  local ctrl, env = setup({ hiddenMana = true, maxMana = 400, regen = 3, group = PARTY, drinks = THREE })
  fight(ctrl, env)                      -- full-bar pick: Mid
  sit(ctrl, env)
  eq(env.hiddenStats, { { "Mid", 400, 3 } })
end)

-- Ready ----------------------------------------------------------------------

local function drank(o, tweak)
  local ctrl, env = setup(o, tweak)
  fight(ctrl, env)
  sit(ctrl, env); env:advance(20)
  return ctrl, env
end

test("ready: posted when I stand up with enough mana", function()
  local ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; stand(ctrl, env)
  eq(env.sent[2], { "Ready — 90% mana", "PARTY" })
end)

test("ready: never while I or anyone in the group is in combat", function()
  local ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; env.groupCombat = true; stand(ctrl, env)
  eq(#env.sent, 1)
  ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; env.inCombat = true; stand(ctrl, env)
  eq(#env.sent, 1)
end)

test("ready: not after a drink that was never announced (buff food at 100%)", function()
  local ctrl, env = setup({ mana = 100, group = PARTY })
  fight(ctrl, env); sit(ctrl, env); env:advance(20); stand(ctrl, env)
  eq(#env.sent, 0)
end)

test("ready: below the threshold nothing; a later drink in the same break posts it once", function()
  local ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 50; stand(ctrl, env)
  eq(#env.sent, 1, "50% < 80%")
  sit(ctrl, env); env:advance(20); env.mana = 95; stand(ctrl, env)
  eq(env.sent[2], { "Ready — 95% mana", "PARTY" })
  sit(ctrl, env); env:advance(20); stand(ctrl, env)
  eq(#env.sent, 2, "once per break")
end)

test("ready: off, and solo behaviour", function()
  local ctrl, env = drank({ mana = 30, group = PARTY }, function(p) p.ready.enabled = false end)
  env.mana = 90; stand(ctrl, env)
  eq(#env.sent, 1)
  ctrl, env = drank({ mana = 30 })
  env.mana = 90; stand(ctrl, env)
  eq(env.printed, { "[Drink] Drinking — 30% mana" }, "solo: silent by default")
  ctrl, env = drank({ mana = 30 }, function(p) p.ready.soloLocal = true end)
  env.mana = 90; stand(ctrl, env)
  eq(env.printed[2], "[Drink] Ready — 90% mana")
end)

test("ready: hidden mana sends 'Ready' without a number unless mana is confirmed low", function()
  local ctrl, env = drank({ hiddenMana = true, group = PARTY })
  stand(ctrl, env)
  eq(env.sent, { { "Drinking", "PARTY" }, { "Ready", "PARTY" } })
  eq(env.hiddenPrints, { "Drinking — %m% mana" }, "Ready is not echoed to me in a group")
  ctrl, env = drank({ hiddenMana = true, group = PARTY })
  env.lowConfirmed = true; stand(ctrl, env)
  eq(#env.sent, 1)
end)

test("ready: preview prints locally", function()
  local ctrl, env = setup({ mana = 88 })
  eq(ctrl:Preview("ready"), true)
  eq(env.printed, { "[Drink] would send: Ready — 88% mana" })
end)

-- Pull while drinking ----------------------------------------------------------

test("pull: a group member entering combat while I drink alerts once", function()
  local ctrl, env = drank({ mana = 30, group = PARTY })
  eq(env.pulls, 0)
  env.groupCombat = true; env:advance(0.5)
  eq(env.pulls, 1)
  env:advance(10)
  eq(env.pulls, 1)
end)

test("pull: not solo, not after standing up, not when off, not if the group never left combat", function()
  local ctrl, env = drank({ mana = 30 })
  env.groupCombat = true; env:advance(2)
  eq(env.pulls, 0, "solo")
  ctrl, env = drank({ mana = 30, group = PARTY })
  stand(ctrl, env); env.groupCombat = true; env:advance(2)
  eq(env.pulls, 0, "stood up")
  ctrl, env = drank({ mana = 30, group = PARTY }, function(p) p.alert.pullWhileDrinking = false end)
  env.groupCombat = true; env:advance(2)
  eq(env.pulls, 0, "off")
  ctrl, env = setup({ mana = 30, group = PARTY, groupCombat = true })
  fight(ctrl, env); sit(ctrl, env); env:advance(5)
  eq(env.pulls, 0, "group still finishing the same fight")
  env.groupCombat = false; env:advance(1); env.groupCombat = true; env:advance(1)
  eq(env.pulls, 1, "calm, then a new pull")
end)

-- Mid-run stock ----------------------------------------------------------------

local function inDungeon(o, tweak)
  local ctrl, env = setup(o, tweak)
  ctrl:OnEnteringWorld(false, "party"); env:advance(3)
  return ctrl, env
end

test("midrun: warns once when stock drops below the threshold inside an instance", function()
  local ctrl, env = inDungeon({ mana = 60, drinks = { d("A", 800, 30, true, 25) } })
  eq(#env.stocks, 1); eq(env.stocks[1].low, false)
  env.printed = {}
  env.drinks = { d("A", 800, 30, true, 10) }
  fight(ctrl, env)
  eq(env.printed, { "[Drink] STOCK UP: 10 drinks left (A x10)" })
  env:advance(5)
  eq(#env.stocks, 2, "stock line after the drink alert has had its time")
  env.printed = {}
  fight(ctrl, env); env:advance(5)
  eq(#env.printed, 0); eq(#env.stocks, 2, "once")
end)

test("midrun: not outside instances, not when already low on entry, not when off", function()
  local ctrl, env = setup({ mana = 60, drinks = { d("A", 800, 30, true, 10) } })
  fight(ctrl, env); env:advance(5)
  eq(#env.stocks, 0, "open world")
  ctrl, env = inDungeon({ mana = 60, drinks = { d("A", 800, 30, true, 10) } })
  env.printed = {}
  fight(ctrl, env); env:advance(5)
  eq(#env.stocks, 1, "entry check already said STOCK UP")
  ctrl, env = inDungeon({ mana = 60, drinks = { d("A", 800, 30, true, 25) } }, function(p) p.stock.midRun = false end)
  env.drinks = { d("A", 800, 30, true, 10) }
  fight(ctrl, env); env:advance(5)
  eq(#env.stocks, 1, "off")
end)

test("midrun: a new pull before the stock line cancels the line", function()
  local ctrl, env = inDungeon({ mana = 60, drinks = { d("A", 800, 30, true, 25) } })
  env.drinks = { d("A", 800, 30, true, 10) }
  fight(ctrl, env)
  ctrl:OnCombatStart(); env:advance(5)
  eq(#env.stocks, 1)
end)

-- Mage request -------------------------------------------------------------------

test("mage: low stock with a mage in the group offers a button; nothing sent until clicked", function()
  local ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = { d("Vendor", 800, 30, false, 5) } })
  eq(env.mageShown, "Jaina")
  eq(#env.whispers, 0); eq(#env.sent, 0)
  ctrl:RequestWater()
  eq(env.whispers, { { "Could I get some water please?", "Jaina" } })
  eq(env.mageShown, nil)
  ctrl:RequestWater()
  eq(#env.whispers, 1, "no button, no send")
end)

test("mage: also offered when stock is fine but none of it is mage water", function()
  local ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = { d("Vendor", 800, 30, false, 40) } })
  eq(env.mageShown, "Jaina")
  ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = { d("Conj", 800, 30, true, 40) } })
  eq(env.mageShown, nil, "plenty of mage water")
end)

test("mage: no mage, or turned off -> no button", function()
  local ctrl, env = inDungeon({ group = PARTY, drinks = {} })
  eq(#env.mageShows, 0)
  ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = {} }, function(p) p.mage.enabled = false end)
  eq(#env.mageShows, 0)
end)

test("mage: button goes away after 10s and when combat starts", function()
  local ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = {} })
  env:advance(9.9); eq(env.mageShown, "Jaina")
  env:advance(0.2); eq(env.mageShown, nil)
  ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = {} })
  ctrl:OnCombatStart()
  eq(env.mageShown, nil)
  ctrl:RequestWater()
  eq(#env.whispers, 0)
end)

test("mage: group-chat option and chat lockdown", function()
  local ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, drinks = {} }, function(p) p.mage.channel = "GROUP" end)
  ctrl:RequestWater()
  eq(env.sent, { { "Could I get some water please?", "PARTY" } })
  ctrl, env = inDungeon({ mage = "Jaina", group = PARTY, locked = true, drinks = {} })
  env.printed = {}
  ctrl:RequestWater()
  eq(#env.whispers, 0)
  eq(env.printed, { "[Drink] (chat locked) Could I get some water please?" })
end)

-- Final-review fixes ---------------------------------------------------------------

test("ready: waits 2s; a second drink or a pull in that time cancels it", function()
  local ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; standNow(ctrl, env)
  eq(#env.sent, 1, "not immediately: the drink may just have run out while I'm still seated")
  env:advance(2)
  eq(env.sent[2], { "Ready — 90% mana", "PARTY" })

  ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; standNow(ctrl, env); env:advance(1)
  sit(ctrl, env); env:advance(5)
  eq(#env.sent, 1, "second drink cancels")

  ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; standNow(ctrl, env); env:advance(1)
  ctrl:OnCombatStart(); env:advance(5)
  eq(#env.sent, 1, "pull cancels")

  ctrl, env = drank({ mana = 30, group = PARTY })
  env.mana = 90; standNow(ctrl, env); env:advance(1)
  env.groupCombat = true; env:advance(5)
  eq(#env.sent, 1, "group pulled during the wait")
end)

test("group combat unknown (hidden by the game): no Ready and no PULL alert", function()
  local ctrl, env = drank({ mana = 30, group = PARTY })
  env.groupCombat = nil
  env:advance(3)
  eq(env.pulls, 0)
  env.mana = 90; stand(ctrl, env)
  eq(#env.sent, 1)
end)

test("stats: a failure printing them never stops the pull watcher", function()
  local ctrl, env = setup({ hiddenMana = true, maxMana = 400, group = PARTY, drinks = THREE })
  fight(ctrl, env)
  env.printHiddenStats = function() error("boom") end
  env.drinking = true
  pcall(function() ctrl:OnAuraChanged() end)
  env.groupCombat = true; env:advance(0.5)
  eq(env.pulls, 1)
end)

test("mage: not offered while I'm in combat", function()
  local ctrl, env = setup({ mage = "Jaina", group = PARTY, inCombat = true, drinks = {} })
  ctrl:StockCheck()
  eq(#env.mageShows, 0)
end)

test("midrun: the delayed stock line doesn't replace alerts while I'm drinking", function()
  local ctrl, env = inDungeon({ mana = 60, group = PARTY, drinks = { d("A", 800, 30, true, 25) } })
  env.drinks = { d("A", 800, 30, true, 10) }
  fight(ctrl, env)
  sit(ctrl, env)
  env:advance(5)
  eq(#env.stocks, 1, "chat line only")
end)
