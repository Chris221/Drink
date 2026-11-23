# Working on Drink

`Drink/` is the addon. Everything else in the repo is tooling, tests and docs.

## Install (dev)

`tools/install.ps1` junctions `Drink/` into the AddOns folder of each client, so edits in the repo are live after `/reload`:

    powershell -ExecutionPolicy Bypass -File tools/install.ps1

The junction points at this checkout, so whichever branch is checked out is what the game loads.

## Tests

    lua tests/run.lua
    pwsh -File tests/test_install.ps1

See `tests/README.md`. The decision logic (`Logic.lua`, `Controller.lua`), API compatibility (`Compat.lua`), options and alert UI paths are covered with stubs. Look and sound still need an in-game check. The same Lua suite runs on every push and pull request (`.github/workflows/tests.yml`).

## Build a release

    npm install
    npm run build

This zips `Drink/` into `build/Drink_v<version>.zip` (the version comes from `Drink/Drink.toc`) and writes `build/release.json` for addon managers. Only the addon folder goes in the zip; tests, docs and tools stay out. `build/` is gitignored: attach both files to the GitHub release.

    gh release create v1.0.0 build/Drink_v1.0.0.zip build/release.json

Before releasing, bump `## Version:` in `Drink/Drink.toc` and `package.json`, and add a section to both `CHANGELOG.md` and the **Changes** list in `README.md` (the README doubles as the CurseForge description).

A daily GitHub Action (`.github/workflows/update-interface.yml`) opens a pull request when Blizzard's live or PTR versions move past the `## Interface:` line. Test in-game before merging it into a release.

## In-game checklist (per client)

1. `/reload`. No Lua errors in BugSack.
2. `/drink` opens the panel. `/drink test fyi`, `heads`, `low` and `critical` each look and sound right.
3. `/drink unlock`, drag, `/drink lock`, `/reload`. The position is kept.
4. `/drink test announce` prints only in your own chat window.
5. In a party: fight a mob and drop combat to get the tier alert. Drink, and the party sees `Drinking — X% mana` once.
6. Druid: check the mana % in cat/bear form.
7. Eat buff food or a feast at full mana. Nothing should post.
8. Check that `/drink` opens the options rather than doing the drink emote. If it does the emote, use `/drinkalert`.
9. Low mana after a fight: the drink button shows a sensible drink. Click it and you drink, and the party sees the announcement.
10. Pull again within 5s of the button appearing: it disappears and doesn't come back after the fight.
11. `/drink unlock`: drag and resize the button, `/drink lock`, `/reload`. Position and size are kept.
12. Enter a dungeon: the stock line appears about 3s after the loading screen. `/reload` inside: it doesn't repeat.
13. If a drink isn't recognized, add it under Options, Drinks, Manual drink values.
