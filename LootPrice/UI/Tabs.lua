local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Tab registry and the tab buttons of header row 3. The ledger never names a
-- tab: it asks the selected tab's spec for its view. A new tab is one
-- Tabs.define call:
--
--   Tabs.define({
--     key   = "bags",                -- saved in db.tab
--     label = L["Bags"],                -- button text
--     title = L["Bag Ledger"],          -- window title while selected
--     build = function(ctx) return view end, -- see View.lua for the view shape
--     sessionControls = false,       -- show the clock and Start / Stop / Reset
--     ticks   = false,               -- per-hour rates change with the clock
--     watches = "bags",              -- data kind whose change redraws the tab
--     invalidate = function() end,   -- optional: drop cached data of `watches`
--     hasItem = function(itemID, ctx) return bool end, -- is the item listed?
--     sorts = { "ah", ... },         -- optional: the sorts the view offers
--     subtabs = { { key, label, build, hasItem?, sorts? }, ... }, -- optional:
--       a second tab row while this tab is shown; the first is the default and
--       the selected one builds the view (saved in db.subtab[key]).
--   })
--
-- ctx = { now, env, session, chardb, opts (View options), ledger,
--   zoneHistory = function() -> the History list Zones reads }.
-- valid, label and title are pure; attach is client-only.
local Tabs = {}
ns.UI.Tabs = Tabs

Tabs.KEYS = {} -- tab keys in display order
Tabs.DEFAULT = "session"

local specs = {}

function Tabs.define(spec)
  assert(type(spec) == "table" and type(spec.key) == "string", "tab needs a key")
  assert(type(spec.build) == "function", "tab needs a build function")
  if not specs[spec.key] then Tabs.KEYS[#Tabs.KEYS + 1] = spec.key end
  specs[spec.key] = spec
  return spec
end

-- The spec of a tab; an unknown key gives the default tab.
function Tabs.get(key)
  return specs[key] or specs[Tabs.DEFAULT]
end

function Tabs.valid(key)
  return specs[key] ~= nil
end

function Tabs.label(key)
  return Tabs.get(key).label
end

function Tabs.title(key)
  return Tabs.get(key).title
end

-- Sub-tabs of a tab, or nil.
function Tabs.subtabs(key)
  local spec = specs[key]
  return spec and type(spec.subtabs) == "table" and #spec.subtabs > 0 and spec.subtabs or nil
end

-- The sub-tab `subKey` of tab `key` (unknown -> its first), or nil without sub-tabs.
function Tabs.subtab(key, subKey)
  local list = Tabs.subtabs(key)
  if not list then return nil end
  for _, sub in ipairs(list) do
    if sub.key == subKey then return sub end
  end
  return list[1]
end

-- What builds the view of tab `key`: its selected sub-tab, else the tab.
local function viewSpec(key, subKey)
  return Tabs.subtab(key, subKey) or Tabs.get(key)
end

function Tabs.build(key, subKey, ctx)
  return viewSpec(key, subKey).build(ctx)
end

-- The hasItem check of the shown view, or nil (every item counts).
function Tabs.hasItemFn(key, subKey)
  return viewSpec(key, subKey).hasItem
end

-- The sorts the shown view offers, or nil (FilterBar.SORTS).
function Tabs.sorts(key, subKey)
  return viewSpec(key, subKey).sorts
end

-- Drops the cached data of every tab watching `what` ("bags", "bank", ...).
function Tabs.invalidate(what)
  for _, key in ipairs(Tabs.KEYS) do
    local spec = specs[key]
    if spec.watches == what and spec.invalidate then spec.invalidate() end
  end
end

-- ---------------------------------------------------------------------------
-- Built-in tabs

-- Session: the loot of the running session.
Tabs.define({
  key = "session", label = L["Session"], title = L["Session Ledger"],
  sessionControls = true,
  ticks = true,
  build = function(ctx) return ns.View.build(ctx.session, ctx.opts) end,
  hasItem = function(itemID, ctx) return ns.Session.hasItemID(ctx.session.items, itemID) end,
})

-- Bags: live bag contents, scanned again only after the bags changed.
local bagItems
Tabs.define({
  key = "bags", label = L["Bags"], title = L["Bag Ledger"],
  watches = "bags",
  invalidate = function() bagItems = nil end,
  build = function(ctx)
    if not bagItems then bagItems = ns.Inventory.scanBags(ctx.env, ctx.now) end
    local view = ns.View.buildInventory(bagItems, ctx.opts)
    view.empty = ns.View.emptyText(view.rows, ctx.opts.filter, L["Your bags are empty."])
    return view
  end,
  hasItem = function(itemID) return bagItems ~= nil and ns.Session.hasItemID(bagItems, itemID) end,
})

-- Bank: the last saved scan (Core scans while the bank window is open).
local function savedBank(ctx)
  local bank = ctx.chardb and ctx.chardb.bank
  return type(bank) == "table" and bank or nil
end

Tabs.define({
  key = "bank", label = L["Bank"], title = L["Bank Ledger"],
  watches = "bank",
  build = function(ctx)
    local bank = savedBank(ctx)
    local view = ns.View.buildInventory(bank and bank.items or {}, ctx.opts)
    local hours = ns.Util.setting("staleHours", nil)
    view.note, view.noteStale = ns.Inventory.scanNote(ctx.now, bank and bank.scannedAt, hours and hours * 3600)
    view.empty = ns.View.emptyText(view.rows, ctx.opts.filter,
      bank and L["Your bank is empty."] or L["Open your bank once to scan it."])
    return view
  end,
  hasItem = function(itemID, ctx)
    local bank = savedBank(ctx)
    return bank ~= nil and ns.Session.hasItemID(bank.items, itemID)
  end,
})

-- History: archived sessions; the opened one (ledger.historyIndex) lists its items.
local function savedHistory(ctx)
  local history = ctx.chardb and ctx.chardb.history
  return type(history) == "table" and history or {}
end

local function buildSessions(ctx)
  local history, ledger = savedHistory(ctx), ctx.ledger
  if ledger.historyIndex and not history[ledger.historyIndex] then ledger.historyIndex = nil end
  return ns.View.buildHistory(history, ctx.opts, ledger.historyIndex)
end

local function sessionsHasItem(itemID, ctx)
  local entry = savedHistory(ctx)[ctx.ledger.historyIndex or 0]
  return type(entry) == "table" and ns.Session.hasItemID(entry.items, itemID)
end

-- Zones: every saved session (of every character with the option
-- "accountZones", ctx.zoneHistory) plus the running one (with its open stretch).
local function zoneEntries(ctx)
  local entries = {}
  local saved = ctx.zoneHistory and ctx.zoneHistory() or savedHistory(ctx)
  for i, e in ipairs(saved) do entries[i] = e end
  local s = ctx.session
  if type(s) == "table" then
    entries[#entries + 1] = { live = true, items = s.items, places = s.places, gold = s.gold,
      zones = ns.Session.zoneSnapshot(s, ctx.now) }
  end
  return entries
end

Tabs.define({
  key = "history", label = L["History"], title = L["Session History"],
  build = buildSessions,
  hasItem = sessionsHasItem,
  subtabs = {
    { key = "sessions", label = L["Sessions"], build = buildSessions, hasItem = sessionsHasItem,
      sorts = { "ah", "recent", "perHour" } }, -- the sorts View.buildHistory knows
    {
      key = "zones", label = L["Zones"],
      sorts = { "ah", "perHour", "vendor", "name", "recent" },
      build = function(ctx)
        local ledger = ctx.ledger
        if type(ledger.zoneOpen) ~= "table" then ledger.zoneOpen = {} end
        return ns.View.buildZones(zoneEntries(ctx), ctx.opts, ledger.zoneOpen)
      end,
      hasItem = function(itemID, ctx)
        for _, e in ipairs(zoneEntries(ctx)) do
          if type(e) == "table" and ns.Session.hasItemID(e.items, itemID) then return true end
        end
        return false
      end,
    },
  },
})

-- ---------------------------------------------------------------------------
-- Buttons

-- Pure. Colors of a tab button: { border, text, glow }. No fill: the tab shows
-- the window background behind it (its opacity and brightness options). The
-- selected tab has the gold edge and glow; hovering lights the edge of the others.
function Tabs.look(selected, hovered)
  local c = ns.Theme.colors
  if selected then
    return { border = c.tabBorderSelected, text = c.tabTextSelected, glow = true }
  end
  return { border = hovered and c.tabBorderHover or c.tabBorder, text = c.tabText, glow = false }
end

-- Vertical gold glow from the top edge of `tex` (opaque) to transparent below.
-- Texture:SetGradient with CreateColor (retail); SetGradientAlpha is the older
-- signature.
local function setGlow(tex, c)
  if tex.SetGradient and CreateColor then
    tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], c[4]))
  elseif tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", c[1], c[2], c[3], 0, c[1], c[2], c[3], c[4])
  else
    tex:SetVertexColor(c[1], c[2], c[3], c[4] / 2)
  end
end

-- Inset of the visible edge line inside the tab's frame (the edge texture
-- draws its line a little inside its own square).
local function edgeInset()
  return math.floor(ns.Theme.sizes.tabEdge / 4)
end

-- Pure. Width of a tab button: Theme.widths.tab, wider when the label needs it
-- (`textW` = measured label width; nil or 0 keeps the theme width).
function Tabs.buttonWidth(textW)
  local T = ns.Theme
  local w = T.widths.tab
  if type(textW) == "number" and textW == textW and textW > 0 then
    w = math.max(w, math.ceil(textW + 2 * T.sizes.tabTextPad))
  end
  return w
end

-- One tab, open at the bottom: the button clips its children, and the edge
-- (a backdrop with no fill on the `skin` frame) is tabEdge px taller than the
-- button, so its bottom edge is cut off. A centered label and the glow of the
-- selected tab sit on the skin.
local function makeTab(row, label)
  local T, W = ns.Theme, ns.UI.Widgets
  local S = T.sizes
  local b = CreateFrame("Button", nil, row)
  b:SetClipsChildren(true)
  local skin = CreateFrame("Frame", nil, b, "BackdropTemplate")
  skin:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  skin:EnableMouse(false)
  local inset = edgeInset()
  skin:SetBackdrop({
    edgeFile = T.textures.tabBorder,
    edgeSize = S.tabEdge,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
  b.skin = skin
  local glow = skin:CreateTexture(nil, "ARTWORK")
  glow:SetTexture(T.textures.rowHighlight)
  glow:SetPoint("TOPLEFT", skin, "TOPLEFT", inset, -inset)
  glow:SetPoint("TOPRIGHT", skin, "TOPRIGHT", -inset, -inset)
  glow:SetHeight(S.tabGlowHeight)
  setGlow(glow, T.colors.tabGlow)
  glow:Hide()
  b.glow = glow
  local text = W.text(skin, T.fonts.tab, T.colors.tabText, "CENTER")
  text:SetPoint("CENTER", b, "CENTER", 0, 0)
  text:SetText(label)
  b.label = text
  local width = Tabs.buttonWidth(text:GetStringWidth())
  b:SetSize(width, S.tabHeight)
  skin:SetSize(width, S.tabHeight + S.tabEdge)
  b.isSelected, b.isHovered = false, false

  function b:ApplyLook()
    local look = Tabs.look(self.isSelected, self.isHovered)
    self.skin:SetBackdropBorderColor(look.border[1], look.border[2], look.border[3], look.border[4])
    W.setTextColor(self.label, look.text)
    self.glow:SetShown(look.glow)
  end
  b:SetScript("OnEnter", function(self) self.isHovered = true; self:ApplyLook() end)
  b:SetScript("OnLeave", function(self) self.isHovered = false; self:ApplyLook() end)
  b:ApplyLook()
  return b
end

-- A strip of tab buttons in `row`: `items` = { { key, label }, ... } in order;
-- `onSelect(key)` is called when another tab's button is clicked. Returns an
-- object with SetSelected(key). The tabs stand on a line along the bottom of the
-- row; the line is open below the selected tab (baseLeft up to it, baseRight
-- after it). Used by the ledger (Tabs.attach) and the options panel.
function Tabs.strip(row, items, onSelect)
  local T, W = ns.Theme, ns.UI.Widgets
  -- Each tab's skin hangs below the row to hide its bottom edge; the row clips
  -- it there, so it never covers the list's first row.
  if row.SetClipsChildren then row:SetClipsChildren(true) end
  local tabs = { buttons = {}, first = items[1] and items[1].key }
  local previous
  for _, item in ipairs(items) do
    local key = item.key
    local b = makeTab(row, item.label)
    if previous then
      b:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", T.sizes.buttonGap, 0)
    else
      b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    end
    b:SetScript("OnClick", function()
      if onSelect and key ~= tabs.selected then onSelect(key) end
    end)
    tabs.buttons[key] = b
    previous = b
  end

  -- The line lives on its own frame above every tab, so the tabs sit behind
  -- it; it is open below the selected tab only.
  local lineFrame = CreateFrame("Frame", nil, row)
  lineFrame:SetAllPoints(row)
  local top = row:GetFrameLevel()
  for _, b in pairs(tabs.buttons) do top = math.max(top, b:GetFrameLevel()) end
  lineFrame:SetFrameLevel(top + 2)
  tabs.lineFrame = lineFrame

  local function baseLine()
    local l = W.line(lineFrame, T.colors.tabBorder, "OVERLAY")
    l:SetHeight(T.sizes.tabLine)
    return l
  end
  tabs.baseLeft, tabs.baseRight = baseLine(), baseLine()

  local function placeBase(selectedButton)
    local inset = edgeInset()
    local left, right = tabs.baseLeft, tabs.baseRight
    left:ClearAllPoints()
    right:ClearAllPoints()
    right:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    if not selectedButton then
      left:Hide()
      right:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
      return
    end
    right:SetPoint("BOTTOMLEFT", selectedButton, "BOTTOMRIGHT", -inset, 0)
    local first = selectedButton == tabs.buttons[tabs.first]
    left:SetShown(not first)
    if not first then
      left:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
      left:SetPoint("BOTTOMRIGHT", selectedButton, "BOTTOMLEFT", inset, 0)
    end
  end

  -- The selected tab gets the gold edge and glow and opens into the list;
  -- clicking it again does nothing.
  function tabs:SetSelected(key)
    self.selected = key
    for k, b in pairs(self.buttons) do
      b.isSelected = k == key
      b:ApplyLook()
    end
    placeBase(self.buttons[key])
  end
  placeBase(nil)

  return tabs
end

-- The ledger's tab buttons (header row 3): one per defined tab.
function Tabs.attach(row, onSelect)
  local items = {}
  for _, key in ipairs(Tabs.KEYS) do items[#items + 1] = { key = key, label = Tabs.label(key) } end
  return Tabs.strip(row, items, onSelect)
end
