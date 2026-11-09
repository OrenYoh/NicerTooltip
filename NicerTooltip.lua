local addonName, ns = ...
local Media = ns.Media

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"

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
  sep.left:SetPoint("LEFT", tooltip, "TOPLEFT", TOOLTIP_PADDING, y)
  sep.mid:SetPoint("LEFT", sep.left, "RIGHT")
  sep.right:SetPoint("LEFT", sep.mid, "RIGHT")

  -- A share of the tooltip width. If the width is secret, use the minimum
  -- width (tooltips are never narrower).
  local w = safe(tooltip:GetWidth())
  if not w or w <= 0 then
    w = db().minWidth
  end
  local side = math.max(1, (w * db().separatorWidth - midWidth) / 2)
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
  if db().showLevel and unit then
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
  skin.separator = db().showSeparator and not NO_SEPARATOR[tooltip:GetName()]
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

local function FindPvPLine(tooltip)
  if not PVP then
    return nil
  end
  for i = 2, tooltip:NumLines() do
    local line = GetLine(tooltip, i)
    local text = line and safe(line:GetText())
    if text and (text == PVP or text:sub(-(#PVP + 1)) == " " .. PVP) then
      return line, text
    end
  end
end

local function ApplyLogo(skin, tooltip, unit)
  if not unit then
    return false
  end
  local changed = false
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
  local wanted = db().minWidth
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

  local changed = ApplyNameLevel(skin, tooltip, unit)
  changed = ApplyGap(skin, tooltip) or changed
  changed = ApplyLogo(skin, tooltip, unit) or changed
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
