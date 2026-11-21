-- Ace3 glue: wires game events and the real env into the Controller.
local ADDON, ns = ...
local Compat = ns.Compat

local Drink = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = Drink

local ctrl, env, nameSet, overrideSet = nil, nil, {}, {}

function ns.ctrl() return ctrl end

-- /drink debug: log when mana is readable and which addon restrictions are active (session only).
local debugOn = false
local function debugLog(what)
  if debugOn and Compat.ManaDebugLine then
    print("|cff33ccff[Drink debug]|r " .. what .. ": " .. Compat.ManaDebugLine())
  end
end

function ns.ToggleDebug()
  debugOn = not debugOn
  print("|cff33ccff[Drink debug]|r " .. (debugOn and "on (until /reload or /drink debug)" or "off"))
  debugLog("now")
end

local function debugAfterCombat()
  if not debugOn or not (C_Timer and C_Timer.After) then return end
  for _, s in ipairs({ 1, 3, 10, 30 }) do
    C_Timer.After(s, function() debugLog("combat ended +" .. s .. "s") end)
  end
end

function ns.RefreshOverrides()
  overrideSet = ns.Drinks.ParseOverrides(Drink.db.profile.recommend.overrides)
end

function ns.RefreshAuraNames()
  nameSet = ns.Logic.ParseNames(Drink.db.profile.announce.auraNames)
end

local function buildEnv()
  return {
    now = function() return GetTime() end,
    after = function(delay, fn) C_Timer.After(delay, fn) end,
    getManaPct = Compat.GetManaPercent,
    manaHidden = function() return Compat.ManaHidden and Compat.ManaHidden() or false end,
    lowManaConfirmed = function() return Compat.LowManaConfirmed and Compat.LowManaConfirmed() or false end,
    showAlertHidden = function(sound)
      if not (ns.Alert and ns.Alert.ShowHidden) then return end
      local p = Drink.db.profile
      ns.Alert.ShowHidden(Compat.HiddenManaView(ns.Logic.TierBands(p.cutoffs, p.tiers, p.alert.skipAtFull)), sound)
    end,
    printHidden = function(template) pcall(print, Compat.HiddenMessage(template)) end,
    hasMana = Compat.HasMana,
    inCombatNow = function() return InCombatLockdown() and true or false end,
    isDead = function() return UnitIsDeadOrGhost("player") and true or false end,
    isDrinking = function() return Compat.IsDrinking(nameSet) end,
    groupState = Compat.GroupState,
    groupInCombat = Compat.GroupInCombat,
    chatLocked = Compat.ChatLocked,
    sendChat = Compat.SendChat,
    print = function(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end,
    showAlert = function(tier, pct) if ns.Alert then ns.Alert.Show(tier, pct) end end,
    hideAlert = function() if ns.Alert then ns.Alert.Hide() end end,
    getUsableDrinks = function() return Compat.ScanDrinks and Compat.ScanDrinks(overrideSet) or {} end,
    getMaxMana = function() return Compat.GetMaxMana and Compat.GetMaxMana() or nil end,
    showDrinkButton = function(drink) return ns.DrinkButton and ns.DrinkButton.Show(drink) or false end,
    hideDrinkButton = function() if ns.DrinkButton then ns.DrinkButton.Hide() end end,
    showStock = function(summary) if ns.Alert and ns.Alert.ShowStock then ns.Alert.ShowStock(summary) end end,
    getManaRegen = function() return Compat.GetManaRegen and Compat.GetManaRegen() or nil end,
    findMage = function() return Compat.FindMage and Compat.FindMage() or nil end,
    sendWhisper = function(msg, name) if Compat.SendWhisper then Compat.SendWhisper(msg, name) end end,
    showMageButton = function(name) if ns.Alert and ns.Alert.ShowMage then ns.Alert.ShowMage(name) end end,
    hideMageButton = function() if ns.Alert and ns.Alert.HideMage then ns.Alert.HideMage() end end,
    showPullAlert = function() if ns.Alert and ns.Alert.ShowPull then ns.Alert.ShowPull() end end,
    printHiddenStats = function(drink, maxMana, regen)
      local msg = Compat.HiddenStatsMessage and Compat.HiddenStatsMessage(drink, maxMana, regen)
      if msg then pcall(print, msg) end
    end,
  }
end

-- (Re)build everything that depends on the active profile.
function Drink:Rebuild()
  ns.RefreshAuraNames()
  ns.RefreshOverrides()
  if ctrl then
    ctrl:SetProfile(self.db.profile)
  else
    ctrl = ns.Controller.New(self.db.profile, env)
  end
  if ns.Alert then ns.Alert.Init(self.db.profile) end
  if ns.DrinkButton then ns.DrinkButton.Init(self.db.profile) end
end

function Drink:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("DrinkDB", ns.defaults, true)
  self.db.RegisterCallback(self, "OnProfileChanged", "Rebuild")
  self.db.RegisterCallback(self, "OnProfileCopied", "Rebuild")
  self.db.RegisterCallback(self, "OnProfileReset", "Rebuild")
  env = buildEnv()
  self:Rebuild()
  if ns.SetupOptions then ns.SetupOptions(self) end
end

function Drink:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("UNIT_AURA")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  if C_RestrictedActions then self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED") end
end

function Drink:ADDON_RESTRICTION_STATE_CHANGED(_, rtype, state)
  debugLog("restriction " .. tostring(rtype) .. " -> " .. tostring(state))
end

function Drink:PLAYER_REGEN_DISABLED()
  debugLog("combat started")
  ctrl:OnCombatStart()
end
function Drink:PLAYER_REGEN_ENABLED()
  debugLog("combat ended")
  debugAfterCombat()
  if ns.DrinkButton then ns.DrinkButton.FlushPending() end
  ctrl:OnCombatEnd()
end

function Drink:UNIT_AURA(_, unit)
  if unit == "player" then ctrl:OnAuraChanged() end
end

function Drink:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
  ctrl:SyncDrinking()
  local _, instanceType = IsInInstance()
  ctrl:OnEnteringWorld(isReloadingUi and true or false, instanceType)
end

function Drink:ZONE_CHANGED_NEW_AREA() ctrl:OnZoneChanged() end
