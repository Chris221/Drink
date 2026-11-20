# Drink

A World of Warcraft addon for healers. The moment combat ends it tells you to drink, louder the lower your mana is, and it can tell your group when you start drinking.

Loads on `_forever_` (1.60), MoP Classic (5.5) and Retail/Midnight (12.x) from one folder.

## What it does

- **Combat-end alert:** scaled by mana %:

  | Tier | Default | Looks like |
  |------|---------|------------|
  | FYI | 80%+ | small green text, silent |
  | Heads-up | 50–79% | yellow text, soft chime |
  | Low | 20–49% | big orange text, ready-check sound |
  | CRITICAL | under 20% | huge pulsing red text, raid-warning sound, red screen-edge flash |

  It skips fights shorter than 3s and stays quiet at 100% mana or when you're dead. It never fires on characters without mana. Optionally it waits until the whole group is out of combat.
- **"Drinking — 34% mana":** posted to instance, raid or party chat (auto-picked) once each time you start drinking. It also dismisses the alert. Never posts at 100% mana (buff food) or again after a `/reload` mid-drink.
- **End-of-fight mana report:** off by default. Posts `Mana: 42%` when you end a fight below 50%.
- On Retail, if Blizzard's chat lockdown is active (boss fights / M+), messages print locally instead of erroring.
- **Which drink?** Below 80% mana after a fight, a clickable button shows the drink that refills you with the least waste. It picks the smallest usable drink that covers what you're missing. It learns the usual time between pulls in the zone, so a long drink you won't finish counts for less. Mage water is preferred (toggle). It only offers drinks in your bags that you can use. Click it to drink. It disappears after 5s or when a pull starts.
- **Stock check:** entering a dungeon or raid shows `Drinks: 34 (~21 refills) - you're good` or `- STOCK UP` (under 20 drinks), plus a breakdown in your chat window.

## Commands

| Command | |
|---|---|
| `/drink` (or `/drinkalert`) | open options |
| `/drink test fyi` / `heads` / `low` / `critical` | preview an alert tier |
| `/drink test announce` / `report` | print the chat message locally (never sends) |
| `/drink test drink` | show the drink button for your current mana (clicking it really drinks) |
| `/drink stock` | run the stock check now |
| `/drink unlock` / `/drink lock` | move the alert and the drink button. Drag the button's corner to resize it |

The options are also in the game's AddOns settings under **Drink**. Every threshold, tier, sound/flash, message template and drink-buff name is configurable, with per-character profiles.

## Install (dev)

`Drink/` is the addon. `tools/install.ps1` junctions it into the AddOns folder of each client, so edits in the repo are live after `/reload`:

    powershell -ExecutionPolicy Bypass -File tools/install.ps1

The junction points at this checkout, so whichever branch is checked out is what the game loads.

## Tests

    lua tests/run.lua
    pwsh -File tests/test_install.ps1

See `tests/README.md`. The decision logic (`Logic.lua`, `Controller.lua`), API compatibility (`Compat.lua`), options and alert UI paths are covered with stubs. Look and sound still need an in-game check.

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
