local ns = {}
load_addon(ns, "Drink/Logic.lua")
load_addon(ns, "Drink/Drinks.lua")
local D = ns.Drinks

local function drink(name, mana, seconds, conjured, count)
  return { itemID = #name, name = name, mana = mana, seconds = seconds or 30,
           conjured = conjured or false, count = count or 1 }
end

-- Parsing -----------------------------------------------------------------

test("drinks: parse flat mana drink", function()
  eq(D.ParseTooltip({ "Morning Glory Dew", "Use: Restores 4200 mana over 30 sec." }), { mana = 4200, seconds = 30 })
end)

test("drinks: parse food & drink takes the mana part", function()
  eq(D.ParseTooltip({ "Restores 2148 health and 4200 mana over 30 sec." }), { mana = 4200, seconds = 30 })
end)

test("drinks: parse thousands separators", function()
  eq(D.ParseTooltip({ "Restores 1,344,000 mana over 20 sec" }), { mana = 1344000, seconds = 20 })
  eq(D.ParseTooltip({ "Restores 1.344.000 mana over 20 sec" }), { mana = 1344000, seconds = 20 })
end)

test("drinks: parse percent drinks", function()
  eq(D.ParseTooltip({ "Restores 7% of your mana per second for 20 sec" }), { pct = 140, seconds = 20 })
  eq(D.ParseTooltip({ "Restores 50% of your mana over 20 sec" }), { pct = 50, seconds = 20 })
end)

test("drinks: potions, gems and plain food are not drinks", function()
  eq(D.ParseTooltip({ "Use: Restores 455 to 585 mana." }), nil)
  eq(D.ParseTooltip({ "Use: Restores 61 health over 18 sec." }), nil)
  eq(D.ParseTooltip({ "Use: Restores 1500 mana." }), nil)
  eq(D.ParseTooltip({}), nil)
end)

test("drinks: resolve percent against max mana, capped at 100%", function()
  eq({ D.Resolve({ mana = 4200, seconds = 30 }, 1000) }, { 4200, 30 })
  eq({ D.Resolve({ pct = 50, seconds = 20 }, 1000) }, { 500, 20 })
  eq({ D.Resolve({ pct = 140, seconds = 20 }, 1000) }, { 1000, 20 })
end)

test("drinks: conjured detection", function()
  eq(D.IsConjured("Conjured Sparkling Water", {}), true)
  eq(D.IsConjured("Mage Water", { "Mage Water", "Conjured Item" }), true)
  eq(D.IsConjured("Morning Glory Dew", { "Morning Glory Dew" }), false)
end)

test("drinks: manual overrides", function()
  local o = D.ParseOverrides("Morning Glory Dew = 2934\n 8079 = 4200, 27 \n\ngarbage\nBad = x")
  eq(o["morning glory dew"], { mana = 2934, seconds = 30 })
  eq(o["8079"], { mana = 4200, seconds = 27 })
  eq(o["garbage"], nil)
  eq(o["bad"], nil)
end)

-- Picking -----------------------------------------------------------------

test("drinks: picks the smallest drink that covers the deficit (Chris's example)", function()
  local pick = D.Pick({ drink("Big", 800), drink("Mid", 450), drink("Small", 300) }, 400, {})
  eq(pick.name, "Mid")
end)

test("drinks: picks the largest when none covers", function()
  local pick = D.Pick({ drink("Big", 800), drink("Mid", 450) }, 900, {})
  eq(pick.name, "Big")
end)

test("drinks: downtime shrinks long drinks", function()
  eq(D.Effective(drink("A", 800, 30), 15), 400)
  eq(D.Effective(drink("A", 800, 30), nil), 800)
  eq(D.Effective(drink("A", 800, 30), 60), 800)
  local pick = D.Pick({ drink("A", 800, 30), drink("B", 450, 30) }, 400, { downtime = 15 })
  eq(pick.name, "A")
end)

test("drinks: prefers conjured when asked", function()
  local list = { drink("Vendor", 450), drink("Conjured Water", 300, 30, true) }
  eq(D.Pick(list, 400, { preferConjured = true }).name, "Conjured Water")
  eq(D.Pick(list, 400, { preferConjured = false }).name, "Vendor")
end)

test("drinks: tie prefers smaller total mana, then conjured", function()
  -- Both effective 300 under a 10s downtime: A 900/30s, B 600/20s -> smaller total B
  local pick = D.Pick({ drink("A", 900, 30), drink("B", 600, 20) }, 250, { downtime = 10 })
  eq(pick.name, "B")
  local pick2 = D.Pick({ drink("Vendor", 450), drink("Conjured", 450, 30, true) }, 400, {})
  eq(pick2.name, "Conjured")
end)

test("drinks: nothing to pick", function()
  eq(D.Pick({}, 400, {}), nil)
  eq(D.Pick({ drink("A", 450) }, 0, {}), nil)
end)

-- Downtime ----------------------------------------------------------------

test("drinks: downtime median, ignores long gaps, keeps last 5", function()
  local t = D.NewDowntime()
  eq(t:Estimate(), nil)
  t:RecordStart(5)                          -- no previous end: ignored
  local now = 0
  local function gap(g) t:RecordEnd(now); now = now + g; t:RecordStart(now); now = now + 20 end
  gap(10); gap(20)
  eq(t:Count(), 2)
  eq(t:Estimate(), nil, "needs 3 gaps")
  gap(500)                                  -- AFK: ignored
  gap(30); gap(40)
  eq(t:Count(), 4)
  eq(t:Estimate(), 25)
  gap(50); gap(60)                          -- keeps 20,30,40,50,60
  eq(t:Count(), 5)
  eq(t:Estimate(), 40)
  t:Reset()
  eq(t:Count(), 0)
  eq(t:Estimate(), nil)
end)

-- Stock -------------------------------------------------------------------

test("drinks: stock summary", function()
  local s = D.StockSummary({ drink("Drink B", 450, 30, false, 4), drink("Drink A", 800, 30, false, 10) }, 1000, 20)
  eq(s.total, 14)
  eq(s.refills, 9)
  eq(s.low, true)
  eq(s.breakdown, "Drink A x10, Drink B x4")
  local big = D.StockSummary({ drink("Huge", 5000, 30, false, 25) }, 1000, 20)
  eq(big.refills, 25, "a drink bigger than the bar counts as one refill")
  eq(big.low, false)
  local none = D.StockSummary({}, 1000, 20)
  eq(none.total, 0); eq(none.refills, 0); eq(none.low, true); eq(none.breakdown, "")
end)
