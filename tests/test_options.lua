local ns = {}
load_addon(ns, "Drink/Logic.lua")
load_addon(ns, "Drink/Defaults.lua")
load_addon(ns, "Drink/Options.lua")

local function build()
  local profile = deepcopy(ns.defaults.profile)
  local opts = ns.BuildOptions(function() return profile end)
  return opts, profile
end

local function leaves(group, out)
  out = out or {}
  for key, opt in pairs(group.args or {}) do
    if opt.type == "group" then leaves(opt, out)
    else opt._key = key; out[#out + 1] = opt end
  end
  return out
end

local function at(t, path)
  for _, k in ipairs(path) do t = t[k] end
  return t
end

local function shape(t)
  if type(t) ~= "table" then return type(t) end
  local s = {}
  for k, v in pairs(t) do s[k] = shape(v) end
  return s
end

local function valid(opt, v)
  if not opt.validate then return true end
  return opt.validate({}, v) == true
end

local function candidate(opt, cur)
  if opt.type == "toggle" then return not cur end
  if opt.type == "input" then return cur .. "x" end
  if opt.type == "select" then
    local values = type(opt.values) == "function" and opt.values() or opt.values
    for k in pairs(values) do if k ~= cur then return k end end
  end
  if opt.type == "range" then
    local step = opt.step or 1
    for _, v in ipairs({ cur + step, cur - step, opt.min, opt.max }) do
      if v ~= cur and v >= opt.min and v <= opt.max and valid(opt, v) then return v end
    end
  end
end

test("options: every setting round-trips into its profile path", function()
  local opts, profile = build()
  local before = shape(profile)
  local n = 0
  for _, opt in ipairs(leaves(opts)) do
    if opt.type ~= "execute" and opt.type ~= "description" and opt.type ~= "header" then
      truthy(type(opt.arg) == "table", opt._key .. " has no profile path")
      local cur = opt.get({})
      local v = candidate(opt, cur)
      truthy(v ~= nil, "no candidate value for " .. opt._key)
      opt.set({}, v)
      eq(opt.get({}), v, opt._key .. " get after set")
      eq(at(profile, opt.arg), v, opt._key .. " stored at profile path")
      n = n + 1
    end
  end
  truthy(n >= 25, "expected at least 25 settings, got " .. n)
  eq(shape(profile), before, "no new profile keys created")
end)

test("options: cutoffs must stay ordered", function()
  local opts = build()
  local heads
  for _, opt in ipairs(leaves(opts)) do
    if opt.arg and opt.arg[1] == "cutoffs" and opt.arg[2] == "heads" then heads = opt end
  end
  truthy(heads, "heads cutoff option missing")
  truthy(type(heads.validate({}, 85)) == "string", "85 above fyi=80 must be rejected")
  truthy(type(heads.validate({}, 15)) == "string", "15 below low=20 must be rejected")
  eq(heads.validate({}, 60), true)
end)

test("options: channel choices", function()
  local opts = build()
  local found = 0
  for _, opt in ipairs(leaves(opts)) do
    if opt.arg and opt.arg[2] == "channel" and opt.arg[1] ~= "mage" then
      found = found + 1
      local keys = {}
      for k in pairs(opt.values) do keys[#keys + 1] = k end
      table.sort(keys)
      eq(keys, { "AUTO", "INSTANCE_CHAT", "OFF", "PARTY", "RAID" })
    end
  end
  eq(found, 3, "announce, report and ready channel selects")
end)

test("options: test buttons preview each tier", function()
  local opts = build()
  local previewed = {}
  ns.ctrl = function() return { Preview = function(_, k) previewed[#previewed + 1] = k end } end
  for _, opt in ipairs(leaves(opts)) do
    if opt.type == "execute" then opt.func({}) end
  end
  ns.ctrl = nil
  table.sort(previewed)
  eq(previewed, { "announce", "critical", "drink", "fyi", "heads", "low", "ready", "report", "stock" })
end)

test("options: slash commands", function()
  local _, profile = build()
  local calls = {}
  ns.ctrl = function() return { Preview = function(_, k) calls[#calls + 1] = "preview:" .. k; return k ~= "bogus" end } end
  ns.Alert = { SetLocked = function(v) calls[#calls + 1] = "locked:" .. tostring(v) end }
  ns.OpenOptions = function() calls[#calls + 1] = "open" end
  local printed = {}
  local say = function(m) printed[#printed + 1] = m end

  ns.HandleSlash("", say)
  ns.HandleSlash("test low", say)
  ns.HandleSlash("TEST Critical", say)
  ns.HandleSlash("unlock", say)
  ns.HandleSlash("lock", say)
  eq(calls, { "open", "preview:low", "preview:critical", "locked:false", "locked:true" })
  eq(#printed, 0)

  ns.HandleSlash("test bogus", say)
  ns.HandleSlash("dance", say)
  eq(#printed, 2, "usage printed for bad input")
  truthy(printed[1]:find("/drink test", 1, true), "usage mentions /drink test")
  ns.ctrl, ns.Alert, ns.OpenOptions = nil, nil, nil
end)

test("options: per-tier sound toggles exist for heads, low, critical", function()
  local opts = build()
  local found = {}
  for _, opt in ipairs(leaves(opts)) do
    if opt.arg and opt.arg[1] == "tiers" and opt.arg[3] == "sound" then found[#found + 1] = opt.arg[2] end
  end
  table.sort(found)
  eq(found, { "critical", "heads", "low" })
end)

test("options: slash lock/unlock refreshes an open options panel; usage lists unknown", function()
  local notified = 0
  ns.Alert = { SetLocked = function() end }
  ns.NotifyOptionsChanged = function() notified = notified + 1 end
  local printed = {}
  ns.HandleSlash("unlock", function() end)
  ns.HandleSlash("lock", function() end)
  ns.HandleSlash("dance", function(m) printed[#printed + 1] = m end)
  eq(notified, 2)
  truthy(printed[1]:find("unknown", 1, true), "usage mentions test unknown")
  ns.Alert, ns.NotifyOptionsChanged = nil, nil
end)

test("options: /drink stock and /drink test drink", function()
  local calls = {}
  ns.ctrl = function() return { Preview = function(_, k) calls[#calls + 1] = k; return true end } end
  ns.HandleSlash("stock", function() end)
  ns.HandleSlash("test drink", function() end)
  eq(calls, { "stock", "drink" })
  local printed = {}
  ns.HandleSlash("dance", function(m) printed[#printed + 1] = m end)
  truthy(printed[1]:find("drink>", 1, true) and printed[1]:find("/drink stock", 1, true), "usage mentions new commands")
  ns.ctrl = nil
end)

test("options: drinks tab settings exist", function()
  local opts = build()
  local paths = {}
  for _, opt in ipairs(leaves(opts)) do
    if opt.arg then paths[table.concat(opt.arg, ".")] = true end
  end
  for _, p in ipairs({ "recommend.enabled", "recommend.below", "recommend.seconds", "recommend.preferConjured",
      "recommend.useDowntime", "recommend.overrides", "stock.enabled", "stock.threshold", "button.size" }) do
    truthy(paths[p], "missing option " .. p)
  end
end)

test("options: solo-to-me toggles exist for both chat messages", function()
  local paths = {}
  for _, opt in ipairs(leaves(build())) do
    if opt.arg then paths[table.concat(opt.arg, ".")] = true end
  end
  truthy(paths["announce.soloLocal"], "announce.soloLocal")
  truthy(paths["report.soloLocal"], "report.soloLocal")
end)

test("options: /drink debug toggles the mana log", function()
  local toggled = 0
  ns.ToggleDebug = function() toggled = toggled + 1 end
  ns.HandleSlash("debug", function() end)
  eq(toggled, 1)
  ns.ToggleDebug = nil
end)

test("options: extras settings exist", function()
  local paths, lockNames, mageChannel = {}, {}, nil
  for _, opt in ipairs(leaves(build())) do
    if opt.arg then
      local key = table.concat(opt.arg, ".")
      paths[key] = true
      if key == "alert.locked" then lockNames[#lockNames + 1] = opt.name end
      if key == "mage.channel" then mageChannel = opt end
    end
  end
  for _, p in ipairs({ "ready.enabled", "ready.channel", "ready.soloLocal", "ready.atLeast", "ready.template",
      "mage.enabled", "mage.channel", "mage.template", "stock.midRun", "alert.pullWhileDrinking", "recommend.stats",
      "alert.lowOnlyOffResource" }) do
    truthy(paths[p], "missing option " .. p)
  end
  eq(lockNames, { "Lock alert and drink button", "Lock alert and drink button" }, "on the Alert and Drinks tabs")
  local keys = {}
  for k in pairs(mageChannel.values) do keys[#keys + 1] = k end
  table.sort(keys)
  eq(keys, { "GROUP", "WHISPER" })
end)

test("options: /drink test ready, and usage mentions it", function()
  local calls = {}
  ns.ctrl = function() return { Preview = function(_, k) calls[#calls + 1] = k; return k == "ready" end } end
  ns.HandleSlash("test ready", function() end)
  eq(calls, { "ready" })
  local printed = {}
  ns.HandleSlash("dance", function(m) printed[#printed + 1] = m end)
  truthy(printed[1]:find("ready", 1, true), "usage mentions ready")
  ns.ctrl = nil
end)
