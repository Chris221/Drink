# Tests

Desktop Lua 5.4 runs the engine-free parts of the addon (`Logic`, `Controller`, `Compat` with stubbed globals, options table).

Install once: `winget install --id DEVCOM.Lua -e`
(installs to `%LOCALAPPDATA%\Programs\Lua\bin`; open a new shell so PATH picks it up)

Run from the repo root:

    lua tests/run.lua              # whole suite
    lua tests/run.lua test_logic   # one file

Test files are listed explicitly in `tests/run.lua` (`FILES`). Addon code must stay valid Lua 5.1 (WoW's dialect) even though tests run on 5.4.
