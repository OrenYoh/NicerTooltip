local addonName, ns = ...

-- Option defaults. ns.db falls back to these until the saved variables are
-- loaded (Options.lua), and for any option missing from them.
ns.defaults = {
  -- Background
  showArt = true,       -- themed art in the top-right corner
  artSize = 80,         -- art height
  bgOpacity = 0.75,
  bgBrightness = 0.8,   -- dims the background to keep the text readable
  -- Separator (not in the options panel)
  showSeparator = true,
  separatorWidth = 0.75, -- share of the tooltip width
  separatorSpacing = 12, -- extra room around it, split above/below
  -- Logo (not in the options panel)
  showLogo = true,
  logoSize = 16,
  -- Name
  showLevel = false,    -- "Name (60)" on units
  -- Size and position
  minWidth = 280,
  followCursor = false, -- default-positioned tooltips follow the cursor
  combatMode = "default", -- in combat: "hide", "default" (position) or "cursor"
}

ns.db = setmetatable({}, { __index = ns.defaults })
