-- Minimal test runner. Run from the repo root:  lua tests/run.lua
package.path = "tests/?.lua;" .. package.path

local FILES = {
  "test_logic",
  "test_controller",
  "test_compat",
  "test_load",
  "test_options",
  "test_alert",
}

local tests = {}

function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, val in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(val) end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepeq(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepeq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function eq(actual, expected, msg)
  if not deepeq(actual, expected) then
    error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", show(expected), show(actual)), 2)
  end
end

function truthy(v, msg)
  if not v then error((msg or "expected truthy value") .. ", got " .. show(v), 2) end
end

-- Load an addon file the way WoW does: chunk receives (addonName, ns).
function load_addon(ns, path)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 2) end
  chunk("Drink", ns)
  return ns
end

-- Fresh deep copy of a table (used for per-test profiles).
function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local only = arg and arg[1]
for _, f in ipairs(FILES) do
  if not only or only == f then
    local chunk, err = loadfile("tests/" .. f .. ".lua")
    if chunk then
      local ok, cerr = pcall(chunk)
      if not ok then
        tests[#tests + 1] = { name = f .. " (setup)", fn = function() error(cerr) end }
      end
    else
      tests[#tests + 1] = { name = f .. " (load)", fn = function() error(err) end }
    end
  end
end

local passed, failed = 0, 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    passed = passed + 1
    print("PASS " .. t.name)
  else
    failed = failed + 1
    print("FAIL " .. t.name .. ": " .. tostring(err))
  end
end
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
