-- Pure drink logic: tooltip parsing, picking the least-wasteful drink, downtime
-- tracking between pulls, and stock summaries. No WoW API calls in this file.
local ADDON, ns = ...

local Drinks = {}
ns.Drinks = Drinks

local MAX_GAP = 120      -- seconds; longer gaps (AFK, wipes) don't count as pull downtime
local MIN_GAP = 5        -- seconds; shorter gaps are chain pulls, not a chance to drink
local KEEP_GAPS = 5
local MIN_GAPS = 3
local DEFAULT_SECONDS = 30

local function num(s)
  return tonumber((string.gsub(s, "[,%.]", "")))
end

local PATTERNS = {
  { "Restores ([%d,%.]+) health and ([%d,%.]+) mana over (%d+) sec", function(_, m, s) return { mana = num(m), seconds = tonumber(s) } end },
  { "Restores ([%d,%.]+) mana over (%d+) sec", function(m, s) return { mana = num(m), seconds = tonumber(s) } end },
  { "Restores (%d+)%% of your mana per second for (%d+) sec", function(p, s) return { pct = tonumber(p) * tonumber(s), seconds = tonumber(s) } end },
  { "Restores (%d+)%% of your mana over (%d+) sec", function(p, s) return { pct = tonumber(p), seconds = tonumber(s) } end },
  { "Restores (%d+)%% health and mana over (%d+) sec", function(p, s) return { pct = tonumber(p), seconds = tonumber(s) } end },
}

-- Every drink (and food & drink) says "Must remain seated"; channeled mana potions and gems don't.
local function seated(lines)
  for _, line in ipairs(lines) do
    if type(line) == "string" and string.find(string.lower(line), "remain seated", 1, true) then return true end
  end
  return false
end

-- lines: tooltip text lines. Returns {mana=, seconds=} or {pct=, seconds=}, or nil if not a drink.
function Drinks.ParseTooltip(lines)
  lines = lines or {}
  if not seated(lines) then return nil end
  for _, line in ipairs(lines) do
    if type(line) == "string" then
      for _, p in ipairs(PATTERNS) do
        local a, b, c = string.match(line, p[1])
        if a then
          local parsed = p[2](a, b, c)
          if parsed and (parsed.mana or parsed.pct) and parsed.seconds and parsed.seconds > 0 then
            return parsed
          end
        end
      end
    end
  end
  return nil
end

function Drinks.Resolve(parsed, maxMana)
  if parsed.pct then
    return math.floor((maxMana or 0) * math.min(parsed.pct, 100) / 100), parsed.seconds
  end
  return parsed.mana, parsed.seconds
end

function Drinks.IsConjured(name, lines)
  if type(name) == "string" and string.find(name, "^Conjured") then return true end
  for _, line in ipairs(lines or {}) do
    if line == "Conjured Item" then return true end
  end
  return false
end

-- "name or itemID = mana[, seconds]" per line. Keys: lowercase name or id string.
-- Mana may use thousands commas ("1,200,000"). A comma followed by a space, or by a group that
-- isn't exactly 3 digits, separates the seconds ("4200, 27", "4200,27", "1,200,000, 20").
local function parseValue(v)
  local mana, secs = v, nil
  local head, sep, tail = string.match(v, "^(.*),(%s*)(%d+)$")
  if head and (sep ~= "" or #tail ~= 3) then mana, secs = head, tail end
  mana = string.match(mana, "^%s*(%d[%d,]*)%s*$")
  if not mana then return nil end
  return { mana = tonumber((string.gsub(mana, ",", ""))), seconds = tonumber(secs) or DEFAULT_SECONDS }
end

function Drinks.ParseOverrides(text)
  local out = {}
  for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    local key, value = string.match(line, "^%s*(.-)%s*=%s*(.-)%s*$")
    local parsed = key and key ~= "" and parseValue(value)
    if parsed then out[string.lower(key)] = parsed end
  end
  return out
end

function Drinks.Effective(drink, downtime)
  if not downtime then return drink.mana end
  return drink.mana * math.min(1, downtime / drink.seconds)
end

-- Is a better than b?  covering: smaller effective wins; otherwise larger effective wins.
-- Ties: smaller total mana, then conjured.
local function better(a, b, covering)
  if a.eff ~= b.eff then
    if covering then return a.eff < b.eff end
    return a.eff > b.eff
  end
  if a.d.mana ~= b.d.mana then return a.d.mana < b.d.mana end
  return a.d.conjured and not b.d.conjured
end

function Drinks.Pick(drinks, deficit, opts)
  opts = opts or {}
  if not deficit or deficit <= 0 or not drinks or #drinks == 0 then return nil end

  local pool = drinks
  if opts.preferConjured then
    local conj = {}
    for _, d in ipairs(drinks) do if d.conjured then conj[#conj + 1] = d end end
    if #conj > 0 then pool = conj end
  end

  local bestCover, bestAny
  for _, d in ipairs(pool) do
    local c = { d = d, eff = Drinks.Effective(d, opts.downtime) }
    if c.eff >= deficit then
      if not bestCover or better(c, bestCover, true) then bestCover = c end
    end
    if not bestAny or better(c, bestAny, false) then bestAny = c end
  end
  return (bestCover or bestAny).d
end

-- Downtime tracker ----------------------------------------------------------

local Downtime = {}
Downtime.__index = Downtime

function Drinks.NewDowntime()
  return setmetatable({ gaps = {}, lastEnd = nil }, Downtime)
end

function Downtime:RecordEnd(t) self.lastEnd = t end

function Downtime:RecordStart(t)
  if not self.lastEnd then return end
  local gap = t - self.lastEnd
  self.lastEnd = nil
  if gap < MIN_GAP or gap > MAX_GAP then return end
  self.gaps[#self.gaps + 1] = gap
  while #self.gaps > KEEP_GAPS do table.remove(self.gaps, 1) end
end

function Downtime:Reset()
  self.gaps = {}
  self.lastEnd = nil
end

function Downtime:Count() return #self.gaps end

function Downtime:Estimate()
  local n = #self.gaps
  if n < MIN_GAPS then return nil end
  local s = {}
  for i, g in ipairs(self.gaps) do s[i] = g end
  table.sort(s)
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

-- Stock -------------------------------------------------------------------

function Drinks.StockSummary(drinks, maxMana, threshold)
  local total, mana = 0, 0
  local rows = {}
  for _, d in ipairs(drinks or {}) do
    total = total + d.count
    mana = mana + math.min(d.mana, maxMana) * d.count
    rows[#rows + 1] = d
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  local parts = {}
  for i, d in ipairs(rows) do parts[i] = d.name .. " x" .. d.count end
  return {
    total = total,
    refills = maxMana and maxMana > 0 and math.floor(mana / maxMana) or 0,
    low = total < threshold,
    breakdown = table.concat(parts, ", "),
  }
end
