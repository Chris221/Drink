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

## Commands

| Command | |
|---|---|
| `/drink` (or `/drinkalert`) | open options |
| `/drink test fyi` / `heads` / `low` / `critical` | preview an alert tier |
| `/drink test announce` / `report` | print the chat message locally (never sends) |
| `/drink unlock` / `/drink lock` | move the alert |

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
