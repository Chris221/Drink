-- Fake implementation of the Controller's env contract, with a controllable clock.
local FakeEnv = {}

function FakeEnv.New(o)
  local env = {
    t = 0, mana = 50, dead = false, drinking = false, noMana = false,
    group = {}, groupCombat = false, locked = false,
    sent = {}, printed = {}, alerts = {}, hidden = 0,
    queue = {}, seq = 0,
    drinks = {}, maxMana = 1000, buttonShown = nil, buttonShows = {}, buttonHides = 0, stocks = {},
  }
  for k, v in pairs(o or {}) do env[k] = v end

  function env.now() return env.t end
  -- Real-world clock (seconds): survives /reload and logging out, unlike now().
  function env.wallTime() return (env.wall or 1700000000) + env.t end
  function env.after(delay, fn)
    env.seq = env.seq + 1
    env.queue[#env.queue + 1] = { at = env.t + delay, seq = env.seq, fn = fn }
  end
  function env.getManaPct() if env.unknownMana or env.hiddenMana then return nil end return env.mana end
  -- _forever_: current mana is a secret value the game can draw but the addon can't read.
  env.hiddenAlerts, env.hiddenPrints = {}, {}
  function env.manaHidden() return env.hiddenMana == true end
  function env.lowManaConfirmed() return env.lowConfirmed == true end
  function env.showAlertHidden(sound, lowOnly)
    env.hiddenAlerts[#env.hiddenAlerts + 1] = { sound = sound, lowOnly = lowOnly or nil }
  end
  -- false in bear or cat form, shadow, elemental...: mana is there but isn't what I fight with.
  function env.manaIsActive() return env.offResource ~= true end
  function env.printHidden(template) env.hiddenPrints[#env.hiddenPrints + 1] = template end
  function env.hasMana() return not env.noMana end
  function env.inCombatNow() return env.inCombat == true end
  function env.isDead() return env.dead end
  -- Second value: when the drink buff runs out (nil where the game won't say).
  function env.isDrinking() return env.drinking, env.drinking and env.drinkEnds or nil end
  function env.groupState() return env.group end
  function env.groupInCombat() return env.groupCombat end
  function env.chatLocked() return env.locked end
  function env.sendChat(msg, channel) env.sent[#env.sent + 1] = { msg, channel } end
  function env.print(msg) env.printed[#env.printed + 1] = msg end
  function env.showAlert(tier, pct) env.alerts[#env.alerts + 1] = { tier, pct } end
  function env.hideAlert() env.hidden = env.hidden + 1 end
  function env.getUsableDrinks() return env.drinks end
  function env.getMaxMana() return env.maxMana end
  function env.showDrinkButton(d)
    if env.inCombat then return false end
    env.buttonShown = d; env.buttonShows[#env.buttonShows + 1] = d.name; return true
  end
  function env.hideDrinkButton() env.buttonHides = env.buttonHides + 1; env.buttonShown = nil end
  function env.showStock(s) env.stocks[#env.stocks + 1] = s end
  env.whispers, env.mageShows, env.pulls, env.hiddenStats = {}, {}, 0, {}
  function env.getManaRegen() return env.regen end
  function env.findMage() return env.mage end
  function env.sendWhisper(msg, name) env.whispers[#env.whispers + 1] = { msg, name } end
  function env.showMageButton(name) env.mageShown = name; env.mageShows[#env.mageShows + 1] = name end
  function env.hideMageButton() env.mageShown = nil end
  function env.showPullAlert() env.pulls = env.pulls + 1 end
  function env.printHiddenStats(drink, max, regen) env.hiddenStats[#env.hiddenStats + 1] = { drink.name, max, regen } end

  -- Advance the clock, running due callbacks in time order (callbacks may schedule more).
  function env:advance(dt)
    local target = self.t + dt
    while true do
      local best, bi
      for i, item in ipairs(self.queue) do
        if item.at <= target and (not best or item.at < best.at or (item.at == best.at and item.seq < best.seq)) then
          best, bi = item, i
        end
      end
      if not best then break end
      table.remove(self.queue, bi)
      self.t = best.at
      best.fn()
    end
    self.t = target
  end

  return env
end

return FakeEnv
