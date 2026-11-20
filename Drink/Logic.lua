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
  return (string.gsub(template, "%%m", tostring(pct)))
end
