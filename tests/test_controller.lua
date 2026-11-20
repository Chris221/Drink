local FakeEnv = require("fake_env")
local ns = {}
load_addon(ns, "Drink/Logic.lua")
load_addon(ns, "Drink/Defaults.lua")
load_addon(ns, "Drink/Controller.lua")

local function setup(envOverrides, tweak)
  local profile = deepcopy(ns.defaults.profile)
  if tweak then tweak(profile) end
  local env = FakeEnv.New(envOverrides)
  local ctrl = ns.Controller.New(profile, env)
  ctrl:SyncDrinking() -- what the glue does on PLAYER_ENTERING_WORLD
  return ctrl, env, profile
end

-- Fight from t to t+len, then let the deferred evaluation run.
local function fight(ctrl, env, len)
  ctrl:OnCombatStart()
  env:advance(len)
  ctrl:OnCombatEnd()
  env:advance(0)
end

local PARTY = { party = true }

test("controller: alert tier on combat end", function()
  local ctrl, env = setup({ mana = 15 })
  fight(ctrl, env, 10)
  eq(env.alerts, { { "critical", 15 } })
end)

test("controller: alert is deferred one frame", function()
  local ctrl, env = setup({ mana = 15 })
  ctrl:OnCombatStart(); env:advance(10); ctrl:OnCombatEnd()
  eq(#env.alerts, 0, "not before the deferred tick")
  env:advance(0)
  eq(#env.alerts, 1)
end)

test("controller: short fight ignored", function()
  local ctrl, env = setup({ mana = 15 })
  fight(ctrl, env, 2)
  eq(#env.alerts, 0)
end)

test("controller: full mana skipped unless skipAtFull off", function()
  local ctrl, env = setup({ mana = 100 })
  fight(ctrl, env, 10)
  eq(#env.alerts, 0)
  ctrl, env = setup({ mana = 100 }, function(p) p.alert.skipAtFull = false end)
  fight(ctrl, env, 10)
  eq(env.alerts, { { "fyi", 100 } })
end)

test("controller: disabled tier is silent", function()
  local ctrl, env = setup({ mana = 90 }, function(p) p.tiers.fyi.enabled = false end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 0)
end)

test("controller: alert disabled entirely", function()
  local ctrl, env = setup({ mana = 10 }, function(p) p.alert.enabled = false end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 0)
end)

test("controller: only-in-group suppresses solo alert", function()
  local ctrl, env = setup({ mana = 10 }, function(p) p.alert.onlyInGroup = true end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 0)
  ctrl, env = setup({ mana = 10, group = PARTY }, function(p) p.alert.onlyInGroup = true end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 1)
end)

test("controller: dead player gets no alert and no report", function()
  local ctrl, env = setup({ mana = 10, dead = true, group = PARTY }, function(p) p.report.enabled = true end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 0)
  eq(#env.sent, 0)
end)

test("controller: secret mana shows unknown tier and sends nothing", function()
  local ctrl, env = setup({ unknownMana = true, group = PARTY }, function(p) p.report.enabled = true end)
  fight(ctrl, env, 10)
  eq(env.alerts, { { "unknown", nil } })
  env.drinking = true
  ctrl:OnAuraChanged()
  eq(#env.sent, 0)
end)

test("controller: re-entering combat cancels pending alert", function()
  local ctrl, env = setup({ mana = 10 })
  ctrl:OnCombatStart(); env:advance(10); ctrl:OnCombatEnd()
  ctrl:OnCombatStart()
  env:advance(0)
  eq(#env.alerts, 0)
end)

test("controller: re-entering combat cancels group wait", function()
  local ctrl, env = setup({ mana = 10, group = PARTY, groupCombat = true },
    function(p) p.alert.waitForGroup = true end)
  ctrl:OnCombatStart(); env:advance(10); ctrl:OnCombatEnd()
  env:advance(1)
  ctrl:OnCombatStart()
  env.groupCombat = false
  env:advance(5)
  eq(#env.alerts, 0)
end)

test("controller: waits for whole group when enabled", function()
  local ctrl, env = setup({ mana = 10, group = PARTY, groupCombat = true },
    function(p) p.alert.waitForGroup = true end)
  fight(ctrl, env, 10)
  env:advance(2)
  eq(#env.alerts, 0, "group still fighting")
  env.groupCombat = false
  env:advance(0.5)
  eq(env.alerts, { { "critical", 10 } })
end)

test("controller: group wait gives up after timeout", function()
  local ctrl, env = setup({ mana = 10, group = PARTY, groupCombat = true },
    function(p) p.alert.waitForGroup = true end)
  fight(ctrl, env, 10)
  env:advance(61)
  env.groupCombat = false
  env:advance(5)
  eq(#env.alerts, 0)
end)

test("controller: group wait ignored when solo", function()
  local ctrl, env = setup({ mana = 10, groupCombat = true }, function(p) p.alert.waitForGroup = true end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 1)
end)

test("controller: announce once per drinking session", function()
  local ctrl, env = setup({ mana = 34, group = PARTY })
  env.drinking = true
  ctrl:OnAuraChanged(); ctrl:OnAuraChanged(); ctrl:OnAuraChanged()
  eq(env.sent, { { "Drinking — 34% mana", "PARTY" } })
  eq(env.hidden, 1)
  env.drinking = false
  ctrl:OnAuraChanged()
  env:advance(6)
  env.drinking = true
  ctrl:OnAuraChanged()
  eq(#env.sent, 2)
end)

test("controller: announce respects below threshold", function()
  local ctrl, env = setup({ mana = 60, group = PARTY }, function(p) p.announce.below = 50 end)
  env.drinking = true
  ctrl:OnAuraChanged()
  eq(#env.sent, 0)
  env.drinking = false; ctrl:OnAuraChanged()
  env.mana = 40
  env.drinking = true; ctrl:OnAuraChanged()
  eq(env.sent, { { "Drinking — 40% mana", "PARTY" } })
end)

test("controller: announce disabled sends nothing", function()
  local ctrl, env = setup({ mana = 30, group = PARTY }, function(p) p.announce.enabled = false end)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 0)
  eq(env.hidden, 1, "still dismisses alert")
end)

test("controller: solo drinking sends no chat", function()
  local ctrl, env = setup({ mana = 30, group = {} })
  env.drinking = true
  ctrl:OnAuraChanged()
  eq(#env.sent, 0)
end)

test("controller: end-of-fight report and dedup with announce", function()
  local ctrl, env = setup({ mana = 30, group = PARTY }, function(p) p.report.enabled = true end)
  fight(ctrl, env, 10)
  eq(env.sent, { { "Mana: 30%", "PARTY" } })
  env:advance(2)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 1, "announce suppressed within dedup window")
  env.drinking = false; ctrl:OnAuraChanged()
  env:advance(4)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 2)
  eq(env.sent[2], { "Drinking — 30% mana", "PARTY" })
end)

test("controller: report only below threshold", function()
  local ctrl, env = setup({ mana = 60, group = PARTY }, function(p) p.report.enabled = true end)
  fight(ctrl, env, 10)
  eq(#env.sent, 0)
end)

test("controller: chat lockdown prints locally instead", function()
  local ctrl, env = setup({ mana = 34, group = PARTY, locked = true })
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 0)
  eq(env.printed, { "[Drink] (chat locked) Drinking — 34% mana" })
end)

test("controller: previews never send chat", function()
  local ctrl, env = setup({ mana = 34, group = PARTY })
  ctrl:Preview("announce")
  eq(#env.sent, 0)
  eq(env.printed, { "[Drink] would send: Drinking — 34% mana" })
  ctrl:Preview("report")
  eq(env.printed[2], "[Drink] would send: Mana: 34%")
  ctrl:Preview("low")
  eq(env.alerts, { { "low", 35 } })
  ctrl:Preview("critical"); ctrl:Preview("fyi"); ctrl:Preview("heads"); ctrl:Preview("unknown")
  eq(env.alerts[2], { "critical", 12 })
  eq(env.alerts[3], { "fyi", 90 })
  eq(env.alerts[4], { "heads", 65 })
  eq(env.alerts[5], { "unknown", nil })
end)

test("controller: preview with unknown mana uses sample 42", function()
  local ctrl, env = setup({ unknownMana = true, group = PARTY })
  ctrl:Preview("announce")
  eq(env.printed, { "[Drink] would send: Drinking — 42% mana" })
end)

test("controller: character without a mana pool gets nothing", function()
  local ctrl, env = setup({ noMana = true, unknownMana = true, group = PARTY },
    function(p) p.report.enabled = true end)
  fight(ctrl, env, 10)
  eq(#env.alerts, 0)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 0)
end)

-- Final-review fixes -------------------------------------------------------

test("controller: drink already in progress at load is not re-announced (reload)", function()
  local profile = deepcopy(ns.defaults.profile)
  local env = FakeEnv.New({ mana = 80, group = PARTY, drinking = true })
  local ctrl = ns.Controller.New(profile, env)
  ctrl:OnAuraChanged()            -- first aura event after /reload
  ctrl:OnAuraChanged()
  eq(#env.sent, 0)
  env.drinking = false; ctrl:OnAuraChanged()
  env:advance(10)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 1, "next real drink announces")
end)

test("controller: SyncDrinking at world entry while drinking suppresses announce", function()
  local profile = deepcopy(ns.defaults.profile)
  local env = FakeEnv.New({ mana = 80, group = PARTY, drinking = true })
  local ctrl = ns.Controller.New(profile, env)
  ctrl:SyncDrinking()
  ctrl:OnAuraChanged()
  eq(#env.sent, 0)
end)

test("controller: SetProfile keeps drinking state and dedup", function()
  local ctrl, env = setup({ mana = 30, group = PARTY })
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 1)
  ctrl:SetProfile(deepcopy(ns.defaults.profile))
  ctrl:OnAuraChanged()
  eq(#env.sent, 1, "no re-announce after profile switch")
end)

test("controller: SetProfile cancels a pending group wait from the old profile", function()
  local ctrl, env = setup({ mana = 10, group = PARTY, groupCombat = true },
    function(p) p.alert.waitForGroup = true end)
  fight(ctrl, env, 10)
  local newp = deepcopy(ns.defaults.profile)
  newp.alert.enabled = false
  ctrl:SetProfile(newp)
  env.groupCombat = false
  env:advance(1)
  eq(#env.alerts, 0)
end)

test("controller: drinking during group wait skips alert and report", function()
  local ctrl, env = setup({ mana = 30, group = PARTY, groupCombat = true },
    function(p) p.alert.waitForGroup = true; p.report.enabled = true end)
  fight(ctrl, env, 10)
  env:advance(1)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(env.sent, { { "Drinking — 30% mana", "PARTY" } })
  env:advance(10)
  env.groupCombat = false
  env:advance(0.5)
  eq(#env.alerts, 0, "no DRINK alert while already drinking")
  eq(#env.sent, 1, "no report after the announce")
end)

test("controller: new pull hides a visible alert", function()
  local ctrl, env = setup({ mana = 10 })
  fight(ctrl, env, 10)
  eq(#env.alerts, 1)
  local before = env.hidden
  ctrl:OnCombatStart()
  eq(env.hidden, before + 1)
end)

test("controller: no drinking announce at full mana (buff food / feasts)", function()
  local ctrl, env = setup({ mana = 100, group = PARTY })
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 0)
end)

test("controller: aura changes during combat are ignored; combat resets drinking", function()
  local ctrl, env = setup({ mana = 30, group = PARTY })
  env.inCombat = true
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 0)
  eq(env.hidden, 0, "no scan side effects in combat")
  env.inCombat = false
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 1)
  ctrl:OnCombatStart()            -- drink buff is lost on entering combat
  env.drinking = false
  ctrl:OnCombatEnd(); env:advance(10)
  env.drinking = true; ctrl:OnAuraChanged()
  eq(#env.sent, 2, "next drink after combat announces even without a falling-edge event")
end)
