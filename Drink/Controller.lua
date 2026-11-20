-- Combat / drinking state machine. Talks to the game only through `env`
-- (see docs/superpowers/plans/2026-11-20-drink-addon.md, Task 2, for the contract).
local ADDON, ns = ...
local Logic = ns.Logic

local Controller = {}
Controller.__index = Controller
ns.Controller = Controller

local SAMPLE_PCT = { fyi = 90, heads = 65, low = 35, critical = 12 }
local POLL_INTERVAL = 0.5

function Controller.New(profile, env)
  return setmetatable({
    p = profile,
    env = env,
    gen = 0,              -- bumps on every combat transition; stale callbacks compare against it
    combatStart = nil,
    drinking = false,
    lastPost = nil,
  }, Controller)
end

local function inGroup(state)
  return state and (state.party or state.raid or state.instance) and true or false
end

function Controller:OnCombatStart()
  self.gen = self.gen + 1
  self.combatStart = self.env.now()
end

function Controller:OnCombatEnd()
  self.gen = self.gen + 1
  local gen, env = self.gen, self.env
  local now = env.now()
  -- Unknown start (e.g. loaded mid-fight) counts as a long fight.
  local duration = self.combatStart and (now - self.combatStart) or math.huge
  self.combatStart = nil

  if self.p.alert.waitForGroup and inGroup(env.groupState()) then
    local started = now
    local function check()
      if gen ~= self.gen then return end
      if not env.groupInCombat() then
        self:Evaluate(duration)
      elseif env.now() - started < self.p.alert.waitTimeout then
        env.after(POLL_INTERVAL, check)
      end
    end
    env.after(0, check)
  else
    env.after(0, function()
      if gen == self.gen then self:Evaluate(duration) end
    end)
  end
end

function Controller:Evaluate(duration)
  local p, env = self.p, self.env
  if env.isDead() then return end
  if duration < p.alert.minFightSeconds then return end
  local pct = env.getManaPct()

  local a = p.alert
  if a.enabled
    and not (a.skipAtFull and pct == 100)
    and not (a.onlyInGroup and not inGroup(env.groupState())) then
    local tier = Logic.GetTier(pct, p.cutoffs)
    local t = p.tiers[tier]
    if tier == "unknown" or (t and t.enabled) then
      env.showAlert(tier, pct)
    end
  end

  local r = p.report
  if r.enabled and pct and pct < r.below then
    self:Post(Logic.FormatMessage(r.template, pct), r.channel)
  end
end

function Controller:OnAuraChanged()
  local env = self.env
  local drinking = env.isDrinking()
  if drinking and not self.drinking then
    self.drinking = true
    env.hideAlert()
    local an = self.p.announce
    local pct = env.getManaPct()
    if an.enabled and pct and (an.below >= 100 or pct < an.below) then
      self:Post(Logic.FormatMessage(an.template, pct), an.channel)
    end
  elseif not drinking then
    self.drinking = false
  end
end

function Controller:Post(msg, mode)
  local env = self.env
  local channel = Logic.PickChannel(mode, env.groupState())
  if not channel then return false end
  local now = env.now()
  if self.lastPost and now - self.lastPost < self.p.dedupSeconds then return false end
  self.lastPost = now
  if env.chatLocked() then
    env.print("[Drink] (chat locked) " .. msg)
  else
    env.sendChat(msg, channel)
  end
  return true
end

function Controller:Preview(kind)
  local env = self.env
  if kind == "announce" or kind == "report" then
    local pct = env.getManaPct() or 42
    env.print("[Drink] would send: " .. Logic.FormatMessage(self.p[kind].template, pct))
    return true
  end
  if SAMPLE_PCT[kind] or kind == "unknown" then
    env.showAlert(kind, SAMPLE_PCT[kind])
    return true
  end
  return false
end
