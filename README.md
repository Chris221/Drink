# Drink

<img src="https://raw.githubusercontent.com/Chris221/Drink/main/Images/icon.png" alt="Drink icon" width="160">

Out of combat, out of mana, and the tank is already pulling? **Drink** tells you to drink the moment a fight ends, louder the lower your mana is, picks the right drink from your bags, and lets your group know you're sitting down. It's for anyone who uses mana: healers, tanks and damage dealers alike.

It goes by your mana, not your role or class, so there's nothing to set up per character. Characters without mana never see it.

![The CRITICAL alert at 6% mana with the red screen-edge flash, and the drink button offering Refreshing Spring Water](https://raw.githubusercontent.com/Chris221/Drink/main/Images/critical-flash.jpg)

## Features summary
### Version Support
One download for **Retail (Midnight)**, **Mists of Pandaria Classic** and **World of Warcraft: Forever**.

### Know when to drink
The moment combat ends you get an alert scaled to your mana:

![The four alert tiers: Top up? at 92%, Drink soon at 66%, DRINK! at 49% in orange and DRINK! at 6% in big red](https://raw.githubusercontent.com/Chris221/Drink/main/Images/alert-tiers.png)

| Tier | Default | Says | Looks like |
|------|---------|------|------------|
| FYI | 80%+ | Top up? | small green text, silent |
| Heads-up | 50–79% | Drink soon | yellow text, soft chime |
| Low | 20–49% | DRINK! | big orange text, ready-check sound |
| CRITICAL | under 20% | DRINK! | huge pulsing red text, raid-warning sound, red screen-edge flash |

Each tier's wording is yours to change in the options. It skips fights shorter than 3s and stays quiet at 100% mana or when you're dead. Optionally it waits until the whole group is out of combat.

### Tell your group
- **"Drinking — 34% mana"** goes to instance, raid or party chat (picked for you) when you sit down, once per break. Never at full mana (buff food), and never again after a `/reload` mid-drink.
- **"Ready — 85% mana"** when you stand up at 80% or more, so the tank knows to go. Never while anyone is in combat.
- **"PULL - stand up!"** on your screen if the group pulls while you're still sitting.
- Optional end-of-fight mana report, `Mana: 42%`, when you finish a fight below 50%.
- Solo? Both messages print just to you instead.
- On Retail, if Blizzard's chat lockdown is on (boss fights, Mythic+), messages print locally instead of erroring.

What your party sees, from a dungeon run on WoW Forever (where the % stays hidden, so it's just "Drinking" and "Ready"):

![Party chat: Drinking when a party member sat down, and Ready when they stood up](https://raw.githubusercontent.com/Chris221/Drink/main/Images/party-chat.png)

### Which drink?
Below 80% mana after a fight, a button shows the drink that refills you with the least waste: the smallest drink in your bags that covers what you're missing. It learns how long you usually get between pulls in each zone, so a long drink you won't finish counts for less. Mage water comes first (toggle). Click it to drink, or bind a key: **Game Menu → Options → Keybindings → Drink → "Use recommended drink"**.

Each time you sit down, your chat shows how long it'll take to fill up, counting natural regen: `[Drink] Melon Juice: full in ~18s`.

![The drink stats line in chat: Refreshing Spring Water x1, about 8s to full](https://raw.githubusercontent.com/Chris221/Drink/main/Images/drink-stats.png)

### Never run dry
- **Stock check** on entering a dungeon or raid: `Drinks: 34 (~21 refills) - you're good` or `- STOCK UP`, with what's in your bags in chat.
- **It learns your dungeons.** In a dungeon you've run before, it checks against the most a recent run there took you: `Drinks: 8 (~14 needed) - STOCK UP`.
- **Low stock mid-run:** one warning if you drop below your threshold inside.
- **Ask a mage for water:** when you're low and there's a mage in the group, an "Ask <name> for water" button appears. Nothing is sent unless you click it.

![The stock check: Drinks: 3, about 2 refills, STOCK UP, and the chat line In your bags: Refreshing Spring Water x3](https://raw.githubusercontent.com/Chris221/Drink/main/Images/stock-check.png)

Back in a dungeon you've run before, it goes by what that dungeon took you:

![The stock check on a second Stockade run: In your bags: Conjured Purified Water x20, Melon Juice x17, Sweet Nectar x13, then Stormwind Stockade: 9 drinks last run](https://raw.githubusercontent.com/Chris221/Drink/main/Images/stock-learned.png)

### Dungeon run tally
Inside a dungeon or raid, Drink counts the drinks you use, the time you spend drinking and the pulls that cut a drink short. Leaving prints one line:

![The run tally after leaving the Stormwind Stockade: 9 drinks, 1m 57s drinking, pulled mid-drink 3 times](https://raw.githubusercontent.com/Chris221/Drink/main/Images/run-tally.png)

`/drink runs` lists your last 5 runs of each dungeon. Runs are saved per character and never leave your computer.

### Stays out of your way
In bear or cat form (or on Retail specs like shadow and elemental, where mana isn't what you fight with) you only hear from Drink at Low or Critical. Mages are never offered a mage-water button.

### On WoW Forever
Forever hides your exact mana from addons. Drink works around it:
- The alert still shows your real % in the right tier style, and the sound plays when the game confirms you're low.
- Your group sees "Drinking" and "Ready" without the number; your own chat still shows it.
- The drink button, stock check and run tally all work.

### Interface
Type **/drink** (or **/drinkalert**) for the options, also in the game's AddOns settings under **Drink**. Every threshold, tier, alert text, sound, flash, message and drink-buff name can be changed. Settings are shared by all your characters unless you give one its own profile.

![The Tiers tab of the options: cutoff sliders, and per tier an Enabled box, seconds on screen, editable alert text, a Test button and a sound toggle](https://raw.githubusercontent.com/Chris221/Drink/main/Images/options-tiers.png)

Opening the game's **Edit Mode** unlocks the alert and the drink button so you can place them with the rest of your UI.

| Command | |
|---|---|
| `/drink` | open options |
| `/drink test fyi` / `heads` / `low` / `critical` | preview an alert tier |
| `/drink test announce` / `report` / `ready` | print a chat message to yourself (never sent) |
| `/drink test drink` | show the drink button for your current mana |
| `/drink stock` | run the stock check now |
| `/drink runs` | list your recent dungeon runs (`/drink runs clear` forgets them) |
| `/drink unlock` / `/drink lock` | move the alert and the drink button; drag the button's corner to resize it |
| `/drink debug` | log mana readability and game restrictions to chat |

Drink not recognized? Add it under **Options → Drinks → Manual drink values**.

### Bugs and ideas
[Open an issue](https://github.com/Chris221/Drink/issues) on GitHub. The source is at [github.com/Chris221/Drink](https://github.com/Chris221/Drink).

## Install
Use your addon manager, or download `Drink_vX.Y.Z.zip` from [GitHub Releases](https://github.com/Chris221/Drink/releases) and extract it into your client's `Interface\AddOns` folder (`_retail_`, `_classic_` or `_forever_`), so you end up with `Interface\AddOns\Drink\Drink.toc`.

## Changes
### Changes in 1.0.0
- First release, for WoW Forever (1.60), Mists of Pandaria Classic (5.5) and Retail/Midnight (12.x) from one folder
- Combat-end alert scaled by mana %: FYI ("Top up?", small and silent), Heads-up ("Drink soon"), Low and CRITICAL ("DRINK!"), each louder than the last, with a red screen-edge flash at Critical
- "Drinking — 34% mana" posted to instance, raid or party chat once per break; never at full mana (buff food) or after a `/reload` mid-drink
- Optional end-of-fight mana report; when solo, both messages print just to you
- "Which drink?" button after a fight: the smallest drink in your bags that refills you, learning the usual time between pulls in the zone; mage water preferred; click it or use the keybind to drink
- Stock check on entering a dungeon or raid, a mid-run "STOCK UP" warning, and an "Ask <mage> for water" button when you're low
- Dungeon run tally: drinks, drinking time and pulls that cut a drink short per run, `/drink runs` to list them, and a stock check that learns from past runs
- Drink stats line (time to full, counting regen), "Ready — 85% mana" when you stand up, and "PULL - stand up!" if the group pulls while you're sitting
- Quiet in bear and cat form (and on Retail specs that don't fight with mana) unless mana is Low or Critical; no mage-water button for mages
- Works with WoW Forever's hidden mana: the alert still shows your real %, and the game decides when you're low
- Edit Mode unlocks the alert and drink button for placing; per-character profiles; every threshold, alert text, sound and message is configurable

*Working on Drink? See [CONTRIBUTING.md](https://github.com/Chris221/Drink/blob/main/CONTRIBUTING.md).*
