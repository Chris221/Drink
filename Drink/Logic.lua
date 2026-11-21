-- Pure decision helpers. No WoW API calls in this file.
local ADDON, ns = ...

local Logic = {}
ns.Logic = Logic

-- pct >= fyi -> "fyi"; >= heads -> "heads"; >= low -> "low"; else "critical".
function Logic.GetTier(pct, cutoffs)
  if pct == nil then return "unknown" end
  if pct >= cutoffs.fyi then return "fyi" end
  if pct >= cutoffs.heads then return "heads" end
  if pct >= cutoffs.low then return "low" end
  return "critical"
end

function Logic.ManaPercent(cur, max)
  if not max or max <= 0 or not cur then return nil end
  return math.floor(cur / max * 100 + 0.5)
end

function Logic.ParseNames(text)
  local set = {}
  for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    local name = line:match("^%s*(.-)%s*$")
    if name ~= "" then set[name] = true end
  end
  return set
end

function Logic.IsDrinkAura(name, nameSet)
  return name ~= nil and nameSet[name] == true
end

local REQUIRES = {
  INSTANCE_CHAT = function(s) return s.instance end,
  RAID = function(s) return s.raid end,
  PARTY = function(s) return s.party or s.raid end,
}

function Logic.PickChannel(mode, state)
  state = state or {}
  if mode == "AUTO" then
    if state.instance then return "INSTANCE_CHAT" end
    if state.raid then return "RAID" end
    if state.party then return "PARTY" end
    return nil
  end
  local ok = REQUIRES[mode]
  if ok and ok(state) then return mode end
  return nil
end

function Logic.FormatMessage(template, pct)
  -- "|" is WoW's escape character; double it so user text is shown literally.
  local escaped = string.gsub(template, "|", "||")
  return (string.gsub(escaped, "%%m", tostring(pct)))
end

-- Hidden mana (_forever_) -------------------------------------------------------
-- There, current mana is a "secret value": addons can't compare it, only hand it to the game.
-- These build what the game needs to do the comparing for us.

local TIER_ORDER = { "critical", "low", "heads", "fyi" }

-- Each enabled tier's mana range as fractions of max: { tier, from, to } (to = nil: up to 100%).
function Logic.TierBands(cutoffs, tiers, skipAtFull)
  local edges = {
    critical = { 0, cutoffs.low / 100 },
    low = { cutoffs.low / 100, cutoffs.heads / 100 },
    heads = { cutoffs.heads / 100, cutoffs.fyi / 100 },
    fyi = { cutoffs.fyi / 100, skipAtFull and 1 or nil },
  }
  local out = {}
  for _, tier in ipairs(TIER_ORDER) do
    local t = tiers[tier]
    if t and t.enabled then
      out[#out + 1] = { tier = tier, from = edges[tier][1], to = edges[tier][2] }
    end
  end
  return out
end

-- A message template as a string.format pattern with %d where %m was.
function Logic.TemplateFormat(template)
  local escaped = string.gsub(template, "|", "||")
  return (string.gsub(escaped, "%%(m?)", function(m) return m == "m" and "%d" or "%%" end))
end

-- The template with the number part cut off ("Drinking — %m% mana" -> "Drinking").
function Logic.WithoutNumber(template, fallback)
  local head = string.match(template, "^(.-)%%m") or template
  local before
  repeat
    before = head
    head = string.gsub(head, "%s+$", "")
    head = string.gsub(head, "—$", "")
    head = string.gsub(head, "[%-:,%(]$", "")
  until head == before
  if head == "" then head = fallback end
  return (string.gsub(head, "|", "||"))
end
