local addonName, ns = ...

-- Options panel in the game's Settings (Options > AddOns > Nicer Tooltip),
-- saved per account in NicerTooltipDB.

local category

local function Percent(value)
  return string.format("%d%%", math.floor(value * 100 + 0.5))
end

local function Plain(value)
  return string.format("%d", math.floor(value + 0.5))
end

local function Register(layoutCategory, layout)
  local db = ns.db

  local VAR_TYPES = { boolean = Settings.VarType.Boolean, number = Settings.VarType.Number, string = Settings.VarType.String }
  local onChange = {} -- extra handlers, by key

  local function Setting(key, name)
    local default = ns.defaults[key]
    local setting = Settings.RegisterAddOnSetting(layoutCategory, addonName .. "_" .. key, key, db, VAR_TYPES[type(default)], name, default)
    setting:SetValueChangedCallback(function(...)
      if onChange[key] then
        onChange[key](...)
      end
      ns.Refresh()
    end)
    return setting
  end

  local function Checkbox(key, name, tooltip)
    return Settings.CreateCheckbox(layoutCategory, Setting(key, name), tooltip)
  end

  local function Dropdown(key, name, tooltip, getOptions)
    local setting = Setting(key, name)
    Settings.CreateDropdown(layoutCategory, setting, getOptions, tooltip)
    return setting
  end

  local function Slider(key, name, tooltip, min, max, step, formatter)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    return Settings.CreateSlider(layoutCategory, Setting(key, name), options, tooltip)
  end

  local function Header(name)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
  end

  Header("Background")
  Slider("bgOpacity", "Opacity", "How opaque the tooltip background is.", 0, 1, 0.05, Percent)
  Slider("bgBrightness", "Brightness", "Dims the background (art and colour) to keep the text readable.", 0.3, 1, 0.05, Percent)
  Checkbox("showArt", "Show Art", "Show the themed art (faction or creature emblem) in the top-right corner. Without it the background is a flat colour.")
  Slider("artSize", "Art Size", "Height of the art in the top-right corner.", 40, 160, 5, Plain)

  Header("Name")
  Checkbox("showLevel", "Show Level", "Show the level of players and NPCs after their name, in parentheses: Name (60).")

  Header("Size and Position")
  Slider("minWidth", "Minimum Width", "Tooltips are never narrower than this.", 0, 500, 10, Plain)
  Checkbox("followCursor", "Follow Cursor", "Tooltips that normally appear in the bottom-right corner (or where Edit Mode's HUD Tooltip is) follow the mouse cursor instead. Tooltips shown next to what you hover (bags, action bars...) are not affected.")

  -- "Keep on Cursor" only exists while Follow Cursor is on.
  if db.combatMode == "cursor" and not db.followCursor then
    db.combatMode = "default"
  end
  local combatSetting = Dropdown("combatMode", "In Combat", "What happens in combat to the tooltips that normally appear in the bottom-right corner (or where Edit Mode's HUD Tooltip is): hide them, show them at that position, or keep them on the cursor (needs Follow Cursor).", function()
    local container = Settings.CreateControlTextContainer()
    container:Add("hide", "Hide")
    container:Add("default", "Original Position")
    if db.followCursor then
      container:Add("cursor", "Keep on Cursor")
    end
    return container:GetData()
  end)
  onChange.followCursor = function()
    if not db.followCursor and db.combatMode == "cursor" then
      combatSetting:SetValue("default")
    end
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= addonName then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")

  NicerTooltipDB = NicerTooltipDB or {}
  NicerTooltipDB.merchants = nil -- from a removed experiment
  NicerTooltipDB.nodes = nil -- from a removed experiment
  -- Options that were removed from the panel: back to their defaults.
  for _, key in ipairs({ "showSeparator", "separatorWidth", "separatorSpacing", "showLogo", "logoSize" }) do
    NicerTooltipDB[key] = nil
  end
  ns.db = setmetatable(NicerTooltipDB, { __index = ns.defaults })

  if Settings and Settings.RegisterVerticalLayoutCategory then
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Nicer Tooltip")
    Register(category, layout)
    Settings.RegisterAddOnCategory(category)
  end
  ns.Refresh()
end)

SLASH_NICERTOOLTIP1 = "/nicertooltip"
SLASH_NICERTOOLTIP2 = "/ntt"
SlashCmdList.NICERTOOLTIP = function()
  if category then
    Settings.OpenToCategory(category:GetID())
  end
end
