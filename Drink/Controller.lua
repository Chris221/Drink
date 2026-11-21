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

function Controller.New(profile, env)
  return setmetatable({
    p = profile,
    env = env,
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

  local a = p.alert
  if a.enabled
    and not self.drinking -- already drinking (e.g. sat down while waiting for the group)
    and not (a.skipAtFull and pct == 100)
    and not (a.onlyInGroup and not inGroup(env.groupState())) then
    if hidden then
      env.showAlertHidden(env.lowManaConfirmed())
    else
      local tier = Logic.GetTier(pct, p.cutoffs)
      local t = p.tiers[tier]
      if tier == "unknown" or (t and t.enabled) then
        env.showAlert(tier, pct)
      end
    end
  end

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
  local summary = ns.Drinks.StockSummary(env.getUsableDrinks(), max, st.threshold)
  local wasLow = self.stockWasLow
  self.stockWasLow = summary.low
  if not summary.low or wasLow then return end
  local detail = summary.breakdown ~= "" and (" (" .. summary.breakdown .. ")") or ""
  env.print("[Drink] STOCK UP: " .. summary.total .. " drinks left" .. detail)
  local gen = self.gen
  env.after(MIDRUN_LINE_DELAY, function()
    if gen == self.gen then env.showStock(summary) end
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

function Controller:OnEnteringWorld(isReload, instanceType)
  self.instanceType = instanceType
  if isReload then return end
  self.stockWasLow = nil
  self:OnZoneChanged()
  if self.p.stock.enabled and (instanceType == "party" or instanceType == "raid") then
    -- Skip while dead/ghost (corpse run): items may read as unusable and falsely say STOCK UP.
    self.env.after(STOCK_DELAY, function() if not self.env.isDead() then self:StockCheck() end end)
  end
end

function Controller:StockCheck()
  local env = self.env
  local max = env.getMaxMana()
  if not env.hasMana() or not max then return end
  local drinks = env.getUsableDrinks()
  local summary = ns.Drinks.StockSummary(drinks, max, self.p.stock.threshold)
  self.stockWasLow = summary.low
  env.showStock(summary)
  if summary.breakdown ~= "" then
    env.print("[Drink] " .. summary.breakdown)
  else
    env.print("[Drink] No drinks in your bags.")
  end
  self:OfferMage(summary, drinks)
end

-- Ask a mage for water ----------------------------------------------------------
-- Only ever offers a button. Nothing is sent until the user clicks it (RequestWater).

function Controller:OfferMage(summary, drinks)
  local env = self.env
  if not self.p.mage.enabled then return end
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

-- While I'm sitting: alert once if the group goes from calm into combat.
function Controller:WatchForPull()
  local env = self.env
  if not self.p.alert.pullWhileDrinking or not inGroup(env.groupState()) then return end
  local token = self.drinkToken
  local seenCalm = not env.groupInCombat() -- still finishing the last fight is not a new pull
  local function poll()
    if token ~= self.drinkToken or not self.drinking or env.inCombatNow() then return end
    if not env.groupInCombat() then
      seenCalm = true
    elseif seenCalm then
      env.showPullAlert()
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
  if env.inCombatNow() or env.groupInCombat() then return end
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
  local drinking = env.isDrinking()
  if self.drinking == nil then
    self.drinking = drinking and true or false
    return
  end
  if drinking and not self.drinking then
    self.drinking = true
    self.drinkToken = self.drinkToken + 1
    env.hideAlert()
    env.hideDrinkButton() -- drank from the action bar (or the button): the button's job is done
    local an = self.p.announce
    local pct = env.getManaPct()
    local hidden = pct == nil and env.manaHidden()
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
    self:PrintDrinkStats(pct, hidden)
    self:WatchForPull()
  elseif not drinking then
    local was = self.drinking
    self.drinking = false
    if was then self:MaybeReady() end
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

