-- Integration: loads every file of the .toc, in order, into one namespace with
-- a stub client environment and drives the real event flow.
local h = ...

local NUMBERS = {
  GetWidth = 300, GetHeight = 300, GetStringWidth = 50, GetStringHeight = 10,
  GetEffectiveScale = 1, GetScale = 1, GetLeft = 0, GetRight = 300, GetTop = 300,
  GetBottom = 0, GetValue = 0, GetAlpha = 1, GetNumPoints = 0,
}

local function newFake(env, name)
  local f = { _scripts = {}, _events = {}, _shown = true, _text = "" }
  local methods = {}
  function methods.SetText(self, t) self._text = t end
  function methods.GetText(self) return self._text end
  function methods.SetShown(self, v) self._shown = v and true or false end
  function methods.Show(self) self._shown = true end
  function methods.Hide(self) self._shown = false end
  function methods.IsShown(self) return self._shown end
  function methods.HasFocus() return false end
  function methods.IsVisible(self) return self._shown end
  function methods.GetCenter() return 0, 0 end
  function methods.SetScript(self, ev, fn) self._scripts[ev] = fn end
  function methods.HookScript() end
  function methods.RegisterEvent(self, ev) self._events[ev] = true end
  function methods.SetSize(self, w, hh) self._w, self._h = w, hh end
  function methods.SetWidth(self, w) self._w = w end
  function methods.SetHeight(self, hh) self._h = hh end
  function methods.GetWidth(self) return self._w or 300 end
  function methods.GetHeight(self) return self._h or 300 end
  function methods.GetName() return name end
  function methods.SetFrameLevel(self, l) self._level = l end
  function methods.GetFrameLevel(self) return self._level or 1 end
  setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if NUMBERS[k] then
      local n = NUMBERS[k]
      return function() return n end
    end
    if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
    -- Create* and Get* methods hand out another fake; everything else is a no-op.
    if k:match("^Create") or k:match("^Get") then
      return function() return newFake(env) end
    end
    return function() end
  end })
  if name then env[name] = f end
  return f
end

local function readToc()
  local files = {}
  local fh = assert(io.open("LootPrice/LootPrice.toc", "r"))
  for line in fh:lines() do
    line = line:gsub("\r", "")
    if line ~= "" and line:sub(1, 2) ~= "##" and line:match("%.lua$") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  fh:close()
  return files
end

local SAFE = { "string", "table", "math", "pairs", "ipairs", "next", "type", "tostring",
  "tonumber", "select", "pcall", "xpcall", "error", "assert", "setmetatable", "getmetatable",
  "rawget", "rawset", "rawequal", "unpack", "os" }

-- Builds a fresh stub client and loads the addon. Returns ctx.
local function boot(opts)
  opts = opts or {}
  local env = {}
  for _, k in ipairs(SAFE) do env[k] = _G[k] end
  env.unpack = env.unpack or table.unpack
  env._G = env
  local ctx = { env = env, printed = {}, errors = {}, now = opts.now or 1000 }
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    ctx.printed[#ctx.printed + 1] = table.concat(parts, " ")
  end
  env.time = function() return ctx.now end
  env.date = os.date
  env.geterrorhandler = function() return function(e) ctx.errors[#ctx.errors + 1] = tostring(e) end end
  env.C_Timer = { After = function(_, fn) fn() end }
  env.C_Item = {
    GetItemInfo = function(id) return "Item" .. id, "link", 1, 1, 1, "t", "st", 1, "", 1, 25 end,
    GetItemIconByID = function() return 134400 end,
  }
  env.C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end }
  env.GetCurrentRegionName = function() return "EU" end
  env.StaticPopupDialogs = {}
  env.StaticPopup_Show = function() end
  env.SlashCmdList = {}
  env.LOOT_ITEM_SELF = "You receive loot: %s."
  env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
  env.YOU_LOOT_MONEY = "You loot %s"
  env.LOOT_MONEY_SPLIT = "Your share of the loot is %s."
  env.YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
  env.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
  env.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
  env.GOLD_AMOUNT = "%d Gold"
  env.SILVER_AMOUNT = "%d Silver"
  env.COPPER_AMOUNT = "%d Copper"
  env.CreateFrame = function(_, name) return newFake(env, name) end
  env.UIParent = newFake(env)
  env.LootPriceDB = opts.db
  env.LootPriceCharDB = opts.chardb

  ctx.baseline = {}
  for k in pairs(env) do ctx.baseline[k] = true end

  local ns = {}
  for _, file in ipairs(readToc()) do
    local chunk, err
    if setfenv then -- Lua 5.1 (the client's version)
      chunk, err = loadfile("LootPrice/" .. file)
      if chunk then setfenv(chunk, env) end
    else
      chunk, err = loadfile("LootPrice/" .. file, "t", env)
    end
    assert(chunk, err)
    chunk("LootPrice", ns)
  end
  ctx.ns = ns
  return ctx
end

local function fire(ctx, event, ...)
  local frame = ctx.ns.Core.frame
  assert(frame, "Core.frame missing (CreateFrame was available at load)")
  assert(frame._events[event], "event not registered: " .. event)
  frame._scripts.OnEvent(frame, event, ...)
end

local function slash(ctx, msg) ctx.env.SlashCmdList["LOOTPRICE"](msg) end

local LINK = "|cffffffff|Hitem:2589::::::::60:::::::::|h[Linen Cloth]|h|r"
local LOOT = "You receive loot: " .. LINK .. "x3."

local function startWorld(ctx, isReload)
  fire(ctx, "ADDON_LOADED", "LootPrice")
  fire(ctx, "PLAYER_ENTERING_WORLD", not isReload, isReload and true or false)
end

h.test("wiring: toc files load and the slash commands register", function()
  local ctx = boot()
  h.eq(ctx.env.SLASH_LOOTPRICE1, "/lp")
  h.eq(ctx.env.SLASH_LOOTPRICE2, "/lootprice")
  h.eq(type(ctx.env.SlashCmdList.LOOTPRICE), "function")
  h.eq(ctx.errors, {})
end)

h.test("wiring: login flow records loot and saves the session", function()
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(ctx.errors, {})
  h.eq(type(ctx.ns.session), "table")
  h.eq(ctx.ns.UI.Ledger.frame ~= nil, true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ctx.ns.session.items[2589].qty, 3)
  h.eq(ctx.env.LootPriceCharDB.session, ctx.ns.session)
  h.eq(ctx.errors, {})
  h.eq(#ctx.ns.UI.Ledger.view.rows, 1)
end)

h.test("wiring: loot before the world is entered is ignored", function()
  local ctx = boot()
  fire(ctx, "ADDON_LOADED", "LootPrice")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ctx.ns.session, nil)
  slash(ctx, "start")
  h.eq(ctx.printed[#ctx.printed]:find("not ready", 1, true) ~= nil, true)
end)

h.test("wiring: demo then reset restores the price cache", function()
  local ctx = boot()
  startWorld(ctx, false)
  local cache = ctx.env.LootPriceDB.cache
  slash(ctx, "demo")
  h.eq(ctx.errors, {})
  h.eq(ctx.ns.session.items[2589].qty, 23)
  h.eq(cache["EU-7"][2589].price, 55)
  slash(ctx, "reset")
  h.eq(ctx.errors, {})
  h.eq(next(ctx.ns.session.items), nil)
  h.eq(cache["EU-7"], nil) -- the bucket demo created is gone again
  h.eq(cache, {})
end)

h.test("wiring: demo on a stopped session seeds nothing", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "stop")
  slash(ctx, "demo")
  h.eq(ctx.printed[#ctx.printed]:find("stopped", 1, true) ~= nil, true)
  h.eq(next(ctx.ns.session.items), nil)
  h.eq(ctx.env.LootPriceDB.cache["EU-7"], nil)
end)

h.test("wiring: logout suspends the session", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.now = 1100
  fire(ctx, "PLAYER_LOGOUT")
  h.eq(ctx.env.LootPriceCharDB.session.elapsedBase, 100)
  h.eq(ctx.env.LootPriceCharDB.session.runningSince, nil)
end)

h.test("wiring: a /reload keeps the session with keep off, a relog starts fresh", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = 1050
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.LootPriceDB, ctx.env.LootPriceCharDB
  h.eq(db.settings.keepSession, false)

  local reload = boot({ db = db, chardb = chardb, now = 2000 })
  startWorld(reload, true)
  h.eq(reload.errors, {})
  h.eq(reload.ns.session.items[2589].qty, 3)
  h.eq(reload.ns.session.runningSince, 2000)

  local relog = boot({ db = db, chardb = chardb, now = 3000 })
  startWorld(relog, false)
  h.eq(next(relog.ns.session.items), nil)
end)

h.test("wiring: later PLAYER_ENTERING_WORLD only re-evaluates the key", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local session = ctx.ns.session
  fire(ctx, "PLAYER_ENTERING_WORLD", false, false) -- zone change
  h.eq(ctx.ns.session == session, true)
  h.eq(ctx.ns.session.items[2589].qty, 3)
end)

h.test("wiring: no unexpected globals leak", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "demo")
  slash(ctx, "reset")
  fire(ctx, "PLAYER_LOGOUT")
  local allowed = {
    LootPriceDB = true, LootPriceCharDB = true, SLASH_LOOTPRICE1 = true,
    SLASH_LOOTPRICE2 = true, LootPriceWindow = true, LootPriceMenu = true,
    LootPriceOptionsPage = true, LootPriceMinimapButton = true, LootPriceExport = true,
  }
  for k in pairs(ctx.env) do
    if not ctx.baseline[k] and not allowed[k] then error("leaked global: " .. tostring(k)) end
  end
end)

h.test("wiring: a failing View.build is reported once, not every tick", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.errors = {}
  ctx.ns.View.build = function() error("boom") end
  ctx.ns.UI.Ledger.refresh()
  ctx.ns.UI.Ledger.refresh()
  ctx.ns.UI.Ledger.refresh()
  h.eq(#ctx.errors, 1)
end)

h.test("wiring: a failing part attach does not stop the ledger", function()
  local ctx = boot()
  ctx.ns.UI.Summary.attach = function() error("summary broke") end
  startWorld(ctx, false)
  h.eq(#ctx.errors, 1)
  h.eq(ctx.ns.UI.Ledger.frame ~= nil, true)
  h.eq(ctx.ns.UI.Ledger.view ~= nil, true)
  h.eq(type(ctx.ns.UI.Ledger.frame._scripts.OnUpdate), "function")
end)

h.test("wiring: looted gold, split share and guild form land in the gold total", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_MONEY", "You loot 1 Gold, 23 Silver, 4 Copper")
  fire(ctx, "CHAT_MSG_MONEY", "Your share of the loot is 5 Silver.")
  fire(ctx, "CHAT_MSG_MONEY", "You loot 2 Gold (1 Gold deposited to guild bank)")
  fire(ctx, "CHAT_MSG_MONEY", "Bob loots 9 Gold.")
  fire(ctx, "CHAT_MSG_MONEY", "garbage")
  h.eq(ctx.errors, {})
  h.eq(ctx.ns.session.gold, 12304 + 500 + 20000)
  h.eq(ctx.ns.UI.Ledger.view.gold.total, 12304 + 500 + 20000)
end)

h.test("wiring: quest turn-in money lands in the same gold total", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  fire(ctx, "QUEST_TURNED_IN", 123, 500, 25000)
  h.eq(ctx.ns.session.gold, 25500)
  for _, bad in ipairs({ 0, -4, "50", true }) do fire(ctx, "QUEST_TURNED_IN", 1, 0, bad) end
  fire(ctx, "QUEST_TURNED_IN", 1, 0, nil)
  fire(ctx, "QUEST_TURNED_IN", 1)
  h.eq(ctx.ns.session.gold, 25500)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a stopped session and a missing session ignore gold", function()
  local ctx = boot()
  fire(ctx, "ADDON_LOADED", "LootPrice")
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  fire(ctx, "QUEST_TURNED_IN", 1, 0, 100)
  h.eq(ctx.ns.session, nil)
  fire(ctx, "PLAYER_ENTERING_WORLD", true, false)
  slash(ctx, "stop")
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  fire(ctx, "QUEST_TURNED_IN", 1, 0, 100)
  h.eq(ctx.ns.session.gold, 0)
  slash(ctx, "start")
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  h.eq(ctx.ns.session.gold, 500)
  h.eq(ctx.errors, {})
end)

h.test("wiring: quest reward item is a normal list item", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", "You receive item: " .. LINK .. ".")
  h.eq(ctx.ns.session.items[2589].qty, 1)
  h.eq(#ctx.ns.UI.Ledger.view.rows, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: demo adds gold through the same path and reset clears it", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "demo")
  h.eq(ctx.ns.session.gold, 1240)
  slash(ctx, "reset")
  h.eq(ctx.ns.session.gold, 0)
  slash(ctx, "stop")
  slash(ctx, "demo")
  h.eq(ctx.ns.session.gold, 0)
end)

local function bagEnv(ctx, bags)
  ctx.env.C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].n or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local s = bags[bag] and bags[bag][slot]
      if not s then return nil end
      return { itemID = s[1], stackCount = s[2], hyperlink = "|cffffffff|Hitem:" .. s[1] .. "::|h[Item" .. s[1] .. "]|h|r" }
    end,
  }
end

h.test("wiring: bags tab lists the bag contents, footer shows only the items block", function()
  local ctx = boot()
  bagEnv(ctx, { [0] = { n = 3, { 2589, 5 }, { 2592, 2 }, { 2589, 15 } } })
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  L.setTab("bags")
  h.eq(ctx.errors, {})
  h.eq(L.tab, "bags")
  h.eq(ctx.env.LootPriceDB.tab, "bags")
  h.eq(#L.view.rows, 2)
  h.eq(L.view.kind, "inventory")
  -- a bag change marks the list dirty and shows up on the next refresh
  bagEnv(ctx, { [0] = { n = 1, { 2592, 9 } } })
  fire(ctx, "BAG_UPDATE_DELAYED")
  h.eq(ctx.errors, {})
  h.eq(#L.view.rows, 1)
  h.eq(L.view.rows[1].quantity, 9)
  L.setTab("session")
  h.eq(L.view.kind, "session")
  h.eq(ctx.errors, {})
end)

h.test("wiring: bank is scanned while open and shown from the saved scan", function()
  local ctx = boot()
  bagEnv(ctx, { [-1] = { n = 2, { 2589, 4 }, { 7910, 1 } } })
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  L.setTab("bank")
  h.eq(#L.view.rows, 0)
  h.eq(L.view.note, "Open your bank once to scan it.")
  fire(ctx, "BANKFRAME_OPENED")
  h.eq(ctx.errors, {})
  h.eq(#L.view.rows, 2)
  h.eq(ctx.env.LootPriceCharDB.bank.scannedAt, ctx.now)
  fire(ctx, "BANKFRAME_CLOSED")
  -- away from the bank the scan is kept, the bags changing does not touch it
  bagEnv(ctx, {})
  fire(ctx, "BAG_UPDATE_DELAYED")
  h.eq(ctx.env.LootPriceCharDB.bank.items[2589].qty, 4)
  ctx.now = ctx.now + 7200
  L.refresh()
  h.eq(L.view.note, "Scanned 2h ago")
  h.eq(#L.view.rows, 2)
end)

h.test("wiring: an empty scan right at opening does not wipe a saved scan", function()
  local ctx = boot()
  bagEnv(ctx, { [-1] = { n = 1, { 2589, 4 } } })
  startWorld(ctx, false)
  fire(ctx, "BANKFRAME_OPENED")
  bagEnv(ctx, {})
  fire(ctx, "BANKFRAME_CLOSED")
  fire(ctx, "BANKFRAME_OPENED") -- slots not loaded yet
  h.eq(ctx.env.LootPriceCharDB.bank.items[2589].qty, 4)
  bagEnv(ctx, {})
  fire(ctx, "BAG_UPDATE_DELAYED") -- bank open: a later empty scan is real
  h.eq(next(ctx.env.LootPriceCharDB.bank.items), nil)
end)

h.test("wiring: the last tab survives a reload", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.ns.UI.Ledger.setTab("bags")
  local reload = boot({ db = ctx.env.LootPriceDB, chardb = ctx.env.LootPriceCharDB, now = 2000 })
  startWorld(reload, true)
  h.eq(reload.errors, {})
  h.eq(reload.ns.UI.Ledger.tab, "bags")
end)

h.test("wiring: footer table height follows the tab and the raw gold option", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, footer = ctx.ns.UI.Ledger, ctx.ns.UI.Window.frame.footer
  local summary = ctx.ns.UI.Summary.instance
  L.refresh()
  h.eq(footer:GetHeight(), 72)
  L.setTab("bags")
  h.eq(footer:GetHeight(), 18)
  h.eq(summary.cells.gold.label:IsShown(), false)
  h.eq(summary.cells.items.rate:IsShown(), false)
  h.eq(summary.titles.value:IsShown(), false)
  L.setTab("session")
  h.eq(footer:GetHeight(), 72)
  h.eq(summary.cells.gold.label:IsShown(), true)
  h.eq(summary.cells.total.value:IsShown(), true)
  h.eq(summary.cells.items.rate:IsShown(), true)
  h.eq(summary.titles.value:IsShown(), true)
  ctx.ns.Options.set(ctx.ns.db, "includeGold", false)
  L.refresh()
  h.eq(footer:GetHeight(), 54)
  h.eq(summary.cells.total.label:IsShown(), false)
  ctx.ns.Options.set(ctx.ns.db, "includeGold", true)
  L.refresh()
  h.eq(footer:GetHeight(), 72)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the font size options re-lay the window out live", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local ns = ctx.ns
  local S, L = ns.Theme.sizes, ns.UI.Ledger
  local footer, summary = ns.UI.Window.frame.footer, ns.UI.Summary.instance
  L.refresh()
  local row = L.list.pool[1]
  h.eq(row:GetHeight(), 30)
  local minHeight = S.minHeight
  ns.Options.set(ns.db, "fontSizeRows", 18)
  h.eq(S.rowHeight, 45)
  h.eq(row:GetHeight(), 45)
  h.eq(row.iconBorder:GetHeight(), 30)
  h.eq(S.minHeight, minHeight + 4 * 15) -- four list rows, 15 px taller each
  ns.Options.set(ns.db, "fontSizeTotals", 15)
  h.eq(summary.cells.items.frame:GetHeight(), 23)
  h.eq(S.footerNoteHeight, 20)
  h.eq(footer:GetHeight(), ns.UI.Summary.tableLayout(L.view).height) -- 4 lines of 23 (+ notes)
  h.eq(footer:GetHeight() >= 4 * 23, true)
  -- back to the defaults: computed from the theme's values, not compounded
  ns.Options.set(ns.db, "fontSizeRows", 12)
  ns.Options.set(ns.db, "fontSizeTotals", 12)
  h.eq(S.rowHeight, 30)
  h.eq(row:GetHeight(), 30)
  h.eq(row.iconBorder:GetHeight(), 20)
  h.eq(S.footerRowHeight, 18)
  h.eq(footer:GetHeight(), ns.UI.Summary.tableLayout(L.view).height)
  h.eq(S.minHeight, minHeight)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the item icon option hides the row icons live", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local ns = ctx.ns
  local L, W = ns.UI.Ledger, ns.UI.Window
  L.refresh()
  local row = L.list.pool[1]
  h.eq(row.icon:IsShown(), true)
  local required = W.requiredWidth
  ns.Options.set(ns.db, "showIcons", false)
  h.eq(row.icon:IsShown(), false)
  h.eq(row.iconBorder:IsShown(), false)
  local S = ns.Theme.sizes
  h.eq(W.requiredWidth, required - (S.rowIconInset + S.iconSize + S.rowIconGap) + S.rowTextLeftNoIcon)
  ns.Options.set(ns.db, "showIcons", true)
  h.eq(row.icon:IsShown(), true)
  h.eq(W.requiredWidth, required)
  h.eq(ctx.errors, {})
end)

h.test("wiring: hovering the footer table shows the vendor / AH tooltip", function()
  local ctx = boot()
  local lines = {}
  ctx.env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end,
    SetText = function() end, IsOwned = function() return false end,
    AddDoubleLine = function(_, l, r) lines[#lines + 1] = { l, r } end,
  }
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local tbl = ctx.ns.UI.Summary.instance.table
  tbl._scripts.OnEnter(tbl)
  h.eq(lines[1][1], "Items")
  h.eq(lines[2][1], "Vendor: ")
  h.eq(#lines, 8)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the Start / Stop button toggles the clock and its label", function()
  local ctx = boot()
  startWorld(ctx, false)
  local header = ctx.ns.UI.Header.instance
  local toggle = header.toggle
  local running = ctx.ns.session.running
  toggle._scripts.OnClick(toggle, "LeftButton")
  h.eq(ctx.ns.session.running, not running)
  ctx.ns.UI.Ledger.refresh()
  h.eq(toggle:GetText(), ctx.ns.session.running and "Stop" or "Start")
  toggle._scripts.OnClick(toggle, "LeftButton")
  h.eq(ctx.ns.session.running, running)
  h.eq(ctx.errors, {})
end)

h.test("wiring: tab buttons switch tabs; the selected one is marked", function()
  local ctx = boot()
  startWorld(ctx, false)
  local tabs = ctx.ns.UI.Ledger.tabs
  local bags = tabs.buttons.bags
  bags._scripts.OnClick(bags, "LeftButton")
  h.eq(ctx.ns.UI.Ledger.tab, "bags")
  h.eq(tabs.selected, "bags")
  h.eq(bags.isSelected, true)
  h.eq(bags.glow:IsShown(), true)
  h.eq(tabs.buttons.session.isSelected, false)
  h.eq(tabs.buttons.session.glow:IsShown(), false)
  -- the line under the tabs is open below the selected tab: a left part only
  -- when a tab before it exists
  h.eq(tabs.baseLeft:IsShown(), true)
  tabs:SetSelected("session")
  h.eq(tabs.baseLeft:IsShown(), false)
  h.eq(tabs.baseRight:IsShown(), true)
  -- the line is drawn on a frame above the tabs, so the tabs sit behind it
  h.eq(tabs.lineFrame ~= nil, true)
  h.eq(tabs.lineFrame:GetFrameLevel() > tabs.buttons.bags:GetFrameLevel(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: top finds collapse on the inventory tabs and come back on Session", function()
  local ctx = boot()
  bagEnv(ctx, { [0] = { n = 1, { 2589, 5 } } })
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local W = ctx.ns.UI.Window
  local topBox = W.frame.topBox
  h.eq(topBox._h > 1, true)
  ctx.ns.UI.Ledger.setTab("bags")
  h.eq(topBox._shown, false)
  ctx.ns.UI.Ledger.setTab("session")
  h.eq(topBox._shown, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: opacity, price source and combat hide options take effect", function()
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(ctx.errors, {})
  local ns, W = ctx.ns, ctx.ns.UI.Window
  local frame = W.frame
  -- price source: Auctionator only, TSM silent
  ctx.env.TSM_API = { GetCustomPriceValue = function() return 111 end }
  ctx.env.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 222 end } } }
  ns.Options.set(ns.db, "priceSource", "tsm")
  h.eq(ns.prices:lookup(2589).ah, 111)
  ns.Options.set(ns.db, "priceSource", "auctionator")
  h.eq(ns.prices:lookup(2589).ah, 222)
  ns.Options.set(ns.db, "priceSource", "auto")
  h.eq(ns.prices:lookup(2589).ah, 111)
  -- opacity
  ns.Options.set(ns.db, "alpha", 0.5)
  h.eq(ns.db.settings.alpha, 0.5)
  -- combat: off by default
  fire(ctx, "PLAYER_REGEN_DISABLED")
  h.eq(frame:IsShown(), true)
  ns.Options.set(ns.db, "combatHide", true)
  fire(ctx, "PLAYER_REGEN_DISABLED")
  h.eq(frame:IsShown(), false)
  fire(ctx, "PLAYER_REGEN_ENABLED")
  h.eq(frame:IsShown(), true)
  -- a window the user hid stays hidden after combat
  W.hide()
  fire(ctx, "PLAYER_REGEN_DISABLED")
  fire(ctx, "PLAYER_REGEN_ENABLED")
  h.eq(frame:IsShown(), false)
  W.show()
  -- turning the option off during combat brings the window back
  fire(ctx, "PLAYER_REGEN_DISABLED")
  h.eq(frame:IsShown(), false)
  ns.Options.set(ns.db, "combatHide", false)
  h.eq(frame:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the options panel builds a widget for every registered option", function()
  local ctx = boot()
  startWorld(ctx, false)
  local P = ctx.ns.UI.OptionsPanel
  P.toggle()
  h.eq(ctx.errors, {})
  h.eq(P.frame ~= nil, true)
  for _, spec in ipairs(ctx.ns.Options.list()) do
    h.eq(P.frame.widgets[spec.key] ~= nil, true, spec.key)
  end
  P.toggle() -- closes
  h.eq(ctx.errors, {})
  h.eq(ctx.ns.UI.Ledger.frame.header ~= nil, true)
end)

h.test("wiring: the options panel has a tab per category, one page shown at a time", function()
  local ctx = boot()
  startWorld(ctx, false)
  local P, O = ctx.ns.UI.OptionsPanel, ctx.ns.Options
  P.toggle()
  local tabbed = P.frame.tabbed
  local sections = O.sections()
  local first, second = sections[1].id, sections[2].id
  for _, s in ipairs(sections) do h.eq(tabbed.strip.buttons[s.id] ~= nil, true, s.id) end
  h.eq(tabbed.pages[first]:IsShown(), true)
  h.eq(tabbed.pages[second]:IsShown(), false)
  h.eq(tabbed.strip.selected, first)
  -- clicking another tab shows its page only
  tabbed.strip.buttons[second]._scripts.OnClick()
  h.eq(tabbed.pages[first]:IsShown(), false)
  h.eq(tabbed.pages[second]:IsShown(), true)
  h.eq(P.tab, second)
  -- the options page in the game's window opens on the same tab
  local page = P.registerPage()
  page._scripts.OnShow(page)
  h.eq(page.tabbed.strip.selected, second)
  -- the panel keeps its size whichever tab is shown
  local height = P.frame:GetHeight()
  tabbed.select(first)
  h.eq(P.frame:GetHeight(), height)
  h.eq(ctx.errors, {})
end)

h.test("wiring: saved option values are applied at login", function()
  local ctx = boot({ db = { settings = { alpha = 7, priceSource = "zzz" } } })
  startWorld(ctx, false)
  h.eq(ctx.errors, {})
  h.eq(ctx.env.LootPriceDB.settings.alpha, 1)
  h.eq(ctx.env.LootPriceDB.settings.priceSource, "auto")
end)

h.test("wiring: the window look options apply to the background and border", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local frame = ns.UI.Window.frame
  local bg, border
  frame.SetBackdropColor = function(_, r, g, b, a) bg = { r, g, b, a } end
  frame.SetBackdropBorderColor = function(_, r, g, b, a) border = { r, g, b, a } end
  ns.Options.set(ns.db, "alpha", 0)
  h.eq(bg[4], 0)
  h.eq(border[4], 0)
  ns.Options.set(ns.db, "alpha", 0.5)
  ns.Options.set(ns.db, "brightness", 2)
  local tint, bd = ns.Theme.colors.panelTint, ns.Theme.colors.panelBorder
  h.near(bg[1], math.min(1, tint[1] * 2))
  h.near(bg[4], tint[4] * 0.5)
  h.near(border[1], math.min(1, bd[1] * 2))
  h.eq(ctx.errors, {})
end)

h.test("wiring: Reset archives the session to History, empty sessions are skipped", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "reset") -- empty: nothing archived
  h.eq(#ctx.env.LootPriceCharDB.history, 0)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Copper")
  slash(ctx, "reset")
  local hist = ctx.env.LootPriceCharDB.history
  h.eq(#hist, 1)
  h.eq(hist[1].items[2589].qty, 3)
  h.eq(hist[1].nItems, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a fresh login archives the discarded session, keep-session does not", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.LootPriceDB, ctx.env.LootPriceCharDB

  local reload = boot({ db = db, chardb = chardb, now = 2000 })
  startWorld(reload, true) -- /reload keeps the session
  h.eq(#chardb.history, 0)

  fire(reload, "PLAYER_LOGOUT")
  local relog = boot({ db = db, chardb = chardb, now = 3000 })
  startWorld(relog, false)
  h.eq(#chardb.history, 1)
  h.eq(chardb.history[1].items[2589].qty, 3)
  h.eq(relog.errors, {})
end)

h.test("wiring: the History option limits and prunes the archive", function()
  local ctx = boot()
  startWorld(ctx, false)
  local function lootAndReset()
    fire(ctx, "CHAT_MSG_LOOT", LOOT)
    slash(ctx, "reset")
  end
  lootAndReset(); lootAndReset(); lootAndReset()
  local hist = ctx.env.LootPriceCharDB.history
  h.eq(#hist, 3)
  ctx.ns.Options.set(ctx.ns.db, "historyLimit", 1)
  h.eq(#hist, 1)
  ctx.ns.Options.set(ctx.ns.db, "historyLimit", 0)
  h.eq(#hist, 0)
  lootAndReset()
  h.eq(#hist, 0)
  ctx.ns.Options.set(ctx.ns.db, "historyLimit", -1)
  lootAndReset(); lootAndReset()
  h.eq(#hist, 2)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a History session opens at the top and collapses on a second click", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  local L = ctx.ns.UI.Ledger
  L.setTab("history")
  h.eq(#L.view.rows, 2)
  L.list.onRowClick(L.view.rows[2]) -- open the older session
  h.eq(L.historyIndex, 2)
  h.eq(#L.view.rows, 3)
  h.eq(L.view.rows[1].historyIndex, 2) -- on top
  h.eq(L.view.rows[2].quantity, 3) -- its item
  h.eq(L.view.rows[3].historyIndex, 1)
  L.list.onRowClick(L.view.rows[1]) -- click it again
  h.eq(L.historyIndex, nil)
  h.eq(#L.view.rows, 2)
  L.list.onRowClick(L.view.rows[1])
  L.setTab("session")
  L.setTab("history")
  h.eq(L.historyIndex, nil) -- leaving the tab collapses
  h.eq(ctx.errors, {})
end)

-- A stub client whose timers wait until the test runs them (a "next frame").
local function bootDeferred()
  local ctx = boot()
  ctx.timers = {}
  ctx.env.C_Timer = { After = function(_, fn) ctx.timers[#ctx.timers + 1] = fn end }
  function ctx.runTimers()
    local due = ctx.timers
    ctx.timers = {}
    for _, fn in ipairs(due) do fn() end
  end
  return ctx
end

local function countCalls(tbl, name)
  local calls, real = { n = 0 }, tbl[name]
  tbl[name] = function(...)
    calls.n = calls.n + 1
    return real(...)
  end
  return calls
end

local function lootMsg(id, qty)
  return "You receive loot: |cffffffff|Hitem:" .. id .. "::::::::60:::::::::|h[Item" .. id .. "]|h|r" .. "x" .. qty .. "."
end

h.test("wiring: several loot messages in one frame share a single rebuild", function()
  local ctx = bootDeferred()
  startWorld(ctx, false)
  ctx.runTimers()
  local builds = countCalls(ctx.ns.View, "build")
  for id = 1, 5 do fire(ctx, "CHAT_MSG_LOOT", lootMsg(id, 2)) end
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  h.eq(ctx.ns.session.items[3].qty, 2) -- the session itself is updated at once
  h.eq(ctx.ns.session.gold, 500)
  h.eq(builds.n, 0)
  ctx.runTimers()
  h.eq(#ctx.ns.UI.Ledger.view.rows, 5)
  h.eq(ctx.ns.UI.Ledger.view.gold.total, 500)
  h.eq(builds.n <= 2, true) -- one for the items, at most one more for the gold
  h.eq(ctx.errors, {})
end)

h.test("wiring: the clock tick updates the rates without rebuilding, prices refresh every 30 s", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local L = ctx.ns.UI.Ledger
  local onUpdate = L.frame._scripts.OnUpdate
  local builds = countCalls(ctx.ns.View, "build")
  local view = L.view
  h.eq(view.totals.vendorPerHour, nil) -- younger than a minute
  ctx.now = ctx.now + 10
  onUpdate(L.frame, 0.4)
  h.eq(builds.n, 0) -- not a full second yet
  ctx.now = ctx.now + 15
  onUpdate(L.frame, 0.7)
  h.eq(builds.n, 0)
  h.eq(L.view == view, true)
  ctx.now = 1000 + 120
  onUpdate(L.frame, 1)
  h.eq(builds.n, 1) -- 30 s since the last full refresh: prices are looked up again
  h.near(L.view.totals.vendorPerHour, 75 * 3600 / 120)
  local fresh = L.view
  ctx.now = ctx.now + 20
  onUpdate(L.frame, 1)
  h.eq(builds.n, 1)
  h.eq(L.view == fresh, true)
  h.near(fresh.totals.vendorPerHour, 75 * 3600 / 140) -- the rate follows the clock
  -- a stopped clock does not tick, another tab does not tick
  slash(ctx, "stop")
  local after = builds.n
  ctx.now = ctx.now + 100
  onUpdate(L.frame, 1)
  h.eq(builds.n, after)
  h.eq(ctx.errors, {})
end)

h.test("wiring: nothing is rebuilt while the window is hidden; showing it catches up", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, W = ctx.ns.UI.Ledger, ctx.ns.UI.Window
  local builds = countCalls(ctx.ns.View, "build")
  W.hide()
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  h.eq(builds.n, 0)
  h.eq(ctx.ns.session.items[2589].qty, 3) -- still recorded
  h.eq(#L.view.rows, 0)
  W.show()
  L.refresh() -- the client fires OnShow, which is hooked to this
  h.eq(builds.n, 1)
  h.eq(#L.view.rows, 1)
  h.eq(L.view.gold.total, 500)
  h.eq(ctx.errors, {})
end)

h.test("wiring: item info only redraws for an item listed on the shown tab", function()
  local ctx = boot()
  bagEnv(ctx, { [0] = { n = 1, { 2592, 2 } } })
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local L = ctx.ns.UI.Ledger
  h.eq(L.wantsItemInfo(2589), true)
  h.eq(L.wantsItemInfo(2592), false)
  L.setTab("bags")
  h.eq(L.wantsItemInfo(2592), true)
  h.eq(L.wantsItemInfo(2589), false)
  h.eq(L.wantsItemInfo(424242), false)
  L.setTab("bank")
  h.eq(L.wantsItemInfo(2592), false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a tab defined by another file shows up and builds through the ledger", function()
  local ctx = boot()
  ctx.ns.UI.Tabs.define({ key = "mail", label = "Mail", title = "Mail Ledger",
    build = function(c) return ctx.ns.View.buildInventory({ [5] = { id = 5, qty = 2, lastSeen = 0 } }, c.opts) end })
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  L.setTab("mail")
  h.eq(L.tab, "mail")
  h.eq(#L.view.rows, 1)
  h.eq(L.tabs.buttons.mail ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: cached prices older than 30 days are dropped at login", function()
  local day = 86400
  local now = 200 * day
  local db = { cache = { ["EU-7"] = {
    [1] = { price = 5, seenAt = now - 40 * day },
    [2] = { price = 6, seenAt = now - 2 * day },
  }, ["US-1"] = { [3] = { price = 7, seenAt = 5 } } } }
  local ctx = boot({ db = db, now = now })
  startWorld(ctx, false)
  local cache = ctx.env.LootPriceDB.cache
  h.eq(cache["EU-7"][1], nil)
  h.eq(cache["EU-7"][2].price, 6)
  h.eq(cache["US-1"], nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: /lp help lists every command, demo included", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.printed = {}
  slash(ctx, "help")
  local text = table.concat(ctx.printed, "\n")
  for _, word in ipairs({ "/lp -", "show | hide", "start | stop", "/lp reset", "/lp keep", "/lp tsm", "/lp demo", "Note:" }) do
    h.eq(text:find(word, 1, true) ~= nil, true, word)
  end
end)

h.test("wiring: the minimap button toggles the window, right click opens the options", function()
  local ctx = boot()
  ctx.env.Minimap = ctx.env.CreateFrame("Frame", "Minimap")
  ctx.env.GameTooltip = ctx.env.CreateFrame("Frame")
  startWorld(ctx, false)
  local ns = ctx.ns
  local button = ns.UI.Minimap.button
  h.eq(button ~= nil, true)
  h.eq(button:IsShown(), true)
  local window = ns.UI.Window.frame
  h.eq(window:IsShown(), true)
  button._scripts.OnClick(button, "LeftButton")
  h.eq(window:IsShown(), false)
  button._scripts.OnClick(button, "LeftButton")
  h.eq(window:IsShown(), true)
  button._scripts.OnClick(button, "RightButton")
  h.eq(ns.UI.OptionsPanel.frame:IsShown(), true)
  button._scripts.OnClick(button, "RightButton")
  h.eq(ns.UI.OptionsPanel.frame:IsShown(), false)
  -- the option hides and shows it again
  ns.Options.set(ns.db, "minimapButton", false)
  h.eq(button:IsShown(), false)
  ns.Options.set(ns.db, "minimapButton", true)
  h.eq(button:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the minimap button stays away when the option is off", function()
  local ctx = boot({ db = { settings = { minimapButton = false } } })
  ctx.env.Minimap = ctx.env.CreateFrame("Frame", "Minimap")
  startWorld(ctx, false)
  h.eq(ctx.ns.UI.Minimap.button, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the options page registers in the game's options window", function()
  local registered
  local ctx = boot()
  ctx.env.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
    RegisterAddOnCategory = function(category) registered = category end,
  }
  startWorld(ctx, false)
  local P = ctx.ns.UI.OptionsPanel
  h.eq(registered ~= nil, true)
  h.eq(registered.name, "LootPrice")
  h.eq(registered.frame, P.page)
  for _, spec in ipairs(ctx.ns.Options.list()) do
    h.eq(P.page.widgets[spec.key] ~= nil, true, spec.key)
  end
  P.page._scripts.OnShow(P.page)
  h.eq(ctx.errors, {})
end)

h.test("wiring: lock, scale, start hidden, gold display, sort and stale options take effect", function()
  local ctx = boot({ db = { settings = { startHidden = true, windowScale = 1.25, defaultSort = "name" } } })
  startWorld(ctx, false)
  local ns = ctx.ns
  local frame = ns.UI.Window.frame
  h.eq(frame:IsShown(), false)
  h.eq(frame:GetScale(), 1) -- the fake frame reports a fixed scale; the call itself must not fail
  h.eq(ns.db.sort, "name")
  -- lock: dragging does nothing
  local moved = false
  frame.StartMoving = function() moved = true end
  ns.Options.set(ns.db, "lockWindow", true)
  frame.header._scripts.OnDragStart()
  h.eq(moved, false)
  ns.Options.set(ns.db, "lockWindow", false)
  frame.header._scripts.OnDragStart()
  h.eq(moved, true)
  -- stale age and gold display
  ns.Options.set(ns.db, "staleHours", 2)
  h.eq(ns.Prices.STALE_AFTER, 7200)
  ns.Options.set(ns.db, "goldDisplay", "gold")
  h.eq(ns.Money.format(12345678), "1234g")
  ns.Options.set(ns.db, "windowScale", 0.8)
  -- the minimap reset button restores the default angle
  ns.db.settings.minimapAngle = 10
  ns.Options.spec("minimapReset").action()
  h.eq(ns.db.settings.minimapAngle, 225)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a valuable drop prints an alert, a cheap one does not", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.prices = { lookup = function() return { ah = 200000 } end } -- 20 g each
  ns.Options.set(ns.db, "alertGold", 50)
  local before = #ctx.printed
  fire(ctx, "CHAT_MSG_LOOT", LOOT) -- x3 = 60 g
  h.eq(#ctx.printed, before + 1)
  h.eq(ctx.printed[#ctx.printed]:find("valuable drop", 1, true) ~= nil, true)
  ns.Options.set(ns.db, "alertGold", 100)
  before = #ctx.printed
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(#ctx.printed, before)
  h.eq(ctx.errors, {})
end)


-- ---------------------------------------------------------------------------
-- Loot kinds, variants, currencies, places, automatic sessions

h.test("wiring: crafted items and purchases only count with the option on", function()
  local ctx = boot()
  ctx.env.LOOT_ITEM_CREATED_SELF = "You create: %s."
  startWorld(ctx, false)
  local ns = ctx.ns
  fire(ctx, "CHAT_MSG_LOOT", "You create: " .. LINK .. ".")
  h.eq(ns.session.items[2589], nil)
  fire(ctx, "MERCHANT_SHOW")
  fire(ctx, "CHAT_MSG_LOOT", "You receive item: " .. LINK .. ".")
  h.eq(ns.session.items[2589], nil)
  fire(ctx, "MERCHANT_CLOSED")
  fire(ctx, "CHAT_MSG_LOOT", "You receive item: " .. LINK .. ".") -- a quest reward
  h.eq(ns.session.items[2589].qty, 1)
  ns.Options.set(ns.db, "countCrafted", true)
  fire(ctx, "CHAT_MSG_LOOT", "You create: " .. LINK .. ".")
  h.eq(ns.session.items[2589].qty, 2)
  h.eq(ctx.errors, {})
end)

h.test("wiring: item variants get their own rows, prices and flash", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local asked = {}
  ns.prices = { lookup = function(_, id, link) asked[#asked + 1] = link return { ah = 100 } end }
  local v1 = "|cffa335ee|Hitem:50::::::::60::::2:1477:4802::::::|h[Sword]|h|r"
  local v2 = "|cffa335ee|Hitem:50::::::::60::::1:9999::::::|h[Sword]|h|r"
  fire(ctx, "CHAT_MSG_LOOT", "You receive loot: " .. v1 .. ".")
  fire(ctx, "CHAT_MSG_LOOT", "You receive loot: " .. v2 .. ".")
  h.eq(ns.session.items["50:1477:4802"].qty, 1)
  h.eq(ns.session.items["50:9999"].qty, 1)
  h.eq(ns.session.items["50:9999"].price, { ah = 100 })
  h.eq(asked[1], v1)
  h.eq(#ns.UI.Ledger.view.rows, 2)
  h.eq(ctx.errors, {})
end)

h.test("wiring: currencies are recorded and listed after the items", function()
  local ctx = boot()
  ctx.env.CURRENCY_GAINED_MULTIPLE = "You receive currency: %s x%d."
  startWorld(ctx, false)
  local ns = ctx.ns
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_CURRENCY", "You receive currency: |cff0070dd|Hcurrency:3008:0|h[Valorstones]|h|r x15.")
  h.eq(ns.session.currencies[3008].qty, 15)
  local rows = ns.UI.Ledger.view.rows
  h.eq(#rows, 2)
  h.eq(rows[2].isCurrency, true)
  ns.Options.set(ns.db, "showCurrencies", false)
  h.eq(#ns.UI.Ledger.view.rows, 1)
  slash(ctx, "reset")
  h.eq(ctx.env.LootPriceCharDB.history[1].currencies[3008].qty, 15)
  h.eq(ctx.errors, {})
end)

h.test("wiring: loot notes the place; a new session per instance with the option", function()
  local ctx = boot()
  local where = { zone = "Dornogal" }
  ctx.env.GetRealZoneText = function() return where.zone end
  ctx.env.GetInstanceInfo = function()
    if where.instance then return where.instance, "party", 2, "Heroic" end
    return where.zone, "none", 0, ""
  end
  startWorld(ctx, false)
  local ns = ctx.ns
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ns.session.places, { Dornogal = 1 })
  -- option off: entering a dungeon keeps the session
  where.instance = "The Stonevault"
  fire(ctx, "PLAYER_ENTERING_WORLD", false, false)
  h.eq(#ctx.env.LootPriceCharDB.history, 0)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ns.Session.placeList(ns.session.places), { "The Stonevault (Heroic)", "Dornogal" })
  -- option on: leaving archives the dungeon session and starts a new one
  ns.Options.set(ns.db, "instanceSession", true)
  where.instance = nil
  fire(ctx, "PLAYER_ENTERING_WORLD", false, false)
  local hist = ctx.env.LootPriceCharDB.history
  h.eq(#hist, 1)
  h.eq(hist[1].places, { "The Stonevault (Heroic)", "Dornogal" })
  h.eq(next(ns.session.items), nil)
  -- a loading screen inside the open world changes nothing
  fire(ctx, "PLAYER_ENTERING_WORLD", false, false)
  h.eq(#hist, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the clock pauses while AFK with the option on", function()
  local ctx = boot()
  local afk = false
  ctx.env.UnitIsAFK = function() return afk end
  startWorld(ctx, false)
  local ns = ctx.ns
  afk = true
  fire(ctx, "PLAYER_FLAGS_CHANGED", "player")
  h.eq(ns.session.running, true) -- option off
  ns.Options.set(ns.db, "afkPause", true)
  fire(ctx, "PLAYER_FLAGS_CHANGED", "player")
  h.eq(ns.session.running, false)
  afk = false
  fire(ctx, "PLAYER_FLAGS_CHANGED", "target")
  h.eq(ns.session.running, false)
  fire(ctx, "PLAYER_FLAGS_CHANGED", "player")
  h.eq(ns.session.running, true)
  -- a clock stopped by hand stays stopped
  slash(ctx, "stop")
  afk = true
  fire(ctx, "PLAYER_FLAGS_CHANGED", "player")
  afk = false
  fire(ctx, "PLAYER_FLAGS_CHANGED", "player")
  h.eq(ns.session.running, false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: /lp keep and /lp tsm go through the options", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "keep on")
  h.eq(ctx.env.LootPriceDB.settings.keepSession, true)
  slash(ctx, "tsm   DBMinBuyout  ")
  h.eq(ctx.env.LootPriceDB.settings.tsmSource, "DBMinBuyout")
  h.eq(ctx.errors, {})
end)

h.test("wiring: /lp export shows the History as CSV", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  slash(ctx, "export")
  local text = ctx.ns.UI.Export.frame.text
  h.eq(text:sub(1, #ctx.ns.History.CSV_HEADER), ctx.ns.History.CSV_HEADER)
  local _, lines = text:gsub("\n", "")
  h.eq(lines, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the bank's own slots rescan while it is open", function()
  local ctx = boot()
  startWorld(ctx, false)
  local slots = { { itemID = 2589, stackCount = 5 } }
  ctx.env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == -1 and #slots or 0 end,
    GetContainerItemInfo = function(bag, slot) return bag == -1 and slots[slot] or nil end,
  }
  fire(ctx, "BANKFRAME_OPENED")
  h.eq(ctx.env.LootPriceCharDB.bank.items[2589].qty, 5)
  slots[1] = { itemID = 2589, stackCount = 7 }
  fire(ctx, "PLAYERBANKSLOTS_CHANGED", 1)
  h.eq(ctx.env.LootPriceCharDB.bank.items[2589].qty, 7)
  fire(ctx, "BANKFRAME_CLOSED")
  slots[1] = { itemID = 2589, stackCount = 1 }
  fire(ctx, "PLAYERBANKSLOTS_CHANGED", 1)
  h.eq(ctx.env.LootPriceCharDB.bank.items[2589].qty, 7)
  h.eq(ctx.errors, {})
end)

h.test("wiring: with LibDataBroker and LibDBIcon the button is LibDBIcon's", function()
  local ctx = boot()
  local objects, registered, shown = {}, {}, {}
  local ldb = { NewDataObject = function(_, name, obj) objects[name] = obj return obj end }
  local icon = {
    Register = function(_, name, obj, saved) registered[name] = saved end,
    Show = function(_, name) shown[name] = true end,
    Hide = function(_, name) shown[name] = false end,
    Refresh = function() end,
  }
  ctx.env.LibStub = function(name) return ({ ["LibDataBroker-1.1"] = ldb, ["LibDBIcon-1.0"] = icon })[name] end
  startWorld(ctx, false)
  local ns = ctx.ns
  h.eq(objects.LootPrice ~= nil, true)
  h.eq(registered.LootPrice, ctx.env.LootPriceDB.minimapIcon)
  h.eq(ns.UI.Minimap.button, nil) -- no own button
  ns.Options.set(ns.db, "minimapButton", false)
  h.eq(shown.LootPrice, false)
  h.eq(ctx.env.LootPriceDB.minimapIcon.hide, true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ns.UI.Broker.update()
  h.eq(type(objects.LootPrice.text), "string")
  h.eq(ctx.errors, {})
end)

h.test("wiring: an event the client does not know does not stop the others", function()
  local ctx = boot()
  -- registered after boot: re-run init with a frame that rejects one event
  local frame = ctx.env.CreateFrame("Frame")
  local real = frame.RegisterEvent
  frame.RegisterEvent = function(self, ev)
    if ev == "CHAT_MSG_CURRENCY" then error("unknown event") end
    return real(self, ev)
  end
  ctx.env.CreateFrame = function() return frame end
  ctx.ns.Core.init()
  h.eq(frame._events.CHAT_MSG_LOOT, true)
  h.eq(frame._events.CHAT_MSG_CURRENCY, nil)
end)

h.test("wiring: TSM sale info shows under the name and follows its options", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.env.TSM_API = { GetCustomPriceValue = function(src)
    if src:find("SaleRate", 1, true) then return 600 end -- 0.6
    if src:find("SoldPerDay", 1, true) then return 50 end -- 0.5 a day
    return 111
  end }
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local ns = ctx.ns
  local L, colors = ns.UI.Ledger, ns.Theme.colors
  L.refresh()
  local row = L.list.pool[1]
  local hex = ns.Money.hex
  h.eq(row.market:GetText(), hex(colors.marketGood) .. "Sells well|r, " .. hex(colors.marketBad) .. "Low volume|r")
  ns.Options.set(ns.db, "saleRateGood", 0.7)
  ns.Options.set(ns.db, "soldMedium", 0)
  h.eq(row.market:GetText(), hex(colors.marketOk) .. "Sells okay|r, " .. hex(colors.marketOk) .. "Medium volume|r")
  ns.Options.set(ns.db, "showMarket", false)
  h.eq(row.market:GetText(), "")
  h.eq(ctx.errors, {})
end)

-- A stub client that knows where the player is (zone / subzone set by the test).
local function bootInZone(zone, sub)
  local ctx = boot()
  ctx.place = { zone = zone, sub = sub }
  ctx.env.GetRealZoneText = function() return ctx.place.zone end
  ctx.env.GetSubZoneText = function() return ctx.place.sub end
  return ctx
end

h.test("wiring: loot and gold are recorded per zone and subzone", function()
  local ctx = bootInZone("Waking Shores", "Dragonheart Outpost")
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = 1060
  ctx.place.sub = "Wingrest"
  fire(ctx, "ZONE_CHANGED")
  fire(ctx, "CHAT_MSG_LOOT", lootMsg(2592, 2))
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  local z = ctx.ns.session.zones["Waking Shores"]
  h.eq(z.subs["Dragonheart Outpost"].items[2589], 3)
  h.eq(z.subs["Dragonheart Outpost"].time, 60)
  h.eq(z.subs.Wingrest.items[2592], 2)
  h.eq(z.subs.Wingrest.gold, 500)
  ctx.now = 1100
  slash(ctx, "reset")
  local e = ctx.env.LootPriceCharDB.history[1]
  h.eq(e.zones["Waking Shores"].subs.Wingrest.time, 40)
  h.eq(ctx.errors, {})
end)

local function rowsWith(view, field, value)
  for i, r in ipairs(view.rows) do
    if r[field] == value then return i, r end
  end
end

h.test("wiring: the Zones sub-tab groups all sessions by zone and subzone", function()
  local ctx = bootInZone("Waking Shores", "Wingrest")
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  ctx.place.zone, ctx.place.sub = "Ohn'ahran Plains", "Teerakai"
  fire(ctx, "ZONE_CHANGED_NEW_AREA")
  fire(ctx, "CHAT_MSG_LOOT", lootMsg(2592, 2)) -- running session
  local L = ctx.ns.UI.Ledger
  L.setTab("history")
  h.eq(L.subtab, "sessions")
  L.setSubtab("zones")
  h.eq(#L.view.rows, 2)
  h.eq(L.view.kind, "zones")
  local i, zone = rowsWith(L.view, "zoneKey", "Waking Shores")
  h.eq(zone.subKey, nil)
  L.list.onRowClick(zone)
  local sub = L.view.rows[i + 1]
  h.eq(sub.subKey, "Wingrest")
  L.list.onRowClick(sub)
  h.eq(L.view.rows[i + 2].id, 2589)
  h.eq(L.view.rows[i + 2].quantity, 3)
  L.list.onRowClick(L.view.rows[i]) -- the zone again: collapsed
  h.eq(#L.view.rows, 2)
  h.eq(ctx.ns.db.subtab.history, "zones")
  h.eq(ctx.errors, {})
end)

h.test("wiring: the sub-tab row only shows on History and the choice survives a reload", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  local row4 = ctx.ns.UI.Window.frame.header.row4
  L.setTab("session")
  h.eq(row4:IsShown(), false)
  L.setTab("history")
  h.eq(row4:IsShown(), true)
  L.setSubtab("zones")
  local reload = boot({ db = ctx.env.LootPriceDB, chardb = ctx.env.LootPriceCharDB, now = 2000 })
  startWorld(reload, true)
  h.eq(reload.ns.UI.Ledger.tab, "history")
  h.eq(reload.ns.UI.Ledger.subtab, "zones")
  h.eq(reload.ns.UI.Ledger.view.kind, "zones")
  h.eq(reload.errors, {})
end)

h.test("wiring: quest items sit in their own group in Zones only", function()
  local ctx = bootInZone("Waking Shores", "Wingrest")
  ctx.env.C_Item.GetItemInfoInstant = function(id)
    return id, "t", "st", "", 1, id == 2592 and 12 or 7, 0
  end
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_LOOT", lootMsg(2592, 2))
  local L = ctx.ns.UI.Ledger
  L.setTab("session")
  local sessionBest = L.view.totals.best
  L.setTab("history")
  L.setSubtab("zones")
  local last = L.view.rows[#L.view.rows]
  h.eq(last.zoneKey, ctx.ns.View.QUEST_ZONE)
  h.eq(last.quantity, 1)
  h.eq(L.view.totals.best, sessionBest - last.value)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Zones follows History pruning", function()
  local ctx = bootInZone("Waking Shores", "Wingrest")
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  ctx.place.zone = "Azure Span"
  fire(ctx, "ZONE_CHANGED_NEW_AREA")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  local L = ctx.ns.UI.Ledger
  L.setTab("history")
  L.setSubtab("zones")
  h.eq(#L.view.rows, 2)
  ctx.ns.Options.set(ctx.ns.db, "historyLimit", 1)
  L.refresh()
  h.eq(#L.view.rows, 1)
  h.eq(L.view.rows[1].zoneKey, "Azure Span")
  h.eq(ctx.errors, {})
end)
