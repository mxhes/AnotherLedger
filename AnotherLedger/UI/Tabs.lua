local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Tab registry and the tab buttons of header row 3. The ledger never names a
-- tab: it asks the selected tab's spec for its view. A new tab is one
-- Tabs.define call:
--
--   Tabs.define({
--     key   = "inventory",           -- saved in db.tab
--     label = L["Bags"],                -- button text
--     title = L["Bag Ledger"],          -- window title while selected
--     build = function(ctx) return view end, -- see View.lua for the view shape
--     sessionControls = false,       -- show the clock and Start / Stop / Reset
--     ticks   = false,               -- per-hour rates change with the clock
--     watches = "bags",              -- data kind whose change redraws the tab
--                                    -- (or a set of kinds: { bags = true, bank = true })
--     invalidate = function() end,   -- optional: drop cached data of `watches`
--     hasItem = function(itemID, ctx) return bool end, -- is the item listed?
--     sorts = { "ah", ... },         -- optional: the sorts the view offers; the
--                                    -- view then keeps its own sort (Tabs.sortSlot)
--     defaultSort = "recent",        -- optional: its first sort (else sorts[1])
--     subtabs = { { key, label, title?, build, hasItem?, sorts?, defaultSort? }, ... }, -- optional:
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

-- The window title of tab `key`: its sub-tab's own title (`subKey`), else the tab's.
function Tabs.title(key, subKey)
  local sub = Tabs.subtab(key, subKey)
  return sub and sub.title or Tabs.get(key).title
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

-- Where the shown view keeps its sort: a view with its own sorts list keeps
-- its own (db.sorts[slot], first `defaultSort`, else its first sort); the
-- item lists (Session, Bags, Bank) share db.sort. Returns slot, default or nil.
function Tabs.sortSlot(key, subKey)
  local spec = viewSpec(key, subKey)
  if type(spec.sorts) ~= "table" then return nil end
  local sub = Tabs.subtab(key, subKey)
  local slot = sub and (Tabs.get(key).key .. "/" .. sub.key) or Tabs.get(key).key
  return slot, spec.defaultSort or spec.sorts[1]
end

-- Pure. Whether tab `key` watches data of kind `what`: its `watches` is that
-- kind, or a set holding it ({ bags = true, bank = true }).
function Tabs.watches(key, what)
  local w = specs[key] and specs[key].watches
  if type(w) == "table" then return w[what] == true end
  return w ~= nil and w == what
end

-- Drops the cached data of every tab watching `what` ("bags", "bank", ...).
function Tabs.invalidate(what)
  for _, key in ipairs(Tabs.KEYS) do
    local spec = specs[key]
    if Tabs.watches(key, what) and spec.invalidate then spec.invalidate() end
  end
end

-- Old tab keys that are now a sub-tab: { [old] = { tab, subtab } } (a saved
-- db.tab from before, slash commands). Tabs.resolve maps them.
Tabs.ALIASES = { bags = { tab = "inventory", subtab = "bags" }, bank = { tab = "inventory", subtab = "bank" } }

-- Pure. The tab and sub-tab (nil: the saved one) that `key` stands for.
function Tabs.resolve(key)
  local alias = Tabs.ALIASES[key]
  if alias then return alias.tab, alias.subtab end
  return key, nil
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

-- Bank: the last saved scan (Core scans while the bank window is open).
local function savedBank(ctx)
  local bank = ctx.chardb and ctx.chardb.bank
  return type(bank) == "table" and bank or nil
end

-- Whether the saved bank record comes from a real scan (the default record
-- has scannedAt 0).
local function wasScanned(bank)
  return bank ~= nil and ns.Util.isNumber(bank.scannedAt) and bank.scannedAt > 0
end

-- This character's net worth parts (Worth.lua): the bag items and the last
-- bank scan unfiltered (bank nil: never scanned) and the gold, or nil without
-- GetMoney. Saved for the all characters total unless the demo's prices are in.
function Tabs.noteWorth(ctx)
  local getMoney = ctx.env.GetMoney
  if type(getMoney) ~= "function" then return nil end
  local ok, money = pcall(getMoney)
  if not (ok and ns.Util.isNumber(money)) then return nil end
  if not bagItems then bagItems = ns.Inventory.scanBags(ctx.env, ctx.now) end
  local bank = savedBank(ctx)
  local snap = {
    bags = ns.View.inventoryWorth(bagItems, ctx.opts),
    bank = wasScanned(bank) and ns.View.inventoryWorth(bank.items, ctx.opts) or nil,
    money = money,
    at = ctx.now,
  }
  local key = ns.Core and ns.Core.character
  if key and ns.db and not (ns.Demo and ns.Demo.active()) then ns.Worth.note(ns.db, key, snap) end
  return snap
end

local function buildBags(ctx)
  if not bagItems then bagItems = ns.Inventory.scanBags(ctx.env, ctx.now) end
  local view = ns.View.buildInventory(bagItems, ctx.opts)
  view.empty = ns.View.emptyText(view.rows, ctx.opts.filter, L["Your bags are empty."])
  -- Gold on hand and net worth rows (bags + bank + gold), all characters'
  -- with more than one saved; free slots next to the item count.
  local snap = Tabs.noteWorth(ctx)
  if snap then
    ns.View.addWorth(view, snap.money, snap.bags, snap.bank)
    local list, sum = ns.Worth.list(ns.db, ns.Core and ns.Core.character)
    if #list > 1 then
      view.totals.allWorth, view.worthList, view.now = sum, list, ctx.now
    end
  end
  local free, total = ns.Inventory.freeSlots(ctx.env)
  if total > 0 then
    local count = ns.History.itemCount(#view.rows)
    local freeText = ns.History.freeCount(free)
    -- Few free slots: orange, almost none: red.
    local level = ns.Inventory.freeLevel(free)
    if level then
      local C = ns.Theme.colors
      freeText = "|cff" .. ns.Theme.colorToHex(level == "low" and C.marketBad or C.stale) .. freeText .. "|r"
    end
    view.headerInfo = count .. " \194\183 " .. freeText
  end
  return view
end

local function bagsHasItem(itemID) return bagItems ~= nil and ns.Session.hasItemID(bagItems, itemID) end

local function buildBank(ctx)
  local bank = savedBank(ctx)
  local view = ns.View.buildInventory(bank and bank.items or {}, ctx.opts)
  -- Before the first scan: one message in the list and a dash in the
  -- footer (no "0c" total, Summary.rowTexts).
  view.unscanned = not wasScanned(bank)
  if not view.unscanned then
    local hours = ns.Util.setting("staleHours", nil)
    view.note, view.noteStale = ns.Inventory.scanNote(ctx.now, bank.scannedAt, hours and hours * 3600)
  end
  view.empty = ns.View.emptyText(view.rows, ctx.opts.filter,
    view.unscanned and L["Not scanned yet. Open your bank once to scan it."] or L["Your bank is empty."])
  return view
end

local function bankHasItem(itemID, ctx)
  local bank = savedBank(ctx)
  return bank ~= nil and ns.Session.hasItemID(bank.items, itemID)
end

-- Inventory: the bags and the last bank scan, one sub-tab each (the old Bank
-- tab's key is an alias, Tabs.ALIASES).
Tabs.define({
  key = "inventory", label = L["Inventory"], title = L["Bag Ledger"],
  watches = { bags = true, bank = true },
  invalidate = function() bagItems = nil end,
  build = buildBags,
  hasItem = bagsHasItem,
  subtabs = {
    { key = "bags", label = L["Bags"], title = L["Bag Ledger"], build = buildBags, hasItem = bagsHasItem },
    { key = "bank", label = L["Bank"], title = L["Bank Ledger"], build = buildBank, hasItem = bankHasItem },
  },
})

-- History: archived sessions; the opened one (ledger.historyIndex) lists its items.
local function savedHistory(ctx)
  local history = ctx.chardb and ctx.chardb.history
  return type(history) == "table" and history or {}
end

-- What a History view adds up, for the footer tooltip (view.scope): Sessions
-- this character's saved sessions; Zones and Mobs also the running one, and
-- every character's with the option "accountZones" (Zones: all characters).
local L_SCOPE_OWN = L["Counts this character's saved sessions."]
local L_SCOPE_ZONES = L["Counts this character's saved sessions and the running one."]
local L_SCOPE_ALL = L["Counts every character's saved sessions and the running one (option Zones: all characters)."]

local function zoneScope()
  return ns.Util.setting("accountZones", true) and L_SCOPE_ALL or L_SCOPE_ZONES
end

-- Zones and Mobs: the scope on the view, and in the header count when they
-- add up every character (so their totals differ from Sessions').
local L_ALL_CHARS = L[", all chars"]
local function withScope(view)
  view.scope = zoneScope()
  if view.headerInfo and ns.Util.setting("accountZones", true) then
    view.headerInfo = view.headerInfo .. L_ALL_CHARS
  end
  return view
end

local function buildSessions(ctx)
  local history, ledger = savedHistory(ctx), ctx.ledger
  if ledger.historyIndex and not history[ledger.historyIndex] then ledger.historyIndex = nil end
  local view = ns.View.buildHistory(history, ctx.opts, ledger.historyIndex)
  view.scope = L_SCOPE_OWN
  return view
end

local function sessionsHasItem(itemID, ctx)
  local entry = savedHistory(ctx)[ctx.ledger.historyIndex or 0]
  return type(entry) == "table" and ns.Session.hasItemID(entry.items, itemID)
end

-- Zones: every saved session (of every character with the option
-- "accountZones", ctx.zoneHistory) plus the running one (with its open stretch).
-- The saved part's change key goes to ctx.opts.historyKey (ViewZones.lua caches
-- over it; nil without one).
local function zoneEntries(ctx)
  local entries = {}
  local saved, key
  if ctx.zoneHistory then saved, key = ctx.zoneHistory() end
  if type(saved) ~= "table" then saved, key = savedHistory(ctx), nil end
  ctx.opts.historyKey = type(key) == "string" and key or nil
  for i, e in ipairs(saved) do entries[i] = e end
  local s = ctx.session
  if type(s) == "table" then
    entries[#entries + 1] = { live = true, items = s.items, places = s.places, gold = s.gold,
      zones = ns.Session.zoneSnapshot(s, ctx.now), mobs = s.mobs }
  end
  return entries
end

-- The item IDs of the Zones entries of the last build ({ [itemID] = true }).
local zoneItemIDs

local function addItemIDs(ids, e)
  if type(e) == "table" and type(e.items) == "table" then
    for _, it in pairs(e.items) do
      if type(it) == "table" and ns.Util.isNumber(it.id) then ids[it.id] = true end
    end
  end
end

-- The saved sessions' IDs are kept per History key (it changes with any
-- History change); only the running session is walked on every build.
local savedIDs = { key = nil, ids = nil }

local function itemIDsOf(entries, historyKey)
  if not historyKey or savedIDs.key ~= historyKey then
    local ids = {}
    for _, e in ipairs(entries) do
      if type(e) == "table" and not e.live then addItemIDs(ids, e) end
    end
    savedIDs.key, savedIDs.ids = historyKey, ids
  end
  local ids = {}
  for id in pairs(savedIDs.ids) do ids[id] = true end
  for _, e in ipairs(entries) do
    if type(e) == "table" and e.live then addItemIDs(ids, e) end
  end
  return ids
end

Tabs.define({
  key = "history", label = L["History"], title = L["Session History"],
  build = buildSessions,
  hasItem = sessionsHasItem,
  subtabs = {
    -- The sorts View.buildHistory knows; newest first until you pick another.
    { key = "sessions", label = L["Sessions"], build = buildSessions, hasItem = sessionsHasItem,
      sorts = { "ah", "recent", "perHour" }, defaultSort = "recent" },
    {
      key = "zones", label = L["Zones"], title = L["Zone History"],
      sorts = { "ah", "perHour", "vendor", "name", "recent" },
      build = function(ctx)
        local ledger = ctx.ledger
        if type(ledger.zoneOpen) ~= "table" then ledger.zoneOpen = {} end
        local entries = zoneEntries(ctx)
        zoneItemIDs = itemIDsOf(entries, ctx.opts.historyKey)
        return withScope(ns.View.buildZones(entries, ctx.opts, ledger.zoneOpen))
      end,
      -- Item info arrives in bursts (hundreds at login): look the item up in
      -- the IDs of the last build instead of gathering every History again.
      hasItem = function(itemID)
        return zoneItemIDs ~= nil and zoneItemIDs[itemID] == true
      end,
    },
    -- Mobs: what each mob and node dropped, over the same sessions as Zones.
    {
      key = "mobs", label = L["Mobs"], title = L["Mob History"],
      sorts = { "ah", "perLoot", "name" },
      build = function(ctx)
        local entries = zoneEntries(ctx)
        zoneItemIDs = itemIDsOf(entries, ctx.opts.historyKey)
        ctx.opts.mobKind = ns.UI.MobKind.current(ns.db)
        return withScope(ns.View.buildMobs(entries, ctx.opts, ctx.ledger.mobOpen))
      end,
      hasItem = function(itemID)
        return zoneItemIDs ~= nil and zoneItemIDs[itemID] == true
      end,
    },
    -- Totals: this character's saved sessions per week and month.
    {
      key = "totals", label = L["Totals"], title = L["Weeks and Months"],
      sorts = { "recent", "ah", "perHour" }, defaultSort = "recent",
      build = function(ctx)
        local view = ns.View.buildTotals(savedHistory(ctx), ctx.opts)
        view.scope = L_SCOPE_OWN
        return view
      end,
    },
  },
})

-- Trade: what sold and how well (Items, over the period of db.tradePeriod:
-- 7 days, 30 days or all) and every recorded entry (Log), for this realm.
local TRADE_DAY = 86400

local function tradeBucket()
  return ns.Core and ns.Core.tradeBucket and ns.Core.tradeBucket() or nil
end

-- The start of the Items period (nil: all time, from the totals).
function Tabs.tradeSince(period, now)
  local days = tonumber(period)
  if not days then return nil end
  return now - days * TRADE_DAY
end

-- The saved period, checked like the period button shows it.
local function tradePeriod()
  return ns.UI.TradePeriod.current(ns.db)
end

local function tradeHasItem(itemID)
  return ns.Trade.hasItemID(tradeBucket(), itemID)
end

local function buildTradeItems(ctx)
  local bucket = tradeBucket()
  local stats = bucket and ns.Trade.itemStats(bucket, Tabs.tradeSince(tradePeriod(), ctx.now), ctx.now) or {}
  return ns.View.buildTradeItems(stats, ctx.opts)
end

Tabs.define({
  key = "trade", label = L["Trade"], title = L["Trade Ledger"],
  watches = "trade",
  build = buildTradeItems,
  hasItem = tradeHasItem,
  subtabs = {
    { key = "items", label = L["Items"], build = buildTradeItems, hasItem = tradeHasItem,
      sorts = { "gold", "sold", "rate", "vsMarket", "name" }, defaultSort = "gold" },
    { key = "log", label = L["Log"], sorts = { "recent", "gold", "name" }, defaultSort = "recent",
      build = function(ctx)
        local bucket = tradeBucket()
        return ns.View.buildTradeLog(bucket and bucket.log or {}, ctx.opts)
      end,
      hasItem = tradeHasItem },
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
-- Square tabs (any border but Round) draw their 1 px edge at the frame edge.
local function pills()
  return ns.Theme.style.tabs == "pills"
end

local function edgeInset()
  if pills() or ns.Theme.style.border ~= "round" then return 0 end
  return math.floor(ns.Theme.sizes.tabEdge / 4)
end

-- Pure. The tab edge backdrop for a border style: the rounded tooltip edge
-- for Round, a square one-pixel edge for the others.
function Tabs.edgeSpec(border)
  local T = ns.Theme
  if border == "round" then
    local inset = math.floor(T.sizes.tabEdge / 4)
    return { edgeFile = T.textures.tabBorder, edgeSize = T.sizes.tabEdge,
      insets = { left = inset, right = inset, top = inset, bottom = inset } }
  end
  return { edgeFile = T.textures.rowHighlight, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 } }
end

-- Every strip made (Tabs.strip), restyled on a skin change.
local strips = {}

-- Pure. Tabs "pills" (option "skinTabs"): a flat fill (none when idle,
-- half on hover, a lifted one on the selected tab, Theme.skinScales.pillSelected)
-- and an underline on the selected one. Returns { fill, fillAlpha, text, underline (color or false) }.
function Tabs.pillLook(selected, hovered)
  local c = ns.Theme.colors
  if selected then
    return { fill = ns.Theme.scaleColor(c.buttonFill, ns.Theme.skinScales.pillSelected), fillAlpha = 1,
      text = c.tabTextSelected, underline = c.tabBorderSelected }
  end
  return { fill = c.buttonFill, fillAlpha = hovered and 0.5 or 0, text = hovered and c.tabTextSelected or c.tabText,
    underline = false }
end

-- One solid color over the whole texture (the glow's gradient undone).
local function setSolid(tex, c)
  if tex.SetGradient and CreateColor then
    tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 1), CreateColor(c[1], c[2], c[3], 1))
  elseif tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", c[1], c[2], c[3], 1, c[1], c[2], c[3], 1)
  else
    tex:SetVertexColor(c[1], c[2], c[3], 1)
  end
end

-- Edge and glow of one tab for the current border; Pills: a fill the height
-- of the button and the glow as the underline along its bottom.
local function shapeTab(b)
  local S = ns.Theme.sizes
  b.glow:ClearAllPoints()
  if pills() then
    b.skin:SetBackdrop({ bgFile = ns.Theme.textures.rowHighlight })
    b.skin:SetHeight(S.tabHeight)
    -- Right above the line under the tabs (Tabs.strip), which is drawn over them.
    b.glow:SetPoint("BOTTOMLEFT", b.skin, "BOTTOMLEFT", 0, S.tabLine)
    b.glow:SetPoint("BOTTOMRIGHT", b.skin, "BOTTOMRIGHT", 0, S.tabLine)
    b.glow:SetHeight(S.tabUnderline)
  else
    local inset = edgeInset()
    b.skin:SetBackdrop(Tabs.edgeSpec(ns.Theme.style.border))
    b.skin:SetHeight(S.tabHeight + S.tabEdge)
    b.glow:SetPoint("TOPLEFT", b.skin, "TOPLEFT", inset, -inset)
    b.glow:SetPoint("TOPRIGHT", b.skin, "TOPRIGHT", -inset, -inset)
    b.glow:SetHeight(S.tabGlowHeight)
  end
  b:ApplyLook()
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
  b.skin = skin
  local glow = skin:CreateTexture(nil, "ARTWORK")
  glow:SetTexture(T.textures.rowHighlight)
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
    if pills() then
      local look = Tabs.pillLook(self.isSelected, self.isHovered)
      self.skin:SetBackdropColor(look.fill[1], look.fill[2], look.fill[3], look.fillAlpha)
      W.setTextColor(self.label, look.text)
      if look.underline then setSolid(self.glow, look.underline) end
      self.glow:SetShown(look.underline ~= false)
      return
    end
    local look = Tabs.look(self.isSelected, self.isHovered)
    self.skin:SetBackdropBorderColor(look.border[1], look.border[2], look.border[3], look.border[4])
    W.setTextColor(self.label, look.text)
    setGlow(self.glow, ns.Theme.colors.tabGlow)
    self.glow:SetShown(look.glow)
  end
  b:SetScript("OnEnter", function(self) self.isHovered = true; self:ApplyLook() end)
  b:SetScript("OnLeave", function(self) self.isHovered = false; self:ApplyLook() end)
  shapeTab(b)
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
    tabs.order = tabs.order or {}
    tabs.order[#tabs.order + 1] = b
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
    local l = W.rule(lineFrame, T.colors.tabBorder, "OVERLAY")
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
    -- Pills: one line under every tab (the underline sits on it).
    if not selectedButton or pills() then
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

  -- Skin change: new edge shape, and the line's gap under the selected tab
  -- follows the new edge inset.
  function tabs:Reshape()
    for _, b in pairs(self.buttons) do shapeTab(b) end
    placeBase(self.selected and self.buttons[self.selected] or nil)
  end
  strips[#strips + 1] = tabs
  if #strips == 1 then W.onSkin(Tabs.reshapeAll) end

  return tabs
end

-- Every tab strip takes the current border's shape (Widgets.onSkin hook).
function Tabs.reshapeAll()
  for _, s in ipairs(strips) do s:Reshape() end
end

-- Pure. Width a strip of tabs needs (px): the button widths and the gaps.
function Tabs.rowNeed(buttonWidths)
  local w, n = 0, 0
  for _, bw in ipairs(buttonWidths) do w, n = w + bw, n + 1 end
  return w + math.max(0, n - 1) * ns.Theme.sizes.buttonGap
end

-- Every window title a tab can show (the tabs' and sub-tabs'), for the
-- header's width (Ledger.measureHeader).
function Tabs.titles()
  local out = {}
  for _, key in ipairs(Tabs.KEYS) do
    out[#out + 1] = Tabs.get(key).title
    for _, sub in ipairs(Tabs.subtabs(key) or {}) do
      if sub.title then out[#out + 1] = sub.title end
    end
  end
  return out
end

-- The ledger's tab buttons (header row 3): one per defined tab.
function Tabs.attach(row, onSelect)
  local items = {}
  for _, key in ipairs(Tabs.KEYS) do items[#items + 1] = { key = key, label = Tabs.label(key) } end
  return Tabs.strip(row, items, onSelect)
end
