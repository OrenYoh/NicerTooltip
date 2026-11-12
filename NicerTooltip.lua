local addonName, ns = ...
local Media = ns.Media

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"
-- Blizzard's own, kept before other addons hook it at login: Animated Default
-- Portraits turns every SetPortraitTexture texture into a model frame, which
-- the medallion can't hide (it stayed on later tooltips).
local SetPortraitTexture = SetPortraitTexture

-- Layout (in UI units). The frame art is drawn slightly outside the tooltip
-- so its ornate corners don't sit on top of the first line of text.
local OUTSET = 5            -- how far the frame sticks out of the tooltip
local CORNER = 32           -- on-screen size of a frame corner piece
local BG_INSET = 1          -- background inset from the tooltip edge
local TOOLTIP_PADDING = 10  -- Blizzard's padding around the tooltip text
local SLOT_HEIGHT = 20      -- healthbar slot height
local SLOT_CAP = 16         -- healthbar slot end cap width
-- Everything else comes from the options (Config.lua / Options.lua).
local function db()
  return ns.db
end

-- Tooltips that get the full look. Others found at load time are skipped.
local TOOLTIPS = {
  "GameTooltip",
  "ItemRefTooltip",
  "ShoppingTooltip1",
  "ShoppingTooltip2",
  "ItemRefShoppingTooltip1",
  "ItemRefShoppingTooltip2",
}

-- Comparison tooltips start with a "Currently Equipped" header, a separator
-- under it would split it from the item name.
local NO_SEPARATOR = {
  ShoppingTooltip1 = true,
  ShoppingTooltip2 = true,
  ItemRefShoppingTooltip1 = true,
  ItemRefShoppingTooltip2 = true,
}

local GAP = "\n "                    -- appended to line 1 to make room for the separator
local LOGO_PREFIX = "|T" .. MEDIA .. "logo_"

-- Per tooltip state lives here, never on Blizzard's frames (taint).
local skins = {}

-- Midnight (12.x) can hand out "secret" values in restricted contexts; they
-- can't be compared or concatenated, so treat them as unknown.
local issecretvalue = issecretvalue
local function safe(v)
  if v ~= nil and issecretvalue and issecretvalue(v) then
    return nil
  end
  return v
end

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------

local FACTION_THEMES = { Alliance = "alliance", Horde = "horde" }

local function GetReactionTheme(unit)
  local reaction = safe(UnitReaction(unit, "player"))
  if not reaction then
    return "creature_neutral"
  elseif reaction >= 5 then
    return "creature_ally"
  elseif reaction == 4 then
    return "creature_neutral"
  end
  return "creature_enemy"
end

-- Returns the tooltip theme (background), the theme of the logo
-- on the faction / creature type line, and for PvP-flagged faction NPCs the
-- faction theme of the logo on the "PvP" line.
local function GetUnitThemes(unit)
  if not unit or not safe(UnitExists(unit)) then
    return nil
  end
  local factionTheme = FACTION_THEMES[safe(UnitFactionGroup(unit)) or ""]
  if safe(UnitIsPlayer(unit)) then
    local theme = factionTheme or "neutral"
    return theme, theme
  end
  local creatureTheme = GetReactionTheme(unit)
  if factionTheme and safe(UnitIsPVP(unit)) then
    return factionTheme, creatureTheme, factionTheme
  end
  return creatureTheme, creatureTheme
end

-- Compact (option): one background over the whole tooltip. Alliance (blue)
-- and Horde (red) players and NPCs by faction, then by reaction: enemies red,
-- allies green; everything else (neutral units, items, spells...) yellow.
local function GetCompactBackground(unit)
  if unit and safe(UnitExists(unit)) then
    local faction = safe(UnitFactionGroup(unit))
    if faction == "Alliance" then
      return "compact_blue"
    elseif faction == "Horde" then
      return "compact_red"
    end
    local reaction = safe(UnitReaction(unit, "player"))
    if reaction and reaction >= 5 then
      return "compact_green"
    elseif reaction and reaction <= 3 then
      return "compact_red"
    end
  end
  return "compact_yellow"
end

local function GetTooltipUnit(tooltip)
  if not tooltip.GetUnit then
    return nil
  end
  local _, unit = tooltip:GetUnit()
  return safe(unit)
end

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------

local function NewTexture(tooltip, layer, subLevel, file)
  local tex = tooltip:CreateTexture(nil, layer, nil, subLevel)
  if file then
    tex:SetTexture(file)
  end
  return tex
end

local function CreateFrameArt(skin, tooltip)
  local file = MEDIA .. "frame.png"
  -- Atlas (128x128): corner at 0,0 (64x64), top edge at 64,0 (32x64),
  -- left edge at 0,64 (64x32). The other pieces are mirrored.
  local h = 0.5 / 128 -- half a texel, avoids bleeding between pieces
  local c0, c1 = 0, 0.5
  local e0, e1 = 64 / 128 + h, 96 / 128 - h

  local function piece(l, r, t, b)
    local tex = NewTexture(tooltip, "BORDER", 0, file)
    tex:SetTexCoord(l, r, t, b)
    return tex
  end

  local tl = piece(c0, c1, c0, c1)
  local tr = piece(c1, c0, c0, c1)
  local bl = piece(c0, c1, c1, c0)
  local br = piece(c1, c0, c1, c0)
  for _, tex in ipairs({ tl, tr, bl, br }) do
    tex:SetSize(CORNER, CORNER)
  end
  tl:SetPoint("TOPLEFT", tooltip, "TOPLEFT", -OUTSET, OUTSET)
  tr:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", OUTSET, OUTSET)
  bl:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", -OUTSET, -OUTSET)
  br:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", OUTSET, -OUTSET)

  local top = piece(e0, e1, c0, c1)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bottom = piece(e0, e1, c1, c0)
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left = piece(c0, c1, e0, e1)
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local right = piece(c1, c0, e0, e1)
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
end

local function CreateBackground(skin, tooltip)
  -- The art sits in the top-right corner; its left and bottom edges fade
  -- into the theme colour, which fills the rest. The pieces don't overlap
  -- so the transparency is the same everywhere.
  skin.bg = NewTexture(tooltip, "BACKGROUND", -7)
  skin.bg:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", BG_INSET, BG_INSET)

  skin.fillLeft = NewTexture(tooltip, "BACKGROUND", -7)
  skin.fillLeft:SetPoint("TOPLEFT", tooltip, "TOPLEFT", -BG_INSET, BG_INSET)
  skin.fillLeft:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", -BG_INSET, -BG_INSET)

  skin.fillBottom = NewTexture(tooltip, "BACKGROUND", -7)
  skin.fillBottom:SetPoint("TOPLEFT", skin.bg, "BOTTOMLEFT")
  skin.fillBottom:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", BG_INSET, -BG_INSET)
end

local function CreateSeparator(skin, tooltip)
  skin.sep = {
    left = NewTexture(tooltip, "ARTWORK", -1),
    mid = NewTexture(tooltip, "ARTWORK", -1),
    right = NewTexture(tooltip, "ARTWORK", -1),
  }
end

-- Portrait medallion (option): a gold ring on the top-left corner of unit
-- tooltips, holding the unit's portrait or its class icon. It sits over the
-- frame's corner, so the name is moved aside with an invisible spacer at the
-- start of line 1 (an inline texture: no measuring, sizes can be secret).
local MEDALLION_SIZE = 64                -- the ring texture's on-screen size
local MEDALLION_X, MEDALLION_Y = 8, -8   -- its centre from the tooltip's top-left corner
local NAME_INDENT = 32                   -- room left before the name
-- A fully transparent corner of the ring texture, NAME_INDENT wide.
local NAME_SPACER = "|T" .. MEDIA .. "medallion.png:1:" .. NAME_INDENT .. ":0:0:256:256:0:4:0:4|t"
-- Compact (option): the medallion is centred on the tooltip's left edge
-- instead, and the whole text moves right (the tooltip's left padding).
local COMPACT_MEDALLION_X = 6            -- its centre from the tooltip's left edge
local COMPACT_INDENT = 30                -- left padding added for it
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_ICON_CROP = 0.06 -- share of each class icon cut from every side (its own rim)

local function CreateMedallion(skin, tooltip)
  -- Over the frame art and the text (ARTWORK), the ring over the picture.
  local picture = NewTexture(tooltip, "OVERLAY", 6)
  local size = MEDALLION_SIZE * Media.medallion.hole + 2 -- tucked under the ring
  picture:SetSize(size, size)
  if tooltip.CreateMaskTexture and picture.AddMaskTexture then
    local mask = tooltip:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "portrait_mask.png", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(picture)
    picture:AddMaskTexture(mask)
  end
  local ring = NewTexture(tooltip, "OVERLAY", 7, MEDIA .. "medallion.png")
  ring:SetSize(MEDALLION_SIZE, MEDALLION_SIZE)
  ring:SetPoint("CENTER", picture)
  picture:Hide()
  ring:Hide()
  skin.picture, skin.ring = picture, ring
end

local function CreateSlot(skin, tooltip)
  local bar = tooltip.StatusBar or _G[tooltip:GetName() .. "StatusBar"]
  if not bar then
    return
  end
  skin.bar = bar

  -- Child of the bar so it shows and hides with it.
  local slot = CreateFrame("Frame", nil, bar)
  slot:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", -OUTSET, -(OUTSET - 2))
  slot:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", OUTSET, -(OUTSET - 2))
  slot:SetHeight(SLOT_HEIGHT)
  skin.slot = slot

  local file = MEDIA .. "slot.png"
  -- Atlas (64x64): end cap at 0,0 (32x40), middle at 32,0 (32x40).
  local v = Media.slot.height
  local h = 0.5 / 64
  local l = slot:CreateTexture(nil, "OVERLAY")
  l:SetTexture(file)
  l:SetTexCoord(0, 0.5, 0, v)
  l:SetPoint("TOPLEFT")
  l:SetPoint("BOTTOMLEFT")
  l:SetWidth(SLOT_CAP)
  local r = slot:CreateTexture(nil, "OVERLAY")
  r:SetTexture(file)
  r:SetTexCoord(0.5, 0, 0, v)
  r:SetPoint("TOPRIGHT")
  r:SetPoint("BOTTOMRIGHT")
  r:SetWidth(SLOT_CAP)
  local m = slot:CreateTexture(nil, "OVERLAY")
  m:SetTexture(file)
  m:SetTexCoord(0.5 + h, 1 - h, 0, v)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT")
  m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")

  -- Dark trough behind the bar.
  local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
  trough:SetColorTexture(0, 0, 0, 0.75)
  trough:SetAllPoints(bar)

  local inset = SLOT_CAP * Media.slot.innerLeft
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", slot, "TOPLEFT", inset, -SLOT_HEIGHT * Media.slot.innerTop)
  bar:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -inset, SLOT_HEIGHT * (1 - Media.slot.innerBottom))
end

local function HideDefaultBorder(tooltip)
  if tooltip.NineSlice then
    tooltip.NineSlice:SetAlpha(0)
  elseif tooltip.SetBackdrop then
    tooltip:SetBackdrop(nil)
  end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function LayoutBackground(skin, tooltip)
  local m = Media.backgrounds[skin.bgTheme]
  local fillLeft = skin.fillLeft
  fillLeft:ClearAllPoints()
  fillLeft:SetPoint("TOPLEFT", tooltip, "TOPLEFT", -BG_INSET, BG_INSET)
  fillLeft:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", -BG_INSET, -BG_INSET)
  local bg = skin.bg
  bg:ClearAllPoints()

  -- Compact backgrounds cover the whole tooltip, stretched (no measuring).
  if m.compact and db().showArt then
    bg:SetPoint("TOPLEFT", tooltip, "TOPLEFT", -BG_INSET, BG_INSET)
    bg:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", BG_INSET, -BG_INSET)
    bg:SetTexCoord(0, 1, 0, 1)
    bg:Show()
    fillLeft:Hide()
    skin.fillBottom:Hide()
    return
  end
  bg:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", BG_INSET, BG_INSET)

  -- Without the art (option), or when the tooltip size is secret
  -- (restricted contexts in 12.x): just fill it with the theme colour.
  local w, h = safe(tooltip:GetWidth()), safe(tooltip:GetHeight())
  if not db().showArt or not w or not h or w <= 0 or h <= 0 then
    skin.bg:Hide()
    skin.fillBottom:Hide()
    fillLeft:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", BG_INSET, BG_INSET)
    fillLeft:Show()
    return
  end
  w, h = w + 2 * BG_INSET, h + 2 * BG_INSET

  -- The art keeps its size and is cropped (from the left / bottom, where it
  -- has already faded into the fill colour) when the tooltip is smaller.
  local artSize = db().artSize
  local fullWidth = artSize * m.aspect
  local imageWidth = math.min(w, fullWidth)
  local imageHeight = math.min(h, artSize)
  skin.bg:SetSize(imageWidth, imageHeight)
  skin.bg:SetTexCoord(1 - imageWidth / fullWidth, 1, 0, imageHeight / artSize)
  skin.bg:Show()

  fillLeft:SetPoint("TOPRIGHT", skin.bg, "TOPLEFT")
  fillLeft:SetShown(w - imageWidth >= 0.5)
  skin.fillBottom:SetShown(h - imageHeight >= 0.5)
end

local function LayoutSeparator(skin, tooltip)
  local sep = skin.sep
  local line = tooltip.TextLeft1 or _G[tooltip:GetName() .. "TextLeft1"]
  if not skin.separator or not line then
    sep.left:Hide(); sep.mid:Hide(); sep.right:Hide()
    return
  end
  -- No measuring here: sizes can be secret in restricted contexts (12.x).
  -- The font size gives the line height, and everything is anchored.
  local m = Media.separator
  local _, fontSize = line:GetFont()
  local lineHeight = safe(fontSize) or 14
  local height = math.max(10, math.min(18, lineHeight * 1.25))
  -- aspect is the visible art's width/height, medallion its share of the width.
  local midWidth = height * m.aspect * m.medallion

  local file = MEDIA .. "separator.png"
  for _, tex in pairs(sep) do
    tex:SetTexture(file)
    tex:SetHeight(height)
    tex:ClearAllPoints()
    tex:Show()
  end
  sep.left:SetTexCoord(0, m.left, m.top, m.bottom)
  sep.mid:SetTexCoord(m.left, m.right, m.top, m.bottom)
  sep.right:SetTexCoord(m.right, 1, m.top, m.bottom)
  sep.mid:SetWidth(midWidth)

  -- Line 1 (name + empty gap line) starts at the tooltip's 10px padding:
  -- the separator sits on the gap line, left-aligned with the text.
  -- The gap is the extra spacing plus the empty line; centre on it.
  local y = -(TOOLTIP_PADDING + lineHeight + ((skin.spacing or 0) + db().separatorSpacing + lineHeight) / 2)
  -- Moved aside with the name when the medallion is shown; its right end stays.
  local indent = (skin.medallion and not db().compact) and NAME_INDENT or 0
  sep.left:SetPoint("LEFT", tooltip, "TOPLEFT", TOOLTIP_PADDING + indent, y)
  sep.mid:SetPoint("LEFT", sep.left, "RIGHT")
  sep.right:SetPoint("LEFT", sep.mid, "RIGHT")

  -- A share of the tooltip width. If the width is secret, use the minimum
  -- width (tooltips are never narrower).
  local w = safe(tooltip:GetWidth())
  if not w or w <= 0 then
    w = db().minWidth
  end
  local side = math.max(1, (w * db().separatorWidth - midWidth - indent) / 2)
  sep.left:SetWidth(side)
  sep.right:SetWidth(side)
end

local function Layout(skin, tooltip)
  if not skin.theme then
    return
  end
  LayoutBackground(skin, tooltip)
  LayoutSeparator(skin, tooltip)
end

---------------------------------------------------------------------------
-- Tooltip text: separator gap and inline logo
---------------------------------------------------------------------------

local function GetLine(tooltip, i)
  return tooltip["TextLeft" .. i] or _G[tooltip:GetName() .. "TextLeft" .. i]
end

-- Makes room for the separator by turning line 1 into two lines.
-- Returns true when the text changed (the tooltip then needs a new layout).
-- Show Level (option): the unit's level after its name, "Name (60)" ("??"
-- for bosses). Kept before the separator gap; removed when the option is
-- turned off. Returns true when the text changed.
local function ApplyNameLevel(skin, tooltip, unit)
  local line = GetLine(tooltip, 1)
  local text = line and safe(line:GetText())
  if not text then
    return false
  end
  local hasGap = text:sub(-#GAP) == GAP
  local base = hasGap and text:sub(1, -#GAP - 1) or text
  local old = skin.levelSuffix
  if old and base:sub(-#old) == old then
    base = base:sub(1, -#old - 1)
  end

  local suffix
  -- Compact (option): always, the level line is merged away.
  if (db().showLevel or db().compact) and unit then
    local level = safe(UnitLevel(unit))
    if type(level) == "number" then
      suffix = " (" .. (level > 0 and level or "??") .. ")"
    end
  end
  skin.levelSuffix = suffix

  local new = base .. (suffix or "") .. (hasGap and GAP or "")
  if new == text then
    return false
  end
  line:SetText(new)
  return true
end

local function ApplyGap(skin, tooltip)
  local line = GetLine(tooltip, 1)
  if not line then
    return false
  end
  local text = safe(line:GetText())
  skin.separator = db().showSeparator and not db().compact and not NO_SEPARATOR[tooltip:GetName()]
    and tooltip:NumLines() >= 2 and text ~= nil and text ~= ""

  -- The separator's breathing room: extra spacing between the name and the
  -- empty gap line. Put back Blizzard's spacing on tooltips without one.
  local changed = false
  if skin.spacing == nil then
    skin.spacing = safe(line:GetSpacing()) or 0
  end
  local spacing = skin.separator and skin.spacing + db().separatorSpacing or skin.spacing
  if safe(line:GetSpacing()) ~= spacing then
    line:SetSpacing(spacing)
    changed = true
  end

  if text then
    local hasGap = text:sub(-#GAP) == GAP
    if skin.separator and not hasGap then
      line:SetText(text .. GAP)
      changed = true
    elseif not skin.separator and hasGap then
      line:SetText(text:sub(1, -#GAP - 1)) -- the separator was just turned off
      changed = true
    end
  end
  return changed
end

local function FindLogoLine(tooltip, unit)
  local wanted
  if safe(UnitIsPlayer(unit)) then
    local _, localized = UnitFactionGroup(unit)
    wanted = safe(localized)
    if wanted then
      for i = 2, tooltip:NumLines() do
        local line = GetLine(tooltip, i)
        local text = line and safe(line:GetText())
        if text == wanted then
          return line, text
        end
      end
    end
  else
    wanted = safe(UnitCreatureType(unit))
  end
  -- Creature type (or, without one, the level line).
  for i = 2, tooltip:NumLines() do
    local line = GetLine(tooltip, i)
    local text = line and safe(line:GetText())
    if text and ((wanted and text:find(wanted, 1, true)) or (not wanted and LEVEL and text:find(LEVEL, 1, true))) then
      return line, text
    end
  end
end

-- Puts the theme's logo in front of the line's text (or removes it when
-- the logo option is off). Returns true when the text changed.
-- Only the factions have a logo.
local LOGO_THEMES = { alliance = true, horde = true }

local function SetLineLogo(line, text, theme)
  local size = db().logoSize
  local logo = (db().showLogo and LOGO_THEMES[theme]) and (LOGO_PREFIX .. theme .. ".png:" .. size .. ":" .. size .. "|t ") or ""
  if text:sub(1, #LOGO_PREFIX) == LOGO_PREFIX then
    if logo ~= "" and text:sub(1, #logo) == logo then
      return false
    end
    text = text:gsub("^|T[^|]*|t ", "", 1)
  elseif logo == "" then
    return false
  end
  line:SetText(logo .. text)
  return true
end

-- The tooltip's PvP line says "PvP", but the PVP string is "Player vs.
-- Player" on some clients (Classic): all of them are known, and the
-- shortest is the one shown when the tooltip has none.
local PVP_TEXTS, PVP_SHORT = {}, nil
local pvpCandidates = { PVP_ENABLED, PVP, "PvP" } -- either string may be nil
for i = 1, 3 do
  local text = pvpCandidates[i]
  if type(text) == "string" and text ~= "" then
    PVP_TEXTS[text] = true
    if not PVP_SHORT or #text < #PVP_SHORT then
      PVP_SHORT = text
    end
  end
end

local function IsPvPText(text)
  return PVP_TEXTS[(text:gsub("^|T[^|]*|t ", ""))] == true -- a logo in front
end

local function FindPvPLine(tooltip)
  for i = 2, tooltip:NumLines() do
    local line = GetLine(tooltip, i)
    local text = line and safe(line:GetText())
    if text and IsPvPText(text) then
      return line, text
    end
  end
end

-- The PvP word as the tooltip writes it.
local function PvPLabel(tooltip)
  local _, text = FindPvPLine(tooltip)
  return text and (text:gsub("^|T[^|]*|t ", "")) or PVP_SHORT
end

local function ApplyLogo(skin, tooltip, unit)
  if not unit then
    return false
  end
  local changed = false
  -- Compact players: the faction line is merged away, its logo goes in
  -- front of the name.
  if skin.compactLine then
    local name = GetLine(tooltip, 1)
    local text = name and safe(name:GetText())
    if text and skin.logoTheme then
      changed = SetLineLogo(name, text, skin.logoTheme)
    end
    return changed
  end
  local line, text = FindLogoLine(tooltip, unit)
  if line and skin.logoTheme then
    changed = SetLineLogo(line, text, skin.logoTheme)
  end
  if skin.pvpTheme then
    line, text = FindPvPLine(tooltip)
    if line then
      changed = SetLineLogo(line, text, skin.pvpTheme) or changed
    end
  end
  return changed
end

-- What the medallion shows for a unit, by the Portrait option: "portrait"
-- (players too far away to be seen get their class icon), "class" (players
-- only), or nil. With the class icon, its texture coordinates too.
local function MedallionContent(unit)
  local mode = db().portrait
  if not unit or mode == "hide" then
    return nil
  end
  if mode == "portrait" and safe(UnitIsVisible(unit)) then
    return "portrait"
  end
  if not safe(UnitIsPlayer(unit)) then
    return nil
  end
  local _, class = UnitClass(unit)
  class = safe(class)
  local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords then
    return "class", coords
  end
end

-- Sets the tooltip's left padding (Blizzard leaves it at 0), keeping the
-- others. Returns true when it changed. Clients without it, or secret
-- values: nothing.
local function SetLeftPadding(tooltip, left)
  if not (tooltip.GetPadding and tooltip.SetPadding) then
    return false
  end
  local r, b, l, t = tooltip:GetPadding()
  r, b, l, t = safe(r), safe(b), safe(l), safe(t)
  if not (r and b and l and t) or l == left then
    return false
  end
  tooltip:SetPadding(r, b, left, t)
  return true
end

-- Shows or hides the medallion, and moves the name aside for it. Without a
-- readable name (secret in restricted contexts) there's no medallion, as it
-- would cover the name. Returns true when the text changed.
local function ApplyMedallion(skin, tooltip, unit)
  local line = GetLine(tooltip, 1)
  local text = line and safe(line:GetText())
  local content, coords
  if text and text ~= "" then
    content, coords = MedallionContent(unit)
  end

  local picture = skin.picture
  if content == "portrait" then
    picture:SetTexCoord(0, 1, 0, 1)
    SetPortraitTexture(picture, unit)
  elseif content == "class" then
    local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
    local dx, dy = (r - l) * CLASS_ICON_CROP, (b - t) * CLASS_ICON_CROP
    picture:SetTexture(CLASS_ICONS)
    picture:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
  end
  skin.medallion = content ~= nil
  picture:SetShown(skin.medallion)
  skin.ring:SetShown(skin.medallion)

  -- Top-left corner, or (compact) the middle of the left edge.
  local compact = db().compact and true or false
  if skin.medallionCompact ~= compact then
    skin.medallionCompact = compact
    picture:ClearAllPoints()
    if compact then
      picture:SetPoint("CENTER", tooltip, "LEFT", COMPACT_MEDALLION_X, 0)
    else
      picture:SetPoint("CENTER", tooltip, "TOPLEFT", MEDALLION_X, MEDALLION_Y)
    end
  end

  -- Compact: the whole text moves right. Otherwise only the name does.
  local changed = SetLeftPadding(tooltip, (skin.medallion and compact) and COMPACT_INDENT or 0)
  if not text then
    return changed
  end
  local wantSpacer = skin.medallion and not compact
  local hasSpacer = text:sub(1, #NAME_SPACER) == NAME_SPACER
  if wantSpacer and not hasSpacer then
    line:SetText(NAME_SPACER .. text)
    return true
  elseif not wantSpacer and hasSpacer then
    line:SetText(text:sub(#NAME_SPACER + 1))
    return true
  end
  return changed
end

-- Compact (option): unit tooltips get two lines (three for players in a
-- guild). Line 1 is the name and level (players: the faction logo in front
-- of it, see ApplyLogo); the lines under it are merged:
-- - players: "PvP · Race" (and the faction without a guild), then
--   "<Guild>" on line 3, from the guild, level/race/class (and any line
--   with the class, e.g. the spec on retail), faction and PvP lines;
-- - NPCs: "PvP · Elite Humanoid · <Title>" (the faction without a title),
--   from the title, level/type, faction and PvP lines. Lines after those
--   (quests...) stay.
-- The lines are told apart by their text, so nothing happens when it's
-- secret (restricted contexts in 12.x). The merged lines take the first of
-- them, the others are emptied (an empty tooltip line takes no room).
local COMPACT_JOIN = " · "

local function Plain(text)
  text = text:gsub("^|T[^|]*|t ", "") -- a logo in front
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Puts the merged texts, in order, in the first lines (from line 2)
-- isPart(i, plain) accepts and empties the others (texts left over, if
-- there were too few lines, are added at the end). Returns true when the
-- text changed, and whether a line took the first text.
local function MergeLines(tooltip, merged, isPart)
  local isMerged = {}
  for _, text in ipairs(merged) do
    isMerged[text] = true
  end
  local changed, used = false, 0
  for i = 2, tooltip:NumLines() do
    local line = GetLine(tooltip, i)
    local text = line and safe(line:GetText())
    if text and text ~= "" and (isMerged[text] or isPart(i, Plain(text))) then
      if used < #merged then
        used = used + 1
        if text ~= merged[used] then
          line:SetText(merged[used])
          changed = true
        end
        line:SetTextColor(1, 1, 1)
      else
        line:SetText("")
        changed = true
      end
      local right = tooltip["TextRight" .. i] or _G[tooltip:GetName() .. "TextRight" .. i]
      local rightText = right and safe(right:GetText())
      if rightText and rightText ~= "" then
        right:SetText("")
        changed = true
      end
    end
  end
  if used > 0 then
    for k = used + 1, #merged do
      tooltip:AddLine(merged[k], 1, 1, 1)
      changed = true
    end
  end
  return changed, used > 0
end

local function PlayerLines(tooltip, unit, faction)
  local race = safe(UnitRace(unit))
  if type(race) ~= "string" or race == "" then
    return nil
  end
  local class = safe(UnitClass(unit))
  if class == "" then
    class = nil
  end
  local guild = safe(GetGuildInfo(unit))
  if guild == "" then
    guild = nil
  end
  local parts = {}
  if safe(UnitIsPVP(unit)) then
    parts[#parts + 1] = PvPLabel(tooltip)
  end
  parts[#parts + 1] = race
  if not guild then
    parts[#parts + 1] = faction
  end
  local merged = { table.concat(parts, COMPACT_JOIN) }
  if guild then
    merged[2] = "<" .. guild .. ">"
  end
  return merged, function(_, plain)
    return plain == faction or IsPvPText(plain) or plain:find(race, 1, true) ~= nil
      or (class and plain:find(class, 1, true)) ~= nil or (guild and plain:find(guild, 1, true)) ~= nil
  end
end

local function NPCLines(tooltip, unit, faction)
  -- The level line ("Level 30 Elite Humanoid"): its type is what's left
  -- once the level is taken out; lines above it are the NPC's title.
  local creatureType = safe(UnitCreatureType(unit))
  if creatureType == "" then
    creatureType = nil
  end
  local levelIndex, levelText
  for i = 2, tooltip:NumLines() do
    local line = GetLine(tooltip, i)
    local text = line and safe(line:GetText())
    if not text then
      return nil -- secret: can't tell the lines apart
    end
    local plain = Plain(text)
    if (LEVEL and plain:find(LEVEL, 1, true)) or (creatureType and plain:find(creatureType, 1, true)) then
      levelIndex, levelText = i, plain
      break
    end
  end
  if not levelIndex then
    return nil
  end
  local kind = levelText
  if LEVEL then
    kind = kind:gsub(LEVEL:gsub("%p", "%%%0") .. "%s*[%d%?%-]*", "", 1)
  end
  kind = Trim(kind)
  if kind == "" then
    kind = creatureType
  end
  local titles = {}
  for i = 2, levelIndex - 1 do
    local text = safe(GetLine(tooltip, i):GetText())
    if text and text ~= "" then
      titles[#titles + 1] = Trim(Plain(text))
    end
  end
  local parts = {}
  if safe(UnitIsPVP(unit)) then
    parts[#parts + 1] = PvPLabel(tooltip)
  end
  parts[#parts + 1] = kind
  if #titles > 0 then
    parts[#parts + 1] = table.concat(titles, COMPACT_JOIN)
  else
    parts[#parts + 1] = faction
  end
  return table.concat(parts, COMPACT_JOIN), function(i, plain)
    return i <= levelIndex or plain == faction or IsPvPText(plain)
  end
end

local function ApplyCompactLines(skin, tooltip, unit)
  local done = skin.compactLine
  skin.compactLine = nil
  if not db().compact or not unit then
    return false
  end
  -- Already merged (the tooltip is updated several times): keep it.
  if done then
    for i = 2, tooltip:NumLines() do
      local line = GetLine(tooltip, i)
      if line and safe(line:GetText()) == done then
        skin.compactLine = done
        return false
      end
    end
  end
  local _, faction = UnitFactionGroup(unit)
  faction = safe(faction)
  if faction == "" then
    faction = nil
  end
  local merged, isPart
  if safe(UnitIsPlayer(unit)) then
    merged, isPart = PlayerLines(tooltip, unit, faction)
  else
    merged, isPart = NPCLines(tooltip, unit, faction)
  end
  if not merged then
    return false
  end
  if type(merged) == "string" then
    merged = { merged }
  end
  local changed, placed = MergeLines(tooltip, merged, isPart)
  skin.compactLine = placed and merged[1] or nil
  return changed
end

-- Realm info (options): the language, type, and realm with its connected
-- realms, added at the end of player tooltips. The data is LibRealmInfo's
-- (bundled), which knows retail and Classic realms: nothing on clients or
-- realms it doesn't know (e.g. WoW Forever). Not in Compact (the options
-- keep their saved values).
local RealmInfo = LibStub and LibStub("LibRealmInfo", true)
local LABEL_COLOR = { r = 1, g = 0.82, b = 0 }
local VALUE_COLOR = { r = 1, g = 1, b = 1 }
-- In English: the tooltip fonts of most clients can't draw Korean or
-- Chinese names.
local REALM_LANGUAGES = {
  enUS = "English", enGB = "English", deDE = "German", esES = "Spanish", esMX = "Spanish (Latin America)",
  frFR = "French", itIT = "Italian", ptBR = "Portuguese (Brazil)", ptPT = "Portuguese", ruRU = "Russian",
  koKR = "Korean", zhCN = "Chinese (Simplified)", zhTW = "Chinese (Traditional)",
}
local REALM_TYPES = { PVE = "PvE", PVP = "PvP", RP = "RP", RPPVP = "RP PvP" }

-- A realm's name as this client shows it: its own (e.g. Cyrillic) name on
-- a client in its language, the English one otherwise.
local function RealmName(realm)
  if realm.englishName and realm.englishName ~= "" and realm.locale ~= GetLocale() then
    return realm.englishName
  end
  return realm.name
end

-- Looked up once per player (by GUID; false: unknown).
local realmCache = {}

local function GetRealm(unit)
  if not RealmInfo then
    return nil
  end
  local guid = safe(UnitGUID(unit))
  if not guid then
    return nil
  end
  if realmCache[guid] == nil then
    local ok, realm = pcall(RealmInfo.GetRealmInfoByUnit, RealmInfo, unit, true)
    realmCache[guid] = (ok and type(realm) == "table" and realm.name) and realm or false
  end
  return realmCache[guid] or nil
end

-- Adds the lines once per tooltip content: they're there as long as the
-- last one is (skin.realmInfo: its index and text). Returns true when lines
-- were added.
local function ApplyRealmInfo(skin, tooltip, unit)
  local mark = skin.realmInfo
  if mark then
    local line = mark.index <= tooltip:NumLines() and GetLine(tooltip, mark.index)
    if line and mark.text and safe(line:GetText()) == mark.text then
      return false
    end
    skin.realmInfo = nil
  end
  local o = db()
  if o.compact or not unit or not safe(UnitIsPlayer(unit))
    or not (o.realmLanguage or o.realmType or o.realmName) then
    return false
  end
  local realm = GetRealm(unit)
  if not realm then
    return false
  end
  local added = false
  local function add(label, value)
    tooltip:AddDoubleLine(label, value, LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b, VALUE_COLOR.r, VALUE_COLOR.g, VALUE_COLOR.b)
    added = true
  end
  if o.realmLanguage and realm.locale then
    add("Realm Language", REALM_LANGUAGES[realm.locale] or realm.locale)
  end
  if o.realmType and realm.rules then
    add("Realm Type", REALM_TYPES[realm.rules] or realm.rules)
  end
  if o.realmName then
    add("Realm", RealmName(realm))
    local names = {}
    for _, id in ipairs(realm.connections or {}) do
      id = tonumber(id)
      if id and id ~= realm.id then
        local other = RealmInfo:GetRealmInfoByID(id, true)
        if type(other) == "table" and other.name then
          names[#names + 1] = RealmName(other)
        end
      end
    end
    if #names > 0 then
      table.sort(names)
      tooltip:AddLine("|cffffd100Connected Realms:|r " .. table.concat(names, ", "), VALUE_COLOR.r, VALUE_COLOR.g, VALUE_COLOR.b, true)
      added = true
    end
  end
  if added then
    local index = tooltip:NumLines()
    local line = GetLine(tooltip, index)
    skin.realmInfo = { index = index, text = line and safe(line:GetText()) }
  end
  return added
end

local function IsSpellTooltip(tooltip)
  if not tooltip.GetSpell then
    return false
  end
  local _, spellID = tooltip:GetSpell()
  return safe(spellID) ~= nil
end

local function IsItemTooltip(tooltip)
  if not tooltip.GetItem then
    return false
  end
  local _, link = tooltip:GetItem()
  return safe(link) ~= nil
end

-- Herbs and mineral veins you can gather (world objects) have a line
-- with the profession, e.g. "Requires Herbalism". The localized profession
-- names are what's left of Blizzard's "Requires Herbalism" and "Requires
-- Mining" after the part they share.
local HERBALISM, MINING = (function()
  local herb, rock = UNIT_SKINNABLE_HERB, UNIT_SKINNABLE_ROCK
  if not herb or not rock then
    return nil, nil
  end
  local i = 1
  while i <= #herb and herb:sub(i, i) == rock:sub(i, i) do
    i = i + 1
  end
  local h, r = herb:sub(i):lower(), rock:sub(i):lower()
  return #h >= 4 and h or nil, #r >= 4 and r or nil
end)()

local function HasLineWith(tooltip, word)
  if not word then
    return false
  end
  for i = 2, tooltip:NumLines() do
    local line = GetLine(tooltip, i)
    local text = line and safe(line:GetText())
    if text and text:lower():find(word, 1, true) then
      return true
    end
  end
  return false
end

-- Spell tooltips show the rank ("Rank 3") on the right of the first line,
-- in grey: write it in white.
local function ApplyRankColor(tooltip, isSpell)
  local line = tooltip.TextRight1 or _G[tooltip:GetName() .. "TextRight1"]
  if isSpell and line and line:IsShown() then
    line:SetTextColor(1, 1, 1)
  end
end

-- Raises the tooltip's minimum width, without lowering one Blizzard set or
-- touching a forced width; follows the option when it changes.
-- Returns true when it changed.
local function ApplyMinimumWidth(skin, tooltip)
  if not tooltip.GetMinimumWidth or not tooltip.SetMinimumWidth then
    return false
  end
  -- Compact (option): the minimum width isn't used (the value is kept).
  local wanted = db().compact and 0 or db().minWidth
  local width, forced = tooltip:GetMinimumWidth()
  width, forced = safe(width), safe(forced)
  if not width or forced or width == wanted then
    return false
  end
  if width < wanted or width == skin.minWidth then
    tooltip:SetMinimumWidth(wanted)
    skin.minWidth = wanted
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

local updating = false

-- "Hide" combat option: the tooltip Blizzard put at its default position
-- (see the GameTooltip_SetDefaultAnchor hook below) is hidden in combat.
local function HideInCombat(skin, tooltip)
  if db().combatMode == "hide" and skin.defaultOwner and InCombatLockdown()
    and tooltip:GetOwner() == skin.defaultOwner then
    tooltip:Hide()
    return true
  end
  return false
end

local function Update(tooltip)
  local skin = skins[tooltip]
  if not skin or updating or tooltip:IsForbidden() or HideInCombat(skin, tooltip) then
    return
  end
  updating = true

  local unit = GetTooltipUnit(tooltip)
  local theme, logoTheme, pvpTheme = GetUnitThemes(unit)
  theme = theme or "neutral"
  skin.logoTheme, skin.pvpTheme = logoTheme, pvpTheme
  -- Dead units (NPCs and players, ghosts included) get the dead background;
  -- their logo keeps the unit's theme.
  -- Buffs and debuffs, spells and abilities, items, herbs and mineral veins
  -- get their own background.
  local isSpell = not unit and IsSpellTooltip(tooltip)
  local bgTheme = theme
  if unit and safe(UnitIsDeadOrGhost(unit)) then
    bgTheme = "dead"
  elseif skin.isAura then
    bgTheme = skin.aura or "buff"
  elseif isSpell then
    bgTheme = "spell"
  elseif not unit and IsItemTooltip(tooltip) then
    bgTheme = "item"
  elseif not unit and HasLineWith(tooltip, HERBALISM) then
    bgTheme = "herb"
  elseif not unit and HasLineWith(tooltip, MINING) then
    bgTheme = "mineral"
  end
  if db().compact then
    bgTheme = GetCompactBackground(unit)
  end
  if theme ~= skin.theme or bgTheme ~= skin.bgTheme then
    skin.theme, skin.bgTheme = theme, bgTheme
    local m = Media.backgrounds[bgTheme]
    local brightness, alpha = db().bgBrightness, db().bgOpacity
    skin.bg:SetTexture(MEDIA .. "background_" .. (m.file or bgTheme) .. ".png")
    skin.bg:SetVertexColor(brightness, brightness, brightness)
    local r, g, b = m.fill[1] * brightness, m.fill[2] * brightness, m.fill[3] * brightness
    skin.fillLeft:SetColorTexture(r, g, b)
    skin.fillBottom:SetColorTexture(r, g, b)
    for _, tex in ipairs({ skin.bg, skin.fillLeft, skin.fillBottom }) do
      tex:SetAlpha(alpha)
    end
  end
  HideDefaultBorder(tooltip)

  local changed = ApplyMedallion(skin, tooltip, unit)
  changed = ApplyCompactLines(skin, tooltip, unit) or changed
  changed = ApplyNameLevel(skin, tooltip, unit) or changed
  changed = ApplyGap(skin, tooltip) or changed
  changed = ApplyLogo(skin, tooltip, unit) or changed
  changed = ApplyRealmInfo(skin, tooltip, unit) or changed
  changed = ApplyMinimumWidth(skin, tooltip) or changed
  ApplyRankColor(tooltip, isSpell)
  if changed and tooltip:IsShown() then
    tooltip:Show() -- recompute the size with the new text
  end
  Layout(skin, tooltip)

  updating = false
end

local function OnSizeChanged(tooltip)
  local skin = skins[tooltip]
  if skin and not updating then
    Layout(skin, tooltip)
  end
end

local function OnCleared(tooltip)
  local skin = skins[tooltip]
  if skin then
    skin.separator = false
    skin.theme = nil
    skin.medallion = false
    skin.compactLine = nil
    skin.realmInfo = nil
    skin.picture:Hide()
    skin.ring:Hide()
    LayoutSeparator(skin, tooltip)
  end
end

local function Skin(tooltip)
  if not tooltip or skins[tooltip] or tooltip:IsForbidden() then
    return
  end
  local skin = {}
  skins[tooltip] = skin
  CreateBackground(skin, tooltip)
  CreateFrameArt(skin, tooltip)
  CreateSeparator(skin, tooltip)
  CreateSlot(skin, tooltip)
  CreateMedallion(skin, tooltip)
  HideDefaultBorder(tooltip)

  tooltip:HookScript("OnShow", Update)
  tooltip:HookScript("OnHide", function()
    skin.defaultOwner = nil
  end)
  tooltip:HookScript("OnSizeChanged", OnSizeChanged)
  if tooltip:HasScript("OnTooltipCleared") then
    tooltip:HookScript("OnTooltipCleared", OnCleared)
  end
  -- Classic flavors without TooltipDataProcessor.
  if not TooltipDataProcessor then
    for _, script in ipairs({ "OnTooltipSetUnit", "OnTooltipSetItem", "OnTooltipSetSpell" }) do
      if tooltip:HasScript(script) then
        tooltip:HookScript(script, Update)
      end
    end
  end
end

for _, name in ipairs(TOOLTIPS) do
  Skin(_G[name])
end

-- Default position: Blizzard places the tooltip in the bottom-right corner
-- (or the Edit Mode "HUD Tooltip" spot). Tooltips anchored to what you
-- hover (bag slots, action buttons...) never come through here.
-- - Follow Cursor (option): anchor it to the cursor instead.
-- - In combat (option): hide it, keep it at the default position, or keep
--   it on the cursor.
local CURSOR_OFFSET_X, CURSOR_OFFSET_Y = 36, -10
if GameTooltip_SetDefaultAnchor then
  hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
    local skin = skins[tooltip]
    if tooltip ~= GameTooltip or not skin or tooltip:IsForbidden() then
      return
    end
    local owner = parent or UIParent
    if db().followCursor and (not InCombatLockdown() or db().combatMode == "cursor") then
      tooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", CURSOR_OFFSET_X, CURSOR_OFFSET_Y)
    end
    skin.defaultOwner = owner -- after SetOwner, which can fire OnHide
  end)
end

-- Right-Click Hint (option): unit frames add "<Right click for Frame
-- Settings>" (and a blank line above it) after the unit's lines, then show
-- the tooltip again: both are emptied (an empty line takes no room).
local hintGuard = false
local function RemoveFrameHint(tooltip)
  if hintGuard or db().frameHint or not UNIT_POPUP_RIGHT_CLICK or not skins[tooltip] or tooltip:IsForbidden() then
    return
  end
  for i = tooltip:NumLines(), 2, -1 do
    local line = GetLine(tooltip, i)
    if line and safe(line:GetText()) == UNIT_POPUP_RIGHT_CLICK then
      line:SetText("")
      local blank = GetLine(tooltip, i - 1)
      if blank and safe(blank:GetText()) == " " then
        blank:SetText("")
      end
      hintGuard = true
      tooltip:Show() -- recompute the size
      hintGuard = false
      return
    end
  end
end
hooksecurefunc(GameTooltip, "Show", RemoveFrameHint)

-- Entering combat with the default tooltip shown: hide it right away.
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function()
  local skin = skins[GameTooltip]
  if skin and GameTooltip:IsShown() and db().combatMode == "hide" and skin.defaultOwner
    and GameTooltip:GetOwner() == skin.defaultOwner then
    GameTooltip:Hide()
  end
end)

-- Buffs and debuffs: the tooltip data doesn't say which, so it comes from
-- the function that filled the tooltip, the aura itself (when it can be
-- read, not in restricted combat), or the hovered button's frame.
-- true/false when the aura can be read, nil otherwise (secret values make
-- any of this error, hence the pcall).
local function IsHarmful(unit, auraInstanceID)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
    return nil
  end
  local ok, harmful = pcall(function()
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if type(safe(aura)) ~= "table" then
      return nil
    end
    local isHarmful, isHelpful = safe(aura.isHarmful), safe(aura.isHelpful)
    if type(isHarmful) == "boolean" then
      return isHarmful
    elseif type(isHelpful) == "boolean" then
      return not isHelpful
    end
  end)
  if ok then
    return harmful
  end
end

local function OwnerIsDebuff(tooltip)
  local frame = tooltip:GetOwner()
  for _ = 1, 3 do
    if not frame then
      break
    end
    local name = frame.GetName and safe(frame:GetName())
    if name and name:find("Debuff") then
      return true
    end
    frame = frame.GetParent and frame:GetParent()
  end
  return false
end

local function SetAura(tooltip, kind)
  local skin = skins[tooltip]
  if skin and skin.isAura then
    skin.aura = kind
    Update(tooltip)
  end
end

for tooltip in pairs(skins) do
  local function hook(method, handler)
    if tooltip[method] then
      hooksecurefunc(tooltip, method, handler)
    end
  end
  local function buff(self) SetAura(self, "buff") end
  local function debuff(self) SetAura(self, "debuff") end
  hook("SetUnitBuff", buff)
  hook("SetUnitBuffByAuraInstanceID", buff)
  hook("SetUnitDebuff", debuff)
  hook("SetUnitDebuffByAuraInstanceID", debuff)
  hook("SetUnitAura", function(self, _, _, filter)
    local f = safe(filter)
    SetAura(self, (type(f) == "string" and f:find("HARMFUL")) and "debuff" or "buff")
  end)
  hook("SetUnitAuraByAuraInstanceID", function(self, unit, auraInstanceID)
    local harmful = IsHarmful(unit, auraInstanceID)
    if harmful == nil then
      harmful = OwnerIsDebuff(self)
    end
    SetAura(self, harmful and "debuff" or "buff")
  end)
end

-- Re-applies the options to the visible tooltips.
function ns.Refresh()
  for tooltip, skin in pairs(skins) do
    skin.theme = nil
    if tooltip:IsShown() then
      Update(tooltip)
    end
  end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
  local AURA = Enum and Enum.TooltipDataType and Enum.TooltipDataType.UnitAura
  TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, tooltipData)
    local skin = skins[tooltip]
    if skin then
      -- Aura tooltips: buff or debuff is set by the hooks below.
      skin.isAura = AURA ~= nil and tooltipData ~= nil and safe(tooltipData.type) == AURA
      if not skin.isAura then
        skin.aura = nil
      end
      Update(tooltip)
    end
  end)
end
