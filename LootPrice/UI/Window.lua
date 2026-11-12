local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Client-only module: every WoW global is touched inside functions only.
local Window = {}
ns.UI.Window = Window

local TITLE = "Session Ledger" -- single place to localize later
local TOPBOX_EMPTY = 0.001     -- zero-height frames anchor badly; keep a hair

local function theme() return ns.Theme end

local function winDB()
  local db = Window.db
  if not db then return nil end
  db.window = db.window or {}
  return db.window
end

-- Screen size expressed in the frame's own scale units.
local function screenSize(frame)
  local fs = frame:GetEffectiveScale()
  if not fs or fs == 0 then fs = 1 end
  local us = UIParent:GetEffectiveScale()
  return UIParent:GetWidth() * us / fs, UIParent:GetHeight() * us / fs
end

-- CENTER-relative offsets from the UIParent center, in the frame's scale units.
local function centerOffset(frame)
  local fx, fy = frame:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not fx or not ux then return nil end
  local fs = frame:GetEffectiveScale()
  if not fs or fs == 0 then fs = 1 end
  local us = UIParent:GetEffectiveScale()
  return (fx * fs - ux * us) / fs, (fy * fs - uy * us) / fs
end

-- Pure. Resize minimum width: the Theme minimum, raised (never lowered) to the
-- width the rows need with the measured font.
function Window.effectiveMinWidth(themeMin, required)
  if type(required) == "number" and required == required and required > themeMin then
    return required
  end
  return themeMin
end

local function minWidth()
  return Window.effectiveMinWidth(theme().sizes.minWidth, Window.requiredWidth)
end

local function applyBounds(frame)
  local T = theme()
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minWidth(), T.sizes.minHeight)
  elseif frame.SetMinResize then
    frame:SetMinResize(minWidth(), T.sizes.minHeight)
  end
end

local function clamp(v, lo, hi)
  if hi < lo then hi = lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function save()
  local frame, w = Window.frame, winDB()
  if not frame or not w then return end
  local x, y = centerOffset(frame)
  if x then
    w.point = "CENTER"
    w.x = x
    w.y = y
  end
  w.width = frame:GetWidth()
  w.height = frame:GetHeight()
  w.hidden = not frame:IsShown()
end

-- Pure. (x, y) = CENTER offset of a w x h window from the screen center on a
-- sw x sh screen. Returns the offset and size moved the shortest way back onto
-- the screen: a window that is only `tol` (default 1) px outside stays where it
-- is, and one larger than the screen shrinks to the screen size.
function Window.clampToScreen(x, y, w, h, sw, sh, tol)
  tol = tol or 1
  if w > sw then w = sw end
  if h > sh then h = sh end
  local maxX, maxY = (sw - w) / 2, (sh - h) / 2
  if x > maxX + tol then x = maxX elseif x < -maxX - tol then x = -maxX end
  if y > maxY + tol then y = maxY elseif y < -maxY - tol then y = -maxY end
  return x, y, w, h
end

-- Moves the frame back onto the screen (nearest valid position) when any part
-- of it lies outside; flush against an edge is fine.
local function ensureOnScreen(frame)
  local sw, sh = screenSize(frame)
  local x, y = centerOffset(frame)
  if not x then return end
  local w, h = frame:GetWidth(), frame:GetHeight()
  local nx, ny, nw, nh = Window.clampToScreen(x, y, w, h, sw, sh, 1)
  if nx ~= x or ny ~= y or nw ~= w or nh ~= h then
    frame:ClearAllPoints()
    frame:SetSize(nw, nh)
    frame:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
  end
end

local function restore(frame)
  local T = theme()
  local w = winDB() or {}
  local sw, sh = screenSize(frame)
  local width = clamp(tonumber(w.width) or 420, minWidth(), sw)
  local height = clamp(tonumber(w.height) or 360, T.sizes.minHeight, sh)
  frame:SetSize(width, height)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(w.x) or 0, tonumber(w.y) or 0)
  ensureOnScreen(frame)
end

local function makeRow(parent, anchorTo, firstRow)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(theme().sizes.headerRowHeight)
  if firstRow then
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  else
    row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, 0)
    row:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
  end
  return row
end

local function build(db)
  local T = theme()
  local inset = T.sizes.padding + 4

  local frame = CreateFrame("Frame", "LootPriceWindow", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetUserPlaced(false)
  frame:SetResizable(true)
  frame:EnableMouse(true)
  applyBounds(frame)

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
  local c = T.colors.panelTint
  frame:SetBackdropColor(c[1], c[2], c[3], c[4])
  local bc = T.colors.panelBorder
  frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])

  -- Header: two 28 px rows. Dragging the header moves the window.
  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(T.sizes.headerHeight)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false) -- db.window is the only position store
    save()
  end)
  header.row1 = makeRow(header, nil, true)
  header.row2 = makeRow(header, header.row1, false)

  local title = header.row1:CreateFontString(nil, "OVERLAY", T.fonts.title)
  title:SetPoint("LEFT", header.row1, "LEFT", 0, 0)
  title:SetText(TITLE)
  title:SetTextColor(T.colors.ink[1], T.colors.ink[2], T.colors.ink[3], T.colors.ink[4])
  header.title = title

  -- Optional top box (Top finds); collapsed until a later task sizes it.
  local topBox = CreateFrame("Frame", nil, frame)
  topBox:SetHeight(TOPBOX_EMPTY)
  topBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  topBox:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  topBox:Hide()

  local footer = CreateFrame("Frame", nil, frame)
  footer:SetHeight(T.sizes.footerHeight)
  footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
  footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)

  local listArea = CreateFrame("Frame", nil, frame)
  listArea:SetPoint("TOPLEFT", topBox, "BOTTOMLEFT", 0, 0)
  listArea:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
  listArea:SetClipsChildren(true)

  -- Resize grip, bottom right.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(T.sizes.gripSize, T.sizes.gripSize)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.sizes.gripInset, T.sizes.gripInset)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture(T.textures.resizeGrip)
  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    -- StartSizing leaves the frame anchored on a corner; normalize to CENTER.
    local x, y = centerOffset(frame)
    if x then
      local w, h = frame:GetWidth(), frame:GetHeight()
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
      frame:SetSize(w, h)
    end
    save()
  end)

  frame:RegisterEvent("UI_SCALE_CHANGED")
  frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
  frame:SetScript("OnEvent", function(self) ensureOnScreen(self) end)

  frame.header = header
  frame.topBox = topBox
  frame.listArea = listArea
  frame.footer = footer
  frame.grip = grip

  Window.db = db
  restore(frame)
  local w = winDB()
  frame:SetShown(not (w and w.hidden))
  return frame
end

-- Creates the window once; later calls return the same frame.
function Window.create(db)
  if db then Window.db = db end
  if Window.frame then return Window.frame end
  if not Window.db then return nil end
  Window.frame = build(Window.db)
  return Window.frame
end

-- Raises the resize minimum to what the measured rows need (never below the
-- Theme minimum) and widens the window when it is currently narrower.
function Window.setMinWidth(required)
  Window.requiredWidth = required
  local frame = Window.frame
  if not frame then return end
  applyBounds(frame)
  local min = minWidth()
  if frame:GetWidth() < min then
    frame:SetWidth(min)
    ensureOnScreen(frame)
    save()
  end
end

-- Resizes the Top finds box; 0 collapses it. listArea reflows by anchoring.
function Window.setTopBoxHeight(h)
  local frame = Window.frame
  if not frame then return end
  h = tonumber(h) or 0
  if h <= 0 then
    frame.topBox:SetHeight(TOPBOX_EMPTY)
    frame.topBox:Hide()
  else
    frame.topBox:SetHeight(h)
    frame.topBox:Show()
  end
end

local function ensure()
  return Window.frame or Window.create(Window.db or ns.db)
end

function Window.show()
  local frame = ensure()
  if not frame then return end
  frame:Show()
  save()
end

function Window.hide()
  local frame = ensure()
  if not frame then return end
  frame:Hide()
  save()
end

function Window.toggle()
  local frame = ensure()
  if not frame then return end
  if frame:IsShown() then Window.hide() else Window.show() end
end

function Window.isShown()
  return Window.frame ~= nil and Window.frame:IsShown() or false
end
