local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Building blocks shared by the UI files: themed buttons and texts, flat
-- colored lines, the window backdrop, tooltips and a small context menu.
-- Client-only; every WoW global is touched inside functions only.
local Widgets = {}
ns.UI.Widgets = Widgets

local MENU_FRAME = "LootPriceMenu" -- global name of the legacy dropdown frame

-- ---------------------------------------------------------------------------
-- Colors

-- Every region colored from a theme color is remembered with that color
-- table (weak keys), so a color option can recolor it live: Theme.setColor
-- changes the table in place, Widgets.recolor applies it again.
--   text     -> { "text", color }
--   line     -> { "line", color, alpha }
--   button   -> { "button" }        (repainted in its current state)
--   input    -> { "input" }
--   backdrop -> { "backdrop", opaque }
local tracked = setmetatable({}, { __mode = "k" })
Widgets.tracked = tracked

-- Sets the text color of a FontString from a theme color {r, g, b[, a]}.
function Widgets.setTextColor(fontString, color)
  fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  tracked[fontString] = { "text", color }
end

-- A color not from the theme (item quality): set, and no longer recolored.
function Widgets.setTextRGB(fontString, r, g, b, a)
  fontString:SetTextColor(r, g, b, a or 1)
  tracked[fontString] = nil
end

local function tint(tex, color, alpha)
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function inputColors(e)
  local T = ns.Theme
  local fill, edge = T.colors.inputFill, T.colors.buttonEdge
  if e.SetBackdropColor then
    e:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
    e:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
  end
end

local function backdropColors(frame, opaque)
  local T = ns.Theme
  local bg, border = T.colors.panelTint, T.colors.panelBorder
  frame:SetBackdropColor(bg[1], bg[2], bg[3], opaque and 1 or bg[4])
  frame:SetBackdropBorderColor(border[1], border[2], border[3], opaque and 1 or border[4])
end

local paint -- defined with the buttons below

-- Applies the theme colors again to every remembered region. `changed` (a set
-- of color tables) limits texts and lines to those colors, so a text another
-- part colored differently keeps its color; buttons, inputs and backdrops are
-- always repainted. Window.applyLook (opacity / brightness) runs after this.
function Widgets.recolor(changed)
  for region, t in pairs(tracked) do
    local kind = t[1]
    if kind == "text" then
      local c = t[2]
      if not changed or changed[c] then region:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    elseif kind == "line" then
      if not changed or changed[t[2]] then tint(region, t[2], t[3]) end
    elseif kind == "button" then
      paint(region, region.look or "normal")
    elseif kind == "input" then
      inputColors(region)
    elseif kind == "backdrop" then
      backdropColors(region, t[2])
    end
  end
end

-- ---------------------------------------------------------------------------
-- Regions

-- Single-line FontString in a theme font and color.
function Widgets.text(parent, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  Widgets.setTextColor(fs, color)
  return fs
end

-- Flat texture tinted with a theme color (lines, separators, dividers).
-- `alpha` overrides the color's own alpha.
function Widgets.line(parent, color, layer, alpha)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK")
  tex:SetTexture(ns.Theme.textures.rowHighlight)
  tint(tex, color, alpha)
  tracked[tex] = { "line", color, alpha }
  return tex
end

-- ---------------------------------------------------------------------------
-- Bronze dark buttons: one style for every button of the addon (dark fill,
-- bronze edge, cream text; gold edge on hover, dimmed text when disabled; a
-- warning button such as Reset keeps a red edge and text).

-- Pure. Colors of a button in `state` ("normal" / "hover" / "disabled").
function Widgets.buttonColors(state, warn)
  local c = ns.Theme.colors
  local hover, disabled = state == "hover", state == "disabled"
  local edge
  if warn then
    edge = hover and c.buttonWarnEdgeHover or c.buttonWarnEdge
  else
    edge = hover and c.buttonEdgeHover or c.buttonEdge
  end
  local text = disabled and c.buttonTextDisabled or (warn and c.buttonWarnText or c.buttonText)
  -- A light button background keeps its label (and arrow) readable.
  text = ns.Theme.readableOn(text, c.buttonFill, disabled)
  return { fill = c.buttonFill, edge = edge, text = text }
end

-- The shared backdrop of buttons and input boxes.
local function buttonBackdrop(frame)
  if not frame.SetBackdrop then return end
  local T = ns.Theme
  local inset = T.sizes.buttonInset
  frame:SetBackdrop({
    bgFile = T.textures.parchment,
    edgeFile = T.textures.buttonEdge,
    edgeSize = T.sizes.buttonEdge,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
end

function paint(b, state)
  b.look = state
  local c = Widgets.buttonColors(state, b.warn)
  if b.SetBackdropColor then
    b:SetBackdropColor(c.fill[1], c.fill[2], c.fill[3], c.fill[4] or 1)
    b:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4] or 1)
  end
  if b.label then b.label:SetTextColor(c.text[1], c.text[2], c.text[3], c.text[4] or 1) end
  if b.glyph and b.glyph.SetDesaturated then b.glyph:SetDesaturated(state == "disabled") end
  if type(b.arrowTex) == "table" then
    b.arrowTex:SetVertexColor(c.text[1], c.text[2], c.text[3], c.text[4] or 1)
  end
end

-- A button counts as disabled only when IsEnabled says false.
local function isDisabled(b)
  return b.IsEnabled ~= nil and b:IsEnabled() == false
end

local function restingState(b)
  return isDisabled(b) and "disabled" or "normal"
end

-- Hover / enable handlers shared by both button kinds.
local function wireStates(b)
  b:SetScript("OnEnter", function(self)
    if not isDisabled(self) then paint(self, "hover") end
    if self.onEnter then self.onEnter(self) end
  end)
  b:SetScript("OnLeave", function(self)
    paint(self, restingState(self))
    if self.onLeave then self.onLeave(self) end
  end)
  b:SetScript("OnEnable", function(self) paint(self, "normal") end)
  b:SetScript("OnDisable", function(self) paint(self, "disabled") end)
  paint(b, "normal")
  tracked[b] = { "button" }
end

-- Text button. `opts.warn` gives the red warning look (Reset).
-- SetText / GetText work on the label; hover / leave hooks go in b.onEnter /
-- b.onLeave (the button's own OnEnter / OnLeave repaint it).
function Widgets.button(parent, label, width, opts)
  local T = ns.Theme
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  if width then
    b:SetSize(width, T.sizes.buttonHeight)
  else
    b:SetHeight(T.sizes.buttonHeight)
  end
  buttonBackdrop(b)
  local fs = b:CreateFontString(nil, "OVERLAY", T.fonts.button)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetWordWrap(false)
  if b.SetFontString then b:SetFontString(fs) end
  b.label, b.glyph, b.onEnter, b.onLeave = fs, false, false, false
  b.kind, b.warn = "bronze", (opts and opts.warn) and true or false
  b:SetText(label or "")
  wireStates(b)
  return b
end

-- Pure. SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy) that turns the
-- right-pointing arrow texture (Theme.textures.arrow) to point "up" or "down".
function Widgets.arrowCoords(direction)
  if direction == "up" then return 1, 0, 0, 0, 1, 1, 0, 1 end
  return 0, 1, 1, 1, 0, 0, 1, 0
end

-- Arrow glyphs of the mode button: a smooth (anti-aliased) white arrow
-- texture tinted with the button's text color (paint), so it follows hover and
-- disabled like a label.
local ARROWS = { compact = "up", full = "down" }

local function setArrow(b, direction)
  local T = ns.Theme
  if not b.arrowTex then
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(T.textures.arrow)
    local pad = T.sizes.arrowPad
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", pad, -pad)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -pad, pad)
    b.arrowTex = tex
  end
  if b.arrowTex.SetTexCoord then b.arrowTex:SetTexCoord(Widgets.arrowCoords(direction)) end
  b.arrow = direction
end

-- Square icon button in the same style: `glyph` = "gear" or "close" (game
-- textures), "compact" (an up arrow) or "full" (a down arrow); b:SetGlyph(glyph)
-- swaps it.
function Widgets.iconButton(parent, glyph, size, onClick)
  local T = ns.Theme
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  size = size or T.sizes.buttonHeight
  b:SetSize(size, size)
  buttonBackdrop(b)
  local tex = b:CreateTexture(nil, "ARTWORK")
  local pad = T.sizes.iconButtonPad
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", pad, -pad)
  tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -pad, pad)
  b.glyph, b.label, b.onEnter, b.onLeave = tex, false, false, false
  b.arrowTex, b.arrow, b.look = false, false, false
  function b:SetGlyph(name)
    local direction = ARROWS[name]
    if direction then
      self.glyph:Hide()
      setArrow(self, direction)
      self.arrowTex:Show()
      if self.look then paint(self, self.look) end
      return
    end
    if self.arrowTex then self.arrowTex:Hide() end
    self.arrow = false
    self.glyph:Show()
    self.glyph:SetTexture(name == "close" and T.textures.iconClose or T.textures.iconGear)
    if self.glyph.SetTexCoord then
      if name == "close" then self.glyph:SetTexCoord(0, 1, 0, 1)
      else self.glyph:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    end
  end
  b:SetGlyph(glyph)
  b.kind, b.warn = "icon", false
  wireStates(b)
  b:SetScript("OnClick", function() if onClick then onClick() end end)
  return b
end

-- Single-line input box with the same edge (Min g, Search).
function Widgets.input(parent, width)
  local T = ns.Theme
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(width, T.sizes.buttonHeight)
  buttonBackdrop(e)
  inputColors(e)
  tracked[e] = { "input" }
  e.kind = "input"
  return e
end

-- The dark leather backdrop of the ledger window and the options panel.
-- `opaque`: full alpha. Both get the opacity / brightness options from
-- Window.applyLook afterwards.
function Widgets.applyBackdrop(frame, opaque)
  local T = ns.Theme
  local inset = T.sizes.backdropInset
  frame:SetBackdrop({
    bgFile = T.textures.parchment,
    edgeFile = T.textures.frameBorder,
    tile = true,
    tileSize = T.sizes.backdropTile,
    edgeSize = T.sizes.backdropEdge,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
  backdropColors(frame, opaque)
  tracked[frame] = { "backdrop", opaque and true or false }
end

-- ---------------------------------------------------------------------------
-- Tooltips

-- Item tooltip for a link (or "item:<id>" string). Returns whether it is shown.
function Widgets.showItemTooltip(owner, link, anchor)
  if not GameTooltip or not link then return false end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(link)
  GameTooltip:Show()
  return true
end

-- `text` is a string, or a rich tooltip from ns.Tooltip (drawn line by line
-- with its colors; the first line takes the tooltip's header font).
function Widgets.showTextTooltip(owner, text, anchor)
  text = ns.Tooltip.resolve(text)
  if not GameTooltip or not text then return false end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  if type(text) == "table" then
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    for _, o in ipairs(ns.Tooltip.render(text)) do
      if o.op == "double" then
        local l, r = o.lc, o.rc
        GameTooltip:AddDoubleLine(o.left, o.right, l[1], l[2], l[3], r[1], r[2], r[3])
      else
        local c = o.color or ns.Theme.colors.tipValue
        GameTooltip:AddLine(o.text, c[1], c[2], c[3], o.wrap and true or false)
      end
    end
  else
    GameTooltip:SetText(text)
  end
  GameTooltip:Show()
  return true
end

function Widgets.hideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

function Widgets.tooltipOwnedBy(owner)
  return GameTooltip ~= nil and GameTooltip:IsOwned(owner) and true or false
end

-- ---------------------------------------------------------------------------
-- Color picker: the game's ColorPickerFrame, opened on `hex` ("rrggbb").
-- `onChange(hex)` runs while the color is dragged and with the old color on
-- Cancel. Returns whether the picker opened (false without it, in the tests).
-- UNVERIFIED (check in client): SetupColorPickerAndShow (retail 10.2.5+) and
-- GetColorRGB; the legacy fields (func, cancelFunc) are the older fallback.
function Widgets.pickColor(hex, onChange)
  local cp = ColorPickerFrame
  if type(cp) ~= "table" or type(cp.GetColorRGB) ~= "function" then return false end
  local T = ns.Theme
  local r, g, b = T.hexToRGB(hex)
  if not r then r, g, b = 1, 1, 1 end
  local function changed()
    local nr, ng, nb = cp:GetColorRGB()
    onChange(T.colorToHex({ nr, ng, nb }))
  end
  local function cancel() onChange(hex) end
  if type(cp.SetupColorPickerAndShow) == "function" then
    cp:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = changed, cancelFunc = cancel })
  else
    cp.hasOpacity, cp.opacityFunc = false, nil
    cp.func, cp.cancelFunc = changed, cancel
    cp.previousValues = { r = r, g = g, b = b }
    cp:SetColorRGB(r, g, b)
    cp:Hide()
    cp:Show()
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Confirmation popup: one shared dialog, its text and handlers set per call.
-- `accept` is the confirm button's text; `onCancel` (optional) runs on Cancel
-- or Esc. Without the popup API (tests) nothing happens and nothing is done.

local CONFIRM = "LOOTPRICE_CONFIRM"
local L_CANCEL = ns.L["Cancel"]

function Widgets.confirm(text, accept, onAccept, onCancel)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
  local dialog = StaticPopupDialogs[CONFIRM]
  if not dialog then
    dialog = { timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, button2 = L_CANCEL }
    StaticPopupDialogs[CONFIRM] = dialog
  end
  dialog.text = text
  dialog.button1 = accept
  dialog.OnAccept = function() if onAccept then onAccept() end end
  dialog.OnCancel = function() if onCancel then onCancel() end end
  StaticPopup_Show(CONFIRM)
  return true
end

-- ---------------------------------------------------------------------------
-- Context menu (feature-detected at call time)
--
-- entries = { { text, isChecked = function() -> bool, onClick = function() }, ... }
-- kind = "checkbox" (independent toggles, the menu stays open) or "radio"
-- (pick one, the menu closes).

local function openModernMenu(anchor, entries, kind)
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    for _, entry in ipairs(entries) do
      if kind == "checkbox" then
        root:CreateCheckbox(entry.text, entry.isChecked, function()
          entry.onClick()
          return MenuResponse and MenuResponse.Refresh or nil
        end)
      else
        root:CreateRadio(entry.text, entry.isChecked, entry.onClick)
      end
    end
  end)
end

local legacyMenu
local function openLegacyMenu(anchor, entries, kind)
  if not legacyMenu then
    legacyMenu = CreateFrame("Frame", MENU_FRAME, UIParent, "UIDropDownMenuTemplate")
  end
  UIDropDownMenu_Initialize(legacyMenu, function()
    for _, entry in ipairs(entries) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.text
      info.checked = entry.isChecked()
      info.func = entry.onClick
      if kind == "checkbox" then
        info.isNotRadio = true
        info.keepShownOnClick = true
      end
      UIDropDownMenu_AddButton(info)
    end
  end, "MENU")
  ToggleDropDownMenu(1, nil, legacyMenu, anchor, 0, 0)
end

function Widgets.openMenu(anchor, entries, kind)
  if MenuUtil and MenuUtil.CreateContextMenu then
    openModernMenu(anchor, entries, kind)
  else
    openLegacyMenu(anchor, entries, kind)
  end
end
