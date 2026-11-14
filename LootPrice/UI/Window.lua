local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Client-only module: every WoW global is touched inside functions only.
local Window = {}
ns.UI.Window = Window

local TITLE = L["Session Ledger"]
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

-- Pure. A theme color with its alpha scaled by `scale` (0..1).
function Window.scaledColor(c, scale)
  local a = c[4] or 1
  if type(scale) ~= "number" or scale ~= scale then scale = 1 end
  scale = math.min(1, math.max(0, scale))
  return { c[1], c[2], c[3], a * scale }
end

-- Opacity and brightness of the window background and border (options
-- "alpha" / "brightness"); text and rows are not touched.
function Window.applyLook()
  local frame = Window.frame
  if not frame then return end
  local T = theme()
  local alpha, k = 1, 1
  if ns.Options and ns.db then
    alpha = ns.Options.get(ns.db, "alpha") or 1
    k = ns.Options.get(ns.db, "brightness") or 1
  end
  local bg = Window.scaledColor(T.scaleColor(T.colors.panelTint, k), alpha)
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
  local bd = Window.scaledColor(T.scaleColor(T.colors.panelBorder, k), alpha)
  frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
end

local function applyBounds(frame)
  local T = theme()
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minWidth(), T.sizes.minHeight)
  elseif frame.SetMinResize then
    frame:SetMinResize(minWidth(), T.sizes.minHeight)
  end
end

local clamp = ns.Util.clamp

-- Option "lockWindow": no moving, no resizing.
local function locked()
  return ns.Options ~= nil and ns.db ~= nil and ns.Options.get(ns.db, "lockWindow") == true
end

local function scaleSetting()
  if ns.Options and ns.db then return ns.Options.get(ns.db, "windowScale") or 1 end
  return 1
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
  local height = clamp(tonumber(w.height) or 440, T.sizes.minHeight, sh)
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

  ns.UI.Widgets.applyBackdrop(frame)

  -- Header: three 28 px rows (title and buttons, filters, tabs). Dragging the
  -- header moves the window.
  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(T.sizes.headerHeight)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    if not locked() then frame:StartMoving() end
  end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false) -- db.window is the only position store
    save()
  end)
  header.row1 = makeRow(header, nil, true)
  header.row2 = makeRow(header, header.row1, false)
  header.row3 = makeRow(header, header.row2, false)

  local title = ns.UI.Widgets.text(header.row1, T.fonts.title, T.colors.ink)
  title:SetPoint("LEFT", header.row1, "LEFT", 0, 0)
  title:SetText(TITLE)
  header.title = title

  -- Top finds box at the very bottom, under the summaries; collapsed (hidden,
  -- ~0 high) until Summary sizes it. Stack from the bottom: topBox, footer
  -- (the three summaries), list area, header.
  local topBox = CreateFrame("Frame", nil, frame)
  topBox:SetHeight(TOPBOX_EMPTY)
  topBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
  topBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  topBox:Hide()

  local footer = CreateFrame("Frame", nil, frame)
  footer:SetHeight(T.sizes.footerHeight)
  footer:SetPoint("BOTTOMLEFT", topBox, "TOPLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", topBox, "TOPRIGHT", 0, 0)

  local listArea = CreateFrame("Frame", nil, frame)
  listArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  listArea:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
  listArea:SetClipsChildren(true)

  -- Resize grip, bottom right.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(T.sizes.gripSize, T.sizes.gripSize)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.sizes.gripInset, T.sizes.gripInset)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture(T.textures.resizeGrip)
  grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and not locked() then frame:StartSizing("BOTTOMRIGHT") end
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
  -- The scale first: the saved position and size are in the scaled units.
  frame:SetScale(scaleSetting())
  restore(frame)
  local w = winDB()
  local startHidden = ns.Options ~= nil and ns.Options.get(db, "startHidden") == true
  frame:SetShown(not ((w and w.hidden) or startHidden))
  return frame
end

-- Option "windowScale": rescales the window and keeps its center where it is
-- on the screen.
function Window.applyScale()
  local frame = Window.frame
  if not frame then return end
  local scale = scaleSetting()
  local old = frame:GetScale()
  if not old or old == 0 then old = 1 end
  if math.abs(old - scale) < 0.0001 then return end
  local x, y = centerOffset(frame)
  frame:SetScale(scale)
  if x then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x * old / scale, y * old / scale)
  end
  ensureOnScreen(frame)
  save()
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

function Window.setTitle(text)
  local frame = Window.frame
  if frame and frame.header and frame.header.title then frame.header.title:SetText(text) end
end

-- Height of the footer (the summaries); the list area reflows by anchoring.
function Window.setFooterHeight(h)
  local frame = Window.frame
  if not frame then return end
  frame.footer:SetHeight(tonumber(h) or ns.Theme.sizes.footerHeight)
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

-- Combat auto hide: remembers that the window was hidden by combat, so only
-- that case is shown again afterwards. The saved hidden flag is not touched.
function Window.combatHide()
  local frame = Window.frame
  if not frame or not frame:IsShown() then return end
  Window.hiddenByCombat = true
  frame:Hide()
end

function Window.combatShow()
  local frame = Window.frame
  if not Window.hiddenByCombat then return end
  Window.hiddenByCombat = false
  if frame then frame:Show() end
end

function Window.show()
  local frame = ensure()
  if not frame then return end
  Window.hiddenByCombat = false
  frame:Show()
  save()
end

function Window.hide()
  local frame = ensure()
  if not frame then return end
  Window.hiddenByCombat = false
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
