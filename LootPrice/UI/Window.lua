local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Client-only module: every WoW global is touched inside functions only.
local Window = {}
ns.UI.Window = Window

local TITLE = L["Session Ledger"]
local TOPBOX_EMPTY = 0.001     -- zero-height frames anchor badly; keep a hair
local COLLAPSED_ROW = TOPBOX_EMPTY -- height of the hidden Daily farm row

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

-- Layout mode: "full" (the ledger) or "compact" (the glance). Ledger.setMode
-- switches it through Window.applyMode.
Window.MODES = { full = true, compact = true }
Window.mode = "full"

local function compact() return Window.mode == "compact" end

local function minWidth()
  if compact() then return theme().sizes.compactMinWidth end
  return Window.effectiveMinWidth(theme().sizes.minWidth, Window.requiredWidth)
end

local function minHeight()
  local S = theme().sizes
  return compact() and S.compactMinHeight or S.minHeight
end

-- Pure. A theme color with its alpha scaled by `scale` (0..1).
function Window.scaledColor(c, scale)
  local a = c[4] or 1
  if type(scale) ~= "number" or scale ~= scale then scale = 1 end
  scale = math.min(1, math.max(0, scale))
  return { c[1], c[2], c[3], a * scale }
end

-- Opacity and brightness (options "alpha" / "brightness") of the background
-- and border of `frame`; text and rows are not touched.
function Window.paintLook(frame)
  if not frame or not frame.SetBackdropColor then return end
  local T = theme()
  local alpha, k = ns.Util.setting("alpha", 1), ns.Util.setting("brightness", 1)
  local bg = Window.scaledColor(T.scaleColor(T.colors.panelTint, k), alpha)
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
  local bd = Window.scaledColor(T.scaleColor(T.colors.panelBorder, k), alpha)
  frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
end

-- The ledger window and the options panel share one background look.
function Window.applyLook()
  Window.paintLook(Window.frame)
  local P = ns.UI.OptionsPanel
  if P then Window.paintLook(P.frame) end
end

local function applyBounds(frame)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minWidth(), minHeight())
  elseif frame.SetMinResize then
    frame:SetMinResize(minWidth(), minHeight())
  end
end

-- The saved size of the current mode: db.window.width / height for full,
-- db.window.compact for compact.
local function sizeSlot(w)
  if not compact() then return w end
  if type(w.compact) ~= "table" then w.compact = {} end
  return w.compact
end

local clamp = ns.Util.clamp

-- Option "lockWindow": no moving, no resizing.
local function locked()
  return ns.Util.setting("lockWindow", false) == true
end

local function scaleSetting()
  return ns.Util.setting("windowScale", 1)
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
  local slot = sizeSlot(w)
  slot.width = frame:GetWidth()
  slot.height = frame:GetHeight()
  -- Hidden only for combat (combat hide): keep the player's own state.
  if not Window.hiddenByCombat then w.hidden = not frame:IsShown() end
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

-- The current mode's saved size, clamped to its minimum and the screen.
local function modeSize(frame)
  local S = theme().sizes
  local w = winDB() or {}
  local slot = compact() and (type(w.compact) == "table" and w.compact or {}) or w
  local sw, sh = screenSize(frame)
  local defaults = ns.DB.defaults.window
  local dw, dh = defaults.width, defaults.height
  if compact() then dw, dh = S.compactWidth, S.compactHeight end
  return clamp(tonumber(slot.width) or dw, minWidth(), sw), clamp(tonumber(slot.height) or dh, minHeight(), sh)
end

local function restore(frame)
  local w = winDB() or {}
  frame:SetSize(modeSize(frame))
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(w.x) or 0, tonumber(w.y) or 0)
  ensureOnScreen(frame)
end

-- Pure. One axis of Window.snapToGrid: `pos` = center offset, `half` = half
-- the size. Moves the edge or center nearest to a grid line (a multiple of
-- `spacing` from the screen center) onto it, if that is at most `dist` away.
local function snapAxis(pos, half, spacing, dist)
  local best
  for _, c in ipairs({ pos - half, pos, pos + half }) do
    local d = math.floor(c / spacing + 0.5) * spacing - c
    if not best or math.abs(d) < math.abs(best) then best = d end
  end
  if math.abs(best) <= dist then return pos + best end
  return pos
end

-- Pure. (x, y) = CENTER offset of a w x h window from the screen center. The
-- Edit Mode grid has lines through the screen center and every `spacing` from
-- it; each axis snaps its nearest edge or center onto a line within `dist`.
-- Returns the (maybe) moved offset; no valid spacing = unchanged.
function Window.snapToGrid(x, y, w, h, spacing, dist)
  if type(spacing) ~= "number" or spacing ~= spacing or spacing <= 0 then return x, y end
  dist = dist or 0
  return snapAxis(x, w / 2, spacing, dist), snapAxis(y, h / 2, spacing, dist)
end

-- Spacing of the Edit Mode grid in UIParent units, or nil when unknown.
-- EditModeManagerFrame.Grid.gridSpacing, else
-- EditModeManagerFrame:GetAccountSettingValue(Enum.EditModeAccountSetting.GridSpacing).
local function gridSpacing()
  local em = EditModeManagerFrame
  if type(em) ~= "table" then return nil end
  local s = type(em.Grid) == "table" and em.Grid.gridSpacing
  if type(s) ~= "number" and type(em.GetAccountSettingValue) == "function"
    and type(Enum) == "table" and type(Enum.EditModeAccountSetting) == "table"
    and Enum.EditModeAccountSetting.GridSpacing ~= nil then
    local ok, v = pcall(em.GetAccountSettingValue, em, Enum.EditModeAccountSetting.GridSpacing)
    if ok then s = v end
  end
  if type(s) == "number" and s > 0 then return s end
  return nil
end

-- Option "snapToGrid": after a drag, snap the window onto the Edit Mode grid.
local function snapFrame(frame)
  if not ns.Util.setting("snapToGrid", false) then return end
  local spacing = gridSpacing()
  local x, y = centerOffset(frame)
  if not spacing or not x then return end
  -- The grid is in UIParent units, the offsets in the frame's own (scaled) units.
  local fs = frame:GetEffectiveScale()
  if not fs or fs == 0 then fs = 1 end
  local k = UIParent:GetEffectiveScale() / fs
  local nx, ny = Window.snapToGrid(x, y, frame:GetWidth(), frame:GetHeight(),
    spacing * k, theme().sizes.gridSnapDistance * k)
  if nx ~= x or ny ~= y then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
    ensureOnScreen(frame)
  end
end

-- Dragging the header (or a header part that catches the mouse, like the
-- Daily farm strip) moves the window unless it is locked.
function Window.beginDrag()
  local frame = Window.frame
  if frame and not locked() then frame:StartMoving() end
end

function Window.endDrag()
  local frame = Window.frame
  if not frame then return end
  frame:StopMovingOrSizing()
  frame:SetUserPlaced(false) -- db.window is the only position store
  snapFrame(frame)
  save()
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

  -- Header rows: row1 title and buttons, row2 filters, rowFarm the Daily
  -- strip (optional), row3 tabs, row4 sub-tabs (optional). Dragging the header
  -- moves the window.
  local header = CreateFrame("Frame", nil, frame)
  header:SetHeight(T.sizes.headerHeight)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", Window.beginDrag)
  header:SetScript("OnDragStop", Window.endDrag)
  header.row1 = makeRow(header, nil, true)
  header.row2 = makeRow(header, header.row1, false)
  -- Daily farm strip between the filters and the tabs, only while there is a
  -- pick (Window.setFarmRow); collapsed to (almost) no height while hidden.
  header.rowFarm = makeRow(header, header.row2, false)
  header.rowFarm:SetHeight(COLLAPSED_ROW)
  header.rowFarm:Hide()
  header.row3 = makeRow(header, header.rowFarm, false)
  -- Row 4: sub-tabs (History: Sessions / Zones), only while the shown tab has
  -- them (Window.setSubtabRow).
  header.row4 = makeRow(header, header.row3, false)
  header.row4:Hide()

  local title = ns.UI.Widgets.text(header.row1, T.fonts.title, T.colors.ink)
  title:SetPoint("LEFT", header.row1, "LEFT", 0, 0)
  title:SetText(TITLE)
  header.title = title

  -- Double-clicking the title switches full / compact (Window.onTitleDoubleClick,
  -- set by the Ledger); dragging it still moves the window.
  -- OnDoubleClick does not fire after a drag.
  local titleButton = CreateFrame("Button", nil, header.row1)
  titleButton:SetPoint("TOPLEFT", header.row1, "TOPLEFT", 0, 0)
  titleButton:SetSize(T.sizes.titleButtonWidth, T.sizes.headerRowHeight)
  titleButton:RegisterForClicks("LeftButtonUp")
  titleButton:RegisterForDrag("LeftButton")
  titleButton:SetScript("OnDoubleClick", function()
    if Window.onTitleDoubleClick then Window.onTitleDoubleClick() end
  end)
  titleButton:SetScript("OnDragStart", function() Window.beginDrag() end)
  titleButton:SetScript("OnDragStop", function() Window.endDrag() end)
  header.titleButton = titleButton

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

  -- Compact mode body (UI/Compact.lua): under the title row, hidden in full.
  local compactArea = CreateFrame("Frame", nil, frame)
  compactArea:SetPoint("TOPLEFT", header.row1, "BOTTOMLEFT", 0, -T.sizes.padding / 2)
  compactArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  compactArea:SetClipsChildren(true)
  compactArea:Hide()

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
  frame.compact = compactArea
  grip:SetShown(not locked())

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

-- Option "lockWindow": the resize grip only shows while the window can be resized.
function Window.applyLock()
  local frame = Window.frame
  if frame and frame.grip then frame.grip:SetShown(not locked()) end
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

-- Theme.sizes changed (font size options): new resize bounds, and a window
-- that is now below the minimum grows to it.
function Window.applySizes()
  local frame = Window.frame
  if not frame then return end
  applyBounds(frame)
  local w, h = frame:GetWidth(), frame:GetHeight()
  local nw, nh = math.max(w, minWidth()), math.max(h, minHeight())
  if nw ~= w or nh ~= h then
    frame:SetSize(nw, nh)
    ensureOnScreen(frame)
    save()
  end
end

-- The optional parts shown right now: sub-tab row, Daily farm row, Top finds.
local optionalRows = { subtab = false, farm = false, topBox = false }

-- Pure. Which parts of the window a mode shows. Full: the filter and tab rows,
-- list and footer (the Daily farm row, sub-tab row and Top finds follow their
-- own setters); compact: only the compact body.
function Window.modeParts(mode)
  if mode == "compact" then
    return { row2 = false, rowFarm = false, row3 = false, row4 = false, listArea = false, footer = false,
      topBox = false, compact = true }
  end
  return { row2 = true, row3 = true, listArea = true, footer = true, compact = false }
end

-- Pure. Header height: the three fixed rows plus each optional row shown;
-- compact mode has the title row only.
function Window.headerHeight(subtab, farm, mode)
  local S = theme().sizes
  if mode == "compact" then return S.headerRowHeight end
  local h = S.headerHeight
  if subtab then h = h + S.headerRowHeight end
  if farm then h = h + S.headerRowHeight end
  return h
end

local function applyHeaderHeight()
  local frame = Window.frame
  if not (frame and frame.header) then return end
  frame.header:SetHeight(Window.headerHeight(optionalRows.subtab, optionalRows.farm, Window.mode))
end

-- Shows or hides header row 4 (sub-tabs); the list area below the header
-- follows by anchoring.
function Window.setSubtabRow(shown)
  local frame = Window.frame
  if not (frame and frame.header and frame.header.row4) then return end
  optionalRows.subtab = shown and true or false
  frame.header.row4:SetShown(optionalRows.subtab and not compact())
  applyHeaderHeight()
end

-- Shows or hides the Daily farm row (between the filters and the tabs).
function Window.setFarmRow(shown)
  local frame = Window.frame
  if not (frame and frame.header and frame.header.rowFarm) then return end
  optionalRows.farm = shown and true or false
  local row = frame.header.rowFarm
  row:SetHeight(optionalRows.farm and theme().sizes.headerRowHeight or COLLAPSED_ROW)
  row:SetShown(optionalRows.farm and not compact())
  applyHeaderHeight()
end

-- Switches the layout mode: the old mode's size is saved, the new mode's size
-- and minimum applied, the parts shown / hidden. Position stays.
function Window.applyMode(mode)
  if not Window.MODES[mode] then mode = "full" end
  local frame = Window.frame
  if not frame then
    Window.mode = mode
    return
  end
  if mode ~= Window.mode then save() end
  Window.mode = mode
  applyBounds(frame)
  frame:SetSize(modeSize(frame))
  local parts = Window.modeParts(mode)
  local full = mode == "full"
  local h = frame.header
  h.row2:SetShown(parts.row2)
  h.row3:SetShown(parts.row3)
  h.rowFarm:SetShown(full and optionalRows.farm)
  h.row4:SetShown(full and optionalRows.subtab)
  frame.listArea:SetShown(parts.listArea)
  frame.footer:SetShown(parts.footer)
  frame.topBox:SetShown(full and optionalRows.topBox)
  frame.compact:SetShown(parts.compact)
  applyHeaderHeight()
  ensureOnScreen(frame)
  save()
end

function Window.setTitle(text)
  local frame = Window.frame
  if frame and frame.header and frame.header.title then frame.header.title:SetText(text) end
end

-- Height of the footer (the summaries); the list area reflows by anchoring.
function Window.setFooterHeight(h)
  local frame = Window.frame
  if not frame then return end
  h = tonumber(h) or ns.Theme.sizes.footerHeight
  -- No footer (History, Zones): a hair, not 0, or the list anchored on it
  -- does not draw (zero-height frames anchor badly).
  frame.footer:SetHeight(h > 0 and h or TOPBOX_EMPTY)
end

-- Resizes the Top finds box; 0 collapses it. listArea reflows by anchoring.
function Window.setTopBoxHeight(h)
  local frame = Window.frame
  if not frame then return end
  h = tonumber(h) or 0
  optionalRows.topBox = h > 0
  if h <= 0 then
    frame.topBox:SetHeight(TOPBOX_EMPTY)
    frame.topBox:Hide()
  else
    frame.topBox:SetHeight(h)
    frame.topBox:SetShown(not compact())
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
