local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Options panel: a small window next to the ledger that shows every option
-- registered with Options.define (Options.lua). Client-only widgets; every WoW
-- global is touched inside functions only.
--
-- Expandability: the panel never names an option. It walks Options.list() and
-- asks WIDGETS[spec.type] for a widget. A new option is one Options.define
-- call; a new kind of control is one entry in WIDGETS (plus its height in
-- Options.HEIGHTS).
local Panel = {}
ns.UI.OptionsPanel = Panel

local TITLE = "Options"
local WIDTH = 280
local TITLE_HEIGHT = 24

local function theme() return ns.Theme end

local function get(spec) return ns.Options.get(ns.db, spec.key) end
local function set(spec, value) return ns.Options.set(ns.db, spec.key, value) end

local function label(parent, font, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  return fs
end

-- ---------------------------------------------------------------------------
-- Choice menu (feature-detected at call time, like the filter bar menu)

local legacyMenu
local function openChoiceMenu(anchor, spec, onPick)
  if MenuUtil and MenuUtil.CreateContextMenu then
    -- UNVERIFIED (check in client): MenuUtil.CreateContextMenu / CreateRadio.
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      for _, c in ipairs(spec.choices) do
        root:CreateRadio(c.label,
          function() return get(spec) == c.value end,
          function() onPick(c.value) end)
      end
    end)
    return
  end
  if not legacyMenu then
    legacyMenu = CreateFrame("Frame", "LootPriceOptionsMenu", UIParent, "UIDropDownMenuTemplate")
  end
  UIDropDownMenu_Initialize(legacyMenu, function()
    for _, c in ipairs(spec.choices) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = c.label
      info.checked = get(spec) == c.value
      info.func = function() onPick(c.value) end
      UIDropDownMenu_AddButton(info)
    end
  end, "MENU")
  ToggleDropDownMenu(1, nil, legacyMenu, anchor, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Widget factories: (block, spec) -> { refresh = function() end }

Panel.WIDGETS = {}

function Panel.WIDGETS.slider(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)

  -- UNVERIFIED (check in client): OptionsSliderTemplate exists on Forever.
  local slider = CreateFrame("Slider", nil, block, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", block, "TOPLEFT", 4, -22)
  slider:SetPoint("TOPRIGHT", block, "TOPRIGHT", -4, -22)
  slider:SetMinMaxValues(spec.min, spec.max)
  slider:SetValueStep(spec.step or 0.05)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  -- The value is shown in the title; hide the template's own texts.
  for _, part in ipairs({ "Text", "Low", "High" }) do
    if type(slider[part]) == "table" and slider[part].SetText then slider[part]:SetText("") end
  end

  local syncing = false
  local function show(value)
    title:SetText(spec.label .. ": " .. ns.Options.valueText(spec, value))
  end
  slider:SetScript("OnValueChanged", function(_, value)
    if syncing then return end
    show(set(spec, value))
  end)

  return {
    refresh = function()
      local value = get(spec)
      syncing = true
      slider:SetValue(value)
      syncing = false
      show(value)
    end,
  }
end

function Panel.WIDGETS.number(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  title:SetText(spec.label)

  local box = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
  box:SetSize(80, 20)
  box:SetPoint("TOPLEFT", block, "TOPLEFT", 6, -22)
  box:SetAutoFocus(false)
  box:SetMaxLetters(10)

  -- Unlimited shows as an empty box.
  local function show(value)
    box:SetText(value < 0 and "" or tostring(value))
  end
  local function commit()
    local parsed = ns.Options.parseNumber(box:GetText())
    if parsed then show(set(spec, parsed)) else show(get(spec)) end
  end
  box:SetScript("OnEnterPressed", function(self)
    commit()
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    show(get(spec))
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", function() commit() end)

  return {
    refresh = function() show(get(spec)) end,
  }
end

function Panel.WIDGETS.checkbox(block, spec)
  local T = theme()
  local box = CreateFrame("CheckButton", nil, block, "UICheckButtonTemplate")
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -2)
  local text = label(block, T.fonts.small, T.colors.ink)
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(spec.label)
  box:SetScript("OnClick", function(self)
    set(spec, self:GetChecked() and true or false)
  end)
  return {
    refresh = function() box:SetChecked(get(spec) == true) end,
  }
end

function Panel.WIDGETS.dropdown(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  title:SetText(spec.label)

  local button = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
  button:SetHeight(T.sizes.buttonHeight)
  button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -20)
  button:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -20)
  button:SetNormalFontObject(T.fonts.button)
  button:SetHighlightFontObject(T.fonts.buttonHighlight)

  local function show(value)
    button:SetText(ns.Options.valueText(spec, value))
  end
  button:SetScript("OnClick", function(self)
    openChoiceMenu(self, spec, function(value) show(set(spec, value)) end)
  end)

  return {
    refresh = function() show(get(spec)) end,
  }
end

-- ---------------------------------------------------------------------------
-- Panel

local function build()
  local T = theme()
  local pad = T.sizes.padding + 4
  local specs = ns.Options.list()
  local layout = ns.Options.layout(specs)

  local frame = CreateFrame("Frame", "LootPriceOptions", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetSize(WIDTH, 2 * pad + TITLE_HEIGHT + layout.height)
  frame:SetBackdrop({
    bgFile = T.textures.parchment,
    edgeFile = T.textures.frameBorder,
    tile = true,
    tileSize = T.sizes.backdropTile,
    edgeSize = T.sizes.backdropEdge,
    insets = {
      left = T.sizes.backdropInset, right = T.sizes.backdropInset,
      top = T.sizes.backdropInset, bottom = T.sizes.backdropInset,
    },
  })
  -- Always fully opaque: the opacity option is for the ledger window.
  local c = T.colors.panelTint
  frame:SetBackdropColor(c[1], c[2], c[3], 1)
  local bc = T.colors.panelBorder
  frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)

  local title = label(frame, T.fonts.title, T.colors.gold)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  title:SetText(TITLE)

  local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  close:SetSize(T.widths.header.hide, T.sizes.buttonHeight)
  close:SetText("X")
  close:SetNormalFontObject(T.fonts.button)
  close:SetHighlightFontObject(T.fonts.buttonHighlight)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad + 2)
  close:SetScript("OnClick", function() frame:Hide() end)

  frame.widgets = {}
  for _, spec in ipairs(specs) do
    local factory = Panel.WIDGETS[spec.type]
    if factory then
      local block = CreateFrame("Frame", nil, frame)
      block:SetHeight(ns.Options.HEIGHTS[spec.type])
      local top = pad + TITLE_HEIGHT + layout.tops[spec.key]
      block:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -top)
      block:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -top)
      frame.widgets[spec.key] = factory(block, spec)
    end
  end

  function frame:RefreshAll()
    for _, w in pairs(self.widgets) do w.refresh() end
  end
  frame:SetScript("OnShow", function(self) self:RefreshAll() end)

  -- Esc closes the panel.
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LootPriceOptions") end
  frame:Hide()
  return frame
end

-- Opens the panel next to the ledger window, or closes it.
function Panel.toggle()
  if not ns.db then return end
  if not Panel.frame then Panel.frame = build() end
  local frame = Panel.frame
  if frame:IsShown() then
    frame:Hide()
    return
  end
  local anchor = ns.UI.Window and ns.UI.Window.frame
  frame:ClearAllPoints()
  if anchor then
    frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  frame:Show()
end
