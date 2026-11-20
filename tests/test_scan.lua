-- Bag scan + tooltip reading (Compat.ScanDrinks) with stubbed WoW globals.
local NAMES = { "Enum", "UnitPower", "UnitPowerMax", "issecretvalue",
  "C_Container", "GetContainerNumSlots", "GetContainerItemID", "GetContainerItemInfo", "C_Item", "GetItemInfo",
  "C_TooltipInfo", "CreateFrame", "WorldFrame", "UnitLevel", "IsUsableItem", "GetItemCooldown",
  "DrinkScanTooltipTextLeft1", "DrinkScanTooltipTextLeft2", "DrinkScanTooltipTextLeft3" }

-- A world: items by id = { name, minLevel, lines = {...}, usable = bool, cd = {start, dur} }
-- bags[bag] = { [slot] = { id, count } }
local ITEMS = {
  [1] = { name = "Morning Glory Dew", minLevel = 45, lines = { "Morning Glory Dew", "Use: Restores 2934 mana over 27 sec." } },
  [2] = { name = "Conjured Sparkling Water", minLevel = 45, lines = { "Conjured Sparkling Water", "Conjured Item", "Use: Restores 4200 mana over 30 sec." } },
  [3] = { name = "Major Mana Potion", minLevel = 49, lines = { "Major Mana Potion", "Use: Restores 1350 to 2250 mana." } },
  [4] = { name = "Star's Tears", minLevel = 65, lines = { "Star's Tears", "Use: Restores 7200 mana over 30 sec." } },
  [5] = { name = "Cooldown Water", minLevel = 1, lines = { "Use: Restores 100 mana over 30 sec." }, cd = { 10, 30 } },
  [6] = { name = "Retail Water", minLevel = 1, lines = { "Use: Restores 7% of your mana per second for 20 sec" } },
  [7] = { name = "Weird Juice", minLevel = 1, lines = { "Weird Juice", "Use: Something unparseable." } },
  [8] = { name = "Unusable Water", minLevel = 1, lines = { "Use: Restores 500 mana over 30 sec." }, usable = false },
}
local BAGS = {
  [0] = { [1] = { 1, 20 }, [2] = { 3, 5 }, [3] = { 1, 4 } },
  [1] = { [1] = { 2, 14 }, [4] = { 4, 10 } },
  [2] = { [1] = { 5, 3 }, [2] = { 6, 2 }, [3] = { 7, 1 }, [4] = { 8, 6 } },
}

local function world(opts)
  opts = opts or {}
  local tipReads = 0
  local g = {
    UnitPower = function() return 2000 end,
    UnitPowerMax = function() return opts.max or 10000 end,
    UnitLevel = function() return 60 end,
    IsUsableItem = function(id) return ITEMS[id].usable ~= false end,
    GetItemCooldown = function(id) local c = ITEMS[id].cd; if c then return c[1], c[2], 1 end return 0, 0, 1 end,
    GetItemInfo = function(id) local it = ITEMS[id]; if it then return it.name, "link", 1, 1, it.minLevel end end,
  }
  local function slots(bag) local n = 0; for s in pairs(BAGS[bag] or {}) do if s > n then n = s end end; return n end
  if opts.legacy then
    g.GetContainerNumSlots = slots
    g.GetContainerItemID = function(bag, slot) local e = BAGS[bag] and BAGS[bag][slot]; return e and e[1] end
    g.GetContainerItemInfo = function(bag, slot) local e = BAGS[bag] and BAGS[bag][slot]; if e then return 100 + e[1], e[2] end end
    -- legacy tooltip scanner
    local tip = { lines = {} }
    function tip:SetOwner() end
    function tip:ClearLines() self.lines = {} end
    function tip:SetItemByID(id)
      tipReads = tipReads + 1
      self.lines = ITEMS[id].lines
      for i = 1, 3 do _G["DrinkScanTooltipTextLeft" .. i] = { GetText = function() return self.lines[i] end } end
    end
    function tip:NumLines() return #self.lines end
    g.CreateFrame = function(kind, name) assert(kind == "GameTooltip" and name == "DrinkScanTooltip"); return tip end
    g.WorldFrame = {}
  else
    g.C_Container = {
      GetContainerNumSlots = slots,
      GetContainerItemInfo = function(bag, slot)
        local e = BAGS[bag] and BAGS[bag][slot]
        if e then return { itemID = e[1], stackCount = e[2], iconFileID = 100 + e[1] } end
      end,
      GetItemCooldown = g.GetItemCooldown,
    }
    g.GetItemCooldown = nil
    g.C_TooltipInfo = { GetItemByID = function(id)
      tipReads = tipReads + 1
      local lines = {}
      for i, t in ipairs(ITEMS[id].lines) do lines[i] = { leftText = t } end
      return { lines = lines }
    end }
  end
  return g, function() return tipReads end
end

local function with_world(g, fn)
  local saved = {}
  for _, n in ipairs(NAMES) do saved[n] = _G[n]; _G[n] = g[n] end
  local ns = {}
  local ok, err = pcall(function()
    load_addon(ns, "Drink/Logic.lua")
    load_addon(ns, "Drink/Drinks.lua")
    load_addon(ns, "Drink/Compat.lua")
    fn(ns.Compat, ns)
  end)
  for _, n in ipairs(NAMES) do _G[n] = saved[n] end
  if not ok then error(err, 0) end
end

local function byName(list)
  local m = {}
  for _, d in ipairs(list) do m[d.name] = d end
  return m
end

local EXPECTED = {
  ["Morning Glory Dew"] = { itemID = 1, name = "Morning Glory Dew", icon = 101, count = 24, mana = 2934, seconds = 27, conjured = false },
  ["Conjured Sparkling Water"] = { itemID = 2, name = "Conjured Sparkling Water", icon = 102, count = 14, mana = 4200, seconds = 30, conjured = true },
  ["Retail Water"] = { itemID = 6, name = "Retail Water", icon = 106, count = 2, mana = 10000, seconds = 20, conjured = false },
}

test("scan: modern API finds usable drinks only", function()
  with_world(world(), function(C)
    eq(byName(C.ScanDrinks({})), EXPECTED)
  end)
end)

test("scan: legacy bag + tooltip API gives the same result", function()
  with_world(world({ legacy = true }), function(C)
    eq(byName(C.ScanDrinks({})), EXPECTED)
  end)
end)

test("scan: percent drinks resolve against current max mana", function()
  with_world(world({ max = 1000 }), function(C)
    eq(byName(C.ScanDrinks({}))["Retail Water"].mana, 1000)
  end)
end)

test("scan: overrides win and can add unparseable items", function()
  with_world(world(), function(C, ns)
    local o = ns.Drinks.ParseOverrides("morning glory dew = 3000\n7 = 900, 18")
    local m = byName(C.ScanDrinks(o))
    eq(m["Morning Glory Dew"].mana, 3000)
    eq(m["Morning Glory Dew"].seconds, 30)
    eq(m["Weird Juice"].mana, 900)
    eq(m["Weird Juice"].seconds, 18)
  end)
end)

test("scan: tooltips are read once per item across scans", function()
  local g, reads = world()
  with_world(g, function(C)
    C.ScanDrinks({})
    local first = reads()
    C.ScanDrinks({})
    eq(reads(), first)
  end)
end)

test("scan: max mana helper", function()
  with_world(world({ max = 1234 }), function(C) eq(C.GetMaxMana(), 1234) end)
  with_world(world({ max = 0 }), function(C) eq(C.GetMaxMana(), nil) end)
end)

test("scan: an item whose tooltip hasn't loaded yet is retried next scan", function()
  local g = world()
  local loaded = false
  local real = g.C_TooltipInfo.GetItemByID
  g.C_TooltipInfo.GetItemByID = function(id)
    if id == 1 and not loaded then return { lines = { { leftText = "Morning Glory Dew" } } } end
    return real(id)
  end
  with_world(g, function(C)
    eq(byName(C.ScanDrinks({}))["Morning Glory Dew"], nil)
    loaded = true
    eq(byName(C.ScanDrinks({}))["Morning Glory Dew"].mana, 2934)
  end)
end)
