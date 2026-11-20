-- Options panel (AceConfig) and /drink slash commands.
local ADDON, ns = ...

local CHANNELS = {
  AUTO = "Auto (instance > raid > party)",
  INSTANCE_CHAT = "Instance",
  RAID = "Raid",
  PARTY = "Party",
  OFF = "Off",
}

local TIER_LABEL = { fyi = "FYI", heads = "Heads-up", low = "Low", critical = "CRITICAL" }

local function preview(kind)
  local ctrl = ns.ctrl and ns.ctrl()
  if ctrl then return ctrl:Preview(kind) end
end

function ns.BuildOptions(getProfile)
  local order = 0
  local function nextOrder() order = order + 1; return order end

  local function read(path)
    local t = getProfile()
    for _, k in ipairs(path) do t = t[k] end
    return t
  end

  local function write(path, v)
    local t = getProfile()
    for i = 1, #path - 1 do t = t[path[i]] end
    t[path[#path]] = v
  end

  -- Build a leaf bound to a profile path. `after` runs once the value is stored.
  local function opt(kind, path, name, extra, after)
    local o = {
      type = kind, name = name, arg = path, order = nextOrder(),
      get = function() return read(path) end,
      set = function(_, v) write(path, v); if after then after(v) end end,
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
  end

  local function relayout() if ns.Alert and ns.Alert.ApplyLayout then ns.Alert.ApplyLayout() end end

  local function cutoff(key, name)
    return opt("range", { "cutoffs", key }, name, {
      min = 1, max = 99, step = 1,
      desc = "Mana % at or above which this tier applies.",
      validate = function(_, v)
        local c = getProfile().cutoffs
        local fyi, heads, low = c.fyi, c.heads, c.low
        if key == "fyi" then fyi = v elseif key == "heads" then heads = v else low = v end
        if fyi > heads and heads > low then return true end
        return "Cutoffs must stay in order: FYI > Heads-up > Low."
      end,
    })
  end

  local function tierGroup(key)
    local g = {
      type = "group", inline = true, name = TIER_LABEL[key], order = nextOrder(),
      args = {
        enabled = opt("toggle", { "tiers", key, "enabled" }, "Enabled"),
        duration = opt("range", { "tiers", key, "duration" }, "Seconds on screen", { min = 1, max = 15, step = 1 }),
        test = { type = "execute", name = "Test", order = nextOrder(), func = function() preview(key) end },
      },
    }
    if key ~= "fyi" then
      g.args.sound = opt("toggle", { "tiers", key, "sound" }, "Play sound")
    end
    if key == "critical" then
      g.args.flash = opt("toggle", { "tiers", "critical", "flash" }, "Red screen-edge flash")
    end
    return g
  end

  local function chatGroup(key, name, extra)
    local g = {
      type = "group", inline = true, name = name, order = nextOrder(),
      args = {
        enabled = opt("toggle", { key, "enabled" }, "Enabled"),
        channel = opt("select", { key, "channel" }, "Channel", { values = CHANNELS }),
        below = opt("range", { key, "below" }, "Only when mana is below %",
          { min = 1, max = 100, step = 1, desc = "100 = always." }),
        template = opt("input", { key, "template" }, "Message", { width = "full", desc = "%m is replaced with your mana %." }),
        test = { type = "execute", name = "Preview (prints locally)", order = nextOrder(),
                 func = function() preview(key) end },
      },
    }
    for k, v in pairs(extra or {}) do g.args[k] = v end
    return g
  end

  return {
    type = "group", name = "Drink", childGroups = "tab",
    args = {
      alert = {
        type = "group", name = "Alert", order = nextOrder(),
        args = {
          enabled = opt("toggle", { "alert", "enabled" }, "Show alert when combat ends", { width = "full" }),
          minFightSeconds = opt("range", { "alert", "minFightSeconds" }, "Ignore fights shorter than (sec)",
            { min = 0, max = 30, step = 1 }),
          skipAtFull = opt("toggle", { "alert", "skipAtFull" }, "No alert at 100% mana"),
          onlyInGroup = opt("toggle", { "alert", "onlyInGroup" }, "Only when in a group"),
          waitForGroup = opt("toggle", { "alert", "waitForGroup" }, "Wait until the whole group is out of combat",
            { width = "full" }),
          waitTimeout = opt("range", { "alert", "waitTimeout" }, "Give up waiting after (sec)",
            { min = 10, max = 180, step = 5 }),
          locked = opt("toggle", { "alert", "locked" }, "Lock alert position", nil,
            function(v) if ns.Alert and ns.Alert.SetLocked then ns.Alert.SetLocked(v) end end),
          scale = opt("range", { "alert", "scale" }, "Alert scale", { min = 0.5, max = 2, step = 0.05 }, relayout),
        },
      },
      tiers = {
        type = "group", name = "Tiers", order = nextOrder(),
        args = {
          fyiCut = cutoff("fyi", "FYI at or above %"),
          headsCut = cutoff("heads", "Heads-up at or above %"),
          lowCut = cutoff("low", "Low at or above % (below = CRITICAL)"),
          fyi = tierGroup("fyi"),
          heads = tierGroup("heads"),
          low = tierGroup("low"),
          critical = tierGroup("critical"),
        },
      },
      chat = {
        type = "group", name = "Announcements", order = nextOrder(),
        args = {
          announce = chatGroup("announce", "When I start drinking", {
            auraNames = opt("input", { "announce", "auraNames" }, "Drink buff names (one per line)",
              { multiline = 4, width = "full" },
              function() if ns.RefreshAuraNames then ns.RefreshAuraNames() end end),
          }),
          report = chatGroup("report", "End-of-fight mana report"),
          dedupSeconds = opt("range", { "dedupSeconds" }, "Min seconds between posts",
            { min = 0, max = 30, step = 1, desc = "Prevents the report and the drinking message double-posting." }),
        },
      },
      drinks = {
        type = "group", name = "Drinks", order = nextOrder(),
        args = {
          recommend = {
            type = "group", inline = true, name = "Drink recommendation", order = nextOrder(),
            args = {
              enabled = opt("toggle", { "recommend", "enabled" }, "Recommend a drink after combat", { width = "full" }),
              below = opt("range", { "recommend", "below" }, "Only when mana is below %",
                { min = 1, max = 100, step = 1, desc = "100 = always." }),
              seconds = opt("range", { "recommend", "seconds" }, "Button visible for (sec)", { min = 2, max = 15, step = 1 }),
              preferConjured = opt("toggle", { "recommend", "preferConjured" }, "Prefer mage water", { width = "full" }),
              useDowntime = opt("toggle", { "recommend", "useDowntime" }, "Factor in time between pulls"),
              downtimeInfo = {
                type = "description", order = nextOrder(), width = "full",
                name = function()
                  local c = ns.ctrl and ns.ctrl()
                  local info = c and c:DowntimeInfo()
                  if not info or not info.estimate then
                    return string.format("Time between pulls: learning (%d of 3 pulls seen in this zone)", info and info.count or 0)
                  end
                  return string.format("Time between pulls: ~%ds (last %d pulls)", math.floor(info.estimate + 0.5), info.count)
                end,
              },
              size = opt("range", { "button", "size" }, "Button size", { min = 24, max = 96, step = 1 },
                function() if ns.DrinkButton then ns.DrinkButton.ApplyLayout() end end),
              overrides = opt("input", { "recommend", "overrides" }, "Manual drink values (name or item ID = mana[, seconds])",
                { multiline = 4, width = "full",
                  desc = "For drinks the tooltip reader doesn't recognize, or to correct one. Example: Morning Glory Dew = 2934, 27" },
                function() if ns.RefreshOverrides then ns.RefreshOverrides() end end),
              test = { type = "execute", name = "Test recommendation", order = nextOrder(),
                       func = function() preview("drink") end },
            },
          },
          stock = {
            type = "group", inline = true, name = "Stock check when entering a dungeon or raid", order = nextOrder(),
            args = {
              enabled = opt("toggle", { "stock", "enabled" }, "Enabled"),
              threshold = opt("range", { "stock", "threshold" }, "Warn when fewer than N drinks", { min = 1, max = 200, step = 1 }),
              test = { type = "execute", name = "Check stock now", order = nextOrder(),
                       func = function() preview("stock") end },
            },
          },
        },
      },
    },
  }
end

local USAGE = "|cff33ccffDrink|r: /drink (options), /drink test <fyi, heads, low, critical, unknown, announce, report, drink>, /drink stock, /drink lock, /drink unlock"

-- Returns nothing; `say` prints user-facing messages.
function ns.HandleSlash(input, say)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if cmd == "" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif cmd == "test" then
    local ctrl = ns.ctrl and ns.ctrl()
    if not (ctrl and ctrl:Preview(arg)) then say(USAGE) end
  elseif cmd == "stock" then
    local ctrl = ns.ctrl and ns.ctrl()
    if ctrl then ctrl:Preview("stock") end
  elseif cmd == "lock" or cmd == "unlock" then
    if ns.Alert then ns.Alert.SetLocked(cmd == "lock") end
    if ns.NotifyOptionsChanged then ns.NotifyOptionsChanged() end
  else
    say(USAGE)
  end
end

-- Called from Drink.lua OnInitialize (in game only).
function ns.SetupOptions(addon)
  local options = ns.BuildOptions(function() return addon.db.profile end)
  options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(addon.db)
  options.args.profiles.order = 100
  LibStub("AceConfig-3.0"):RegisterOptionsTable(ADDON, options)
  local dialog = LibStub("AceConfigDialog-3.0")
  dialog:AddToBlizOptions(ADDON, "Drink")
  dialog:SetDefaultSize(ADDON, 640, 560)
  ns.OpenOptions = function() dialog:Open(ADDON) end
  ns.NotifyOptionsChanged = function() LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON) end
  local function onSlash(input)
    ns.HandleSlash(input, function(m) DEFAULT_CHAT_FRAME:AddMessage(m) end)
  end
  addon:RegisterChatCommand("drink", onSlash)
  addon:RegisterChatCommand("drinkalert", onSlash) -- fallback in case a client resolves the /drink emote first
end
