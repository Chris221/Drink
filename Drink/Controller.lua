-- Combat / drinking state machine. Talks to the game only through `env`
-- (see docs/superpowers/plans/2026-11-20-drink-addon.md, Task 2, for the contract).
local ADDON, ns = ...
local Logic = ns.Logic

local Controller = {}
Controller.__index = Controller
ns.Controller = Controller

local SAMPLE_PCT = { fyi = 90, heads = 65, low = 35, critical = 12 }
local POLL_INTERVAL = 0.5
-- Mana unreadable and the game can't draw it either (no curve API): re-read it a few times
-- before giving up and showing "mana unknown". (_forever_'s always-secret mana skips this.)
local MANA_POLL, MANA_WAIT = 0.25, 2
local STOCK_DELAY = 3     -- seconds after a loading screen, so bag item data has settled
local MAGE_SECONDS = 10   -- how long the "ask a mage" button stays up
local MIDRUN_LINE_DELAY = 5 -- let the drink alert have its time before the stock line replaces it
local READY_GRACE = 2     -- the drink buff ending isn't standing up: wait for a 2nd drink or a pull

-- store: this character's saved table (dungeon run tally, see Tally.lua).
function Controller.New(profile, env, store)
  store = store or {}
  store.runs = store.runs or {}
  return setmetatable({
    p = profile,
    env = env,
    store = store,
    gen = 0,              -- bumps on every combat transition; stale callbacks compare against it
    combatStart = nil,
    drinking = nil,       -- nil = not yet observed (e.g. right after /reload): first observation is not an edge
    lastPost = nil,
    announcedAt = nil,
    downtime = ns.Drinks.NewDowntime(),
    buttonToken = 0,      -- bumps on every button show; a hide timer only acts on its own show
    -- A "break" is the time between two fights: one Drinking and one Ready post per break.
    announcedThisBreak = false,
    readyThisBreak = false,
    drinkToken = 0,       -- bumps on every drink start; the pull watcher only acts on its own drink
    lastRec = nil,        -- last recommended drink: what the drink stats assume I'm drinking
    instanceType = nil,
    stockWasLow = nil,    -- result of the last stock check in this instance
    mageName = nil,       -- set while the "ask a mage" button is showing
    mageToken = 0,
    drinkStartedAt = nil, -- when the drink I'm timing began (only drinks that count)
    drinkEnds = nil,      -- when the drink buff runs out, where the game says
    pullCounted = false,  -- one mid-drink pull per break
    worldToken = 0,       -- bumps on every loading screen; a pending "left the dungeon" checks it
  }, Controller)
end

-- Swap profiles (AceDB profile change) without losing drinking / dedup / pending-timer state.
function Controller:SetProfile(profile)
  self.p = profile
end

-- Record the current drinking state without announcing (PLAYER_ENTERING_WORLD).
function Controller:SyncDrinking()
  if self.env.inCombatNow() then return end
  self.drinking = self.env.isDrinking() and true or false
end

local function inGroup(state)
  return state and (state.party or state.raid or state.instance) and true or false
end

function Controller:OnCombatStart()
  self.gen = self.gen + 1
  self.combatStart = self.env.now()
  if self.drinking and self.drinkStartedAt then self:CountPull() end -- still seated when it reached me
  self:StopDrinkClock()
  self.drinking = false   -- entering combat removes the drink buff; aura scans pause in combat
  self.downtime:RecordStart(self.combatStart)
  self.env.hideAlert()    -- don't carry a DRINK alert / red flash into the next pull
  self.env.hideDrinkButton() -- runs before combat lockdown applies; never leave a stale button
  self.announcedThisBreak = false
  self.readyThisBreak = false
  if self.mageName then self:HideMage() end
end

function Controller:OnCombatEnd()
  self.gen = self.gen + 1
  local gen, env = self.gen, self.env
  local now = env.now()
  self.downtime:RecordEnd(now)
  self.pullCounted = false
  local run = self:Run()
  if run then
    run.fights = run.fights + 1
    run.seen = env.wallTime()
  end
  env.hideDrinkButton()
  -- Unknown start (e.g. loaded mid-fight) counts as a long fight.
  local duration = self.combatStart and (now - self.combatStart) or math.huge
  self.combatStart = nil

  if self.p.alert.waitForGroup and inGroup(env.groupState()) then
    local started = now
    local function check()
      if gen ~= self.gen then return end
      if not env.groupInCombat() then
        self:EvaluateWhenReadable(duration, now, gen)
      elseif env.now() - started < self.p.alert.waitTimeout then
        env.after(POLL_INTERVAL, check)
      end
    end
    env.after(0, check)
  else
    env.after(0, function()
      if gen == self.gen then self:EvaluateWhenReadable(duration, now, gen) end
    end)
  end
end

function Controller:EvaluateWhenReadable(duration, endedAt, gen)
  local env = self.env
  local started = env.now()
  local function try()
    if gen ~= self.gen then return end -- a new pull started meanwhile
    if env.getManaPct() or env.manaHidden() or not env.hasMana() or env.now() - started >= MANA_WAIT then
      self:Evaluate(duration, endedAt)
    else
      env.after(MANA_POLL, try)
    end
  end
  try()
end

-- endedAt: when combat ended; anything announced since then makes the report redundant.
function Controller:Evaluate(duration, endedAt)
  local p, env = self.p, self.env
  if env.isDead() or not env.hasMana() then return end
  if duration < p.alert.minFightSeconds then return end
  local pct = env.getManaPct()
  -- _forever_: mana is a secret value. The game draws it, but the addon can't compare it,
  -- so tiers are picked by the game (curves) and thresholds can't apply.
  local hidden = pct == nil and env.manaHidden()
  local confirmedLow = hidden and env.lowManaConfirmed()

  local a = p.alert
  -- Fighting on another resource (bear or cat form, shadow, elemental...): mana isn't what
  -- I'm spending, so only speak up when it is actually low.
  local lowOnly = a.lowOnlyOffResource and not env.manaIsActive()
  local alertOnly = false
  if lowOnly then
    if hidden then
      -- The game still draws the alert (Low and Critical only); the rest needs confirmed low.
      alertOnly = not confirmedLow
    else
      local tier = Logic.GetTier(pct, p.cutoffs)
      if tier ~= "low" and tier ~= "critical" then return end
    end
  end

  if a.enabled
    and not self.drinking -- already drinking (e.g. sat down while waiting for the group)
    and not (a.skipAtFull and pct == 100)
    and not (a.onlyInGroup and not inGroup(env.groupState())) then
    if hidden then
      env.showAlertHidden(confirmedLow, lowOnly)
    else
      local tier = Logic.GetTier(pct, p.cutoffs)
      local t = p.tiers[tier]
      if tier == "unknown" or (t and t.enabled) then
        env.showAlert(tier, pct)
      end
    end
  end

  if alertOnly then return end

  local r = p.report
  local announcedSinceEnd = self.announcedAt and endedAt and self.announcedAt >= endedAt
  if r.enabled and not announcedSinceEnd then
    if hidden then
      env.printHidden(r.template) -- the number can't be sent to chat, only shown to me
    elseif pct and pct < r.below then
      self:Post(Logic.FormatMessage(r.template, pct), r.channel, r.soloLocal)
    end
  end

  local rc = p.recommend
  if rc.enabled and not self.drinking and (hidden or (pct and (rc.below >= 100 or pct < rc.below))) then
    self:ShowRecommendation()
  end

  self:MidRunStock()
end

-- Inside an instance: warn once when the drink count drops below the threshold.
function Controller:MidRunStock()
  local env, st = self.env, self.p.stock
  if not (st.enabled and st.midRun) then return end
  if self.instanceType ~= "party" and self.instanceType ~= "raid" then return end
  local max = env.getMaxMana()
  if not max then return end
  local need, usual = self:StockNeed()
  local summary = ns.Drinks.StockSummary(env.getUsableDrinks(), max, need)
  if usual then summary.need = need end
  local wasLow = self.stockWasLow
  self.stockWasLow = summary.low
  if not summary.low or wasLow then return end
  local detail = summary.breakdown ~= "" and (" (" .. summary.breakdown .. ")") or ""
  env.print("[Drink] STOCK UP: " .. summary.total .. " drinks left" .. detail)
  local gen = self.gen
  env.after(MIDRUN_LINE_DELAY, function()
    -- Not while I'm sitting: a PULL warning matters more than the stock line (chat has it).
    if gen == self.gen and not self.drinking then env.showStock(summary) end
  end)
end

-- Drink recommendation ------------------------------------------------------

function Controller:Recommend()
  local env, rc = self.env, self.p.recommend
  local pct, max = env.getManaPct(), env.getMaxMana()
  if not max then return nil end
  local deficit
  if pct then
    deficit = math.floor(max * (100 - pct) / 100)
  elseif env.manaHidden() then
    deficit = max -- missing mana unknown: offer a full refill
  else
    return nil
  end
  return ns.Drinks.Pick(env.getUsableDrinks(), deficit, {
    preferConjured = rc.preferConjured,
    downtime = rc.useDowntime and self.downtime:Estimate() or nil,
  })
end

-- Shows the button for the configured seconds; returns the drink or nil.
function Controller:ShowRecommendation()
  local env = self.env
  local rec = self:Recommend()
  if rec then self.lastRec = rec end
  if not rec or not env.showDrinkButton(rec) then return nil end
  self.buttonToken = self.buttonToken + 1
  local token, gen = self.buttonToken, self.gen
  env.after(self.p.recommend.seconds, function()
    if token == self.buttonToken and gen == self.gen then env.hideDrinkButton() end
  end)
  return rec
end

function Controller:DowntimeInfo()
  return { estimate = self.downtime:Estimate(), count = self.downtime:Count() }
end

function Controller:OnZoneChanged()
  self.downtime:Reset()
end

-- Stock check ---------------------------------------------------------------

function Controller:OnEnteringWorld(isReload, instanceType, instanceName)
  local wasInside = self.instanceType == "party" or self.instanceType == "raid"
  self.instanceType = instanceType
  if isReload then return end -- the open run is saved: it simply carries on
  self:TrackRun(wasInside, instanceName)
  self.stockWasLow = nil
  self:OnZoneChanged()
  if self.p.stock.enabled and (instanceType == "party" or instanceType == "raid") then
    -- Skip while dead/ghost (corpse run): items may read as unusable and falsely say STOCK UP.
    self.env.after(STOCK_DELAY, function()
      local env = self.env
      if env.isDead() then return end
      -- Not fighting on mana (bear or cat form, shadow...): don't nag about drinks.
      if self.p.alert.lowOnlyOffResource and not env.manaIsActive() then return end
      self:StockCheck()
    end)
  end
end

function Controller:StockCheck()
  local env = self.env
  local max = env.getMaxMana()
  if not env.hasMana() or not max then return end
  local drinks = env.getUsableDrinks()
  local need, usual = self:StockNeed()
  local summary = ns.Drinks.StockSummary(drinks, max, need)
  if usual then summary.need = need end
  self.stockWasLow = summary.low
  env.showStock(summary)
  if summary.breakdown ~= "" then
    env.print("[Drink] " .. summary.breakdown)
  else
    env.print("[Drink] No drinks in your bags.")
  end
  if usual then env.print("[Drink] " .. ns.Tally.UsualLine(self.store.run.name, usual)) end
  self:OfferMage(summary, drinks)
end

-- How many drinks I should be carrying. In a dungeon I've run before: the most one of the
-- kept runs took, less what this run has used so far (returned with those past figures).
-- Anywhere else: the fixed number from the options.
function Controller:StockNeed()
  local st, run = self.p.stock, self:Run()
  local usual = st.learn and run and ns.Tally.Usual(self.store, run.name) or nil
  if not usual then return st.threshold end
  if usual.most == 0 then return 0, usual end -- never needed a drink here: nothing to nag about
  return math.max(1, usual.most - run.drinks), usual
end

-- Dungeon run tally ---------------------------------------------------------------

-- The run I'm in, while I'm inside its dungeon or raid; nil anywhere else or with the tally off.
function Controller:Run()
  if not self.p.tally.enabled then return nil end
  if self.instanceType ~= "party" and self.instanceType ~= "raid" then return nil end
  return self.store.run
end

-- A loading screen. Landing in a dungeon or raid starts a run or carries one on; landing
-- anywhere else alive finishes it. Dead is a corpse run: the run stays open.
function Controller:TrackRun(wasInside, name)
  local env, store = self.env, self.store
  self.worldToken = self.worldToken + 1
  if not self.p.tally.enabled then return end
  if self.instanceType == "party" or self.instanceType == "raid" then
    if name then
      ns.Tally.Open(store, name, env.wallTime())
    else
      ns.Tally.Close(store) -- no name to file it under: don't count into somebody else's run
    end
    return
  end
  if not store.run then return end
  local token = self.worldToken
  env.after(STOCK_DELAY, function() -- dead-or-ghost has settled by now
    if token ~= self.worldToken or env.isDead() then return end
    local done, dungeon = ns.Tally.Close(store)
    if done and wasInside and self.p.tally.summary then
      env.print("[Drink] " .. ns.Tally.RunLine(dungeon, done))
    end
  end)
end

function Controller:CountDrink()
  local run = self:Run()
  if not run then return end
  run.drinks = run.drinks + 1
  run.seen = self.env.wallTime()
end

function Controller:StopDrinkClock()
  local run, at = self:Run(), self.drinkStartedAt
  self.drinkStartedAt = nil
  if run and at then run.seconds = run.seconds + (self.env.now() - at) end
end

function Controller:CountPull()
  local run = self:Run()
  if not run or self.pullCounted then return end
  self.pullCounted = true
  run.pulls = run.pulls + 1
end

function Controller:RunLines() return ns.Tally.List(self.store) end
function Controller:ForgetRuns() ns.Tally.Clear(self.store) end

-- Ask a mage for water ----------------------------------------------------------
-- Only ever offers a button. Nothing is sent until the user clicks it (RequestWater).

function Controller:OfferMage(summary, drinks)
  local env = self.env
  if not self.p.mage.enabled or env.inCombatNow() then return end
  local name = env.findMage()
  if not name then return end
  local hasConjured = false
  for _, d in ipairs(drinks) do
    if d.conjured then hasConjured = true end
  end
  if not summary.low and hasConjured then return end
  self.mageName = name
  self.mageToken = self.mageToken + 1
  local token = self.mageToken
  env.showMageButton(name)
  env.after(MAGE_SECONDS, function()
    if token == self.mageToken and self.mageName then self:HideMage() end
  end)
end

function Controller:HideMage()
  self.mageName = nil
  self.env.hideMageButton()
end

-- The click on the "ask a mage" button.
function Controller:RequestWater()
  local env, m = self.env, self.p.mage
  local name = self.mageName
  if not name then return end
  local msg = string.gsub(m.template, "|", "||")
  local channel = m.channel == "GROUP" and Logic.PickChannel("AUTO", env.groupState()) or nil
  if env.chatLocked() then
    env.print("[Drink] (chat locked) " .. msg)
  elseif channel then
    env.sendChat(msg, channel)
  else
    env.sendWhisper(msg, name)
  end
  self:HideMage()
end

-- Drinking --------------------------------------------------------------------

-- Printed to my own chat on every drink start: time to full and drinks needed, with regen.
function Controller:PrintDrinkStats(pct, hidden)
  local env, rec = self.env, self.lastRec
  if not self.p.recommend.stats or not rec then return end
  local max = env.getMaxMana()
  if not max then return end
  local regen = env.getManaRegen()
  if pct then
    local st = ns.Drinks.FillStats(rec, max * (100 - pct) / 100, regen)
    if not st then return end
    if st.drinks <= 1 then
      env.print("[Drink] " .. rec.name .. ": full in ~" .. st.seconds .. "s")
    else
      env.print("[Drink] " .. rec.name .. ": " .. st.drinks .. " drinks to fill (~" .. st.seconds .. "s)")
    end
  elseif hidden then
    env.printHiddenStats(rec, max, regen) -- the game does the maths on the hidden amount
  end
end

-- While I'm sitting: alert once if the group goes from calm into combat (and tally it).
function Controller:WatchForPull()
  local env = self.env
  local alert = self.p.alert.pullWhileDrinking
  if not (alert or self:Run()) or not inGroup(env.groupState()) then return end
  local token = self.drinkToken
  -- groupInCombat() may be nil (hidden by the game): unknown is neither calm nor a pull.
  local seenCalm = env.groupInCombat() == false -- still finishing the last fight is not a new pull
  local function poll()
    if token ~= self.drinkToken or not self.drinking or env.inCombatNow() then return end
    local fighting = env.groupInCombat()
    if fighting == false then
      seenCalm = true
    elseif fighting == true and seenCalm then
      if self.drinkStartedAt then self:CountPull() end
      if alert then env.showPullAlert() end
      return
    end
    env.after(POLL_INTERVAL, poll)
  end
  env.after(POLL_INTERVAL, poll)
end

-- "Ready" when I stand up: once per break, only after an announced drink, and never while
-- I or anyone in the group is in combat.
function Controller:MaybeReady()
  local env, r = self.env, self.p.ready
  if not r.enabled or not self.announcedThisBreak or self.readyThisBreak then return end
  if env.inCombatNow() or env.groupInCombat() ~= false then return end -- unknown counts as fighting
  local pct = env.getManaPct()
  if pct then
    if pct >= r.atLeast and self:Post(Logic.FormatMessage(r.template, pct), r.channel, r.soloLocal) then
      self.readyThisBreak = true
    end
  elseif env.manaHidden() then
    if not env.lowManaConfirmed() and self:PostHidden(r.template, r.channel, r.soloLocal, "Ready", false) then
      self.readyThisBreak = true
    end
  end
end

function Controller:OnAuraChanged()
  local env = self.env
  if env.inCombatNow() then return end -- nobody drinks in combat; skip the scan (raid aura spam)
  local drinking, ends = env.isDrinking() -- ends: when the buff runs out, where the game says
  if self.drinking == nil then
    self.drinking = drinking and true or false
    self.drinkEnds = drinking and ends or nil
    return
  end
  if drinking and not self.drinking then
    self.drinking = true
    self.drinkEnds = ends
    self.drinkToken = self.drinkToken + 1
    env.hideAlert()
    env.hideDrinkButton() -- drank from the action bar (or the button): the button's job is done
    local an = self.p.announce
    local pct = env.getManaPct()
    local hidden = pct == nil and env.manaHidden()
    if pct ~= 100 then -- at full mana it's food, not a drink
      self:CountDrink()
      self.drinkStartedAt = env.now()
    end
    if an.enabled and not self.announcedThisBreak then -- a 2nd drink in the same break stays quiet
      local posted
      if hidden then
        posted = self:PostHidden(an.template, an.channel, an.soloLocal, "Drinking", true)
      -- Never at 100%: stat food / feasts named "Food & Drink" would otherwise spam the raid.
      elseif pct and pct < 100 and (an.below >= 100 or pct < an.below) then
        posted = self:Post(Logic.FormatMessage(an.template, pct), an.channel, an.soloLocal)
      end
      if posted then
        self.announcedAt = env.now()
        self.announcedThisBreak = true
      end
    end
    self:WatchForPull() -- before the stats, so nothing there can stop the watcher
    self:PrintDrinkStats(pct, hidden)
  elseif drinking then
    -- Still drinking, but the buff now runs out later: another drink went down.
    if ends and self.drinkEnds and ends > self.drinkEnds + 0.5 and self.drinkStartedAt then
      self:CountDrink()
    end
    self.drinkEnds = ends or self.drinkEnds
  elseif not drinking then
    local was = self.drinking
    self.drinking = false
    if was then
      self:StopDrinkClock()
      -- The buff ending isn't standing up (a drink can run out while seated): wait a moment;
      -- a second drink or a pull cancels it.
      local token, gen = self.drinkToken, self.gen
      env.after(READY_GRACE, function()
        if token == self.drinkToken and gen == self.gen and not self.drinking then self:MaybeReady() end
      end)
    end
  end
end

-- soloLocal: when not in any group, show the message in my own chat window instead (never sent).
function Controller:Post(msg, mode, soloLocal)
  local env = self.env
  local state = env.groupState() or {}
  local channel = Logic.PickChannel(mode, state)
  local solo = not (state.instance or state.raid or state.party)
  if not channel and not (solo and soloLocal) then return false end
  local now = env.now()
  if self.lastPost and now - self.lastPost < self.p.dedupSeconds then return false end
  self.lastPost = now
  if not channel then
    env.print("[Drink] " .. msg)
  elseif env.chatLocked() then
    env.print("[Drink] (chat locked) " .. msg)
  else
    env.sendChat(msg, channel)
  end
  return true
end

-- Hidden mana: the group gets the message without the number (secret values can't be sent).
-- fallback: what to send if the template is nothing but the number.
-- echoLocal: also show me the full line with the real %, drawn by the game (always when solo).
function Controller:PostHidden(template, mode, soloLocal, fallback, echoLocal)
  local env = self.env
  local state = env.groupState() or {}
  local channel = Logic.PickChannel(mode, state)
  local solo = not (state.instance or state.raid or state.party)
  if not channel and not (solo and soloLocal) then return false end
  local now = env.now()
  if self.lastPost and now - self.lastPost < self.p.dedupSeconds then return false end
  self.lastPost = now
  if channel then
    local msg = Logic.WithoutNumber(template, fallback or "Drinking")
    if env.chatLocked() then
      env.print("[Drink] (chat locked) " .. msg)
    else
      env.sendChat(msg, channel)
    end
  end
  if echoLocal or not channel then env.printHidden(template) end
  return true
end

function Controller:Preview(kind)
  local env = self.env
  if kind == "announce" or kind == "report" or kind == "ready" then
    local pct = env.getManaPct() or (kind == "ready" and 90 or 42)
    env.print("[Drink] would send: " .. Logic.FormatMessage(self.p[kind].template, pct))
    return true
  end
  if kind == "drink" then
    if not self:ShowRecommendation() then env.print("[Drink] No usable drink to recommend.") end
    return true
  end
  if kind == "stock" then
    self:StockCheck()
    return true
  end
  if SAMPLE_PCT[kind] or kind == "unknown" then
    env.showAlert(kind, SAMPLE_PCT[kind])
    return true
  end
  return false
end

