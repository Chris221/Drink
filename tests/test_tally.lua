-- Dungeon run tally: the bookkeeping (Tally.lua) and how the controller feeds and uses it.
local FakeEnv = require("fake_env")
local ns = {}
load_addon(ns, "Drink/Logic.lua")
load_addon(ns, "Drink/Drinks.lua")
load_addon(ns, "Drink/Tally.lua")
load_addon(ns, "Drink/Defaults.lua")
load_addon(ns, "Drink/Controller.lua")
local Tally = ns.Tally

local function finished(drinks, seconds, pulls)
  return { at = 1, fights = 20, drinks = drinks, seconds = seconds or 0, pulls = pulls or 0 }
end

-- Finished runs with these drink counts, oldest first.
local function past(...)
  local list = {}
  for i, n in ipairs({ ... }) do list[i] = finished(n) end
  return list
end

-- Bookkeeping -----------------------------------------------------------------

test("tally: a run starts empty, and the same dungeon soon after carries it on", function()
  local store = { runs = {} }
  local run = Tally.Open(store, "Deadmines", 1000)
  eq(run, { name = "Deadmines", seen = 1000, fights = 0, drinks = 0, seconds = 0, pulls = 0 })
  truthy(store.run == run, "the open run lives in the saved table")
  run.drinks = 3
  truthy(Tally.Open(store, "Deadmines", 1000 + 15 * 60) == run, "back within 15 minutes: same run")
  eq(run.seen, 1000 + 15 * 60)
  local fresh = Tally.Open(store, "Deadmines", run.seen + 15 * 60 + 1)
  truthy(fresh ~= run, "later than that is a new run")
  eq(fresh.drinks, 0)
  truthy(Tally.Open(store, "Wailing Caverns", fresh.seen) ~= fresh, "another dungeon is a new run")
  eq(store.run.name, "Wailing Caverns")
end)

test("tally: finished runs are kept newest last, five per dungeon; short ones are dropped", function()
  local store = { runs = {} }
  for i = 1, 6 do
    local run = Tally.Open(store, "Deadmines", i * 10000)
    run.fights, run.drinks, run.seconds, run.pulls = 20, i, 99.6, 1
    local done, name = Tally.Close(store)
    eq(done, { at = i * 10000, fights = 20, drinks = i, seconds = 100, pulls = 1 })
    eq(name, "Deadmines")
    eq(store.run, nil)
  end
  local kept = {}
  for i, r in ipairs(store.runs.Deadmines) do kept[i] = r.drinks end
  eq(kept, { 2, 3, 4, 5, 6 })

  local short = Tally.Open(store, "Stockade", 1)
  short.fights, short.drinks = 4, 2
  eq((Tally.Close(store)), nil, "fewer than 5 fights isn't a run")
  eq(store.runs.Stockade, nil)
  eq(store.run, nil)
  eq((Tally.Close(store)), nil, "nothing open")
end)

test("tally: starting a new run files the one left open", function()
  local store = { runs = {} }
  local old = Tally.Open(store, "Deadmines", 1000)
  old.fights, old.drinks = 12, 7
  Tally.Open(store, "Stockade", 2000)
  eq(#store.runs.Deadmines, 1)
  eq(store.runs.Deadmines[1].drinks, 7)
end)

test("tally: what a dungeon has taken before", function()
  local store = { runs = {} }
  eq(Tally.Usual(store, "Deadmines"), nil)
  store.runs.Deadmines = past(9, 14, 11)
  eq(Tally.Usual(store, "Deadmines"), { runs = 3, least = 9, most = 14, last = 11 })
  eq(Tally.Usual(store, "Stockade"), nil)
end)

test("tally: wording", function()
  eq(Tally.RunLine("Deadmines", finished(11, 220, 2)), "Deadmines: 11 drinks, 3m 40s drinking, pulled mid-drink 2 times")
  eq(Tally.RunLine("Deadmines", finished(1, 45, 1)), "Deadmines: 1 drink, 45s drinking, pulled mid-drink once")
  eq(Tally.RunLine("Deadmines", finished(3, 60)), "Deadmines: 3 drinks, 1m 0s drinking")
  eq(Tally.RunLine("Deadmines", finished(0)), "Deadmines: no drinks used")
  eq(Tally.UsualLine("Deadmines", { runs = 1, least = 11, most = 11, last = 11 }), "Deadmines: 11 drinks last run")
  eq(Tally.UsualLine("Deadmines", { runs = 4, least = 9, most = 14, last = 11 }), "Deadmines: 9-14 drinks a run (last 4 runs)")
  eq(Tally.UsualLine("Deadmines", { runs = 2, least = 1, most = 1, last = 1 }), "Deadmines: 1 drink a run (last 2 runs)")
end)

test("tally: the list shows this run so far, then each dungeon newest first; clearing keeps the open run", function()
  local store = { runs = {} }
  eq(Tally.List(store), {})
  store.runs["Wailing Caverns"] = { finished(20, 600) }
  store.runs.Deadmines = { finished(9, 200), finished(14, 300, 1) }
  local run = Tally.Open(store, "Deadmines", 5)
  run.drinks, run.seconds = 2, 50
  eq(Tally.List(store), {
    "Deadmines (this run so far): 2 drinks, 50s drinking",
    "Deadmines: 9-14 drinks a run (last 2 runs)",
    "   14 drinks, 5m 0s drinking, pulled mid-drink once",
    "   9 drinks, 3m 20s drinking",
    "Wailing Caverns: 20 drinks last run",
    "   20 drinks, 10m 0s drinking",
  })
  local runs = store.runs
  Tally.Clear(store)
  truthy(store.runs == runs, "same table: it is the saved one")
  eq(store.runs, {})
  truthy(store.run == run, "the run I'm in carries on")
end)

-- Controller ------------------------------------------------------------------

local function d(name, mana, count)
  return { itemID = #name, name = name, icon = 1, mana = mana, seconds = 30, conjured = false, count = count or 5 }
end
local PARTY = { party = true }
local function noStock(p) p.stock.enabled = false end

local function setup(o, tweak, store)
  local profile = deepcopy(ns.defaults.profile)
  if tweak then tweak(profile) end
  local env = FakeEnv.New(o)
  store = store or { runs = {} }
  local ctrl = ns.Controller.New(profile, env, store)
  ctrl:SyncDrinking()
  return ctrl, env, store, profile
end

local function enter(ctrl, env, name) ctrl:OnEnteringWorld(false, "party", name or "Deadmines"); env:advance(0) end
-- A loading screen out into the world, and the few seconds it takes to settle.
local function leave(ctrl, env) ctrl:OnEnteringWorld(false, "none", nil); env:advance(3) end
local function fight(ctrl, env, len)
  ctrl:OnCombatStart(); env:advance(len or 10); ctrl:OnCombatEnd(); env:advance(0)
end
local function sit(ctrl, env) env.drinking = true; ctrl:OnAuraChanged() end
local function stand(ctrl, env) env.drinking = false; ctrl:OnAuraChanged(); env:advance(2) end

test("run: fights, drinks and drinking time are counted inside a dungeon", function()
  local ctrl, env, store = setup({ mana = 30, group = PARTY }, noStock)
  enter(ctrl, env)
  eq(store.run.name, "Deadmines")
  fight(ctrl, env)
  sit(ctrl, env); env:advance(20); stand(ctrl, env)
  fight(ctrl, env)
  sit(ctrl, env); env:advance(12.5); stand(ctrl, env)
  eq(store.run.fights, 2)
  eq(store.run.drinks, 2)
  eq(store.run.seconds, 32.5)
end)

test("run: nothing is counted out in the world", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  leave(ctrl, env)
  fight(ctrl, env); sit(ctrl, env); env:advance(20); stand(ctrl, env)
  eq(store.run, nil)
  eq(store.runs, {})
end)

test("run: a dungeon whose name the game won't give isn't tallied", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  ctrl:OnEnteringWorld(false, "party", nil); env:advance(0)
  fight(ctrl, env)
  eq(store.run, nil)
end)

test("run: a drink buff that now ends later is another drink", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  enter(ctrl, env); fight(ctrl, env)
  env.drinkEnds = env.t + 30; sit(ctrl, env)
  env:advance(10); ctrl:OnAuraChanged()
  eq(store.run.drinks, 1, "some other buff changed")
  env:advance(15); env.drinkEnds = env.t + 30; ctrl:OnAuraChanged()
  eq(store.run.drinks, 2, "a second drink before the first ran out")
  env:advance(30); stand(ctrl, env)
  eq(store.run.seconds, 55)
end)

test("run: eating at full mana is not a drink", function()
  local ctrl, env, store = setup({ mana = 100 }, noStock)
  enter(ctrl, env); fight(ctrl, env)
  env.drinkEnds = env.t + 30; sit(ctrl, env)
  env:advance(20); env.drinkEnds = env.t + 30; ctrl:OnAuraChanged()
  env:advance(5); ctrl:OnCombatStart()
  eq(store.run.drinks, 0)
  eq(store.run.seconds, 0)
  eq(store.run.pulls, 0)
end)

test("run: a pull that cuts my drink short is counted once per break", function()
  local ctrl, env, store = setup({ mana = 30, group = PARTY },
    function(p) noStock(p); p.alert.pullWhileDrinking = false end)
  enter(ctrl, env); fight(ctrl, env)
  sit(ctrl, env); env:advance(5)
  env.groupCombat = true; env:advance(1) -- the group pulls while I'm sitting
  eq(store.run.pulls, 1)
  eq(env.pulls, 0, "the on-screen warning itself is switched off")
  ctrl:OnCombatStart()                   -- ...and the fight reaches me, still seated
  eq(store.run.pulls, 1, "same pull")
  eq(store.run.seconds, 6, "the drink ended when the fight reached me")
  env:advance(10); env.groupCombat = false; ctrl:OnCombatEnd(); env:advance(0)
  env.drinking = false; ctrl:OnAuraChanged()
  sit(ctrl, env); env:advance(4); ctrl:OnCombatStart() -- no warning this time: straight into combat
  eq(store.run.pulls, 2)
  eq(store.run.seconds, 10)
end)

test("run: leaving alive files the run and prints the tally", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  enter(ctrl, env)
  for _ = 1, 5 do fight(ctrl, env); sit(ctrl, env); env:advance(20); stand(ctrl, env) end
  env.printed = {}
  leave(ctrl, env)
  eq(env.printed, { "[Drink] Deadmines: 5 drinks, 1m 40s drinking" })
  eq(store.run, nil)
  eq(#store.runs.Deadmines, 1)
  eq(store.runs.Deadmines[1].drinks, 5)
end)

test("run: a corpse run carries on with the same run", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  enter(ctrl, env)
  for _ = 1, 3 do fight(ctrl, env) end
  local run = store.run
  env.dead = true; env.printed = {}
  leave(ctrl, env)
  truthy(store.run == run, "still open while I'm a ghost")
  eq(env.printed, {})
  env:advance(120); env.dead = false
  enter(ctrl, env)
  truthy(store.run == run, "same run after walking back in")
  for _ = 1, 3 do fight(ctrl, env) end
  eq(run.fights, 6)
  leave(ctrl, env)
  eq(#store.runs.Deadmines, 1)
  eq(store.runs.Deadmines[1].fights, 6)
end)

test("run: stepping out and straight back in doesn't end it", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  enter(ctrl, env)
  for _ = 1, 5 do fight(ctrl, env) end
  local run = store.run
  env.printed = {}
  ctrl:OnEnteringWorld(false, "none", nil); env:advance(1)
  enter(ctrl, env); env:advance(10)
  truthy(store.run == run, "the pending goodbye was dropped")
  eq(env.printed, {})
  eq(store.runs, {})
end)

test("run: a /reload carries on counting", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  enter(ctrl, env); fight(ctrl, env)
  local run = store.run
  -- /reload: a brand new controller over the same saved table
  local env2 = FakeEnv.New({ mana = 30 })
  local ctrl2 = ns.Controller.New(deepcopy(ns.defaults.profile), env2, store)
  ctrl2:SyncDrinking()
  ctrl2:OnEnteringWorld(true, "party", "Deadmines"); env2:advance(5)
  fight(ctrl2, env2)
  truthy(store.run == run)
  eq(run.fights, 2)
end)

test("run: a few fights and out isn't recorded", function()
  local ctrl, env, store = setup({ mana = 30 }, noStock)
  enter(ctrl, env)
  for _ = 1, 4 do fight(ctrl, env) end
  env.printed = {}
  leave(ctrl, env)
  eq(env.printed, {})
  eq(store.runs, {})
  eq(store.run, nil)
end)

test("run: one left open from an earlier session is filed quietly", function()
  local store = { runs = {}, run = { name = "Deadmines", seen = 5, fights = 9, drinks = 4, seconds = 80, pulls = 0 } }
  local ctrl, env = setup({ mana = 30 }, noStock, store)
  leave(ctrl, env) -- logging in out in the world
  eq(env.printed, {})
  eq(store.run, nil)
  eq(store.runs.Deadmines[1].drinks, 4)
end)

test("run: tally switched off counts nothing; summary off still files the run", function()
  local ctrl, env, store = setup({ mana = 30 }, function(p) noStock(p); p.tally.enabled = false end)
  enter(ctrl, env); fight(ctrl, env)
  eq(store.run, nil)

  ctrl, env, store = setup({ mana = 30 }, function(p) noStock(p); p.tally.summary = false end)
  enter(ctrl, env)
  for _ = 1, 5 do fight(ctrl, env) end
  env.printed = {}
  leave(ctrl, env)
  eq(env.printed, {})
  eq(#store.runs.Deadmines, 1)
end)

test("run: the controller lists and forgets saved runs", function()
  local ctrl = setup({}, noStock, { runs = { Deadmines = past(9) } })
  eq(ctrl:RunLines(), { "Deadmines: 9 drinks last run", "   9 drinks, 0s drinking" })
  ctrl:ForgetRuns()
  eq(ctrl:RunLines(), {})
end)

test("run: a controller made without a saved table still works", function()
  local env = FakeEnv.New({ mana = 30 })
  local ctrl = ns.Controller.New(deepcopy(ns.defaults.profile), env)
  ctrl:SyncDrinking()
  enter(ctrl, env); fight(ctrl, env)
  eq(ctrl:RunLines(), { "Deadmines (this run so far): no drinks used" })
end)

-- Stock check -----------------------------------------------------------------

test("stock: in a dungeon I've run before, the check goes by what it took", function()
  local ctrl, env = setup({ drinks = { d("Dew", 500, 16) } }, nil, { runs = { Deadmines = past(9, 14, 11) } })
  ctrl:OnEnteringWorld(false, "party", "Deadmines"); env:advance(3)
  eq(env.stocks[1].low, false, "16 covers the 14 a run has taken (the fixed 20 would have nagged)")
  eq(env.stocks[1].need, 14)
  eq(env.printed, { "[Drink] Dew x16", "[Drink] Deadmines: 9-14 drinks a run (last 3 runs)" })

  ctrl, env = setup({ drinks = { d("Dew", 500, 10) } }, nil, { runs = { Deadmines = past(9, 14, 11) } })
  ctrl:OnEnteringWorld(false, "party", "Deadmines"); env:advance(3)
  eq(env.stocks[1].low, true, "10 doesn't")
end)

test("stock: a dungeon I haven't run, or learning switched off, uses the fixed number", function()
  local ctrl, env = setup({ drinks = { d("Dew", 500, 16) } }, nil, { runs = { Deadmines = past(9, 14) } })
  ctrl:OnEnteringWorld(false, "party", "Wailing Caverns"); env:advance(3)
  eq(env.stocks[1].low, true, "16 is under the fixed 20")
  eq(env.stocks[1].need, nil)
  eq(env.printed, { "[Drink] Dew x16" })

  ctrl, env = setup({ drinks = { d("Dew", 500, 16) } }, function(p) p.stock.learn = false end,
    { runs = { Deadmines = past(9, 14) } })
  ctrl:OnEnteringWorld(false, "party", "Deadmines"); env:advance(3)
  eq(env.stocks[1].low, true)
  eq(env.stocks[1].need, nil)
end)

test("stock: mid-run, what's still needed shrinks as I drink", function()
  local dew = d("Dew", 500, 16)
  local ctrl, env = setup({ mana = 30, drinks = { dew } }, nil, { runs = { Deadmines = past(14) } })
  ctrl:OnEnteringWorld(false, "party", "Deadmines"); env:advance(3)
  env.printed = {}
  for _ = 1, 5 do
    fight(ctrl, env); sit(ctrl, env); dew.count = dew.count - 1; env:advance(20); stand(ctrl, env)
  end
  fight(ctrl, env) -- 11 left, 9 still needed: fine (the fixed 20 would have warned by now)
  for _, line in ipairs(env.printed) do truthy(not line:find("STOCK UP"), line) end
  dew.count = 3    -- handed most of it to someone: 3 left, 9 still needed
  fight(ctrl, env)
  truthy(env.printed[#env.printed]:find("STOCK UP: 3 drinks left", 1, true), env.printed[#env.printed])
  env:advance(5)
  eq(env.stocks[#env.stocks].need, 9)
end)

test("stock: a dungeon that has never taken a drink doesn't nag", function()
  local ctrl, env = setup({ drinks = {} }, nil, { runs = { Deadmines = past(0, 0) } })
  ctrl:OnEnteringWorld(false, "party", "Deadmines"); env:advance(3)
  eq(env.stocks[1].low, false)
  eq(env.stocks[1].need, 0)
end)
