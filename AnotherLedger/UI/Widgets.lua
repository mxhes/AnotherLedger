local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Building blocks shared by the UI files: themed buttons and texts, flat
-- colored lines, the window backdrop, tooltips and a small context menu.
-- Client-only; every WoW global is touched inside functions only.
local Widgets = {}
ns.UI.Widgets = Widgets

local MENU_FRAME = "AnotherLedgerMenu" -- global name of the legacy dropdown frame

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
  Widgets.paintEdges(frame, { border[1], border[2], border[3], opaque and 1 or border[4] })
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
    elseif kind == "rule" then
      Widgets.restyleRule(region)
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

-- Gives a line of Widgets.line (or a styled Widgets.rule) another theme color
-- (still recolored live).
function Widgets.setLineColor(tex, color, alpha)
  if tracked[tex] and tracked[tex][1] == "rule" then
    tracked[tex] = { "rule", color, alpha }
    Widgets.restyleRule(tex)
    return
  end
  tint(tex, color, alpha)
  tracked[tex] = { "line", color, alpha }
end

-- ---------------------------------------------------------------------------
-- Whole screen pixels. One UI unit is 1.17 or 1.4 screen pixels at most UI
-- scales, and frames start anywhere inside a pixel, so a thin line comes out
-- 0, 1 or 2 px thick depending on where it lands. A region whose size AND
-- position are whole pixels draws every edge exactly. Uses
-- PixelUtil.GetPixelToUIUnitFactor and Region:GetLeft / GetTop right after
-- SetPoint (both fine in the client); without them the plain UI units are used.

local function effectiveScale(region)
  local s = region.GetEffectiveScale and region:GetEffectiveScale()
  return type(s) == "number" and s > 0 and s or nil
end

-- One screen pixel in `region`'s units, or nil when unknown.
function Widgets.pixelSize(region)
  local P = _G.PixelUtil
  local scale = effectiveScale(region)
  if not (scale and type(P) == "table" and type(P.GetPixelToUIUnitFactor) == "function") then return nil end
  local factor = P.GetPixelToUIUnitFactor()
  if type(factor) ~= "number" or factor <= 0 then return nil end
  return factor / scale
end

-- Pure. How far `v` lies past the nearest whole pixel of size `p`.
function Widgets.pixelError(v, p)
  return v - math.floor(v / p + 0.5) * p
end

-- `units` UI units of `region` rounded to whole screen pixels, at least one.
function Widgets.pixels(region, units)
  units = units or 1
  local p = Widgets.pixelSize(region)
  if not p then return units end
  return math.max(1, math.floor(units / p + 0.5)) * p
end

-- SetPoint, then moved by less than a pixel so the region's left and top edge
-- sit on whole screen pixels (with a whole pixel size, so do the others). Run
-- it again whenever the window moved.
function Widgets.snapPoint(region, point, rel, relPoint, x, y)
  region:ClearAllPoints()
  region:SetPoint(point, rel, relPoint, x, y)
  local p = Widgets.pixelSize(region)
  if not p then return end
  local left, top = region:GetLeft(), region:GetTop()
  if type(left) ~= "number" or type(top) ~= "number" then return end
  region:ClearAllPoints()
  region:SetPoint(point, rel, relPoint, x - Widgets.pixelError(left, p), y - Widgets.pixelError(top, p))
end

-- ---------------------------------------------------------------------------
-- Gilded two-tone buttons: one style for every button of the addon. An outer
-- dark line, a fill that is light in its top third, dark in its bottom third
-- and fades between them, and the edge color as a thin line just inside.
-- Gold edge on hover, the halves swapped while pressed, dimmed text when
-- disabled; a warning button such as Reset keeps a red edge and text. All
-- colors come from the preset's button fill and edge.

Widgets.BUTTON_TOP = 1.8      -- top third: the fill this much lighter
Widgets.BUTTON_BOTTOM = 0.75  -- bottom third: this much darker
Widgets.BUTTON_OUTLINE = 0.3  -- the outer line
Widgets.BUTTON_HOVER = 1.25   -- hover lightens both halves by this

-- Pure. Colors of a button in `state` ("normal" / "hover" / "pressed" /
-- "disabled"): fill (the preset color), top / bottom of the fill, outline,
-- edge (the inner line) and text.
function Widgets.buttonColors(state, warn)
  local T = ns.Theme
  local c = T.colors
  local lit, disabled = state == "hover" or state == "pressed", state == "disabled"
  local edge
  if warn then
    edge = lit and c.buttonWarnEdgeHover or c.buttonWarnEdge
  else
    edge = lit and c.buttonEdgeHover or c.buttonEdge
  end
  local text = disabled and c.buttonTextDisabled or (warn and c.buttonWarnText or c.buttonText)
  -- A light button background keeps its label (and arrow) readable.
  text = ns.Theme.readableOn(text, c.buttonFill, disabled)
  local top = T.scaleColor(c.buttonFill, Widgets.BUTTON_TOP)
  local bottom = T.scaleColor(c.buttonFill, Widgets.BUTTON_BOTTOM)
  if state == "hover" then
    top, bottom = T.scaleColor(top, Widgets.BUTTON_HOVER), T.scaleColor(bottom, Widgets.BUTTON_HOVER)
  elseif state == "pressed" then
    top, bottom = bottom, top
  end
  -- Raised style: a light top / left and a dark bottom / right edge line.
  local k = T.skinScales
  local light, dark = T.scaleColor(c.buttonFill, k.raisedLight), T.scaleColor(c.buttonFill, k.raisedDark)
  if state == "hover" then
    light, dark = T.scaleColor(light, Widgets.BUTTON_HOVER), T.scaleColor(dark, Widgets.BUTTON_HOVER)
  elseif state == "pressed" then
    light, dark = dark, light
  end
  return {
    fill = c.buttonFill, top = top, bottom = bottom,
    outline = T.scaleColor(c.buttonFill, Widgets.BUTTON_OUTLINE), edge = edge, text = text,
    light = light, dark = dark,
  }
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

-- A vertical fade from `bottom` (low) to `top` (high) on a texture:
-- SetGradient with CreateColor on retail, SetGradientAlpha on older clients,
-- else a flat color halfway.
local function setFade(tex, bottom, top)
  if tex.SetGradient and type(CreateColor) == "function" then
    tex:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1),
      CreateColor(top[1], top[2], top[3], top[4] or 1))
  elseif tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", bottom[1], bottom[2], bottom[3], bottom[4] or 1,
      top[1], top[2], top[3], top[4] or 1)
  else
    tex:SetVertexColor((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, top[4] or 1)
  end
end

-- The fill of a button `height` units tall: three bands inside the outer
-- line (top third light, middle fading, bottom third dark) and the inner
-- line, a backdrop edge on a child frame just inside the outer one.
local function buttonFill(b, height)
  local T = ns.Theme
  local inset = T.sizes.buttonInset
  local band = math.max(1, (height - 2 * inset) / 3)
  local function tex()
    local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetTexture(T.textures.parchment)
    return t
  end
  local top, mid, bottom = tex(), tex(), tex()
  top:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
  top:SetPoint("TOPRIGHT", b, "TOPRIGHT", -inset, -inset)
  top:SetHeight(band)
  bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", inset, inset)
  bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
  bottom:SetHeight(band)
  mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
  mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
  local inner = CreateFrame("Frame", nil, b, "BackdropTemplate")
  inner:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
  inner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
  if inner.SetBackdrop then
    inner:SetBackdrop({ edgeFile = T.textures.buttonEdge, edgeSize = T.sizes.buttonEdge })
  end
  b.fill = { top = top, mid = mid, bottom = bottom, inner = inner }
  b.raise = false -- Raised style edge lines (raiseLines), made when first needed
end

-- The four 1 px edge lines of a Raised button, just inside its outer edge
-- (made the first time a button is drawn Raised).
local function raiseLines(b)
  if type(b.raise) == "table" then return b.raise end
  local T = ns.Theme
  local inset = T.sizes.buttonInset
  local px = Widgets.pixels(b, 1)
  local function tex() local t = b:CreateTexture(nil, "BACKGROUND", nil, 2); t:SetTexture(T.textures.buttonEdge); return t end
  local r = { top = tex(), left = tex(), bottom = tex(), right = tex() }
  r.top:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
  r.top:SetPoint("TOPRIGHT", b, "TOPRIGHT", -inset, -inset)
  r.top:SetHeight(px)
  r.bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", inset, inset)
  r.bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
  r.bottom:SetHeight(px)
  r.left:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
  r.left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", inset, inset)
  r.left:SetWidth(px)
  r.right:SetPoint("TOPRIGHT", b, "TOPRIGHT", -inset, -inset)
  r.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
  r.right:SetWidth(px)
  b.raise = r
  return r
end

local function showParts(parts, shown)
  if type(parts) ~= "table" then return end
  for _, region in pairs(parts) do region:SetShown(shown) end
end

function paint(b, state)
  b.look = state
  local c = Widgets.buttonColors(state, b.warn)
  local style = ns.Theme.style.buttons
  if b.SetBackdropColor and type(b.fill) == "table" and style ~= "bronze" then
    -- Raised / Flat: one fill and the edge color; Raised adds its edge lines.
    showParts(b.fill, false)
    b:SetBackdropColor(c.fill[1], c.fill[2], c.fill[3], c.fill[4] or 1)
    b:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4] or 1)
    if style == "raised" then
      local r = raiseLines(b)
      showParts(r, true)
      tint(r.top, c.light); tint(r.left, c.light)
      tint(r.bottom, c.dark); tint(r.right, c.dark)
    else
      showParts(b.raise, false)
    end
  elseif b.SetBackdropColor then
    if type(b.fill) == "table" then
      local f = b.fill
      showParts(f, true)
      showParts(b.raise, false)
      b:SetBackdropColor(c.bottom[1], c.bottom[2], c.bottom[3], c.bottom[4] or 1)
      b:SetBackdropBorderColor(c.outline[1], c.outline[2], c.outline[3], 1)
      tint(f.top, c.top)
      tint(f.bottom, c.bottom)
      setFade(f.mid, c.bottom, c.top)
      if f.inner.SetBackdropBorderColor then
        f.inner:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4] or 1)
      end
    else
      b:SetBackdropColor(c.fill[1], c.fill[2], c.fill[3], c.fill[4] or 1)
      b:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4] or 1)
    end
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
  -- Pressed while the mouse is held down; back to hover (still over it) or
  -- normal on release.
  b:SetScript("OnMouseDown", function(self)
    if not isDisabled(self) then paint(self, "pressed") end
  end)
  b:SetScript("OnMouseUp", function(self)
    local over = type(MouseIsOver) == "function" and MouseIsOver(self)
    paint(self, isDisabled(self) and "disabled" or (over and "hover" or "normal"))
  end)
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
  buttonFill(b, T.sizes.buttonHeight)
  local fs = b:CreateFontString(nil, "OVERLAY", T.fonts.button)
  -- Anchored to both sides so a long label is cut off inside the button.
  fs:SetPoint("LEFT", b, "LEFT", T.sizes.buttonTextPad, 0)
  fs:SetPoint("RIGHT", b, "RIGHT", -T.sizes.buttonTextPad, 0)
  fs:SetWordWrap(false)
  if b.SetFontString then b:SetFontString(fs) end
  b.label, b.glyph, b.onEnter, b.onLeave = fs, false, false, false
  b.kind, b.warn = "bronze", (opts and opts.warn) and true or false
  b:SetText(label or "")
  wireStates(b)
  return b
end

-- Pure. Width of a text button that fits its widest label: `base` (the theme
-- width), wider when one of `textWidths` (px) needs more with buttonTextPad on
-- both sides. Longer translations widen the button instead of being cut off.
function Widgets.fitWidth(base, textWidths)
  local pad = ns.Theme.sizes.buttonTextPad
  local w = tonumber(base) or 0
  for _, tw in ipairs(type(textWidths) == "table" and textWidths or {}) do
    if type(tw) == "number" and tw == tw and tw > 0 then w = math.max(w, math.ceil(tw + 2 * pad)) end
  end
  return w
end

-- The natural width of a FontString's text, also when its box is narrower.
function Widgets.textWidth(fs)
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(w) == "number" and w > 0 then return w end
  w = fs.GetStringWidth and fs:GetStringWidth()
  return type(w) == "number" and w or 0
end

-- Sizes text button `b` (Widgets.button) to its widest label of `texts`, at
-- least `base` px; the shown text stays. Call again after a font change.
function Widgets.fitButton(b, texts, base)
  local fs = b and b.label
  if not fs then return end
  local shown = fs.GetText and fs:GetText()
  local widths = {}
  for i, text in ipairs(texts) do
    fs:SetText(text)
    widths[i] = Widgets.textWidth(fs)
  end
  fs:SetText(type(shown) == "string" and shown or "")
  if not b.fitTexts then Widgets.fitted[#Widgets.fitted + 1] = b end
  b.fitTexts, b.fitBase = texts, base
  b:SetWidth(Widgets.fitWidth(base, widths))
end

-- Every button sized by fitButton, to fit again after a font change (Ledger.relayout).
Widgets.fitted = {}

function Widgets.refitButtons()
  for _, b in ipairs(Widgets.fitted) do Widgets.fitButton(b, b.fitTexts, b.fitBase) end
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
  buttonFill(b, size)
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
-- The border and background follow the skin (Theme.style): Round is the
-- backdrop's own tooltip edge; Bevel / Thin / Gilded are line rectangles on
-- the frame (frame.skinEdges, Theme.edgeRects) plus, for Gilded, a stud in
-- each corner (frame.skinStuds). Called again on a skin change: the regions
-- are made once and shown / hidden.
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local STUD_OFFSET = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function edgeRect(frame)
  local T = ns.Theme
  local function tex()
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(T.textures.rowHighlight)
    return t
  end
  return { top = tex(), bottom = tex(), left = tex(), right = tex() }
end

local function placeRect(frame, r, inset)
  local p = Widgets.pixelSize(frame) or 1
  local o, t = inset * p, p
  r.top:ClearAllPoints(); r.bottom:ClearAllPoints(); r.left:ClearAllPoints(); r.right:ClearAllPoints()
  r.top:SetPoint("TOPLEFT", frame, "TOPLEFT", o, -o); r.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -o, -o)
  r.top:SetHeight(t)
  r.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", o, o); r.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -o, o)
  r.bottom:SetHeight(t)
  r.left:SetPoint("TOPLEFT", frame, "TOPLEFT", o, -o); r.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", o, o)
  r.left:SetWidth(t)
  r.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -o, -o); r.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -o, o)
  r.right:SetWidth(t)
end

local function skinEdges(frame)
  local T = ns.Theme
  local border = T.style.border
  local rects = T.edgeRects(border)
  if type(frame.skinEdges) ~= "table" then frame.skinEdges = {} end
  local edges = frame.skinEdges
  for i, spec in ipairs(rects) do
    edges[i] = edges[i] or edgeRect(frame)
    edges[i].shade = spec.shade
    placeRect(frame, edges[i], spec.inset)
    showParts({ edges[i].top, edges[i].bottom, edges[i].left, edges[i].right }, true)
  end
  for i = #rects + 1, #edges do
    showParts({ edges[i].top, edges[i].bottom, edges[i].left, edges[i].right }, false)
  end
  local studs = T.edgeStuds(border)
  if studs and type(frame.skinStuds) ~= "table" then
    frame.skinStuds = {}
    for i, corner in ipairs(CORNERS) do
      local s = frame:CreateTexture(nil, "OVERLAY")
      -- SetTexture returns false when the file cannot be loaded: no stud then.
      s.loaded = s:SetTexture(T.textures.skinStud) ~= false
      s:SetSize(T.sizes.studSize, T.sizes.studSize)
      local off = STUD_OFFSET[corner]
      s:SetPoint("CENTER", frame, corner, off[1], off[2])
      frame.skinStuds[i] = s
    end
  end
  if type(frame.skinStuds) == "table" then
    for _, s in ipairs(frame.skinStuds) do s:SetShown(studs and s.loaded) end
  end
end

-- Colors the edge lines and studs of `frame` from `border` (the backdrop
-- border color with opacity / brightness already applied): each line its
-- shade of it, alpha kept.
function Widgets.paintEdges(frame, border)
  if type(frame) ~= "table" then return end
  local T = ns.Theme
  if type(frame.skinEdges) == "table" then
    for _, r in ipairs(frame.skinEdges) do
      local c = T.scaleColor(border, r.shade or 1)
      c[4] = border[4] or 1
      tint(r.top, c); tint(r.bottom, c); tint(r.left, c); tint(r.right, c)
    end
  end
  if type(frame.skinStuds) == "table" then
    for _, s in ipairs(frame.skinStuds) do tint(s, border) end
  end
end

function Widgets.applyBackdrop(frame, opaque)
  local T = ns.Theme
  frame:SetBackdrop(T.backdropSpec(T.style.border))
  skinEdges(frame)
  backdropColors(frame, opaque)
  tracked[frame] = { "backdrop", opaque and true or false }
end

-- ---------------------------------------------------------------------------
-- Styled lines (option "skinLines"): dividers and separators that follow the
-- Lines pick. Gold is one line in its color; Groove adds a light line right
-- under it; Plain is greyed toward the panel; Dotted tiles a dash texture.
-- Plain lines and bars that are not dividers stay Widgets.line.

local function styleRule(tex)
  local T = ns.Theme
  local t = tracked[tex]
  if not t then return end
  local color, alpha = t[2], t[3]
  local lines = T.style.lines
  local main, second = T.lineColors(lines, color, T.colors.panelTint)
  local dotted = false
  if lines == "dotted" then
    -- An addon texture tiled along the line with SetHorizTile.
    dotted = tex:SetTexture(T.textures.skinDotted, "REPEAT", "CLAMP") ~= false
  end
  if not dotted then tex:SetTexture(T.textures.rowHighlight) end
  if tex.SetHorizTile then tex:SetHorizTile(dotted) end
  tint(tex, main, alpha)
  if second then
    if not tex.groove then
      local g = tex.ruleParent:CreateTexture(nil, tex.ruleLayer)
      g:SetTexture(T.textures.rowHighlight)
      g:SetPoint("TOPLEFT", tex, "BOTTOMLEFT", 0, 0)
      g:SetPoint("TOPRIGHT", tex, "BOTTOMRIGHT", 0, 0)
      g:SetHeight(Widgets.pixels(tex, 1))
      tex.groove = g
    end
    tint(tex.groove, second, alpha)
    tex.groove:SetShown(tex:IsShown() ~= false)
  elseif tex.groove then
    tex.groove:Hide()
  end
end

Widgets.restyleRule = styleRule

-- Shows / hides a styled line with its groove line.
function Widgets.showRule(tex, shown)
  tex:SetShown(shown)
  if tex.groove then tex.groove:SetShown(shown and ns.Theme.style.lines == "groove") end
end

-- A horizontal divider line in a theme color that follows the Lines pick.
function Widgets.rule(parent, color, layer, alpha)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK")
  tex.ruleParent, tex.ruleLayer, tex.groove = parent, layer or "ARTWORK", false
  tracked[tex] = { "rule", color, alpha }
  styleRule(tex)
  return tex
end

-- ---------------------------------------------------------------------------
-- Skin changes: hooks of UI parts that draw something of their own (tabs,
-- the sunken list box), run after the shared regions are redrawn.
local skinHooks = {}

function Widgets.onSkin(fn)
  skinHooks[#skinHooks + 1] = fn
end

-- Redraws every backdrop, button and styled line in the current Theme.style,
-- runs the hooks, then the window look (opacity / brightness).
function Widgets.applySkin()
  for region, t in pairs(tracked) do
    local kind = t[1]
    if kind == "backdrop" then
      Widgets.applyBackdrop(region, t[2])
    elseif kind == "button" then
      paint(region, region.look or "normal")
    elseif kind == "rule" then
      styleRule(region)
    end
  end
  for _, fn in ipairs(skinHooks) do fn() end
  local Window = ns.UI.Window
  if Window and Window.applyLook then Window.applyLook() end
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
-- Adds the lines of a rich tooltip (ns.Tooltip) to the shown GameTooltip.
function Widgets.addTooltipLines(tip)
  if not GameTooltip then return end
  for _, o in ipairs(ns.Tooltip.render(tip)) do
    if o.op == "double" then
      local l, r = o.lc, o.rc
      GameTooltip:AddDoubleLine(o.left, o.right, l[1], l[2], l[3], r[1], r[2], r[3])
    else
      local c = o.color or ns.Theme.colors.tipValue
      GameTooltip:AddLine(o.text, c[1], c[2], c[3], o.wrap and true or false)
    end
  end
end

function Widgets.showTextTooltip(owner, text, anchor)
  text = ns.Tooltip.resolve(text)
  if not GameTooltip or not text then return false end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  if type(text) == "table" then
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    Widgets.addTooltipLines(text)
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
-- SetupColorPickerAndShow and GetColorRGB; the legacy fields (func,
-- cancelFunc) are the older fallback.
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

local CONFIRM = "ANOTHERLEDGER_CONFIRM"
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

-- Text popup: the shared dialog with an edit box, filled with `initial`;
-- `onAccept(text)` gets what was typed (Enter or the `accept` button).
-- The popup's edit box is GetEditBox() (newer clients) or the editBox /
-- EditBox field.
local PROMPT = "ANOTHERLEDGER_PROMPT"
Widgets.PROMPT_MAX_LETTERS = 60

local function popupEditBox(popup)
  if type(popup) ~= "table" then return nil end
  if type(popup.GetEditBox) == "function" then return popup:GetEditBox() end
  return popup.editBox or popup.EditBox
end

function Widgets.prompt(text, accept, initial, onAccept)
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
  local dialog = StaticPopupDialogs[PROMPT]
  if not dialog then
    dialog = { timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, button2 = L_CANCEL,
      hasEditBox = true, maxLetters = Widgets.PROMPT_MAX_LETTERS }
    dialog.OnShow = function(self)
      local box = popupEditBox(self)
      if box then
        box:SetText(dialog.initial or "")
        box:HighlightText()
      end
    end
    dialog.OnAccept = function(self)
      local box = popupEditBox(self)
      if dialog.onAccept then dialog.onAccept(box and box:GetText() or "") end
    end
    dialog.EditBoxOnEnterPressed = function(box)
      local popup = box:GetParent()
      if dialog.onAccept then dialog.onAccept(box:GetText() or "") end
      if popup then popup:Hide() end
    end
    dialog.EditBoxOnEscapePressed = function(box)
      local popup = box:GetParent()
      if popup then popup:Hide() end
    end
    StaticPopupDialogs[PROMPT] = dialog
  end
  dialog.text = text
  dialog.button1 = accept
  dialog.initial = initial
  dialog.onAccept = onAccept
  StaticPopup_Show(PROMPT)
  return true
end

-- ---------------------------------------------------------------------------
-- Context menu (feature-detected at call time)
--
-- entries = { { text, isChecked = function() -> bool, onClick = function(),
--   kind = (optional, else the menu's kind), title = true (a heading) }, ... }
-- kind = "checkbox" (independent toggles, the menu stays open), "radio"
-- (pick one, the menu closes) or "button" (an action, the menu closes).

local function entryKind(entry, kind)
  if entry.title then return "title" end
  return entry.kind or kind
end

local function notChecked() return false end

local function openModernMenu(anchor, entries, kind)
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    for _, entry in ipairs(entries) do
      local k = entryKind(entry, kind)
      -- The client menu calls isChecked for every radio / checkbox; a missing
      -- one is a "call a nil value" warning per entry.
      if type(entry.isChecked) ~= "function" then entry.isChecked = notChecked end
      if k == "title" then
        if root.CreateTitle then root:CreateTitle(entry.text) end
      elseif k == "checkbox" then
        root:CreateCheckbox(entry.text, entry.isChecked, function()
          entry.onClick()
          return MenuResponse and MenuResponse.Refresh or nil
        end)
      elseif k == "button" then
        root:CreateButton(entry.text, function() entry.onClick() end)
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
      local k = entryKind(entry, kind)
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.text
      if k == "title" then
        info.isTitle, info.notCheckable = true, true
      elseif k == "button" then
        info.notCheckable = true
        info.func = entry.onClick
      else
        info.checked = type(entry.isChecked) == "function" and entry.isChecked() or false
        info.func = entry.onClick
        if k == "checkbox" then
          info.isNotRadio = true
          info.keepShownOnClick = true
        end
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
