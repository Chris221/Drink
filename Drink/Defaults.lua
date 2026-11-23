-- Saved-variable defaults (AceDB format). Schema is shared by Controller, Alert and Options.
local ADDON, ns = ...

ns.defaults = {
  profile = {
    alert = {
      enabled = true,
      minFightSeconds = 3,
      skipAtFull = true,
      onlyInGroup = false,
      waitForGroup = false,
      waitTimeout = 60,
      locked = true,
      pullWhileDrinking = true, -- alert if the group pulls while I'm sitting
      lowOnlyOffResource = true, -- bear/cat form, shadow...: only alert at Low or Critical
      scale = 1,
      point = { "CENTER", "CENTER", 0, 180 },
    },
    -- pct >= fyi -> fyi; >= heads -> heads; >= low -> low; else critical
    cutoffs = { fyi = 80, heads = 50, low = 20 },
    tiers = {
      fyi      = { enabled = true, duration = 2 },
      heads    = { enabled = true, duration = 3, sound = true },
      low      = { enabled = true, duration = 4, sound = true },
      critical = { enabled = true, duration = 6, sound = true, flash = true },
    },
    announce = {
      enabled = true,
      channel = "AUTO",
      soloLocal = true,
      below = 100,
      template = "Drinking — %m% mana",
      auraNames = "Drink\nFood & Drink\nRefreshment",
    },
    report = {
      enabled = false,
      channel = "AUTO",
      soloLocal = true,
      below = 50,
      template = "Mana: %m%",
    },
    ready = {
      enabled = true,
      channel = "AUTO",
      soloLocal = false,
      atLeast = 80,        -- only say Ready at this mana % or more
      template = "Ready — %m% mana",
    },
    mage = {
      enabled = true,
      channel = "WHISPER", -- or "GROUP"
      template = "Could I get some water please?",
    },
    dedupSeconds = 5,
    recommend = {
      enabled = true,
      below = 80,          -- only recommend below this mana % (100 = always)
      seconds = 5,         -- how long the drink button stays up
      preferConjured = true,
      useDowntime = true,
      overrides = "",      -- "name or itemID = mana[, seconds]" per line
      stats = true,        -- print time-to-full / drinks needed when I start drinking
    },
    -- learn: in a dungeon I've run before, go by what it took in place of the fixed threshold
    stock = { enabled = true, threshold = 20, midRun = true, learn = true },
    -- Dungeon run tally (see Tally.lua); summary = print it when I leave
    tally = { enabled = true, summary = true },
    button = { point = { "CENTER", "CENTER", 0, 110 }, size = 40 },
  },
  -- Per character: the open dungeon run and the finished ones (see Tally.lua).
  char = { runs = {} },
}
