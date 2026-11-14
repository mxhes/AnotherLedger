-- Integration: loads every file of the .toc, in order, into one namespace with
-- a stub client environment and drives the real event flow.
local h = ...

local NUMBERS = {
  GetWidth = 300, GetHeight = 300, GetStringWidth = 50, GetStringHeight = 10,
  GetEffectiveScale = 1, GetScale = 1, GetLeft = 0, GetRight = 300, GetTop = 300,
  GetBottom = 0, GetFrameLevel = 1, GetValue = 0, GetAlpha = 1, GetNumPoints = 0,
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
    local chunk, err = loadfile("LootPrice/" .. file, "t", env)
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
    LootPriceOptionsPage = true, LootPriceMinimapButton = true,
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
  h.eq(L.view.kind, nil)
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
