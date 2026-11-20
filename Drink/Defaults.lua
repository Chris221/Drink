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
      scale = 1,
      point = { "CENTER", "CENTER", 0, 180 },
    },
    -- pct >= fyi -> fyi; >= heads -> heads; >= low -> low; else critical
    cutoffs = { fyi = 80, heads = 50, low = 20 },
    tiers = {
      fyi      = { enabled = true, duration = 2 },
      heads    = { enabled = true, duration = 3 },
      low      = { enabled = true, duration = 4 },
      critical = { enabled = true, duration = 6, flash = true },
    },
    announce = {
      enabled = true,
      channel = "AUTO",
      below = 100,
      template = "Drinking — %m% mana",
      auraNames = "Drink\nFood & Drink\nRefreshment",
    },
    report = {
      enabled = false,
      channel = "AUTO",
      below = 50,
      template = "Mana: %m%",
    },
    dedupSeconds = 5,
  },
}
