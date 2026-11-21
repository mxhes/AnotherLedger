local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Options panel: a small window next to the ledger that shows every option
-- registered with Options.define (Options.lua). Client-only widgets; every WoW
-- global is touched inside functions only.
--
-- Expandability: the panel never names an option. It shows one tab per
-- section of Options.sections() (the option categories, tab buttons from
-- UI/Tabs.lua) and asks WIDGETS[spec.type] for a widget per option. A new option is one Options.define
-- call; a new kind of control is one entry in WIDGETS (plus its height in
-- Options.HEIGHTS).
local Panel = {}
ns.UI.OptionsPanel = Panel

local TITLE = L["Options"]
local L_DELETE = L["Delete"]
local COLUMNS = 2

local function theme() return ns.Theme end
local function sizes() return ns.Theme.options end

local function get(spec) return ns.Options.get(ns.db, spec.key) end
-- A choice in the panel: Options.pick (runs the option's `picked` hook too).
local function set(spec, value) return ns.Options.pick(ns.db, spec.key, value) end

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
-- Widget factories: (block, spec) -> { refresh = function() end, controls = { frame, ... } }
-- `controls` are the frames that take the mouse; hovering them (or the block)
-- shows the option's tooltip (Options.tooltip).

Panel.WIDGETS = {}

function Panel.WIDGETS.slider(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)

  local O = sizes()
  local slider = CreateFrame("Slider", nil, block, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", block, "TOPLEFT", 4, -O.controlTop)
  slider:SetWidth(O.control)
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
    controls = { slider },
  }
end

-- An input box in the window's own look (Widgets.input, like the search box),
-- not the game's InputBoxTemplate.
local function inputBox(block, width)
  local T = theme()
  local box = ns.UI.Widgets.input(block, width)
  box:SetHeight(sizes().boxHeight)
  box:SetAutoFocus(false)
  box:SetFontObject(T.fonts.small)
  box:SetTextInsets(4, 4, 0, 0)
  return box
end

function Panel.WIDGETS.number(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  title:SetText(spec.label)

  local box = inputBox(block, sizes().numberBox)
  box:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -sizes().controlTop)
  box:SetMaxLetters(10)

  -- Unlimited shows as an empty box, 0 as the option's zeroText ("Off").
  local function show(value)
    if value < 0 then
      box:SetText("")
    elseif value == 0 and spec.zeroText then
      box:SetText(spec.zeroText)
    else
      box:SetText(tostring(value))
    end
  end
  -- Typing into "Off" starts from the number it stands for.
  box:SetScript("OnEditFocusGained", function(self)
    if spec.zeroText and self:GetText() == spec.zeroText then
      self:SetText("0")
      self:HighlightText()
    end
  end)
  -- A value the option wants confirmed (History kept: deletes sessions) waits
  -- for the popup; the box shows the stored value until then.
  local function commit()
    local parsed = ns.Options.parseNumber(box:GetText())
    if not parsed or ns.Options.normalize(spec, parsed) == get(spec) then
      show(get(spec))
      return
    end
    local question = spec.confirm and spec.confirm(ns.Options.normalize(spec, parsed))
    if question then
      show(get(spec))
      ns.UI.Widgets.confirm(question, L_DELETE, function() show(set(spec, parsed)) end)
      return
    end
    show(set(spec, parsed))
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
    controls = { box },
  }
end

-- Section title: gold text with a thin line under it.
function Panel.WIDGETS.header(block, spec)
  local T = theme()
  local title = label(block, T.fonts.body, T.colors.gold)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -2)
  title:SetText(spec.label)
  local line = ns.UI.Widgets.rule(block, T.colors.goldLine, "ARTWORK", 0.5)
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

  -- As wide as the dropdowns and buttons, not the whole column.
  local box = inputBox(block, sizes().control)
  box:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -sizes().controlTop)
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
    controls = { box },
  }
end

function Panel.WIDGETS.button(block, spec)
  local button = ns.UI.Widgets.button(block, spec.label, sizes().control)
  button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -1)
  button:SetScript("OnClick", function(self)
    if spec.action then spec.action(self) end
  end)
  return { refresh = function() end, controls = { button } }
end

function Panel.WIDGETS.checkbox(block, spec)
  local T = theme()
  local box = CreateFrame("CheckButton", nil, block, "UICheckButtonTemplate")
  box:SetSize(sizes().checkbox, sizes().checkbox)
  box:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -1)
  local text = label(block, T.fonts.small, T.colors.ink)
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(spec.label)
  box:SetScript("OnClick", function(self)
    set(spec, self:GetChecked() and true or false)
  end)
  return {
    refresh = function() box:SetChecked(get(spec) == true) end,
    controls = { box },
  }
end

function Panel.WIDGETS.dropdown(block, spec)
  local T = theme()
  local title = label(block, T.fonts.small, T.colors.ink)
  title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  title:SetText(spec.label)

  local button = ns.UI.Widgets.button(block, nil, sizes().control)
  button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -sizes().controlTop)

  local function show(value)
    button:SetText(ns.Options.buttonText(spec, value))
  end
  button:SetScript("OnClick", function(self)
    openChoiceMenu(self, spec, function(value) show(set(spec, value)) end)
  end)

  return {
    refresh = function() show(get(spec)) end,
    controls = { button },
  }
end

-- Pure. A color option's label with its hex code after it, in the hint color.
function Panel.colorLabel(text, hex)
  if type(hex) ~= "string" or hex == "" then return text end
  return text .. "  " .. ns.Money.colorCode(ns.Theme.colors.hint) .. "#" .. hex .. "|r"
end

-- Color: a swatch and the label. Click opens the game's color picker (the
-- color changes live while you drag, Cancel restores it); right-click sets
-- the default.
function Panel.WIDGETS.color(block, spec)
  local T = theme()
  local W = ns.UI.Widgets
  -- A wide chip with a light frame: a dark color on the dark panel still
  -- reads as a color, not as an empty checkbox.
  local swatch = CreateFrame("Button", nil, block, "BackdropTemplate")
  swatch:SetSize(2 * sizes().swatch, sizes().swatch)
  swatch:SetPoint("TOPLEFT", block, "TOPLEFT", 2, -3)
  if swatch.SetBackdrop then swatch:SetBackdrop({ edgeFile = T.textures.buttonEdge, edgeSize = 1 }) end
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(T.textures.rowHighlight)
  fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
  local text = label(block, T.fonts.small, T.colors.ink)
  text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
  text:SetText(spec.label)

  -- The hex code after the label, quiet: a dark color on the dark panel still
  -- reads as a color, not as an empty checkbox.
  local function show(value)
    -- The frame follows the Text color (set again on every refresh).
    local e = T.colors.ink
    if swatch.SetBackdropBorderColor then swatch:SetBackdropBorderColor(e[1], e[2], e[3], 0.8) end
    local r, g, b = T.hexToRGB(value)
    if r then fill:SetVertexColor(r, g, b, 1) end
    text:SetText(Panel.colorLabel(spec.label, value))
  end
  if swatch.RegisterForClicks then swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  swatch:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      show(set(spec, ns.Options.defaultFor(spec.key)))
      return
    end
    W.pickColor(get(spec), function(hex) show(set(spec, hex)) end)
  end)
  return {
    refresh = function() show(get(spec)) end,
    controls = { swatch },
  }
end

-- ---------------------------------------------------------------------------
-- Panel

-- Hover on an option's block and its controls shows the option's tooltip.
-- Bronze buttons (Widgets.button) take their hover hooks as fields; other
-- controls keep their template's scripts and get ours hooked after them.
local function wireTooltip(widget, block, spec)
  local W = ns.UI.Widgets
  local function show(owner) W.showTextTooltip(owner, ns.Options.tooltip(spec), "ANCHOR_RIGHT") end
  block:EnableMouse(true)
  block:SetScript("OnEnter", show)
  block:SetScript("OnLeave", W.hideTooltip)
  for _, c in ipairs(widget.controls or {}) do
    if c.kind == "bronze" then
      c.onEnter, c.onLeave = show, W.hideTooltip
    elseif c.HookScript then
      c:HookScript("OnEnter", show)
      c:HookScript("OnLeave", W.hideTooltip)
    end
  end
end

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
      local x = pad + ((layout.cols[spec.key] or 1) - 1) * (columnWidth + sizes().columnGap)
      block:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(top + layout.tops[spec.key]))
      local widget = factory(block, spec)
      widget.block = block
      -- Dimmed (still usable) while the option does nothing (Options.inactive).
      local refresh = widget.refresh
      widget.refresh = function()
        refresh()
        block:SetAlpha(ns.Options.inactive(spec) and sizes().inactiveAlpha or 1)
      end
      if spec.type ~= "header" then wireTooltip(widget, block, spec) end
      widgets[spec.key] = widget
    end
  end
  return widgets
end

-- Pure. Height of the tabbed area for one section: the tab row, the gap
-- under it and the section laid out in `columns`. The panel takes the shown
-- tab's height (a short tab leaves no empty space under it).
function Panel.tabbedHeight(section, columns)
  return theme().sizes.headerRowHeight + sizes().tabGap + ns.Options.layout(section.specs, columns).height
end

-- The selected tab, shared by the panel and the options page and kept for the
-- session. A section id; an unknown one falls back to the first section.
Panel.tab = nil

-- One tab per section (Options.sections) in `parent`, `pad` from the sides and
-- `top` from the top: the tab row, and under it one page per section with its
-- options in COLUMNS columns; only the selected tab's page is shown. Returns
-- { widgets = { [key] = widget }, select = function(id), height (the shown
-- tab's), heights = { [id] = height }, onResize = function(height) or nil }.
function Panel.buildTabbed(parent, pad, top)
  local S = theme().sizes
  local O = sizes()
  local sections = ns.Options.sections()
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(S.headerRowHeight)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, -top)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -top)

  local tabbed = { widgets = {}, pages = {}, heights = {}, height = 0 }
  local items = {}
  for _, section in ipairs(sections) do
    items[#items + 1] = { key = section.id, label = section.label }
    local height = Panel.tabbedHeight(section, COLUMNS)
    tabbed.heights[section.id] = height
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", row, "BOTTOMLEFT", -pad, -O.tabGap)
    page:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", pad, -O.tabGap)
    page:SetHeight(height - S.headerRowHeight - O.tabGap)
    page:Hide()
    local layout = ns.Options.layout(section.specs, COLUMNS)
    for key, w in pairs(Panel.populate(page, pad, 0, section.specs, layout, O.columnWidth)) do
      tabbed.widgets[key] = w
    end
    tabbed.pages[section.id] = page
  end

  local strip
  function tabbed.select(id)
    if not tabbed.pages[id] then id = sections[1] and sections[1].id end
    if not id then return end
    Panel.tab = id
    for key, page in pairs(tabbed.pages) do page:SetShown(key == id) end
    if strip then strip:SetSelected(id) end
    tabbed.height = tabbed.heights[id]
    if tabbed.onResize then tabbed.onResize(tabbed.height) end
  end
  strip = ns.UI.Tabs.strip(row, items, tabbed.select)
  tabbed.strip = strip
  tabbed.select(Panel.tab)
  return tabbed
end

local function build()
  local T = theme()
  local O = sizes()
  local pad = T.sizes.padding + 4
  local width = 2 * pad + COLUMNS * O.columnWidth + (COLUMNS - 1) * O.columnGap

  local frame = CreateFrame("Frame", "AnotherLedgerOptions", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  -- Dragging the panel moves it; the place is kept (Panel.savePosition) and
  -- used from then on instead of the spot next to the ledger window.
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    Panel.savePosition(self)
  end)
  local tabbed = Panel.buildTabbed(frame, pad, pad + O.titleHeight)
  frame.tabbed = tabbed
  -- Wider than the two columns when the tab row needs it (six tabs, German).
  local extent, n = 0, 0
  for _, b in pairs(tabbed.strip.buttons or {}) do extent, n = extent + b:GetWidth(), n + 1 end
  if n > 0 then width = math.max(width, 2 * pad + extent + (n - 1) * T.sizes.buttonGap) end
  frame:SetWidth(width)
  -- The shown tab sets the height; the top edge stays where it is, so the
  -- tab row never moves under the mouse.
  function tabbed.onResize(height)
    -- Any anchor but the top one (the default CENTER, or where a drag left
    -- it) becomes TOP at the current spot first.
    local point = frame:GetPoint(1)
    if point and point ~= "TOP" and point ~= "TOPLEFT" and point ~= "TOPRIGHT" then
      local fx, ftop = frame:GetCenter(), frame:GetTop()
      local ux, utop = UIParent:GetCenter(), UIParent:GetTop()
      if fx and ftop and ux and utop then
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", fx - ux, ftop - utop)
      end
    end
    frame:SetHeight(2 * pad + O.titleHeight + height)
  end
  tabbed.onResize(tabbed.height)
  -- Same background as the ledger window: its opacity and brightness too.
  ns.UI.Widgets.applyBackdrop(frame)
  if ns.UI.Window and ns.UI.Window.paintLook then ns.UI.Window.paintLook(frame) end

  local title = label(frame, T.fonts.title, T.colors.gold)
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
  title:SetText(TITLE)

  local close = ns.UI.Widgets.iconButton(frame, "close", T.widths.header.hide, function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad + 2)

  frame.widgets = tabbed.widgets

  function frame:RefreshAll()
    for _, w in pairs(self.widgets) do w.refresh() end
  end
  -- Opens on the tab last used (here or on the options page).
  frame:SetScript("OnShow", function(self)
    self.tabbed.select(Panel.tab)
    self:RefreshAll()
  end)

  -- Esc closes the panel.
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AnotherLedgerOptions") end
  frame:Hide()
  return frame
end

-- Shows the stored values again in the panel and the options page (after a
-- slash command changed a setting).
function Panel.refreshAll()
  for _, f in ipairs({ Panel.frame or false, Panel.page or false }) do
    if f and f.RefreshAll and f:IsShown() then f:RefreshAll() end
  end
end

-- Remembers where the panel was dragged to (db.optionsWindow: its top edge's
-- middle as an offset from the screen's top middle; the height changes with
-- the tab, the top stays).
function Panel.savePosition(frame)
  if not ns.db then return end
  local fx, ftop = frame:GetCenter(), frame:GetTop()
  local ux, utop = UIParent:GetCenter(), UIParent:GetTop()
  if not (fx and ftop and ux and utop) then return end
  ns.db.optionsWindow = { x = fx - ux, top = ftop - utop }
end

-- Pure. Where the panel opens once it was dragged, else nil (next to the
-- ledger window): { x, top } (TOP offset), or { x, y } (CENTER offset, saved
-- by versions before the height followed the tab).
function Panel.savedPosition(db)
  local p = type(db) == "table" and db.optionsWindow
  if type(p) ~= "table" or not ns.Util.isNumber(p.x) then return nil end
  if ns.Util.isNumber(p.top) or ns.Util.isNumber(p.y) then return p end
  return nil
end

-- Opens the panel where it was dragged to (else next to the ledger window),
-- or closes it.
function Panel.toggle()
  if not ns.db then return end
  if not Panel.frame then Panel.frame = build() end
  local frame = Panel.frame
  if frame:IsShown() then
    frame:Hide()
    return
  end
  local saved = Panel.savedPosition(ns.db)
  local anchor = ns.UI.Window and ns.UI.Window.frame
  frame:ClearAllPoints()
  if saved and saved.top then
    frame:SetPoint("TOP", UIParent, "TOP", saved.x, saved.top)
  elseif saved then
    frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
  elseif anchor then
    frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  frame:Show()
end

-- ---------------------------------------------------------------------------
-- Page in the game's own options window (Esc > Options > AddOns > AnotherLedger):
-- the same widgets as the floating panel, so both always show the same values.

local PAGE_NAME = "AnotherLedger"

local function buildPage()
  local T = theme()
  local pad = 16

  local page = CreateFrame("Frame", "AnotherLedgerOptionsPage")
  page.name = PAGE_NAME
  local title = label(page, T.fonts.title, T.colors.gold)
  title:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -pad)
  title:SetText(PAGE_NAME)

  -- The tab row spans the two columns (the canvas may be wider).
  local tabbed = Panel.buildTabbed(page, pad, pad + sizes().titleHeight)
  page.tabbed = tabbed
  page.widgets = tabbed.widgets
  function page:RefreshAll()
    for _, w in pairs(self.widgets) do w.refresh() end
  end
  page:SetScript("OnShow", function(self)
    self.tabbed.select(Panel.tab)
    self:RefreshAll()
  end)
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
