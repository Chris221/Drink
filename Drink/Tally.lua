-- Dungeon run tally: drinks used, time spent drinking and pulls that cut a drink short, for
-- each dungeon or raid run. Pure bookkeeping over a plain saved table; no WoW API calls here.
--
-- store (saved per character):
--   run  = the run still open: { name, seen, fights, drinks, seconds, pulls }, or nil
--   runs = finished runs by dungeon name, oldest first: { at, fights, drinks, seconds, pulls }
-- `seen` and `at` are real-world clock seconds, so they still mean something after a /reload.
local ADDON, ns = ...

local Tally = {}
ns.Tally = Tally

local KEEP = 5           -- finished runs kept per dungeon
local MIN_FIGHTS = 5     -- fewer fights than this isn't a run worth learning from
local RESUME = 15 * 60   -- back in the same dungeon this soon (corpse run, disconnect): same run

-- Carry on the open run if it is this dungeon and recent; otherwise file it and start a new one.
function Tally.Open(store, name, now)
  local run = store.run
  if run and run.name == name and now - (run.seen or 0) <= RESUME then
    run.seen = now
    return run
  end
  Tally.Close(store)
  run = { name = name, seen = now, fights = 0, drinks = 0, seconds = 0, pulls = 0 }
  store.run = run
  return run
end

-- Finish the open run. Returns the filed run and its dungeon, or nil if there was nothing
-- worth keeping.
function Tally.Close(store)
  local run = store.run
  store.run = nil
  if not run or (run.fights or 0) < MIN_FIGHTS then return nil end
  store.runs = store.runs or {}
  local list = store.runs[run.name] or {}
  store.runs[run.name] = list
  local done = { at = run.seen, fights = run.fights, drinks = run.drinks,
                 seconds = math.floor(run.seconds + 0.5), pulls = run.pulls }
  list[#list + 1] = done
  while #list > KEEP do table.remove(list, 1) end
  return done, run.name
end

-- What the kept runs of a dungeon took: { runs, least, most, last } drinks, or nil if none.
function Tally.Usual(store, name)
  local list = store.runs and store.runs[name]
  if not list or #list == 0 then return nil end
  local least, most = list[1].drinks, list[1].drinks
  for _, r in ipairs(list) do
    least, most = math.min(least, r.drinks), math.max(most, r.drinks)
  end
  return { runs = #list, least = least, most = most, last = list[#list].drinks }
end

-- Forget the finished runs. The run I'm in carries on.
function Tally.Clear(store)
  store.runs = store.runs or {}
  for name in pairs(store.runs) do store.runs[name] = nil end
end

-- Wording ---------------------------------------------------------------------

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function clock(seconds)
  seconds = math.floor(seconds + 0.5)
  if seconds < 60 then return seconds .. "s" end
  return math.floor(seconds / 60) .. "m " .. (seconds % 60) .. "s"
end

local function describe(run)
  if run.drinks == 0 and run.pulls == 0 then return "no drinks used" end
  local s = plural(run.drinks, "drink") .. ", " .. clock(run.seconds) .. " drinking"
  if run.pulls > 0 then
    s = s .. ", pulled mid-drink " .. (run.pulls == 1 and "once" or (run.pulls .. " times"))
  end
  return s
end

function Tally.RunLine(name, run) return name .. ": " .. describe(run) end

function Tally.UsualLine(name, usual)
  if usual.runs == 1 then return name .. ": " .. plural(usual.last, "drink") .. " last run" end
  local range = usual.least == usual.most and plural(usual.most, "drink")
    or (usual.least .. "-" .. usual.most .. " drinks")
  return name .. ": " .. range .. " a run (last " .. usual.runs .. " runs)"
end

-- Everything saved, as chat lines: this run so far, then each dungeon with its runs newest first.
function Tally.List(store)
  local lines = {}
  if store.run then
    lines[#lines + 1] = store.run.name .. " (this run so far): " .. describe(store.run)
  end
  local names = {}
  for name, list in pairs(store.runs or {}) do
    if #list > 0 then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local list = store.runs[name]
    lines[#lines + 1] = Tally.UsualLine(name, Tally.Usual(store, name))
    for i = #list, 1, -1 do lines[#lines + 1] = "   " .. describe(list[i]) end
  end
  return lines
end
