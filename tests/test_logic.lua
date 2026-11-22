local ns = load_addon({}, "Drink/Logic.lua")
local L = ns.Logic
local CUT = { fyi = 80, heads = 50, low = 20 }

test("logic: GetTier boundaries", function()
  eq(L.GetTier(81, CUT), "fyi")
  eq(L.GetTier(80, CUT), "fyi")
  eq(L.GetTier(79, CUT), "heads")
  eq(L.GetTier(50, CUT), "heads")
  eq(L.GetTier(49, CUT), "low")
  eq(L.GetTier(20, CUT), "low")
  eq(L.GetTier(19, CUT), "critical")
  eq(L.GetTier(0, CUT), "critical")
  eq(L.GetTier(nil, CUT), "unknown")
end)

test("logic: ManaPercent rounds and guards zero max", function()
  eq(L.ManaPercent(34, 100), 34)
  eq(L.ManaPercent(995, 1000), 100)
  eq(L.ManaPercent(5, 0), nil)
end)

test("logic: drink aura names parsed and matched", function()
  local set = L.ParseNames("Drink\n Food & Drink \n\nRefreshment")
  eq(L.IsDrinkAura("Food & Drink", set), true)
  eq(L.IsDrinkAura("Drink", set), true)
  eq(L.IsDrinkAura("Refreshment", set), true)
  eq(L.IsDrinkAura("Well Fed", set), false)
  eq(L.IsDrinkAura(nil, set), false)
end)

test("logic: PickChannel auto priority", function()
  eq(L.PickChannel("AUTO", { instance = true, raid = true, party = true }), "INSTANCE_CHAT")
  eq(L.PickChannel("AUTO", { raid = true, party = true }), "RAID")
  eq(L.PickChannel("AUTO", { party = true }), "PARTY")
  eq(L.PickChannel("AUTO", {}), nil)
end)

test("logic: PickChannel fixed modes require matching group", function()
  eq(L.PickChannel("RAID", { party = true }), nil)
  eq(L.PickChannel("RAID", { raid = true, party = true }), "RAID")
  eq(L.PickChannel("PARTY", { raid = true, party = true }), "PARTY")
  eq(L.PickChannel("PARTY", {}), nil)
  eq(L.PickChannel("INSTANCE_CHAT", { party = true }), nil)
  eq(L.PickChannel("INSTANCE_CHAT", { instance = true }), "INSTANCE_CHAT")
  eq(L.PickChannel("OFF", { party = true }), nil)
end)

test("logic: FormatMessage substitutes %m", function()
  eq(L.FormatMessage("Drinking — %m% mana", 34), "Drinking — 34% mana")
  eq(L.FormatMessage("Mana: %m%", 7), "Mana: 7%")
end)

test("logic: FormatMessage escapes | so chat/print never sees a broken escape code", function()
  eq(L.FormatMessage("Drinking | %m%", 40), "Drinking || 40%")
  eq(L.FormatMessage("a||b", 1), "a||||b")
end)

-- _forever_ hidden mana ---------------------------------------------------------

local ALL_ON = { fyi = { enabled = true }, heads = { enabled = true }, low = { enabled = true }, critical = { enabled = true } }

test("logic: tier bands as mana fractions for the game's curves", function()
  eq(L.TierBands(CUT, ALL_ON, true), {
    { tier = "critical", from = 0, to = 0.2 },
    { tier = "low", from = 0.2, to = 0.5 },
    { tier = "heads", from = 0.5, to = 0.8 },
    { tier = "fyi", from = 0.8, to = 1 },        -- skip at full: nothing at exactly 100%
  })
  local some = deepcopy(ALL_ON); some.heads.enabled = false
  local bands = L.TierBands(CUT, some, false)
  eq(#bands, 3)
  eq(bands[3], { tier = "fyi", from = 0.8 }, "no upper bound when 100% still alerts")
end)

test("logic: low-only bands keep just Low and Critical", function()
  eq(L.TierBands(CUT, ALL_ON, true, true), {
    { tier = "critical", from = 0, to = 0.2 },
    { tier = "low", from = 0.2, to = 0.5 },
  })
end)

test("logic: template to format string for a hidden %", function()
  eq(L.TemplateFormat("Drinking — %m% mana"), "Drinking — %d%% mana")
  eq(L.TemplateFormat("100% sure |cff %m"), "100%% sure ||cff %d")
  eq(L.TemplateFormat("no number"), "no number")
end)

test("logic: message without the number for the group", function()
  eq(L.WithoutNumber("Drinking — %m% mana", "Drinking"), "Drinking")
  eq(L.WithoutNumber("Drinking: %m%", "Drinking"), "Drinking")
  eq(L.WithoutNumber("Drinking (%m%)", "Drinking"), "Drinking")
  eq(L.WithoutNumber("%m% mana, drinking", "Drinking"), "Drinking")
  eq(L.WithoutNumber("Sitting | drinking", "Drinking"), "Sitting || drinking")
end)
