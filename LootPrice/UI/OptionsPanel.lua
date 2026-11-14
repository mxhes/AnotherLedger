local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Options panel: a small window next to the ledger that shows every option
-- registered with Options.define (Options.lua). Client-only widgets; every WoW
-- global is touched inside functions only.
--
-- Expandability: the panel never names an option. It walks Options.entries() (sections with their options) and
-- asks WIDGETS[spec.type] for a widget. A new option is one Options.define
-- call; a new kind of control is one entry in WIDGETS (plus its height in
-- Options.HEIGHTS).
local Panel = {}
ns.UI.OptionsPanel = Panel

local TITLE = "Options"
local COLUMNS = 2
local COLUMN_WIDTH = 250
local COLUMN_GAP = 24
local TITLE_HEIGHT = 24

local function theme() return ns.Theme end

local function get(spec) return ns.Options.get(ns.db, spec.key) end
local function set(spec, value) return ns.Options.set(ns.db, spec.key, value) end

local function label(parent, font, color)
  return ns.UI.Widgets.text(parent, font, color)
end

-- One radio entry per choice of a dropdown option.
local function openChoiceMenu(anchor, spec, onPick)
  local entries = {}
  for _, choice in ipairs(ns.Options.choices(spec)) do
    entries[#entries + 1] = {
      text = choice.label,
      isChecked = function() return get(spec) == choice.value end,
      onClick = function() onPick(choice.value) end,
    }
  end
  ns.UI.Widgets.openMenu(anchor, entries, "radio")
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

-- Section title: gold text with a thin line under it.
function Panel.WIDGETS.header(block, spec)
  local T = theme()
  local title = label(block, T.fonts.body, T.colors.gold)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -2)
  title:SetText(spec.label)
  local line = ns.UI.Widgets.line(block, T.colors.goldLine, "ARTWORK", 0.5)
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", 0, 2)
  line:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", 0, 2)
  return { refresh = function() end }
end

function Panel.WIDGETS.text(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  title:SetText(spec.label)

  local box = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
  box:SetHeight(20)
  box:SetPoint("TOPLEFT", block, "TOPLEFT", 6, -22)
  box:SetPoint("TOPRIGHT", block, "TOPRIGHT", -4, -22)
  box:SetAutoFocus(false)
  box:SetMaxLetters(200)

  local function show(value) box:SetText(tostring(value)) end
  local function commit() show(set(spec, box:GetText())) end
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

function Panel.WIDGETS.button(block, spec)
  local button = ns.UI.Widgets.button(block, spec.label)
  button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -2)
  button:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -2)
  button:SetScript("OnClick", function()
    if spec.action then spec.action() end
  end)
  return { refresh = function() end }
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

  local button = ns.UI.Widgets.button(block)
  button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -20)
  button:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -20)

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

-- Builds one widget per option into `parent`, `pad` from the left and `top`
-- from the top, in the columns of `layout` (Options.layout). Returns
-- { [key] = widget }.
function Panel.populate(parent, pad, top, specs, layout, columnWidth)
  local widgets = {}
  for _, spec in ipairs(specs) do
    local factory = Panel.WIDGETS[spec.type]
    if factory then
      local block = CreateFrame("Frame", nil, parent)
      block:SetSize(columnWidth, ns.Options.HEIGHTS[spec.type])
      local x = pad + ((layout.cols[spec.key] or 1) - 1) * (columnWidth + COLUMN_GAP)
      block:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(top + layout.tops[spec.key]))
      widgets[spec.key] = factory(block, spec)
    end
  end
  return widgets
end

local function build()
  local T = theme()
  local pad = T.sizes.padding + 4
  local specs = ns.Options.entries()
  local layout = ns.Options.layout(specs, COLUMNS)
  local width = 2 * pad + COLUMNS * COLUMN_WIDTH + (COLUMNS - 1) * COLUMN_GAP

  local frame = CreateFrame("Frame", "LootPriceOptions", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetSize(width, 2 * pad + TITLE_HEIGHT + layout.height)
  ns.UI.Widgets.applyBackdrop(frame)
  -- Always fully opaque: the opacity option is for the ledger window.
  local c = T.colors.panelTint
  frame:SetBackdropColor(c[1], c[2], c[3], 1)
  local bc = T.colors.panelBorder
  frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)

  local title = label(frame, T.fonts.title, T.colors.gold)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  title:SetText(TITLE)

  local close = ns.UI.Widgets.button(frame, "X", T.widths.header.hide)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad + 2)
  close:SetScript("OnClick", function() frame:Hide() end)

  frame.widgets = Panel.populate(frame, pad, pad + TITLE_HEIGHT, specs, layout, COLUMN_WIDTH)

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

-- ---------------------------------------------------------------------------
-- Page in the game's own options window (Esc > Options > AddOns > LootPrice):
-- the same widgets as the floating panel, so both always show the same values.

local PAGE_NAME = "LootPrice"

local function buildPage()
  local T = theme()
  local pad = 16
  local specs = ns.Options.entries()
  local layout = ns.Options.layout(specs, COLUMNS)

  local page = CreateFrame("Frame", "LootPriceOptionsPage")
  page.name = PAGE_NAME
  local title = label(page, T.fonts.title, T.colors.gold)
  title:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -pad)
  title:SetText(PAGE_NAME)

  page.widgets = Panel.populate(page, pad, pad + TITLE_HEIGHT, specs, layout, COLUMN_WIDTH)
  function page:RefreshAll()
    for _, w in pairs(self.widgets) do w.refresh() end
  end
  page:SetScript("OnShow", function(self) self:RefreshAll() end)
  -- Callbacks of the legacy interface options window; values save as they change.
  page.refresh = function(self) self:RefreshAll() end
  page.okay = function() end
  page.cancel = function() end
  page.default = function() end
  return page
end

-- Registers the page once. Safe when neither options API exists.
function Panel.registerPage()
  if Panel.page or not ns.db then return Panel.page end
  local page = buildPage()
  if type(Settings) == "table" and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(page, PAGE_NAME)
    Settings.RegisterAddOnCategory(category)
    Panel.category = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(page)
  end
  Panel.page = page
  return page
end
