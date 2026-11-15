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

-- Sets the text color of a FontString from a theme color {r, g, b[, a]}.
function Widgets.setTextColor(fontString, color)
  fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
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
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
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

local function paint(b, state)
  b.look = state
  local c = Widgets.buttonColors(state, b.warn)
  if b.SetBackdropColor then
    b:SetBackdropColor(c.fill[1], c.fill[2], c.fill[3], c.fill[4] or 1)
    b:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4] or 1)
  end
  if b.label then b.label:SetTextColor(c.text[1], c.text[2], c.text[3], c.text[4] or 1) end
  if b.glyph and b.glyph.SetDesaturated then b.glyph:SetDesaturated(state == "disabled") end
  if type(b.bars) == "table" then
    for _, bar in ipairs(b.bars) do bar:SetVertexColor(c.text[1], c.text[2], c.text[3], c.text[4] or 1) end
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
end

-- Text button. `opts.warn` gives the red warning look (Reset).
-- SetText / GetText work on the label; hover / leave hooks go in b.onEnter /
-- b.onLeave (the button's own OnEnter / OnLeave repaint it).
-- UNVERIFIED (check in client): Button:SetFontString with a BackdropTemplate
-- button keeps SetText / GetText working.
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

-- Pure. The bars of a stepped triangle `rows` px high pointing "up" or "down":
-- { width, y } per row from the top, y = the bar's top edge above the center.
-- Each row is 1 px high and 2 px wider than the one before.
function Widgets.arrowBars(direction, rows)
  local bars = {}
  for i = 1, rows do
    local step = direction == "up" and i or (rows - i + 1)
    bars[i] = { width = 2 * step, y = rows / 2 - (i - 1) }
  end
  return bars
end

-- Arrow glyphs of the mode button: drawn from flat bars and tinted with the
-- button's text color (paint), so they follow hover and disabled like a label.
local ARROWS = { compact = "up", full = "down" }

local function setArrow(b, direction)
  local T = ns.Theme
  local rows = T.sizes.arrowRows
  if not b.bars then
    b.bars = {}
    for i = 1, rows do
      local bar = b:CreateTexture(nil, "ARTWORK")
      bar:SetTexture(T.textures.buttonEdge)
      bar:SetHeight(1)
      b.bars[i] = bar
    end
  end
  for i, spec in ipairs(Widgets.arrowBars(direction, rows)) do
    local bar = b.bars[i]
    bar:ClearAllPoints()
    bar:SetWidth(spec.width)
    bar:SetPoint("TOP", b, "CENTER", 0, spec.y)
  end
  b.arrow = direction
end

-- Square icon button in the same style: `glyph` = "gear" or "close" (game
-- textures), "compact" (an up arrow) or "full" (a down arrow); b:SetGlyph(glyph)
-- swaps it.
-- UNVERIFIED (check in client): the glyph textures (Theme.textures.iconGear /
-- iconClose) exist on Forever.
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
  b.bars, b.arrow, b.look = false, false, false
  function b:SetGlyph(name)
    local direction = ARROWS[name]
    if direction then
      self.glyph:Hide()
      setArrow(self, direction)
      for _, bar in ipairs(self.bars) do bar:Show() end
      if self.look then paint(self, self.look) end
      return
    end
    if self.bars then for _, bar in ipairs(self.bars) do bar:Hide() end end
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
  local fill, edge = T.colors.inputFill, T.colors.buttonEdge
  if e.SetBackdropColor then
    e:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
    e:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
  end
  e.kind = "input"
  return e
end

-- The dark leather backdrop of the ledger window and the options panel.
function Widgets.applyBackdrop(frame)
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
  local bg, border = T.colors.panelTint, T.colors.panelBorder
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
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

function Widgets.showTextTooltip(owner, text, anchor)
  if not GameTooltip or not text then return false end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:SetText(text)
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
-- Context menu (feature-detected at call time)
--
-- entries = { { text, isChecked = function() -> bool, onClick = function() }, ... }
-- kind = "checkbox" (independent toggles, the menu stays open) or "radio"
-- (pick one, the menu closes).

local function openModernMenu(anchor, entries, kind)
  -- UNVERIFIED (check in client): MenuUtil.CreateContextMenu, CreateCheckbox /
  -- CreateRadio and MenuResponse.Refresh.
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
