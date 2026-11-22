# Drink

A World of Warcraft addon for anyone who uses mana: healers, tanks and damage dealers alike. The moment combat ends it tells you to drink, louder the lower your mana is, and it can tell your group when you start drinking.

It goes by your mana, not your role or class, so it needs no setup per character. Characters without mana never see it. Settings are shared by all your characters unless you give one its own profile (Profiles tab).

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
- **Solo:** with no group, both messages print in your own chat window instead (nobody else sees them). Turn this off per message with "When solo, show it just to me".
- On Retail, if Blizzard's chat lockdown is active (boss fights / M+), messages print locally instead of erroring.
- **Which drink?** Below 80% mana after a fight, a clickable button shows the drink that refills you with the least waste. It picks the smallest usable drink that covers what you're missing. It learns the usual time between pulls in the zone, so a long drink you won't finish counts for less. Mage water is preferred (toggle). It only offers drinks in your bags that you can use. Click it to drink. It disappears after 5s, when you start drinking, or when a pull starts.
- **Stock check:** entering a dungeon or raid shows `Drinks: 34 (~21 refills) - you're good` or `- STOCK UP` (under 20 drinks), plus a breakdown in your chat window.

## Extras

- **Bear form, cat form and the like.** When mana isn't what you're fighting with (druid forms, or specs like shadow and elemental on Retail), you're only alerted at Low or Critical, with the drink button and report as usual then. Above that it stays quiet, and the stock check on entering a dungeon is skipped (`/drink stock` still answers). Untick "In bear or cat form, only alert when mana is low" to be alerted as usual.

- **Drink stats, just for you.** Each time you start drinking, your chat shows how long the recommended drink takes to fill you up, counting natural regen: `[Drink] Melon Juice: full in ~18s`, or `2 drinks to fill (~42s)`.
- **"Drinking" once per break.** A second or third drink before the next fight isn't announced to the group again. The stats line still prints.
- **"Ready" when you stand up.** Posts `Ready — 85% mana` once per break, at 80% mana or more, after a drink that was announced. Never while you or anyone in the group is in combat.
- **Ask a mage for water.** When the stock check finds you low, or with no mage water, and a mage is in your group, an "Ask <name> for water" button appears for 10s. Clicking it whispers them (or uses group chat). Nothing is sent unless you click. Never offered when you're a mage yourself.
- **Keybind.** Game Menu → Options → Keybindings → Drink → "Use recommended drink". It drinks the last drink the button offered, even after the button has faded.
- **Low stock mid-run.** One "STOCK UP" warning if you drop below your threshold inside a dungeon or raid.
- **Pulled while drinking.** "PULL - stand up!" if the group goes into combat while you're sitting.

## On WoW Forever

Forever hides your current mana from addons all the time (a "secret value"): an addon can hand
it to the game to display, but can't compare it or put it in a chat message. So there:

- The alert still shows your real % in the right tier style. The game picks the tier; every tier stays up for 4s.
- Alert sounds play only when the game confirms you're low. The addon asks whether you can afford the spell whose cost is nearest your Critical cutoff (20% by default), so it's roughly the critical range and depends on your spells. A spell that takes all your mana (Lay on Hands) is never used for this.
- Your party sees "Drinking" (no number). Your own chat shows the full "Drinking — 57% mana".
- The end-of-fight report, if on, prints to your own chat after every fight.
- The drink button shows after every fight with the smallest drink that refills your whole bar.
- The stock check works as normal.
- "Ready" is sent without the number, and is held back only when the game confirms you're low.
- In bear or cat form the alert still shows at Low or Critical, but the drink button and report need the game to confirm you're low.
- The drink stats line always shows both parts: `[Drink] Melon Juice x1: ~18s to full`. The game works the numbers out; at full mana it reads `x0: ~0s`.
- `/drink debug` logs whether mana is readable and which game restrictions are active.

## Commands

| Command | |
|---|---|
| `/drink` (or `/drinkalert`) | open options |
| `/drink test fyi` / `heads` / `low` / `critical` | preview an alert tier |
| `/drink test announce` / `report` / `ready` | print the chat message locally (never sends) |
| `/drink test drink` | show the drink button for your current mana (clicking it really drinks) |
| `/drink stock` | run the stock check now |
| `/drink debug` | log mana readability and game restrictions to chat (until `/reload`) |
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
