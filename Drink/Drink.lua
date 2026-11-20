-- Ace3 glue: wires game events and the real env into the Controller.
local ADDON, ns = ...
local Compat = ns.Compat

local Drink = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = Drink

local ctrl, env, nameSet, overrideSet = nil, nil, {}, {}

function ns.ctrl() return ctrl end

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
end

function Drink:PLAYER_REGEN_DISABLED() ctrl:OnCombatStart() end
function Drink:PLAYER_REGEN_ENABLED() ctrl:OnCombatEnd() end

function Drink:UNIT_AURA(_, unit)
  if unit == "player" then ctrl:OnAuraChanged() end
end

function Drink:PLAYER_ENTERING_WORLD() ctrl:SyncDrinking() end
