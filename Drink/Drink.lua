-- Ace3 glue: wires game events and the real env into the Controller.
local ADDON, ns = ...
local Compat = ns.Compat

local Drink = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = Drink

local ctrl, env, nameSet = nil, nil, {}

function ns.ctrl() return ctrl end

function ns.RefreshAuraNames()
  nameSet = ns.Logic.ParseNames(Drink.db.profile.announce.auraNames)
end

local function buildEnv()
  return {
    now = function() return GetTime() end,
    after = function(delay, fn) C_Timer.After(delay, fn) end,
    getManaPct = Compat.GetManaPercent,
    hasMana = Compat.HasMana,
    isDead = function() return UnitIsDeadOrGhost("player") and true or false end,
    isDrinking = function() return Compat.IsDrinking(nameSet) end,
    groupState = Compat.GroupState,
    groupInCombat = Compat.GroupInCombat,
    chatLocked = Compat.ChatLocked,
    sendChat = Compat.SendChat,
    print = function(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end,
    showAlert = function(tier, pct) if ns.Alert then ns.Alert.Show(tier, pct) end end,
    hideAlert = function() if ns.Alert then ns.Alert.Hide() end end,
  }
end

-- (Re)build everything that depends on the active profile.
function Drink:Rebuild()
  ns.RefreshAuraNames()
  ctrl = ns.Controller.New(self.db.profile, env)
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
end

function Drink:PLAYER_REGEN_DISABLED() ctrl:OnCombatStart() end
function Drink:PLAYER_REGEN_ENABLED() ctrl:OnCombatEnd() end

function Drink:UNIT_AURA(_, unit)
  if unit == "player" then ctrl:OnAuraChanged() end
end
