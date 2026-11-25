-- Integration: loads every file of the .toc, in order, into one namespace with
-- a stub client environment and drives the real event flow.
local h = ...

local NUMBERS = {
  GetWidth = 300, GetHeight = 300, GetStringWidth = 50, GetStringHeight = 10,
  GetEffectiveScale = 1, GetScale = 1, GetLeft = 0, GetRight = 300, GetTop = 300,
  GetBottom = 0, GetValue = 0, GetAlpha = 1, GetNumPoints = 0,
}

-- Methods every fake frame shares (one set per run: a test makes thousands of
-- fakes, and building them per fake was a large part of the suite's time).
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
function methods.EnableMouse(self, on) self._mouse = on end
function methods.RegisterEvent(self, ev) self._events[ev] = true end
function methods.SetSize(self, w, hh) self._w, self._h = w, hh end
function methods.SetWidth(self, w) self._w = w end
function methods.SetHeight(self, hh) self._h = hh end
function methods.GetWidth(self) return self._w or 300 end
function methods.GetHeight(self) return self._h or 300 end
function methods.GetName(self) return self._name end
function methods.SetFrameLevel(self, l) self._level = l end
function methods.GetFrameLevel(self) return self._level or 1 end
function methods.SetClipsChildren(self, v) self._clips = v end
function methods.SetTexture(self, t) self._texture = t end
function methods.SetBackdrop(self, b) self._backdrop = b end
function methods.SetVertexColor(self, r, g, b, a) self._vertex = { r, g, b, a } end
for k, n in pairs(NUMBERS) do
  if not methods[k] then methods[k] = function() return n end end
end
local function noop() end

-- What a missing field answers: a shared method, nil for "_" fields, another
-- fake for Create* / Get*, else a no-op. Cached per key name.
local kindOf = {}
local function fieldKind(k)
  local kind = kindOf[k]
  if kind == nil then
    if type(k) ~= "string" or k:sub(1, 1) == "_" then kind = "none"
    elseif k:match("^Create") or k:match("^Get") then kind = "fake"
    else kind = "noop" end
    kindOf[k] = kind
  end
  return kind
end

local function newFake(env, name)
  local f = { _scripts = {}, _events = {}, _shown = true, _text = "", _name = name }
  local makeFake
  setmetatable(f, { __index = function(_, k)
    local m = methods[k]
    if m then return m end
    local kind = fieldKind(k)
    if kind == "noop" then return noop end
    if kind == "none" then return nil end
    makeFake = makeFake or function() return newFake(env) end
    return makeFake
  end })
  if name then env[name] = f end
  return f
end

local function readToc()
  local files = {}
  local fh = assert(io.open("AnotherLedger/AnotherLedger.toc", "r"))
  for line in fh:lines() do
    line = line:gsub("\r", "")
    if line ~= "" and line:sub(1, 2) ~= "##" and line:match("%.lua$") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  fh:close()
  return files
end

-- The .toc's files as precompiled bytecode, compiled once per run: a boot only
-- loads them into its own env (parsing ~40 files per test was most of the
-- suite's time). Error messages keep the file names and line numbers.
local bytecodeCache
local function addonChunks()
  if not bytecodeCache then
    bytecodeCache = {}
    for _, file in ipairs(readToc()) do
      local chunk = assert(loadfile("AnotherLedger/" .. file))
      bytecodeCache[#bytecodeCache + 1] = string.dump(chunk)
    end
  end
  return bytecodeCache
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
  -- A test that seeds `settings` (the shape before profiles) gets them as an
  -- already migrated "Default" profile, so the options still apply.
  local seed = opts.db
  if type(seed) == "table" and type(seed.settings) == "table" and seed.profiles == nil then
    seed.profiles, seed.profilesMigrated = { Default = seed.settings }, true
  end
  env.AnotherLedgerDB = opts.db
  env.AnotherLedgerCharDB = opts.chardb

  ctx.baseline = {}
  for k in pairs(env) do ctx.baseline[k] = true end

  local ns = {}
  for _, code in ipairs(addonChunks()) do
    local chunk, err
    if setfenv then -- Lua 5.1 (the client's version)
      chunk, err = loadstring(code)
      if chunk then setfenv(chunk, env) end
    else
      chunk, err = load(code, nil, "b", env)
    end
    assert(chunk, err)
    chunk("AnotherLedger", ns)
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

local function slash(ctx, msg) ctx.env.SlashCmdList["ANOTHERLEDGER"](msg) end

local LINK = "|cffffffff|Hitem:2589::::::::60:::::::::|h[Linen Cloth]|h|r"
local LOOT = "You receive loot: " .. LINK .. "x3."

-- The rows of a view without the History day / week headings.
local function sessions(view)
  local out = {}
  for _, r in ipairs(view.rows) do
    if not r.isHeading then out[#out + 1] = r end
  end
  return out
end

local function startWorld(ctx, isReload)
  fire(ctx, "ADDON_LOADED", "AnotherLedger")
  fire(ctx, "PLAYER_ENTERING_WORLD", not isReload, isReload and true or false)
end

-- A player can install the libraries as their own addons (and update them apart
-- from AnotherLedger). Every library folder embeds.xml loads must be an OptionalDep
-- (same name as the standalone addon's folder), so an installed copy loads
-- first; LibStub then skips our bundled copy unless ours is newer.
h.test("wiring: every bundled library is an OptionalDep", function()
  local fh = assert(io.open("AnotherLedger/AnotherLedger.toc", "r"))
  local toc = fh:read("*a")
  fh:close()
  local deps = {}
  local line = toc:match("## OptionalDeps:([^\r\n]*)") or ""
  for name in line:gmatch("[^,%s]+") do deps[name] = true end
  fh = assert(io.open("AnotherLedger/embeds.xml", "r"))
  local xml = fh:read("*a")
  fh:close()
  local count = 0
  for folder in xml:gmatch('file="Libs[\\/]([^\\/"]+)[\\/]') do
    count = count + 1
    h.eq(deps[folder], true, folder .. " missing from ## OptionalDeps")
  end
  h.eq(count, 4)
end)

h.test("wiring: toc files load and the slash commands register", function()
  local ctx = boot()
  h.eq(ctx.env.SLASH_ANOTHERLEDGER1, "/al")
  h.eq(ctx.env.SLASH_ANOTHERLEDGER2, "/anotherledger")
  h.eq(type(ctx.env.SlashCmdList.ANOTHERLEDGER), "function")
  h.eq(ctx.errors, {})
end)

h.test("wiring: saved data under the old name LootPrice is taken over", function()
  local ctx = boot()
  ctx.env.LootPriceDB = { ignored = { [7] = "Old" } }
  ctx.env.LootPriceCharDB = { history = { { startedAt = 5 } } }
  startWorld(ctx, false)
  h.eq(ctx.env.AnotherLedgerDB.ignored[7], "Old")
  h.eq(ctx.env.AnotherLedgerCharDB.history[1].startedAt, 5)
  h.eq(ctx.env.LootPriceDB, nil)
  h.eq(ctx.env.LootPriceCharDB, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: saved data under the new name wins over the old one", function()
  local ctx = boot({ db = { ignored = { [8] = "New" } } })
  ctx.env.LootPriceDB = { ignored = { [7] = "Old" } }
  startWorld(ctx, false)
  h.eq(ctx.env.AnotherLedgerDB.ignored[8], "New")
  h.eq(ctx.env.AnotherLedgerDB.ignored[7], nil)
end)

h.test("wiring: login flow records loot and saves the session", function()
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(ctx.errors, {})
  h.eq(type(ctx.ns.session), "table")
  h.eq(ctx.ns.UI.Ledger.frame ~= nil, true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ctx.ns.session.items[2589].qty, 3)
  h.eq(ctx.env.AnotherLedgerCharDB.session, ctx.ns.session)
  h.eq(ctx.errors, {})
  h.eq(#ctx.ns.UI.Ledger.view.rows, 1)
end)

h.test("wiring: loot before the world is entered is ignored", function()
  local ctx = boot()
  fire(ctx, "ADDON_LOADED", "AnotherLedger")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ctx.ns.session, nil)
  slash(ctx, "start")
  h.eq(ctx.printed[#ctx.printed]:find("not ready", 1, true) ~= nil, true)
end)

h.test("wiring: demo then reset restores the price cache", function()
  local ctx = boot()
  startWorld(ctx, false)
  local cache = ctx.env.AnotherLedgerDB.cache
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

h.test("wiring: demo loot never reaches History, also after a relog", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "demo")
  h.eq(ctx.ns.session.demo, true)
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
  local relog = boot({ db = db, chardb = chardb, now = 3000 })
  startWorld(relog, false) -- keep session off: the old one would be archived
  h.eq(relog.errors, {})
  h.eq(#chardb.history, 0)
  h.eq(next(relog.ns.session.items), nil)
  h.eq(relog.ns.session.demo, nil)
  -- Real loot after a reset is archived again.
  fire(relog, "CHAT_MSG_LOOT", LOOT)
  slash(relog, "reset")
  h.eq(#chardb.history, 1)
end)

h.test("wiring: the sort button keeps the Gold/h label in Zones after a redraw", function()
  local ctx = boot()
  startWorld(ctx, false)
  local Ledger = ctx.ns.UI.Ledger
  Ledger.setTab("history")
  Ledger.setSubtab("zones")
  Ledger.setSort("perHour")
  Ledger.refresh()
  h.eq(ctx.ns.UI.FilterBar.sortButton:GetText(), "Sort: Gold/h")
  h.eq(ctx.errors, {})
end)

h.test("wiring: each History view keeps its own sort; Sessions starts newest first", function()
  local ctx = boot()
  startWorld(ctx, false)
  local Ledger, F = ctx.ns.UI.Ledger, ctx.ns.UI.FilterBar
  local db = ctx.env.AnotherLedgerDB
  db.sort = "name"
  Ledger.setTab("history")
  Ledger.setSubtab("sessions")
  h.eq(Ledger.currentSort(), "recent")
  h.eq(F.sortButton:GetText(), "Sort: Recent")
  F.sortButton._scripts.OnClick() -- recent -> perHour, Session tab untouched
  h.eq(Ledger.currentSort(), "perHour")
  h.eq(db.sort, "name")
  Ledger.setSubtab("zones")
  h.eq(Ledger.currentSort(), "ah")
  Ledger.setTab("session")
  h.eq(Ledger.currentSort(), "name")
  h.eq(F.sortButton:GetText(), "Sort: Name")
  Ledger.setTab("history")
  Ledger.setSubtab("sessions")
  h.eq(Ledger.currentSort(), "perHour")
  h.eq(ctx.errors, {})
end)

h.test("wiring: History kept asks before deleting, reset asks for a valuable session", function()
  local ctx = boot()
  startWorld(ctx, false)
  local shown = {}
  ctx.env.StaticPopup_Show = function(name) shown[#shown + 1] = ctx.env.StaticPopupDialogs[name] end
  local history = ctx.env.AnotherLedgerCharDB.history
  for i = 1, 3 do history[i] = { startedAt = i, elapsed = 60, gold = 1, nItems = 0, vendor = 0, ah = 0, items = {} } end
  local spec = ctx.ns.Options.spec("historyLimit")
  h.eq(spec.confirm(5), nil) -- nothing would be deleted
  h.eq(spec.confirm(-1), nil)
  h.eq(spec.confirm(1):find("2 oldest", 1, true) ~= nil, true)

  -- 150 gold of raw gold, one item: Reset asks first, Cancel keeps it.
  ctx.ns.Core.recordGold(1500000)
  slash(ctx, "reset")
  h.eq(#shown, 1)
  h.eq(ctx.ns.session.gold, 1500000)
  shown[1].OnCancel()
  h.eq(ctx.ns.session.gold, 1500000)
  shown[1].OnAccept()
  h.eq(ctx.ns.session.gold, 0)
  h.eq(#history, 4)
  h.eq(ctx.errors, {})
end)

-- A stub MenuUtil that keeps every opened menu: a list of { text, kind,
-- click, checked } (kind "title" / "button" / "checkbox" / "radio").
-- A loot message for item `id` (name "Item<id>", 25c vendor price each).
local function itemLoot(id, qty)
  return "You receive loot: |cffffffff|Hitem:" .. id .. "::::::::60:::::::::|h[Item" .. id .. "]|h|r" .. "x" .. qty .. "."
end

local function captureMenus(ctx)
  local menus = {}
  local function root(items)
    local function add(kind) return function(_, text, a, b)
      local click = kind == "button" and a or b
      items[#items + 1] = { text = text, kind = kind, click = click, checked = kind ~= "button" and a or nil }
    end end
    return { CreateTitle = add("title"), CreateButton = add("button"), CreateCheckbox = add("checkbox"),
      CreateRadio = add("radio") }
  end
  ctx.env.MenuUtil = { CreateContextMenu = function(anchor, gen)
    local items = { anchor = anchor }
    gen(nil, root(items))
    menus[#menus + 1] = items
  end }
  return menus
end

local function menuItem(menu, text)
  for _, it in ipairs(menu) do
    if it.text == text then return it end
  end
  return nil
end

h.test("wiring: a History session's menu deletes it, /al undo brings it back", function()
  local ctx = boot()
  startWorld(ctx, false)
  local menus = captureMenus(ctx)
  local shown = {}
  ctx.env.StaticPopup_Show = function(name) shown[#shown + 1] = ctx.env.StaticPopupDialogs[name] end
  local history = ctx.env.AnotherLedgerCharDB.history
  for i = 1, 3 do history[i] = { startedAt = 4 - i, elapsed = 60, gold = 1, nItems = 0, vendor = 0, ah = 0, items = {} } end
  local Ledger = ctx.ns.UI.Ledger
  local L = ctx.ns.L
  Ledger.setTab("history")
  Ledger.toggleHistory(3) -- the oldest one is open
  local row = sessions(Ledger.view)[2]
  h.eq(row.historyIndex, 1)
  Ledger.list.onRowClick(row, "RightButton", "rowFrame")
  local menu = menus[#menus]
  h.eq(menu.anchor, "rowFrame")
  h.eq(menu[1].kind, "title")
  h.eq(menuItem(menu, L["Add note"]) ~= nil, true)
  h.eq(menuItem(menu, L["Rename"]) ~= nil, true)
  menuItem(menu, L["Delete"]).click() -- asks first
  h.eq(#shown, 1); h.eq(#history, 3)
  shown[1].OnAccept()
  h.eq(#history, 2); h.eq(history[1].startedAt, 2)
  h.eq(Ledger.historyIndex, 2) -- still the same (oldest) session
  h.eq(ctx.printed[#ctx.printed]:find("/al undo", 1, true) ~= nil, true)
  slash(ctx, "undo")
  h.eq(#history, 3); h.eq(history[1].startedAt, 3)

  ctx.ns.Options.spec("clearHistory").action()
  h.eq(#history, 3) -- asks first
  shown[#shown].OnAccept()
  h.eq(#history, 0)
  h.eq(ctx.env.AnotherLedgerCharDB.history == history, true)
  slash(ctx, "undo")
  h.eq(#history, 3)
  slash(ctx, "undo")
  h.eq(ctx.printed[#ctx.printed]:find(L["nothing to undo."], 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: merging History sessions, two and more, and /al undo splits them", function()
  local ctx = boot()
  startWorld(ctx, false)
  local menus = captureMenus(ctx)
  local history = ctx.env.AnotherLedgerCharDB.history
  for i = 1, 3 do
    history[i] = { startedAt = 4000 - i * 1000, elapsed = 600, gold = 100 * i, nItems = 0, vendor = 0, ah = 0,
      items = {} }
  end
  local Ledger, L = ctx.ns.UI.Ledger, ctx.ns.L
  Ledger.setTab("history")
  Ledger.toggleHistory(2)
  local function menuFor(index)
    for _, r in ipairs(Ledger.view.rows) do
      if r.historyIndex == index then
        Ledger.list.onRowClick(r, "RightButton", "f")
        return menus[#menus]
      end
    end
  end
  -- The oldest session has nothing older to merge with.
  h.eq(menuItem(menuFor(3), L["Merge with the older session"]), nil)
  menuItem(menuFor(1), L["Merge with the older session"]).click()
  h.eq(#history, 2)
  h.eq({ history[1].startedAt, history[1].elapsed, history[1].gold }, { 2000, 1200, 300 })
  h.eq(Ledger.historyIndex, 1) -- the opened session is in the merged one
  menuItem(menuFor(1), L["Merge with the older session"]).click()
  h.eq(#history, 1)
  h.eq({ history[1].startedAt, history[1].elapsed, history[1].gold }, { 1000, 1800, 600 })
  slash(ctx, "undo")
  h.eq(#history, 2)
  h.eq(history[1].elapsed, 1200)
  slash(ctx, "undo")
  h.eq(#history, 3)
  h.eq({ history[1].gold, history[2].gold, history[3].gold }, { 100, 200, 300 })
  h.eq(ctx.errors, {})
end)

h.test("wiring: Reset asks for the saved session's note with the option on", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local popup
  ctx.env.StaticPopup_Show = function(name) popup = ctx.env.StaticPopupDialogs[name] end
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  h.eq(popup, nil) -- off by default
  ns.Options.set(ns.db, "resetNote", true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  h.eq(popup ~= nil and popup.hasEditBox, true)
  local box = { text = "", SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
    HighlightText = function() end }
  popup.OnShow({ editBox = box })
  box.text = "Wingrest herbs"
  popup.OnAccept({ editBox = box })
  local history = ctx.env.AnotherLedgerCharDB.history
  h.eq(#history, 2)
  h.eq(history[1].note, "Wingrest herbs"); h.eq(history[2].note, nil)
  -- an empty session saves nothing, so nothing to ask
  popup = nil
  slash(ctx, "reset")
  h.eq(popup, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a note on a History session shows on its row and is searched", function()
  local ctx = boot()
  startWorld(ctx, false)
  local menus = captureMenus(ctx)
  local popup
  ctx.env.StaticPopup_Show = function(name) popup = ctx.env.StaticPopupDialogs[name] end
  local history = ctx.env.AnotherLedgerCharDB.history
  history[1] = { startedAt = 5, elapsed = 60, gold = 1, nItems = 0, vendor = 0, ah = 0, items = {} }
  history[2] = { startedAt = 4, elapsed = 60, gold = 1, nItems = 0, vendor = 0, ah = 0, items = {} }
  local Ledger, L = ctx.ns.UI.Ledger, ctx.ns.L
  Ledger.setTab("history")
  Ledger.list.onRowClick(sessions(Ledger.view)[2], "RightButton", "f")
  menuItem(menus[#menus], L["Add note"]).click()
  h.eq(popup.hasEditBox, true)
  local box = { text = "", SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
    HighlightText = function() end }
  popup.OnShow({ editBox = box })
  h.eq(box.text, "")
  box.text = "  Wingrest herbs "
  popup.OnAccept({ editBox = box })
  h.eq(history[2].note, "Wingrest herbs")
  h.eq(sessions(Ledger.view)[2].name:find("Wingrest herbs", 1, true) ~= nil, true)
  -- Editing shows the note; the search finds it.
  Ledger.list.onRowClick(sessions(Ledger.view)[2], "RightButton", "f")
  menuItem(menus[#menus], L["Edit note"]).click()
  popup.OnShow({ GetEditBox = function() return box end })
  h.eq(box.text, "Wingrest herbs")
  ctx.ns.db.filter.search = "wingrest"
  Ledger.refresh()
  h.eq(#sessions(Ledger.view), 1)
  h.eq(sessions(Ledger.view)[1].entry, history[2])
  h.eq(ctx.errors, {})
end)

h.test("wiring: an ignored item leaves the lists and totals; the options menu takes it back", function()
  local ctx = boot()
  startWorld(ctx, false)
  local menus = captureMenus(ctx)
  local L, Ledger = ctx.ns.L, ctx.ns.UI.Ledger
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(7, 4))
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(8, 2))
  h.eq(#Ledger.view.rows, 2)
  h.eq(Ledger.view.totals.vendor, 150)
  local row = Ledger.view.rows[ctx.ns.View.indexOf(Ledger.view.rows, 7)]
  Ledger.list.onRowClick(row, "RightButton", "f")
  menuItem(menus[#menus], L["Ignore this item"]).click()
  h.eq(ctx.env.AnotherLedgerDB.ignored[7], row.name)
  h.eq(#Ledger.view.rows, 1)
  h.eq(Ledger.view.totals.vendor, 50)
  h.eq(ctx.ns.Core.sessionValue(ctx.ns.session), 50)
  -- Still recorded: taking it off the list brings it back.
  h.eq(ctx.ns.session.items[7].qty, 4)
  ctx.ns.Options.spec("ignoredItems").action("button")
  local menu = menus[#menus]
  h.eq(menu.anchor, "button")
  h.eq(menu[1].text, row.name)
  h.eq(menu[1].checked(), true)
  menu[1].click()
  h.eq(ctx.env.AnotherLedgerDB.ignored[7], nil)
  h.eq(#Ledger.view.rows, 2)
  -- An empty list says so in chat instead of an empty menu.
  local n = #menus
  ctx.ns.Options.spec("ignoredItems").action("button")
  h.eq(#menus, n)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the session goals announce themselves once", function()
  local ctx = boot({ db = { settings = { goalGold = 1, goalMinutes = 2 } } })
  startWorld(ctx, false)
  local Core = ctx.ns.Core
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(7, 200)) -- 200 x 25c = 50s
  h.eq(ctx.ns.UI.Ledger.view.goal.value, 5000)
  h.eq(ctx.ns.UI.Ledger.view.goal.goal, 10000)
  local before = #ctx.printed
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(8, 200)) -- 1g in all
  h.eq(#ctx.printed, before + 1)
  h.eq(ctx.printed[#ctx.printed]:find("session goal reached", 1, true) ~= nil, true)
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(9, 1))
  h.eq(#ctx.printed, before + 1) -- once
  ctx.now = ctx.now + 121
  Core.checkGoals(false)
  h.eq(#ctx.printed, before + 2)
  Core.checkGoals(false)
  h.eq(#ctx.printed, before + 2)
  -- A reset starts the goals over.
  slash(ctx, "reset")
  h.eq(ctx.ns.session.goalsNoted, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: History is account-wide; Zones reads every character's", function()
  local alt = { { startedAt = 50, elapsed = 3600, gold = 0, nItems = 1, vendor = 25, ah = 0, items = {
    [7] = { id = 7, key = 7, qty = 1 } }, places = { "Alt place" } } }
  local own = { { startedAt = 40, elapsed = 3600, gold = 0, nItems = 0, vendor = 0, ah = 0, items = {} } }
  local ctx = boot({ db = { histories = { ["Alt-Realm"] = alt } }, chardb = { history = own } })
  ctx.env.UnitName = function() return "Me" end
  ctx.env.GetRealmName = function() return "Realm" end
  startWorld(ctx, false)
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
  h.eq(ctx.ns.Core.character, "Me-Realm")
  h.eq(chardb.history == db.histories["Me-Realm"], true)
  h.eq(#chardb.history, 1)
  local list = ctx.ns.Core.zoneHistory()
  h.eq(#list, 2)
  ctx.ns.Options.set(ctx.ns.db, "accountZones", false)
  h.eq(#ctx.ns.Core.zoneHistory(), 1)
  ctx.ns.Options.set(ctx.ns.db, "accountZones", true)
  local Ledger = ctx.ns.UI.Ledger
  Ledger.setTab("history")
  Ledger.setSubtab("zones")
  local altRows = 0
  for _, r in ipairs(Ledger.view.rows) do
    if r.zoneKey == "Alt place" and r.subKey == nil then altRows = altRows + 1 end
  end
  h.eq(altRows, 1)
  -- Saved once: the character's own copy is dropped at logout.
  fire(ctx, "PLAYER_LOGOUT")
  h.eq(chardb.history, nil)
  local relog = boot({ db = db, chardb = chardb, now = 5000 })
  relog.env.UnitName = function() return "Me" end
  relog.env.GetRealmName = function() return "Realm" end
  startWorld(relog, false)
  h.eq(#relog.env.AnotherLedgerCharDB.history, 1)
  h.eq(relog.env.AnotherLedgerCharDB.history[1].startedAt, 40)
  h.eq(ctx.errors, {}); h.eq(relog.errors, {})
end)

h.test("wiring: each tab keeps its scroll position for the login", function()
  local ctx = boot()
  startWorld(ctx, false)
  for id = 1, 60 do fire(ctx, "CHAT_MSG_LOOT", itemLoot(id, 1)) end
  local Ledger = ctx.ns.UI.Ledger
  Ledger.list:SetOffset(20)
  h.eq(Ledger.list.offset, 20)
  Ledger.setTab("bags")
  h.eq(Ledger.list.offset, 0)
  Ledger.setTab("session")
  h.eq(Ledger.list.offset, 20)
  h.eq(ctx.errors, {})
end)

h.test("wiring: /al export copies the session or Zones as CSV", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(7, 4))
  ctx.ns.db.filter.search = "nothing like this" -- an export ignores the filter
  slash(ctx, "export session")
  local text = ctx.ns.UI.Export.frame.text
  h.eq(text:match("^[^\n]+"), ctx.ns.View.ITEMS_CSV_HEADER)
  -- name (the stub client's item name), quantity, vendor, AH, destroy, counted, kind
  local line = text:match("\n(.*)$")
  h.eq(line:sub(-#",4,0.0100,,,0.0100,vendor"), ",4,0.0100,,,0.0100,vendor")
  h.eq(line:sub(1, 4), "Item")
  slash(ctx, "export zones")
  h.eq(ctx.ns.UI.Export.frame.text:match("^[^\n]+"), ctx.ns.View.ZONES_CSV_HEADER)
  slash(ctx, "export mobs")
  h.eq(ctx.ns.UI.Export.frame.text:match("^[^\n]+"), ctx.ns.View.MOBS_CSV_HEADER)
  slash(ctx, "export")
  h.eq(ctx.ns.UI.Export.frame.text:match("^[^\n]+"), ctx.ns.History.CSV_HEADER)
  slash(ctx, "export nonsense")
  h.eq(ctx.printed[#ctx.printed]:find("export", 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: key bindings name their commands; /al clock switches the clock", function()
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(ctx.env.BINDING_HEADER_ANOTHERLEDGER, "AnotherLedger")
  h.eq(type(ctx.env.BINDING_NAME_ANOTHERLEDGER_TOGGLE), "string")
  local fh = assert(io.open("AnotherLedger/Bindings.xml", "r"))
  local xml = fh:read("*a")
  fh:close()
  -- Every bound command exists: an unknown one would print the whole help.
  local commands = 0
  for cmd in xml:gmatch('SlashCmdList%["ANOTHERLEDGER"%]%("(%a+)"%)') do
    local before = #ctx.printed
    slash(ctx, cmd)
    h.eq(#ctx.printed - before <= 1, true)
    commands = commands + 1
  end
  h.eq(commands, 4)
  for name in xml:gmatch('name="(ANOTHERLEDGER_%u+)"') do
    h.eq(type(ctx.env["BINDING_NAME_" .. name]), "string")
  end
  local running = ctx.ns.session.running
  slash(ctx, "clock")
  h.eq(ctx.ns.session.running, not running)
  slash(ctx, "clock")
  h.eq(ctx.ns.session.running, running)
  h.eq(ctx.errors, {})
end)

h.test("wiring: demo on a stopped session seeds nothing", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "stop")
  slash(ctx, "demo")
  h.eq(ctx.printed[#ctx.printed]:find("stopped", 1, true) ~= nil, true)
  h.eq(next(ctx.ns.session.items), nil)
  h.eq(ctx.env.AnotherLedgerDB.cache["EU-7"], nil)
end)

h.test("wiring: logout suspends the session", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.now = 1100
  fire(ctx, "PLAYER_LOGOUT")
  h.eq(ctx.env.AnotherLedgerCharDB.session.elapsedBase, 100)
  h.eq(ctx.env.AnotherLedgerCharDB.session.runningSince, nil)
end)

h.test("wiring: a /reload keeps the session with keep off, a relog starts fresh", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = 1050
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
  h.eq(db.profiles.Default.keepSession, false)

  local reload = boot({ db = db, chardb = chardb, now = 2000 })
  startWorld(reload, true)
  h.eq(reload.errors, {})
  h.eq(reload.ns.session.items[2589].qty, 3)
  h.eq(reload.ns.session.runningSince, 2000)

  db.profiles.Default.minSessionMinutes = 0 -- a short session would continue
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
    AnotherLedgerDB = true, AnotherLedgerCharDB = true, SLASH_ANOTHERLEDGER1 = true,
    SLASH_ANOTHERLEDGER2 = true, AnotherLedgerWindow = true, AnotherLedgerMenu = true,
    AnotherLedgerOptionsPage = true, AnotherLedgerMinimapButton = true, AnotherLedgerExport = true,
    BINDING_HEADER_ANOTHERLEDGER = true, BINDING_NAME_ANOTHERLEDGER_TOGGLE = true,
    BINDING_NAME_ANOTHERLEDGER_COMPACT = true, BINDING_NAME_ANOTHERLEDGER_CLOCK = true,
    BINDING_NAME_ANOTHERLEDGER_SCAN = true,
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
  fire(ctx, "ADDON_LOADED", "AnotherLedger")
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
  h.eq(ctx.env.AnotherLedgerDB.tab, "bags")
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
  -- One message before the first scan, and no "0c" total (view.unscanned).
  h.eq(L.view.note, nil)
  h.eq(L.view.unscanned, true)
  -- the default bank record (scannedAt 0) is no scan: never "empty"
  h.eq(L.view.empty, "Not scanned yet. Open your bank once to scan it.")
  fire(ctx, "BANKFRAME_OPENED")
  h.eq(ctx.errors, {})
  h.eq(#L.view.rows, 2)
  h.eq(ctx.env.AnotherLedgerCharDB.bank.scannedAt, ctx.now)
  fire(ctx, "BANKFRAME_CLOSED")
  -- away from the bank the scan is kept, the bags changing does not touch it
  bagEnv(ctx, {})
  fire(ctx, "BAG_UPDATE_DELAYED")
  h.eq(ctx.env.AnotherLedgerCharDB.bank.items[2589].qty, 4)
  ctx.now = ctx.now + 7200
  L.refresh()
  h.eq(L.view.note, "Scanned 2h ago")
  h.eq(L.view.unscanned, false)
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
  h.eq(ctx.env.AnotherLedgerCharDB.bank.items[2589].qty, 4)
  bagEnv(ctx, {})
  fire(ctx, "BAG_UPDATE_DELAYED") -- bank open: a later empty scan is real
  h.eq(next(ctx.env.AnotherLedgerCharDB.bank.items), nil)
end)

h.test("wiring: the last tab survives a reload", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.ns.UI.Ledger.setTab("bags")
  local reload = boot({ db = ctx.env.AnotherLedgerDB, chardb = ctx.env.AnotherLedgerCharDB, now = 2000 })
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
  ctx.ns.Options.set(ctx.ns.db, "rawGold", "apart")
  L.refresh()
  h.eq(footer:GetHeight(), 54)
  h.eq(summary.cells.total.label:IsShown(), false)
  ctx.ns.Options.set(ctx.ns.db, "rawGold", "row")
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

h.test("wiring: the font outline and shadow options restyle the text live and re-lay out", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local L, F = ns.UI.Ledger, ns.UI.Fonts
  local relayouts, styled = 0, nil
  local realRelayout, realStyle = L.relayout, F.applyStyle
  L.relayout = function() relayouts = relayouts + 1; return realRelayout() end
  F.applyStyle = function(o, s) styled = { o, s }; return realStyle(o, s) end
  local S = ns.Theme.sizes
  local timerW, charPx = S.timerWidth, S.summaryCharPx
  ns.Options.set(ns.db, "fontOutline", "THICKOUTLINE")
  -- now and again on the next frame (the stub timer runs it at once)
  h.eq(styled, { "THICKOUTLINE", true }); h.eq(relayouts, 2)
  -- the clock and the footer's glyph estimate grow with the outline
  local extra = S.outlineGlyphPx.THICKOUTLINE
  h.eq(S.timerWidth, timerW + S.timerGlyphs * extra)
  h.eq(ns.UI.Header.instance.timer._w, S.timerWidth)
  h.near(S.summaryCharPx, charPx + extra, 1e-9)
  -- room for the outline's overhang, the tag's text shift and padding
  h.eq(S.textOverhang, S.outlineOverhangPx.THICKOUTLINE)
  h.eq(S.tagTextShift, S.outlineTagShiftPx.THICKOUTLINE)
  h.eq(S.tagPadExtra, S.outlineTagPadPx.THICKOUTLINE)
  h.eq(ns.UI.Rows.labelGap(), S.rowLabelGap + S.textOverhang)
  h.eq(S.minWidth >= ns.UI.Summary.tableWorstWidth(), true)
  ns.Options.set(ns.db, "fontShadow", false)
  h.eq(styled, { "THICKOUTLINE", false }); h.eq(relayouts, 4)
  ns.Options.set(ns.db, "fontOutline", "none")
  h.eq(S.timerWidth, timerW); h.near(S.summaryCharPx, charPx, 1e-9)
  h.eq(S.textOverhang, 0); h.eq(S.tagTextShift, 0); h.eq(S.tagPadExtra, 0)
  ns.Options.set(ns.db, "fontOutline", "bogus") -- refused: the saved value stays valid
  h.eq(ns.Options.get(ns.db, "fontOutline") ~= "bogus", true)
  L.relayout, F.applyStyle = realRelayout, realStyle
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

h.test("wiring: a wide header (a long translation) raises the window's minimum width", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local L, W, FB = ns.UI.Ledger, ns.UI.Window, ns.UI.FilterBar
  local S = ns.Theme.sizes
  -- at startup the header is measured
  h.eq(type(W.headerWidth), "number")
  -- a sort button the font made 300 px wide
  FB.sortButton.GetWidth = function() return 300 end
  local need = L.measureHeader()
  h.eq(need, math.ceil(FB.rowNeed(nil, 300) + 2 * (S.padding + 4)))
  h.eq(W.headerWidth, need)
  h.eq(need > ns.Theme.sizes.minWidth, true)
  -- font changes measure again
  FB.sortButton.GetWidth = function() return 78 end
  L.relayout()
  h.eq(W.headerWidth < need, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: hovering the footer table shows the vendor / AH tooltip", function()
  local ctx = boot()
  local lines = {}
  ctx.env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end,
    SetText = function() end, IsOwned = function() return false end,
    AddDoubleLine = function(_, l, r) lines[#lines + 1] = { l, r } end,
    AddLine = function(_, l) lines[#lines + 1] = { l } end,
  }
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local tbl = ctx.ns.UI.Summary.instance.table
  tbl._scripts.OnEnter(tbl)
  h.eq(lines[1][1], "Items")
  h.eq(lines[2][1], "Vendor: ")
  -- 8 value lines, then the unpriced Linen Cloth by name and why (no price
  -- addon, no scan in the stub client).
  h.eq(#lines, 11)
  h.eq(lines[9][1], "Without AH price")
  h.eq(lines[10][1]:find("Linen Cloth", 1, true) ~= nil and lines[10][1]:match(" x3$") ~= nil, true)
  h.eq(lines[11][1]:find("/al scan", 1, true) ~= nil, true)
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
  -- price source: Auctionator only, TSM silent (raw prices: no AH cut)
  ns.Options.set(ns.db, "ahCut", false)
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

h.test("wiring: an option without its price addon shows dimmed in the panel", function()
  local ctx = boot()
  startWorld(ctx, false)
  local P = ctx.ns.UI.OptionsPanel
  P.toggle()
  local w = P.frame.widgets.tsmSource
  local alpha
  w.block.SetAlpha = function(_, a) alpha = a end
  w.refresh()
  h.eq(alpha, ctx.ns.Theme.options.inactiveAlpha)
  ctx.env.TSM_API = { GetCustomPriceValue = function() return nil end }
  w.refresh()
  h.eq(alpha, 1)
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
  -- A color shows its hex code; a number option of 0 shows its zeroText.
  h.eq(P.colorLabel("Text", "ffffff"):find("#ffffff", 1, true) ~= nil, true)
  h.eq(P.colorLabel("Text", nil), "Text")
  local goal = P.frame.widgets.goalGold
  goal.refresh()
  h.eq(goal.controls[1]:GetText(), ctx.ns.L["Off"])
  P.toggle() -- closes
  h.eq(ctx.errors, {})
  h.eq(ctx.ns.UI.Ledger.frame.header ~= nil, true)
end)

h.test("wiring: the options panel opens where it was dragged to", function()
  local ctx = boot()
  startWorld(ctx, false)
  local P = ctx.ns.UI.OptionsPanel
  h.eq(P.savedPosition(ctx.ns.db), nil) -- never dragged: next to the ledger
  P.toggle()
  local frame = P.frame
  frame.GetCenter = function() return 120, -40 end -- UIParent's fake center is 0, 0
  frame.GetTop = function() return 250 end -- UIParent's fake top is 300
  frame._scripts.OnDragStart(frame)
  frame._scripts.OnDragStop(frame)
  h.eq(P.savedPosition(ctx.ns.db), { x = 120, top = -50 })
  local placed
  frame.SetPoint = function(_, point, _, _, x, y) placed = { point, x, y } end
  P.toggle() -- closes
  P.toggle() -- opens at the saved place, by its top edge
  h.eq(placed, { "TOP", 120, -50 })
  -- A center saved by an older version still opens there.
  ctx.ns.db.optionsWindow = { x = 10, y = 20 }
  P.toggle(); P.toggle()
  h.eq(placed, { "CENTER", 10, 20 })
  ctx.ns.db.optionsWindow = { x = "bad" }
  h.eq(P.savedPosition(ctx.ns.db), nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: hovering an option shows its tooltip with the default", function()
  local ctx = boot()
  local lines, hooks = {}, 0
  ctx.env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end, ClearLines = function() end,
    SetText = function() end, IsOwned = function() return false end,
    AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function() end,
  }
  startWorld(ctx, false)
  local P, O = ctx.ns.UI.OptionsPanel, ctx.ns.Options
  P.toggle()
  local w = P.frame.widgets.lockWindow
  h.eq(w.block ~= nil, true)
  w.block._scripts.OnEnter(w.block)
  h.eq(lines[1], O.spec("lockWindow").label)
  h.eq(lines[2], O.spec("lockWindow").tooltip)
  h.eq(lines[3], ctx.ns.L["Default: "] .. ctx.ns.L["Off"])
  -- the control itself shows it too (a dropdown's bronze button)
  lines = {}
  local dd = P.frame.widgets.fontSizeRows
  h.eq(type(dd.controls[1].onEnter), "function")
  dd.controls[1].onEnter(dd.controls[1])
  h.eq(lines[1], O.spec("fontSizeRows").label)
  h.eq(lines[#lines], ctx.ns.L["Default: "] .. "12 px")
  h.eq(ctx.errors, {})
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
  -- the panel is as tall as the shown tab needs
  local height = P.frame:GetHeight()
  tabbed.select(first)
  local delta = tabbed.heights[first] - tabbed.heights[second]
  h.eq(P.frame:GetHeight(), height + delta)
  local look = 0
  for _, s in ipairs(sections) do look = math.max(look, tabbed.heights[s.id]) end
  h.eq(look > tabbed.heights[first], true) -- Appearance is the tallest, Window shorter
  h.eq(ctx.errors, {})
end)

h.test("wiring: saved option values are applied at login", function()
  local ctx = boot({ db = { settings = { alpha = 7, priceSource = "zzz" } } })
  startWorld(ctx, false)
  h.eq(ctx.errors, {})
  h.eq(ctx.env.AnotherLedgerDB.settings.alpha, 1)
  h.eq(ctx.env.AnotherLedgerDB.settings.priceSource, "auto")
end)

h.test("wiring: the window look options apply to the background and border", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local frame = ns.UI.Window.frame
  local bg, border
  frame.SetBackdropColor = function(_, r, g, b, a) bg = { r, g, b, a } end
  frame.SetBackdropBorderColor = function(_, r, g, b, a) border = { r, g, b, a } end
  ns.Options.set(ns.db, "alpha", 1)
  h.eq(bg[4], 1) -- 100% opacity is fully opaque
  h.eq(border[4], 1)
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
  h.eq(#ctx.env.AnotherLedgerCharDB.history, 0)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Copper")
  slash(ctx, "reset")
  local hist = ctx.env.AnotherLedgerCharDB.history
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
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB

  local reload = boot({ db = db, chardb = chardb, now = 2000 })
  startWorld(reload, true) -- /reload keeps the session
  h.eq(#chardb.history, 0)

  fire(reload, "PLAYER_LOGOUT")
  db.profiles.Default.minSessionMinutes = 0 -- a short session would continue
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
  local hist = ctx.env.AnotherLedgerCharDB.history
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

h.test("wiring: hovering a History session shows the colored tooltip", function()
  local ctx = boot()
  local ops = {}
  ctx.env.GameTooltip = {
    SetOwner = function() end, Show = function() end, Hide = function() end, ClearLines = function() end,
    SetText = function() end, IsOwned = function() return false end, SetHyperlink = function() end,
    AddLine = function(_, t, r, g, b) ops[#ops + 1] = { "line", t, r, g, b } end,
    AddDoubleLine = function(_, l, r, lr) ops[#ops + 1] = { "double", l, r, lr } end,
  }
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  local L = ctx.ns.UI.Ledger
  L.setTab("history")
  local C = ctx.ns.Theme.colors
  local shown = ctx.ns.UI.Widgets.showTextTooltip({}, sessions(L.view)[1].hint)
  h.eq(shown, true)
  h.eq(ops[1][1], "line"); h.eq(ops[1][3], C.tipTitle[1]) -- the date, gold
  local doubles, last = 0, ops[#ops]
  for _, o in ipairs(ops) do if o[1] == "double" then doubles = doubles + 1 end end
  h.eq(doubles >= 4, true) -- Vendor, AH, Best, Raw gold
  h.eq(ops[#ops - 1][2], ctx.ns.L["Click to show the items"]); h.eq(last[4], C.tipHint[2])
  h.eq(last[2], ctx.ns.L["Right-click: note, merge or delete"])
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
  h.eq(#sessions(L.view), 2)
  L.list.onRowClick(sessions(L.view)[2]) -- open the older session
  h.eq(L.historyIndex, 2)
  h.eq(#sessions(L.view), 3)
  h.eq(sessions(L.view)[1].historyIndex, 2) -- on top
  h.eq(sessions(L.view)[2].quantity, 3) -- its item
  h.eq(sessions(L.view)[3].historyIndex, 1)
  L.list.onRowClick(sessions(L.view)[1]) -- click it again
  h.eq(L.historyIndex, nil)
  h.eq(#sessions(L.view), 2)
  L.list.onRowClick(sessions(L.view)[1])
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
  -- a stopped clock does not tick; the prices still refresh on time
  slash(ctx, "stop")
  local after = builds.n
  ctx.now = ctx.now + 5
  onUpdate(L.frame, 1)
  h.eq(builds.n, after)
  ctx.now = ctx.now + 30
  onUpdate(L.frame, 1)
  h.eq(builds.n, after + 1)
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
  local cache = ctx.env.AnotherLedgerDB.cache
  h.eq(cache["EU-7"][1], nil)
  h.eq(cache["EU-7"][2].price, 6)
  h.eq(cache["US-1"], nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: /al help lists every command, demo included", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.printed = {}
  slash(ctx, "help")
  local text = table.concat(ctx.printed, "\n")
  for _, word in ipairs({ "/al -", "show | hide", "start | stop", "/al reset", "/al keep", "/al tsm", "/al demo", "/al compact", "Note:" }) do
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
  h.eq(registered.name, "AnotherLedger")
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
  h.eq(ns.Money.format(12345678), "1234" .. ns.Money.ICONS.gold) -- coin icons by default
  ns.Options.set(ns.db, "coinIcons", false)
  h.eq(ns.Money.format(12345678), "1234g")
  ns.Options.set(ns.db, "coinIcons", true)
  h.eq(ns.Money.format(12345678), "1234" .. ns.Money.ICONS.gold)
  ns.Options.set(ns.db, "windowScale", 0.8)
  -- the minimap reset button restores the default angle
  ns.db.minimapAngle = 10
  ns.Options.spec("minimapReset").action()
  h.eq(ns.db.minimapAngle, 225)
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
  h.eq(ctx.env.AnotherLedgerCharDB.history[1].currencies[3008].qty, 15)
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
  h.eq(#ctx.env.AnotherLedgerCharDB.history, 0)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ns.Session.placeList(ns.session.places), { "The Stonevault (Heroic)", "Dornogal" })
  -- option on: leaving archives the dungeon session and starts a new one
  ns.Options.set(ns.db, "instanceSession", true)
  ns.Options.set(ns.db, "minSessionMinutes", 0)
  where.instance = nil
  fire(ctx, "PLAYER_ENTERING_WORLD", false, false)
  local hist = ctx.env.AnotherLedgerCharDB.history
  h.eq(#hist, 1)
  h.eq(hist[1].places, { "The Stonevault (Heroic)", "Dornogal" })
  h.eq(next(ns.session.items), nil)
  -- a loading screen inside the open world changes nothing
  fire(ctx, "PLAYER_ENTERING_WORLD", false, false)
  h.eq(#hist, 1)
  -- a stopped clock splits nothing (like Session per zone)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "stop")
  where.instance = "The Stonevault"
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

h.test("wiring: /al keep and /al tsm go through the options", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "keep on")
  h.eq(ctx.env.AnotherLedgerDB.settings.keepSession, true)
  slash(ctx, "tsm   DBMinBuyout  ")
  h.eq(ctx.env.AnotherLedgerDB.settings.tsmSource, "DBMinBuyout")
  h.eq(ctx.errors, {})
end)

h.test("wiring: /al export shows the History as CSV", function()
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
  h.eq(ctx.env.AnotherLedgerCharDB.bank.items[2589].qty, 5)
  slots[1] = { itemID = 2589, stackCount = 7 }
  fire(ctx, "PLAYERBANKSLOTS_CHANGED", 1)
  h.eq(ctx.env.AnotherLedgerCharDB.bank.items[2589].qty, 7)
  fire(ctx, "BANKFRAME_CLOSED")
  slots[1] = { itemID = 2589, stackCount = 1 }
  fire(ctx, "PLAYERBANKSLOTS_CHANGED", 1)
  h.eq(ctx.env.AnotherLedgerCharDB.bank.items[2589].qty, 7)
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
  h.eq(objects.AnotherLedger ~= nil, true)
  h.eq(registered.AnotherLedger, ctx.env.AnotherLedgerDB.minimapIcon)
  h.eq(ns.UI.Minimap.button, nil) -- no own button
  ns.Options.set(ns.db, "minimapButton", false)
  h.eq(shown.AnotherLedger, false)
  h.eq(ctx.env.AnotherLedgerDB.minimapIcon.hide, true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ns.UI.Broker.update()
  h.eq(type(objects.AnotherLedger.text), "string")
  -- The broker total follows the option Raw gold.
  ns.Core.recordGold(50000)
  local function total(includeGold)
    return ns.UI.Broker.summary(ns.session, ns.Core.lookupPrice, ctx.now, includeGold).total
  end
  h.eq(total(true) - total(false), 50000)
  ns.Options.set(ns.db, "rawGold", "apart")
  ns.UI.Broker.update()
  h.eq(objects.AnotherLedger.text, ns.UI.Broker.text({ total = total(false) }, ns.Money.formatColored))
  -- "Auction from" counts in the broker like in the window: AH 120 must beat
  -- vendor 100 by 50 %.
  local s = { running = false, elapsedBase = 3600, gold = 0, items = { [7] = { id = 7, key = 7, qty = 1 } } }
  local function lookup() return { vendor = 100, ah = 120 } end
  h.eq(ns.UI.Broker.summary(s, lookup, ctx.now, false, 0).total, 120)
  h.eq(ns.UI.Broker.summary(s, lookup, ctx.now, false, 50).total, 100)
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
  local hex = ns.Money.colorCode
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
  ctx.env.C_Map = {
    GetBestMapForUnit = function() return ctx.pos and ctx.pos[1] end,
    GetPlayerMapPosition = function()
      local p = ctx.pos
      if not p then return nil end
      return { GetXY = function() return p[2], p[3] end }
    end,
  }
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
  local e = ctx.env.AnotherLedgerCharDB.history[1]
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

-- One saved session: an hour in Wingrest, five minutes in Teerakai.
local function bootWithFarm(pos)
  local ctx = bootInZone("Waking Shores", "Wingrest")
  ctx.pos = pos
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = ctx.now + 3600
  ctx.place.sub = "Teerakai"
  fire(ctx, "ZONE_CHANGED")
  fire(ctx, "CHAT_MSG_LOOT", lootMsg(2592, 9))
  ctx.now = ctx.now + 300
  slash(ctx, "reset")
  return ctx
end

h.test("wiring: loot and gold record the map position of their place", function()
  local ctx = bootInZone("Waking Shores", "Wingrest")
  ctx.pos = { 2022, 0.4, 0.6 }
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.pos = { 2022, 0.6, 0.8 }
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  ctx.pos = nil -- e.g. inside an instance
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local pos = ctx.ns.session.zones["Waking Shores"].subs.Wingrest.pos[2022]
  h.eq(pos.n, 2); h.near(pos.x, 1.0); h.near(pos.y, 1.4)
  ctx.now = ctx.now + 60
  slash(ctx, "reset")
  h.eq(ctx.ns.chardb.history[1].zones["Waking Shores"].subs.Wingrest.pos[2022].n, 2)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the daily farm is picked from saved History only", function()
  local ctx = bootWithFarm()
  local L = ctx.ns.UI.Ledger
  L.refresh()
  local farm = L.view.dailyFarm
  h.eq(farm.best.zone, "Waking Shores"); h.eq(farm.best.sub, "Wingrest") -- Teerakai is under 20 min
  -- loot in the running session at another place: the pick stays
  ctx.place.zone, ctx.place.sub = "Ohn'ahran Plains", "Rusza'thar Reach"
  fire(ctx, "ZONE_CHANGED_NEW_AREA")
  fire(ctx, "CHAT_MSG_LOOT", lootMsg(2592, 50))
  ctx.now = ctx.now + 7200
  L.refresh()
  h.eq(L.view.dailyFarm.best.sub, "Wingrest")
  -- the filter bar does not change it
  ctx.ns.db.filter = { search = "nothing matches" }
  L.refresh()
  h.eq(L.view.dailyFarm.best.sub, "Wingrest")
  -- a shorter minimum lets Teerakai in
  ctx.ns.Options.set(ctx.ns.db, "dailyFarmMinutes", 5)
  L.refresh()
  h.eq(L.view.dailyFarm.best.sub, "Teerakai")
  -- option off: no farm
  ctx.ns.Options.set(ctx.ns.db, "dailyFarm", false)
  L.refresh()
  h.eq(L.view.dailyFarm, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the daily farm is cached until History, options or the price interval change", function()
  local ctx = bootWithFarm()
  local L, V = ctx.ns.UI.Ledger, ctx.ns.View
  local real, calls = V.dailyFarm, 0
  V.dailyFarm = function(...) calls = calls + 1; return real(...) end
  ctx.now = ctx.now + 1000
  L.refresh()
  h.eq(calls, 1)
  L.refresh(); L.setTab("bags"); L.setTab("session")
  h.eq(calls, 1) -- nothing changed: the cached pick
  h.eq(L.view.dailyFarm.best.sub, "Wingrest")
  ctx.now = ctx.now + ctx.ns.Options.get(ctx.ns.db, "refreshSeconds")
  L.refresh()
  h.eq(calls, 2) -- prices may have changed
  ctx.ns.Options.set(ctx.ns.db, "dailyFarmMinutes", 5)
  h.eq(calls, 3)
  h.eq(L.view.dailyFarm.best.sub, "Teerakai")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = ctx.now + 1
  slash(ctx, "reset") -- a new History entry
  h.eq(calls, 4)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a failing daily farm leaves the rest of the window drawn", function()
  local ctx = bootWithFarm()
  local L = ctx.ns.UI.Ledger
  ctx.ns.View.dailyFarm = function() error("farm broke") end
  ctx.now = ctx.now + 1000
  L.refresh()
  h.eq(L.view.kind, "session")
  h.eq(L.view.dailyFarm, nil)
  h.eq(ctx.ns.UI.DailyFarm.shown, false)
  ctx.now = ctx.now + 1000
  L.refresh()
  h.eq(#ctx.errors, 1)
  h.eq(ctx.errors[1]:find("farm broke", 1, true) ~= nil, true)
end)

h.test("wiring: no daily farm without History", function()
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(ctx.ns.UI.Ledger.view.dailyFarm, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: showFarm opens History Zones at the place", function()
  local ctx = bootWithFarm()
  local L = ctx.ns.UI.Ledger
  L.setTab("bags")
  L.showFarm("Waking Shores", "Wingrest")
  h.eq(L.tab, "history"); h.eq(L.subtab, "zones")
  h.eq(L.zoneOpen.zone, "Waking Shores"); h.eq(L.zoneOpen.sub, "Wingrest")
  local _, sub = rowsWith(L.view, "subKey", "Wingrest")
  h.eq(sub ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the daily farm strip shows between filters and tabs and opens Zones", function()
  local ctx = bootWithFarm()
  local L, W, DF = ctx.ns.UI.Ledger, ctx.ns.UI.Window, ctx.ns.UI.DailyFarm
  local S, header = ctx.ns.Theme.sizes, W.frame.header
  L.setTab("session")
  h.eq(DF.shown, true)
  h.eq(header.rowFarm:IsShown(), true)
  h.eq(header._h, S.headerHeight + S.headerRowHeight)
  h.eq(DF.text:GetText():find("Wingrest (Waking Shores)", 1, true) ~= nil, true)
  DF.button._scripts.OnClick(DF.button)
  h.eq(L.tab, "history"); h.eq(L.subtab, "zones")
  h.eq(L.zoneOpen.sub, "Wingrest")
  h.eq(header._h, S.headerHeight + 2 * S.headerRowHeight)
  ctx.ns.Options.set(ctx.ns.db, "dailyFarm", false)
  h.eq(DF.shown, false)
  h.eq(header.rowFarm:IsShown(), false)
  h.eq(header._h, S.headerHeight + S.headerRowHeight)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the strip click redraws once and scrolls the place into view", function()
  local ctx = bootWithFarm()
  local L = ctx.ns.UI.Ledger
  local zones = ctx.ns.chardb.history[1].zones
  for i = 1, 30 do zones["Zone" .. i] = { subs = { ["Sub" .. i] = { time = 60, gold = 100000, items = {} } } } end
  ctx.ns.History.changed() -- an edit in place: caches over History must see it
  L.setTab("bags")
  local real, refreshes = L.refresh, 0
  L.refresh = function(...) refreshes = refreshes + 1; return real(...) end
  L.showFarm("Waking Shores", "Wingrest")
  L.refresh = real
  h.eq(refreshes, 1)
  local idx = ctx.ns.View.indexOf(L.view.rows, "s:Waking Shores\1Wingrest")
  h.eq(idx ~= nil, true)
  local visible = ctx.ns.UI.Rows.visibleCount(L.list.area:GetHeight(), ctx.ns.Theme.sizes.rowHeight)
  h.eq(idx > L.list.offset and idx <= L.list.offset + visible, true)
  h.eq(L.list.offset > 0, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: dragging the strip moves the window unless it is locked", function()
  local ctx = bootWithFarm()
  local DF, frame = ctx.ns.UI.DailyFarm, ctx.ns.UI.Window.frame
  local moved = 0
  frame.StartMoving = function() moved = moved + 1 end
  DF.button._scripts.OnDragStart(DF.button)
  h.eq(moved, 1)
  DF.button._scripts.OnDragStop(DF.button)
  ctx.ns.Options.set(ctx.ns.db, "lockWindow", true)
  DF.button._scripts.OnDragStart(DF.button)
  h.eq(moved, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: strip clicks set a waypoint, open Zones, show the /way line", function()
  local ctx = bootWithFarm({ 2022, 0.4, 0.6 })
  local L, DF = ctx.ns.UI.Ledger, ctx.ns.UI.DailyFarm
  local tom
  ctx.env.TomTom = { AddWaypoint = function(_, m, x, y, o) tom = { m, x, y, o.title }; return tom end }
  ctx.env.IsShiftKeyDown = function() return ctx.shift end
  L.setTab("session")
  h.eq(DF.farm.best.sub, "Wingrest")
  local printed = #ctx.printed
  DF.button._scripts.OnClick(DF.button, "LeftButton")
  h.eq(tom[1], 2022); h.near(tom[2], 0.4); h.near(tom[3], 0.6)
  h.eq(tom[4], "Wingrest (Waking Shores)")
  h.eq(L.tab, "session")
  h.eq(#ctx.printed, printed + 1)
  h.eq(ctx.printed[#ctx.printed]:find("Wingrest (Waking Shores)", 1, true) ~= nil, true)
  ctx.shift = true
  DF.button._scripts.OnClick(DF.button, "LeftButton")
  h.eq(L.tab, "history"); h.eq(L.subtab, "zones"); h.eq(L.zoneOpen.sub, "Wingrest")
  ctx.shift = false
  DF.button._scripts.OnClick(DF.button, "RightButton")
  h.eq(ctx.ns.UI.Export.frame.text, "/way #2022 40.0 60.0 Wingrest")
  h.eq(ctx.ns.UI.Export.frame:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: quest money counts as gold but does not move the farm spot", function()
  local ctx = bootInZone("Waking Shores", "Wingrest")
  ctx.pos = { 2022, 0.4, 0.6 }
  startWorld(ctx, false)
  fire(ctx, "QUEST_TURNED_IN", 1, 0, 5000)
  h.eq(ctx.ns.session.gold, 5000)
  local sub = ctx.ns.session.zones["Waking Shores"].subs.Wingrest
  h.eq(sub.gold, 5000)
  h.eq(sub.pos == nil or sub.pos[2022] == nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the copy box is titled for what it holds", function()
  local ctx = bootWithFarm({ 2022, 0.4, 0.6 })
  local DF = ctx.ns.UI.DailyFarm
  ctx.ns.UI.Ledger.setTab("session")
  DF.button._scripts.OnClick(DF.button, "RightButton")
  local E = ctx.ns.UI.Export
  h.eq(E.frame.titleText:GetText(), ctx.ns.L["Waypoint (/way)"])
  slash(ctx, "export")
  h.eq(E.frame.titleText:GetText(), ctx.ns.L["History export (CSV)"])
  h.eq(ctx.errors, {})
end)

h.test("wiring: a place without a position opens Zones on click, no copy box", function()
  local ctx = bootWithFarm()
  local L, DF = ctx.ns.UI.Ledger, ctx.ns.UI.DailyFarm
  L.setTab("session")
  DF.button._scripts.OnClick(DF.button, "RightButton")
  h.eq(ctx.ns.UI.Export.frame, nil)
  DF.button._scripts.OnClick(DF.button, "LeftButton")
  h.eq(L.tab, "history"); h.eq(L.zoneOpen.sub, "Wingrest")
  h.eq(ctx.errors, {})
end)

h.test("wiring: no TomTom and no map pin says so in chat", function()
  local ctx = bootWithFarm({ 2022, 0.4, 0.6 })
  local DF = ctx.ns.UI.DailyFarm
  ctx.ns.UI.Ledger.setTab("session")
  DF.button._scripts.OnClick(DF.button, "LeftButton")
  h.eq(ctx.printed[#ctx.printed]:find(ctx.ns.L["No waypoint could be set."], 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: hiding Top finds and the Raw gold row takes effect at once", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local W = ctx.ns.UI.Window
  h.eq(W.frame.topBox:IsShown(), true)
  ctx.ns.Options.set(ctx.ns.db, "showTopFinds", false)
  h.eq(W.frame.topBox:IsShown(), false)
  ctx.ns.Options.set(ctx.ns.db, "showTopFinds", true)
  h.eq(W.frame.topBox:IsShown(), true)
  ctx.ns.Options.set(ctx.ns.db, "rawGold", "total")
  h.eq(ctx.ns.UI.Summary.tableLayout(ctx.ns.UI.Ledger.view).rows, { "items", "total" })
  h.eq(ctx.errors, {})
end)

h.test("wiring: every header and filter button has the bronze style", function()
  local ctx = boot()
  startWorld(ctx, false)
  local H = ctx.ns.UI.Header.instance
  h.eq(H.toggle.kind, "bronze"); h.eq(H.toggle.warn, false)
  h.eq(H.reset.kind, "bronze"); h.eq(H.reset.warn, true)
  h.eq(H.options.kind, "icon"); h.eq(H.hide.kind, "icon")
  local F = ctx.ns.UI.FilterBar.instance
  h.eq(F.quality.kind, "bronze"); h.eq(F.sort.kind, "bronze")
  h.eq(F.minBox.kind, "input"); h.eq(F.search.kind, "input")
  -- hover lights the edge gold, leaving restores it
  local b = H.toggle
  b._scripts.OnEnter(b)
  h.eq(b.look, "hover")
  b._scripts.OnLeave(b)
  h.eq(b.look, "normal")
  slash(ctx, "export")
  h.eq(ctx.ns.UI.Export.frame.close.kind, "icon")
  h.eq(ctx.errors, {})
end)

h.test("wiring: loot fills the last drops; reset and History leave them out", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_LOOT", lootMsg(2592, 2))
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local r = ctx.ns.session.recent
  h.eq(#r, 3)
  h.eq(r[1].key, 2589); h.eq(r[1].qty, 3); h.eq(r[2].key, 2592); h.eq(r[2].qty, 2)
  slash(ctx, "reset")
  h.eq(ctx.ns.session.recent, {})
  h.eq(ctx.ns.chardb.history[1].recent, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the mode button in the header switches compact / full and swaps its glyph", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, H, T = ctx.ns.UI.Ledger, ctx.ns.UI.Header.instance, ctx.ns.Theme
  local b = H.modeButton
  h.eq(b ~= nil, true)
  h.eq(b:IsShown(), true)
  h.eq(b.arrow, "up")
  b._scripts.OnClick(b, "LeftButton")
  h.eq(L.mode, "compact")
  h.eq(b:IsShown(), true)
  h.eq(b.arrow, "down")
  b._scripts.OnClick(b, "LeftButton")
  h.eq(L.mode, "full")
  h.eq(b.arrow, "up")
  h.eq(ctx.errors, {})
end)

h.test("wiring: the tab rows clip the tab edge so it never covers the list", function()
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(ctx.ns.UI.Window.frame.header.row3._clips, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: /al compact switches the window to the compact layout and back", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local L, W, S = ctx.ns.UI.Ledger, ctx.ns.UI.Window, ctx.ns.Theme.sizes
  local f = W.frame
  h.eq(L.mode, "full")
  local fullW, fullH = f:GetWidth(), f:GetHeight()
  slash(ctx, "compact")
  h.eq(L.mode, "compact"); h.eq(ctx.ns.db.mode, "compact")
  h.eq(f.listArea:IsShown(), false); h.eq(f.footer:IsShown(), false)
  h.eq(f.header.row2:IsShown(), false); h.eq(f.header.row3:IsShown(), false)
  h.eq(f.compact:IsShown(), true)
  h.eq(f.header._h, S.headerRowHeight)
  h.eq(f:GetWidth(), S.compactWidth); h.eq(f:GetHeight(), S.compactHeight)
  local C = ctx.ns.UI.Compact
  h.eq(C.drops[1].name:GetText():find("x3", 1, true) ~= nil, true)
  h.eq(C.drops[1].frame:IsShown(), true); h.eq(C.drops[2].frame:IsShown(), false)
  -- the drop's source tag is framed like a list row's, as wide as the widest tag
  local tag = C.drops[1].tag
  h.eq(#tag.edges, 4); h.eq(tag:IsShown(), true)
  h.eq(tag.text:GetText(), ctx.ns.UI.Rows.SOURCE_TEXT.vendor)
  h.eq(tag._w, ctx.ns.UI.Rows.widestSource)
  h.eq(C.total:GetText() ~= "", true)
  -- the Daily farm row and the tabs stay hidden while compact
  W.setFarmRow(true)
  h.eq(f.header.rowFarm:IsShown(), false)
  slash(ctx, "compact")
  h.eq(L.mode, "full")
  h.eq(f.listArea:IsShown(), true); h.eq(f.compact:IsShown(), false)
  W.setFarmRow(true) -- full mode lets the Daily farm row show again
  h.eq(f.header.rowFarm:IsShown(), true)
  W.setFarmRow(false)
  h.eq(f:GetWidth(), fullW); h.eq(f:GetHeight(), fullH)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Compact: item icons puts the icon before each drop; the quantity is quiet", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "compact")
  local C = ctx.ns.UI.Compact
  local w = C.drops[1]
  h.eq(w.icon:IsShown(), false) -- off by default
  h.eq(w.name:GetText():find("|c%x%x%x%x%x%x%x%xx3|r") ~= nil, true)
  ctx.ns.Options.set(ctx.ns.db, "compactIcons", true)
  ctx.ns.UI.Ledger.refresh()
  h.eq(w.icon:IsShown(), true)
  h.eq(w.icon:GetTexture() ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: hovering a compact drop shows its item tooltip with the values", function()
  local ctx = boot()
  local ops = {}
  ctx.env.GameTooltip = {
    SetOwner = function(_, owner) ops.owner = owner end, Show = function() end, Hide = function() end,
    ClearLines = function() end, SetText = function() end, IsOwned = function(_, f) return ops.owner == f end,
    SetHyperlink = function(_, link) ops.link = link end,
    AddLine = function(_, t) ops[#ops + 1] = t end, AddDoubleLine = function() end,
  }
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "compact")
  local f = ctx.ns.UI.Compact.drops[1].frame
  h.eq(type(f._scripts.OnEnter), "function")
  f._scripts.OnEnter(f)
  h.eq(type(ops.link), "string"); h.eq(ops.link:find("item:") ~= nil, true)
  h.eq(#ops >= 1, true) -- the values (Vendor / AH / Destroy) follow the item
  h.eq(type(f._scripts.OnLeave), "function")
  h.eq(ctx.errors, {})
end)

h.test("wiring: double-clicking the title toggles the mode", function()
  local ctx = boot()
  startWorld(ctx, false)
  local tb = ctx.ns.UI.Window.frame.header.titleButton
  tb._scripts.OnDoubleClick(tb, "LeftButton")
  h.eq(ctx.ns.UI.Ledger.mode, "compact")
  tb._scripts.OnDoubleClick(tb, "LeftButton")
  h.eq(ctx.ns.UI.Ledger.mode, "full")
  h.eq(ctx.errors, {})
end)

h.test("wiring: switching compact / full keeps the corner nearest the edge, both ways", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local f = ctx.ns.UI.Window.frame
  ctx.env.UIParent:SetSize(1920, 1080)
  -- the window's CENTER offset follows its last SetPoint (UIParent's center is 0, 0)
  local cx, cy = 0, 0
  f.GetCenter = function() return cx, cy end
  f.SetPoint = function(_, p, _, _, x, y) if p == "CENTER" then cx, cy = x or 0, y or 0 end end
  local function edges() return { cx - f:GetWidth() / 2, cy + f:GetHeight() / 2 } end -- left, top
  local function rightBottom() return { cx + f:GetWidth() / 2, cy - f:GetHeight() / 2 } end
  -- compact dragged to just above the screen center on the left: its top left stays
  slash(ctx, "compact")
  cx, cy = -600, 40
  ctx.ns.UI.Window.endDrag()
  local compactEdges = edges()
  slash(ctx, "compact") -- to full: taller, so its center drops below the screen center
  h.eq(edges(), compactEdges)
  h.eq(cy < 0, true)
  slash(ctx, "compact") -- and back: the same top left, the same place as before
  h.eq(edges(), compactEdges)
  h.eq({ cx, cy }, { -600, 40 })
  -- full dragged to the bottom right: its bottom right stays, both ways
  slash(ctx, "compact")
  cx, cy = 500, -60
  ctx.ns.UI.Window.endDrag()
  local fullCorner = rightBottom()
  slash(ctx, "compact")
  h.eq(rightBottom(), fullCorner)
  slash(ctx, "compact")
  h.eq(rightBottom(), fullCorner)
  h.eq({ cx, cy }, { 500, -60 })
  h.eq(ctx.errors, {})
end)

h.test("wiring: a click on the footer's unpriced note lists those items first, a second click undoes it", function()
  local ctx = boot()
  ctx.env.TSM_API = { GetCustomPriceValue = function(_, itemString)
    if tostring(itemString):find("2589", 1, true) then return 100000 end
    return nil
  end }
  startWorld(ctx, false)
  local ns = ctx.ns
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(2589, 1))
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(2592, 1))
  local L = ns.UI.Ledger
  L.refresh()
  h.eq(L.view.rows[1].id, 2589)
  local notes = ns.UI.Summary.instance.notesFrame
  h.eq(notes._mouse, true)
  notes._scripts.OnMouseUp(notes)
  h.eq(L.unpricedFirst, true)
  h.eq(L.view.rows[1].id, 2592)
  h.eq(ns.UI.Summary.instance.notes:GetText():find("listed first", 1, true) ~= nil, true)
  notes._scripts.OnMouseUp(notes)
  h.eq(L.view.rows[1].id, 2589)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a login without TSM or Auctionator says so once in chat", function()
  local function hints(ctx)
    local n = 0
    for _, line in ipairs(ctx.printed) do
      if line:find("No auction price addon found", 1, true) then n = n + 1 end
    end
    return n
  end
  local ctx = boot()
  startWorld(ctx, false)
  h.eq(hints(ctx), 1)
  h.eq(ctx.env.AnotherLedgerDB.priceHintShown, true)
  local tsm = boot()
  tsm.env.TSM_API = { GetCustomPriceValue = function() return nil end }
  startWorld(tsm, false)
  h.eq(hints(tsm), 0)
  h.eq(ctx.errors, {}); h.eq(tsm.errors, {})
end)

h.test("wiring: compact shows the goal bar with a session goal and the last 15 minutes' rate", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local C = ns.UI.Compact
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "compact")
  h.eq(C.goalBar:IsShown(), false)
  h.eq(C.recent:GetText(), "")
  ns.Options.set(ns.db, "goalGold", 1)
  C.area._w = 200
  ns.UI.Ledger.refresh()
  h.eq(C.goalBar:IsShown(), true)
  h.eq(C.goalBar._w >= 1 and C.goalBar._w <= 200, true)
  -- a quarter hour of samples later the rate of that stretch shows
  for _ = 1, 16 do
    ctx.now = ctx.now + 60
    ns.Core.heartbeat()
  end
  ns.UI.Ledger.refresh()
  h.eq(C.recent:GetText():find(ns.L["Last 15 min: "], 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the full header shows the goal bar on the Session tab, minutes goal too", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local H = ns.UI.Header.instance
  H.row._w = 300
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ns.UI.Ledger.refresh()
  h.eq(H.goalBar:IsShown(), false) -- no goal
  ns.Options.set(ns.db, "goalMinutes", 10)
  ctx.now = ctx.now + 300
  ns.UI.Ledger.refresh()
  h.eq(H.goalBar:IsShown(), true)
  h.eq(H.goalBar._w, 150) -- 5 of 10 minutes
  ns.UI.Ledger.setTab("bags")
  ns.UI.Ledger.refresh()
  h.eq(H.goalBar:IsShown(), false)
  ns.UI.Ledger.setTab("session")
  slash(ctx, "compact")
  h.eq(H.goalBar:IsShown(), false) -- compact draws its own
  h.eq(ctx.errors, {})
end)

h.test("wiring: in compact the clock starts and stops the session, Paused while stopped", function()
  local ctx = boot()
  startWorld(ctx, false)
  local H = ctx.ns.UI.Header.instance
  slash(ctx, "compact")
  h.eq(H.toggle:IsShown(), false); h.eq(H.reset:IsShown(), false); h.eq(H.timer:IsShown(), true)
  h.eq(H.pausedText:IsShown(), false)
  H.clockButton._scripts.OnClick(H.clockButton, "LeftButton")
  h.eq(ctx.ns.session.running, false)
  h.eq(H.pausedText:IsShown(), true)
  H.clockButton._scripts.OnClick(H.clockButton, "LeftButton")
  h.eq(ctx.ns.session.running, true)
  h.eq(H.pausedText:IsShown(), false)
  -- in full mode the clock is not a button
  slash(ctx, "compact")
  H.clockButton._scripts.OnClick(H.clockButton, "LeftButton")
  h.eq(ctx.ns.session.running, true)
  h.eq(H.toggle:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the mode survives a reload; a bad saved mode starts full", function()
  local ctx = boot()
  startWorld(ctx, false)
  slash(ctx, "compact")
  local reload = boot({ db = ctx.env.AnotherLedgerDB, chardb = ctx.env.AnotherLedgerCharDB, now = 2000 })
  startWorld(reload, true)
  h.eq(reload.ns.UI.Ledger.mode, "compact")
  h.eq(reload.ns.UI.Window.frame.listArea:IsShown(), false)
  local db = ctx.env.AnotherLedgerDB
  db.mode = "weird"
  local bad = boot({ db = db, chardb = ctx.env.AnotherLedgerCharDB, now = 3000 })
  startWorld(bad, true)
  h.eq(bad.ns.UI.Ledger.mode, "full")
  h.eq(bad.errors, {})
end)

h.test("wiring: switching while hidden draws the compact view when shown", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "hide")
  slash(ctx, "compact")
  slash(ctx, "show")
  ctx.ns.UI.Ledger.refresh() -- the client fires OnShow, which is hooked to this
  h.eq(ctx.ns.UI.Compact.drops[1].name:GetText():find("x3", 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: applying every option redraws the window once", function()
  local ctx = boot()
  startWorld(ctx, true)
  local ns = ctx.ns
  local builds, original = 0, ns.UI.Ledger.buildView
  ns.UI.Ledger.buildView = function(...) builds = builds + 1; return original(...) end
  ns.Options.applyAll(ns.db)
  ns.UI.Ledger.buildView = original
  h.eq(builds <= 1, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: compact clock sits right of the title and wins the mouse over it", function()
  local ctx = boot()
  startWorld(ctx, false)
  local H = ctx.ns.UI.Header.instance
  local tb = ctx.ns.UI.Window.frame.header.titleButton
  slash(ctx, "compact")
  h.eq(H.timerAnchor, "mode")
  h.eq(H.clockButton:GetFrameLevel() > tb:GetFrameLevel(), true)
  slash(ctx, "compact")
  h.eq(H.timerAnchor, "toggle")
  -- dragging the clock still moves the window
  local moved = 0
  ctx.ns.UI.Window.frame.StartMoving = function() moved = moved + 1 end
  H.clockButton._scripts.OnDragStart(H.clockButton)
  h.eq(moved, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: compact ticks the clock and shows the session title on any tab", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, H = ctx.ns.UI.Ledger, ctx.ns.UI.Header.instance
  L.setTab("bags")
  slash(ctx, "compact")
  h.eq(ctx.ns.UI.Window.frame.header.title:GetText(), ctx.ns.UI.Tabs.title("session"))
  local before = H.timer:GetText()
  ctx.now = ctx.now + 5
  L.tick()
  h.eq(H.timer:GetText() ~= before, true)
  slash(ctx, "compact")
  h.eq(ctx.ns.UI.Window.frame.header.title:GetText(), ctx.ns.UI.Tabs.title("bags"))
  h.eq(ctx.errors, {})
end)

h.test("wiring: a mode switch during combat hide does not save the window hidden", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.ns.Options.set(ctx.ns.db, "combatHide", true)
  fire(ctx, "PLAYER_REGEN_DISABLED")
  h.eq(ctx.ns.UI.Window.frame:IsShown(), false)
  slash(ctx, "compact")
  h.eq(ctx.ns.db.window.hidden, false)
  fire(ctx, "PLAYER_REGEN_ENABLED")
  h.eq(ctx.ns.UI.Window.frame:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: no daily farm strip on a character without History", function()
  local ctx = boot()
  startWorld(ctx, false)
  local header = ctx.ns.UI.Window.frame.header
  h.eq(ctx.ns.UI.DailyFarm.shown, false)
  h.eq(header.rowFarm:IsShown(), false)
  h.eq(header._h, ctx.ns.Theme.sizes.headerHeight)
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
  local reload = boot({ db = ctx.env.AnotherLedgerDB, chardb = ctx.env.AnotherLedgerCharDB, now = 2000 })
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
  h.eq(last.detail, "1 item")
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

h.test("wiring: the coin icons option re-lays the window out and redraws the amounts", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local ns = ctx.ns
  h.eq(ns.Money.iconsOn(), true) -- the default, applied at login
  local relayouts, orig = 0, ns.UI.Ledger.relayout
  ns.UI.Ledger.relayout = function(...) relayouts = relayouts + 1; return orig(...) end
  ns.Options.set(ns.db, "coinIcons", false)
  h.eq(ns.Money.iconsOn(), false)
  h.eq(relayouts, 1)
  local amount = ns.UI.Ledger.list.pool[1].amount:GetText()
  h.eq(amount ~= "", true)
  h.eq(amount:find("|T", 1, true), nil)
  ns.Options.set(ns.db, "coinIcons", true)
  h.eq(ns.UI.Ledger.list.pool[1].amount:GetText():find("|T", 1, true) ~= nil, true)
  ns.UI.Ledger.relayout = orig
  h.eq(ctx.errors, {})
end)

h.test("wiring: amounts show in shared coin columns in the list, footer, Top finds and compact", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(2592, 1))
  local ns = ctx.ns
  ns.UI.Ledger.refresh()
  local pool = ns.UI.Ledger.list.pool
  local a, b = pool[1].amount, pool[2].amount
  -- one FontString per unit, the same column places in every row
  h.eq(type(a.parts.copper), "table"); h.eq(a.full ~= "", true)
  h.eq(a.layoutKey ~= false, true); h.eq(a.layoutKey, b.layoutKey)
  local s = ns.UI.Summary.instance
  h.eq(s.cells.items.value.layoutKey, s.cells.total.value.layoutKey)
  h.eq(s.cells.items.value:GetText() ~= "", true)
  h.eq(s.rows[1].value:GetText() ~= "", true)
  slash(ctx, "compact")
  local C = ns.UI.Compact
  h.eq(C.drops[1].amount.layoutKey, C.drops[2].amount.layoutKey)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the resize grip hides while the window is locked", function()
  local ctx = boot()
  startWorld(ctx, false)
  local grip = ctx.ns.UI.Window.frame.grip
  h.eq(grip:IsShown(), true)
  ctx.ns.Options.set(ctx.ns.db, "lockWindow", true)
  h.eq(grip:IsShown(), false)
  ctx.ns.Options.set(ctx.ns.db, "lockWindow", false)
  h.eq(grip:IsShown(), true)
end)

h.test("wiring: Scroll to new loot off keeps the Session list where it is", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  local function loot(id)
    fire(ctx, "CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:" .. id .. "::::::::60:::::::::|h[I" .. id .. "]|h|r.")
  end
  for id = 1000, 1039 do loot(id) end
  L.list:SetOffset(0)
  ctx.ns.Options.set(ctx.ns.db, "followLoot", false)
  loot(9999) -- sorts last (same value, name "Item9999")
  h.eq(L.list.offset, 0)
  ctx.ns.Options.set(ctx.ns.db, "followLoot", true)
  loot(9998) -- a new row near the end
  h.eq(L.list.offset > 0, true)
  h.eq(ctx.errors, {})
end)

h.test("Core.missingGold: only money no message counted", function()
  local ctx = boot()
  local m = ctx.ns.Core.missingGold
  h.eq(m(100, 600, 500), 0) -- the message had it all
  h.eq(m(100, 600, 200), 300)
  h.eq(m(100, 50, 0), 0) -- money spent: nothing looted
  h.eq(m(nil, 600, 0), 0)
end)

h.test("wiring: money looted without a known message counts once", function()
  local ctx = boot()
  local money = 10000
  ctx.env.GetMoney = function() return money end
  startWorld(ctx, false)
  local S = ctx.ns.session
  -- A message form the parser does not know: the money change counts.
  fire(ctx, "LOOT_OPENED")
  money = money + 2500
  fire(ctx, "CHAT_MSG_MONEY", "Something new: 25 Silver")
  fire(ctx, "LOOT_CLOSED")
  h.eq(S.gold, 2500)
  -- A known message: counted once, not again from the money change.
  fire(ctx, "LOOT_OPENED")
  money = money + 300
  fire(ctx, "CHAT_MSG_MONEY", "You loot 3 Silver")
  fire(ctx, "LOOT_CLOSED")
  h.eq(S.gold, 2800)
  -- Without GetMoney nothing happens.
  ctx.env.GetMoney = nil
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_CLOSED")
  h.eq(S.gold, 2800)
  h.eq(ctx.errors, {})
end)

h.test("wiring: gold of a quick second loot window counts once when its money message is late", function()
  local ctx = bootDeferred()
  local money = 10000
  ctx.env.GetMoney = function() return money end
  startWorld(ctx, false)
  ctx.runTimers()
  local S = ctx.ns.session
  fire(ctx, "LOOT_OPENED")
  money = money + 300 -- the money is there, its chat line not yet
  fire(ctx, "LOOT_CLOSED")
  fire(ctx, "LOOT_OPENED") -- the next mob, within the settle time
  fire(ctx, "CHAT_MSG_MONEY", "You loot 3 Silver") -- the first mob's line
  money = money + 200
  fire(ctx, "CHAT_MSG_MONEY", "You loot 2 Silver")
  fire(ctx, "LOOT_CLOSED")
  ctx.runTimers()
  h.eq(S.gold, 500)
  -- the money of a window without a known message still counts once
  fire(ctx, "LOOT_OPENED")
  money = money + 700
  fire(ctx, "LOOT_CLOSED")
  ctx.runTimers()
  h.eq(S.gold, 1200)
  h.eq(ctx.errors, {})
end)

h.test("wiring: History and Zones show the footer with the session count", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, footer = ctx.ns.UI.Ledger, ctx.ns.UI.Window.frame.footer
  local summary = ctx.ns.UI.Summary.instance
  local history = ctx.env.AnotherLedgerCharDB.history
  for i = 1, 2 do history[i] = { startedAt = 10 - i, elapsed = 3600, gold = 100, nItems = 0, vendor = 0, ah = 0, items = {} } end
  L.refresh()
  local sessionHeight = footer:GetHeight()
  h.eq(sessionHeight > 1, true)
  L.setTab("history")
  h.eq(footer:GetHeight() > 1, true)
  h.eq(summary.table:IsShown(), true)
  h.eq(L.view.headerInfo, "2 sessions")
  h.eq(ctx.ns.UI.Header.instance.info:GetText(), "2 sessions")
  h.eq(ctx.ns.UI.Header.instance.info:IsShown(), true)
  h.eq(L.view.gold.total, 200)
  L.setSubtab("zones")
  h.eq(L.view.kind, "zones")
  h.eq(footer:GetHeight() > 1, true)
  L.setTab("session")
  h.eq(footer:GetHeight(), sessionHeight)
  h.eq(ctx.ns.UI.Header.instance.info:IsShown(), false) -- the clock's place
  h.eq(ctx.errors, {})
end)

h.test("wiring: a color option recolors texts, buttons and the window live", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.UI.Ledger.refresh()
  local label = ns.UI.Summary.instance.cells.items.label
  local total = ns.UI.Summary.instance.cells.total.label
  local colors = {}
  local function watch(fs, name)
    fs.SetTextColor = function(_, r, g, b) colors[name] = ns.Theme.colorToHex({ r, g, b }) end
  end
  watch(label, "items")
  watch(total, "total")
  local frame = ns.UI.Window.frame
  local bg
  frame.SetBackdropColor = function(_, r, g, b) bg = ns.Theme.colorToHex({ r, g, b }) end
  ns.Options.set(ns.db, "colorText", "ff0000")
  h.eq(colors.items, "ff0000")
  h.eq(colors.total, nil) -- the Total row is a title color, untouched
  ns.Options.set(ns.db, "colorTitles", "00ff00")
  h.eq(colors.total, "00ff00")
  ns.Options.set(ns.db, "colorBackground", "102030")
  h.eq(bg, "102030")
  h.eq(ctx.env.AnotherLedgerDB.settings.colorText, "ff0000")
  h.eq(ctx.errors, {})
end)

h.test("wiring: saved colors are applied at login", function()
  local ctx = boot({ db = { settings = { colorAuction = "123456", colorText = "nonsense" } } })
  startWorld(ctx, false)
  h.eq(ctx.ns.Theme.colorToHex(ctx.ns.Theme.colors.tagAh), "123456")
  h.eq(ctx.ns.Theme.colorToHex(ctx.ns.Theme.colors.ink), "ffffff")
  h.eq(ctx.errors, {})
end)

h.test("wiring: dropping the window near an Edit Mode grid line snaps it there", function()
  local ctx = boot()
  ctx.env.EditModeManagerFrame = { Grid = { gridSpacing = 100 } }
  startWorld(ctx, false)
  local ns = ctx.ns
  local frame = ns.UI.Window.frame
  frame:SetSize(300, 200)
  ctx.env.UIParent:SetSize(1920, 1080)
  frame.GetCenter = function() return 103, -96 end -- 3 / 4 px off the lines
  local placed
  frame.SetPoint = function(_, p, rel, rp, x, y) placed = { p, rp, x, y } end
  frame.header._scripts.OnDragStop()
  h.eq(placed, { "CENTER", "CENTER", 100, -100 })
  -- option off: the window stays where it was dropped
  placed = nil
  ns.Options.set(ns.db, "snapToGrid", false)
  frame.header._scripts.OnDragStop()
  h.eq(placed, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the options window shares the window's opacity and brightness", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Options.set(ns.db, "alpha", 0.5)
  local bg, border
  local real = ctx.env.CreateFrame
  ctx.env.CreateFrame = function(kind, name, ...)
    local f = real(kind, name, ...)
    if name == "AnotherLedgerOptions" then
      f.SetBackdropColor = function(_, r, g, b, a) bg = { r, g, b, a } end
      f.SetBackdropBorderColor = function(_, r, g, b, a) border = { r, g, b, a } end
    end
    return f
  end
  ns.UI.OptionsPanel.toggle()
  ctx.env.CreateFrame = real
  local tint = ns.Theme.colors.panelTint
  h.near(bg[4], (tint[4] or 1) * 0.5, 1e-9) -- opacity at open
  ns.Options.set(ns.db, "alpha", 0.25)
  h.near(bg[4], (tint[4] or 1) * 0.25, 1e-9) -- and live
  h.eq(border ~= nil, true)
  ns.Options.set(ns.db, "brightness", 0)
  h.near(bg[1], 0, 1e-9)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Session per zone splits after the delay, not on flights or detours", function()
  local ctx = boot()
  local where = { zone = "Dornogal", taxi = false }
  ctx.env.GetRealZoneText = function() return where.zone end
  ctx.env.UnitOnTaxi = function() return where.taxi end
  startWorld(ctx, false)
  local ns, hist = ctx.ns, ctx.env.AnotherLedgerCharDB.history
  ns.Options.set(ns.db, "zoneSession", true)
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(2589, 4))
  local function go(zone, seconds)
    where.zone = zone
    fire(ctx, "ZONE_CHANGED_NEW_AREA")
    ctx.now = ctx.now + seconds
    ns.Core.heartbeat()
  end
  go("Isle of Dorn", 60)
  h.eq(#hist, 0)
  go("Dornogal", 300) -- back before the delay: a detour
  h.eq(#hist, 0)
  where.taxi = true
  go("Isle of Dorn", 300) -- on a flight
  h.eq(#hist, 0)
  where.taxi = false
  ns.Core.heartbeat()
  ctx.now = ctx.now + 120
  ns.Core.heartbeat()
  h.eq(#hist, 1)
  h.eq(next(ns.session.items), nil)
  h.eq(ctx.printed[#ctx.printed]:find(ns.L["new session"] .. ": Isle of Dorn.", 1, true) ~= nil, true)
  -- An empty session just starts over in the new zone, quietly.
  local lines = #ctx.printed
  go("The Ringing Deeps", 0)
  ctx.now = ctx.now + 120
  ns.Core.heartbeat()
  h.eq(#hist, 1)
  h.eq(ns.session.startedAt, ctx.now)
  h.eq(#ctx.printed, lines)
  -- Option off: nothing splits.
  ns.Options.set(ns.db, "zoneSession", false)
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(2589, 4))
  go("Dornogal", 0)
  ctx.now = ctx.now + 600
  ns.Core.heartbeat()
  h.eq(#hist, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the gold per hour graph samples the session and shows in the tooltips", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  for _, qty in ipairs({ 4, 4, 0 }) do
    if qty > 0 then fire(ctx, "CHAT_MSG_LOOT", itemLoot(2589, qty)) end
    ctx.now = ctx.now + 60
    ns.Core.heartbeat()
  end
  h.eq(#ns.session.samples, 3)
  ns.UI.Ledger.refresh()
  h.eq(ns.UI.Ledger.view.graph.bars, { 6000, 6000, 0 })
  local c = ns.View.buildCompact(ns.session, { now = ctx.now })
  local text = ns.Tooltip.text(ns.UI.Compact.hint(c))
  h.eq(text:find(ns.L["Gold per hour over time"], 1, true) ~= nil, true)
  slash(ctx, "reset")
  h.eq(ns.session.samples, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: keeping an item in Bags splits the footer into kept and sellable", function()
  local ctx = boot()
  bagEnv(ctx, { [0] = { n = 2, { 2589, 5 }, { 2592, 2 } } })
  startWorld(ctx, false)
  local menus = captureMenus(ctx)
  local Ledger, L = ctx.ns.UI.Ledger, ctx.ns.L
  local summary = ctx.ns.UI.Summary.instance
  local function menuFor(id)
    for _, r in ipairs(Ledger.view.rows) do
      if r.id == id then
        Ledger.list.onRowClick(r, "RightButton", "f")
        return menus[#menus]
      end
    end
  end
  -- The Session tab has no keep entry.
  fire(ctx, "CHAT_MSG_LOOT", itemLoot(2589, 1))
  h.eq(menuItem(menuFor(2589), L["Keep (not for sale)"]), nil)
  Ledger.setTab("bags")
  menuItem(menuFor(2589), L["Keep (not for sale)"]).click()
  h.eq(ctx.env.AnotherLedgerDB.kept[2589] ~= nil, true)
  local t = Ledger.view.totals
  h.eq({ t.kept, t.sellable }, { 125, 50 })
  h.eq(summary.cells.kept.label:IsShown(), true)
  h.eq(ctx.ns.UI.Window.frame.footer:GetHeight(), 70) -- three rows and the "unpriced" note
  menuItem(menuFor(2589), L["Sell again (not kept)"]).click()
  h.eq(Ledger.view.totals.kept, nil)
  h.eq(summary.cells.kept.label:IsShown(), false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: logout clears settings alias, the profile is saved once", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Options.set(ns.db, "alpha", 0.5)
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
  h.eq(db.settings, nil)
  h.eq(db.profiles.Default.alpha, 0.5)
  h.eq(chardb.profile, "Default")
  local relog = boot({ db = db, chardb = chardb, now = 5000 })
  startWorld(relog, false)
  h.eq(relog.ns.Options.get(relog.ns.db, "alpha"), 0.5)
  h.eq(relog.ns.db.settings == relog.env.AnotherLedgerDB.profiles.Default, true)
  h.eq(ctx.errors, {}); h.eq(relog.errors, {})
end)

h.test("wiring: old settings start fresh, account options are kept", function()
  local ctx = boot({ db = { settings = { alpha = 0.3, historyLimit = -1 } } })
  -- boot() turns seeded settings into a profile; undo that for this test.
  ctx.env.AnotherLedgerDB.profiles, ctx.env.AnotherLedgerDB.profilesMigrated = nil, nil
  startWorld(ctx, false)
  local ns = ctx.ns
  h.eq(ns.Options.get(ns.db, "alpha"), 1)
  h.eq(ns.Options.get(ns.db, "historyLimit"), -1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: switching profile applies the look", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Profiles.create(ns.db, "Night", { colorPreset = "midnight" })
  ns.Profiles.activate(ns.db, ns.chardb, "Night")
  h.eq(ns.Theme.colorToHex(ns.Theme.colors.panelTint), ns.Theme.preset("midnight").colors.panelTint)
  h.eq(ctx.env.AnotherLedgerCharDB.profile, "Night")
  h.eq(ctx.errors, {})
end)

h.test("wiring: import through the box creates and activates a profile", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns, L = ctx.ns, ctx.ns.L
  local popups = {}
  ctx.env.StaticPopup_Show = function(name) popups[#popups + 1] = ctx.env.StaticPopupDialogs[name] end
  local line = ns.Profiles.encode({ alpha = 0.5, colorPreset = "midnight" })
  ns.Options.spec("profileImport").action()
  local frame = ns.UI.Export.frame
  h.eq(frame.mode, "edit")
  frame.onAccept(line .. ";nope=1")
  h.eq(popups[#popups].hasEditBox, true)
  popups[#popups].onAccept("Farm")
  h.eq(ns.Profiles.active(ctx.env.AnotherLedgerCharDB), "Farm")
  h.eq(ns.Options.get(ns.db, "alpha"), 0.5)
  h.eq(ns.Theme.colorToHex(ns.Theme.colors.panelTint), ns.Theme.preset("midnight").colors.panelTint)
  local said = ctx.printed[#ctx.printed]
  h.eq(said:find(string.format(L["Imported %d settings, skipped %d."], 2, 1), 1, true) ~= nil, true)
  -- the same name again asks before overwriting
  ns.Options.spec("profileImport").action()
  frame.onAccept(ns.Profiles.encode({ alpha = 0.25 }))
  popups[#popups].onAccept("farm")
  h.eq(popups[#popups].hasEditBox, nil) -- the confirmation
  h.eq(ns.Options.get(ns.db, "alpha"), 0.5)
  popups[#popups].OnAccept()
  h.eq(ns.Options.get(ns.db, "alpha"), 0.25)
  -- export shows the copy box again (read-only)
  ns.Options.spec("profileExport").action()
  h.eq(frame.mode, "copy")
  h.eq(frame.text, ns.Profiles.encode(ns.db.settings))
  -- garbage: a message, nothing created
  ns.Options.spec("profileImport").action()
  local n = #ns.Profiles.names(ns.db)
  frame.onAccept("hello")
  h.eq(#ns.Profiles.names(ns.db), n)
  h.eq(ctx.printed[#ctx.printed]:find(L["This is not an AnotherLedger profile."], 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the options window is wide enough for every tab", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.UI.OptionsPanel.toggle()
  local frame = ns.UI.OptionsPanel.frame
  local S = ns.Theme.sizes
  local extent, n = 0, 0
  for _, b in pairs(frame.tabbed.strip.buttons) do extent, n = extent + b:GetWidth(), n + 1 end
  extent = extent + (n - 1) * S.buttonGap
  h.eq(n, #ns.Options.sections())
  h.eq(frame:GetWidth() >= extent + 2 * (S.padding + 4), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Session summary in chat sums up a saved session", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Core.recordGold(250000)
  ctx.now = ctx.now + 3600
  slash(ctx, "reset")
  for _, line in ipairs(ctx.printed) do h.eq(line:find("session saved", 1, true), nil) end -- off by default
  ns.Options.set(ns.db, "sessionChat", true)
  ns.Core.recordGold(250000)
  ctx.now = ctx.now + 1800
  slash(ctx, "reset")
  local found
  for _, line in ipairs(ctx.printed) do
    if line:find("session saved: 30m", 1, true) then found = line end
  end
  h.eq(found ~= nil, true)
  h.eq(found:find(ns.Money.format(250000), 1, true) ~= nil, true)
  h.eq(found:find(ns.Money.format(500000) .. "/h", 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: AH cut and Destroy values change the prices at once", function()
  local ctx = boot()
  ctx.env.UnitName = function() return "Me" end
  ctx.env.GetRealmName = function() return "Realm" end
  startWorld(ctx, false)
  local ns = ctx.ns
  ctx.env.TSM_API = { GetCustomPriceValue = function(src)
    if src:find("Destroy", 1, true) then return 50000 end
    return 10000
  end }
  h.eq(ns.Options.get(ns.db, "ahCut"), true)
  local r = ns.prices:lookup(2589)
  h.eq(r.ah, 9500); h.eq(r.ahGross, 10000)
  ns.Options.set(ns.db, "ahCut", false)
  h.eq(ns.prices:lookup(2589).ah, 10000)
  -- Destroy: Linen Cloth's class comes from GetItemInfoInstant (armor here).
  ctx.env.C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "", 1, 4, 1 end
  h.eq(ns.prices:lookup(2589).de, 50000)
  ns.Options.set(ns.db, "destroyMode", "self")
  h.eq(ns.prices:lookup(2589).de, nil) -- no enchanter
  h.eq(ns.Core.character, "Me-Realm")
  ns.db.professions = { ["Me-Realm"] = { enchanting = true } }
  h.eq(ns.prices:lookup(2589).de, 50000)
  ns.Options.set(ns.db, "destroyMode", "never")
  h.eq(ns.prices:lookup(2589).de, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: SKILL_LINES_CHANGED saves this character's destroy professions", function()
  local ctx = boot()
  ctx.env.UnitName = function() return "Me" end
  ctx.env.GetRealmName = function() return "Realm" end
  startWorld(ctx, false)
  local ns = ctx.ns
  ctx.env.GetProfessions = function() return 1, nil end
  ctx.env.GetProfessionInfo = function() return "Enchanting", 0, 1, 100, 0, 0, 333 end
  fire(ctx, "SKILL_LINES_CHANGED")
  h.eq(ns.db.professions["Me-Realm"], { enchanting = true })
  h.eq(ctx.errors, {})
end)

h.test("wiring: Auction from turns a thin AH margin into a Vendor row", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ctx.env.TSM_API = { GetCustomPriceValue = function(src) return not src:find("Destroy", 1, true) and 30 or nil end }
  fire(ctx, "CHAT_MSG_LOOT", LOOT) -- vendor 25 each, AH 30 (28 after the cut)
  local L = ns.UI.Ledger
  L.refresh()
  h.eq(L.view.rows[1].bestKind, "ah")
  ns.Options.set(ns.db, "ahMinGain", 20)
  L.refresh()
  h.eq(L.view.rows[1].bestKind, "vendor")
  h.eq(ctx.errors, {})
end)

h.test("wiring: a short session continues over a zone split, a long one is archived", function()
  local function run(seconds)
    local ctx = boot()
    local where = { zone = "Dornogal" }
    ctx.env.GetRealZoneText = function() return where.zone end
    startWorld(ctx, false)
    local ns, hist = ctx.ns, ctx.env.AnotherLedgerCharDB.history
    ns.Options.set(ns.db, "zoneSession", true)
    ns.Options.set(ns.db, "zoneSessionMinutes", 1)
    h.eq(ns.Options.get(ns.db, "minSessionMinutes"), 2)
    fire(ctx, "CHAT_MSG_LOOT", itemLoot(2589, 4))
    ctx.now = ctx.now + seconds
    where.zone = "Isle of Dorn"
    fire(ctx, "ZONE_CHANGED_NEW_AREA")
    ctx.now = ctx.now + 61
    ns.Core.heartbeat()
    h.eq(ctx.errors, {})
    return ctx, ns, hist
  end
  local _, ns, hist = run(-31) -- 30 s in all
  h.eq(#hist, 0)
  h.eq(ns.session.items[2589].qty, 4)
  _, ns, hist = run(600)
  h.eq(#hist, 1)
  h.eq(next(ns.session.items), nil)
end)

h.test("wiring: a zone split saves a session with only mobs, and an open History session stays open", function()
  local ctx = boot()
  local where = { zone = "Dornogal" }
  ctx.env.GetRealZoneText = function() return where.zone end
  startWorld(ctx, false)
  local ns, hist = ctx.ns, ctx.env.AnotherLedgerCharDB.history
  hist[1] = { startedAt = 1, elapsed = 60, gold = 1, nItems = 0, vendor = 0, ah = 0, items = {} }
  local Ledger = ns.UI.Ledger
  Ledger.setTab("history")
  Ledger.toggleHistory(1)
  ns.Options.set(ns.db, "zoneSession", true)
  ns.Options.set(ns.db, "zoneSessionMinutes", 1)
  ns.session.mobs = { ["npc:1"] = { kind = "npc", kills = 2, looted = 0, gold = 0, items = {}, places = {} } }
  ctx.now = ctx.now + 600
  where.zone = "Isle of Dorn"
  fire(ctx, "ZONE_CHANGED_NEW_AREA")
  ctx.now = ctx.now + 61
  ns.Core.heartbeat()
  h.eq(#hist, 2)
  h.eq(hist[1].mobs["npc:1"].kills, 2)
  h.eq(Ledger.historyIndex, 2) -- still the same session
  h.eq(ctx.errors, {})
end)

h.test("wiring: a short session at login continues, a long one is archived", function()
  local function relog(seconds)
    local ctx = boot()
    startWorld(ctx, false)
    fire(ctx, "CHAT_MSG_LOOT", LOOT)
    ctx.now = ctx.now + seconds
    fire(ctx, "PLAYER_LOGOUT")
    local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
    local saved = chardb.session
    local again = boot({ db = db, chardb = chardb, now = ctx.now + 5000 })
    startWorld(again, false)
    h.eq(again.errors, {})
    return again, saved, chardb
  end
  local ctx, saved, chardb = relog(60)
  h.eq(ctx.ns.session, saved)
  h.eq(#chardb.history, 0)
  h.eq(ctx.ns.session.items[2589].qty, 3)
  ctx, saved, chardb = relog(1800)
  h.eq(ctx.ns.session ~= saved, true)
  h.eq(#chardb.history, 1)
end)

h.test("wiring: /al reset still archives a short session", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = ctx.now + 20
  slash(ctx, "reset")
  h.eq(#ctx.env.AnotherLedgerCharDB.history, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Pause in cities freezes the clock while resting, loot and quest gold still count", function()
  local ctx = boot()
  local resting = true
  ctx.env.IsResting = function() return resting end
  startWorld(ctx, false)
  local ns = ctx.ns
  h.eq(ns.Options.get(ns.db, "cityPause"), true)
  h.eq(ns.session.resting, "city") -- logged in inside a city
  ctx.now = ctx.now + 100
  h.eq(ns.Session.elapsed(ns.session, ctx.now), 0)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  fire(ctx, "QUEST_TURNED_IN", 1, 0, 2500)
  h.eq(ns.session.items[2589].qty, 3)
  h.eq(ns.session.gold, 2500)
  local H = ns.UI.Header.instance
  slash(ctx, "compact")
  h.eq(H.pausedText:IsShown(), true)
  h.eq(H.pausedText:GetText(), ns.L["Resting"])
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING")
  ctx.now = ctx.now + 60
  h.eq(ns.Session.elapsed(ns.session, ctx.now), 60)
  h.eq(H.pausedText:IsShown(), false)
  -- Stop in a city, then leave: still stopped
  resting = true
  fire(ctx, "PLAYER_UPDATE_RESTING")
  slash(ctx, "stop")
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING")
  h.eq(ns.session.running, false)
  h.eq(H.pausedText:GetText(), ns.L["Paused"])
  -- Start inside a city: rests at once
  resting = true
  slash(ctx, "start")
  h.eq(ns.session.resting, "city")
  -- Option off: the clock runs in the city
  ns.Options.set(ns.db, "cityPause", false)
  h.eq(ns.session.resting, nil)
  local before = ns.Session.elapsed(ns.session, ctx.now)
  ctx.now = ctx.now + 30
  h.eq(ns.Session.elapsed(ns.session, ctx.now), before + 30)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Bags shows free slots, gold on hand and net worth; Bank has no money rows", function()
  local ctx = boot()
  bagEnv(ctx, { [0] = { n = 12, { 2589, 5 }, { 2592, 2 }, { 7910, 1 } } })
  ctx.env.C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 9 or 0, 0 end
  local money = 56200
  ctx.env.GetMoney = function() return money end
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  L.setTab("bags")
  h.eq(L.view.headerInfo, "3 items \194\183 9 free")
  h.eq(L.view.totals.money, 56200)
  h.eq(L.view.totals.worth, L.view.totals.best + 56200)
  money = 100
  fire(ctx, "PLAYER_MONEY")
  L.refresh()
  h.eq(L.view.totals.money, 100)
  L.setTab("bank")
  h.eq(L.view.totals.money, nil)
  -- Two free slots: the count turns red.
  ctx.env.C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 2 or 0, 0 end
  L.setTab("bags")
  local red = ctx.ns.Theme.colorToHex(ctx.ns.Theme.colors.marketBad)
  h.eq(L.view.headerInfo, "3 items \194\183 |cff" .. red .. "2 free|r")
  h.eq(ctx.errors, {})
end)

h.test("wiring: net worth adds the bank scan; all characters with an alt saved; logout and /al worth", function()
  local alt = { bags = 1000, bank = 500, money = 2000, at = 10 }
  local bankItems = { [2592] = { id = 2592, qty = 4, link = "|cffffffff|Hitem:2592::|h[Item2592]|h|r" } }
  local ctx = boot({ db = { worth = { ["Alt-Realm"] = alt } }, chardb = { bank = { scannedAt = 50, items = bankItems } } })
  ctx.env.UnitName = function() return "Me" end
  ctx.env.GetRealmName = function() return "Realm" end
  bagEnv(ctx, { [0] = { n = 2, { 2589, 5 }, { 7910, 1 } } })
  local money = 300
  ctx.env.GetMoney = function() return money end
  startWorld(ctx, false)
  local L = ctx.ns.UI.Ledger
  L.setTab("bags")
  local t = L.view.totals
  h.eq(t.bank, 100) -- 4 x 25 vendor
  h.eq(t.bagsWorth, 150)
  h.eq(t.worth, 150 + 100 + 300)
  h.eq(t.allWorth, 550 + 3500)
  local db = ctx.env.AnotherLedgerDB
  h.eq(db.worth["Me-Realm"].bags, 150)
  -- the Bags filter hides rows but not the net worth
  db.filter.search = "nothing matches"
  L.refresh()
  h.eq(#L.view.rows, 0)
  h.eq(L.view.totals.worth, 550)
  db.filter.search = ""
  -- logout saves the new gold even without the Bags tab shown
  L.setTab("session")
  money = 1300
  fire(ctx, "PLAYER_LOGOUT")
  h.eq(db.worth["Me-Realm"].money, 1300)
  ctx.printed = {}
  slash(ctx, "worth")
  local text = table.concat(ctx.printed, " ")
  h.eq(text:find("Alt-Realm", 1, true) ~= nil, true)
  h.eq(text:find("net worth of all characters", 1, true) ~= nil, true)
  slash(ctx, "worth forget alt")
  h.eq(db.worth["Alt-Realm"], nil)
  L.setTab("bags")
  h.eq(L.view.totals.allWorth, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: History Sessions shows day headings; a click folds one", function()
  local ctx = boot()
  startWorld(ctx, false)
  local Ledger = ctx.ns.UI.Ledger
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  Ledger.setTab("history")
  Ledger.setSubtab("sessions")
  local rows = Ledger.view.rows
  h.eq(rows[1].isHeading, true)
  h.eq(rows[1].name, ctx.ns.L["Today"])
  h.eq(#rows, 3)
  Ledger.list.onRowClick(rows[1], "LeftButton", "f")
  h.eq(#Ledger.view.rows, 1)
  h.eq(Ledger.view.headerInfo, "2 sessions")
  h.eq(Ledger.rowMenu(Ledger.view.rows[1]), nil)
  Ledger.list.onRowClick(Ledger.view.rows[1], "LeftButton", "f")
  h.eq(#Ledger.view.rows, 3)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Daily farm: my level leaves out a place of another level at once", function()
  local ctx = bootWithFarm({ 2022, 0.4, 0.6 })
  local L, ns = ctx.ns.UI.Ledger, ctx.ns
  local level = 70
  ctx.env.UnitLevel = function() return level end
  ctx.env.C_Map = ctx.env.C_Map or {}
  ctx.env.C_Map.GetMapLevels = function(mapID) if mapID == 2022 then return 60, 70 end end
  L.refresh()
  h.eq(L.view.dailyFarm.best.sub, "Wingrest")
  ns.Options.set(ns.db, "dailyFarmLevel", true)
  L.refresh()
  h.eq(L.view.dailyFarm.best.sub, "Wingrest") -- 70 fits 60-70
  level = 80
  L.refresh()
  h.eq(L.view.dailyFarm, nil) -- the only place is below your level now
  h.eq(ctx.errors, {})
end)

h.test("wiring: Open on first loot shows a hidden window once per session", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns, W = ctx.ns, ctx.ns.UI.Window
  ns.Options.set(ns.db, "showOnLoot", true)
  W.hide()
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(W.isShown(), true)
  W.hide()
  fire(ctx, "CHAT_MSG_LOOT", LOOT) -- not the first item any more
  h.eq(W.isShown(), false)
  slash(ctx, "reset")
  fire(ctx, "CHAT_MSG_LOOT", LOOT) -- a new session's first item
  h.eq(W.isShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Open in instances shows inside and hides again only its own opening", function()
  local ctx = boot()
  local where = { zone = "Dornogal" }
  ctx.env.GetRealZoneText = function() return where.zone end
  ctx.env.GetInstanceInfo = function()
    if where.instance then return where.instance, "party", 1, "Normal" end
    return where.zone, "none", 0, ""
  end
  startWorld(ctx, false)
  local ns, W = ctx.ns, ctx.ns.UI.Window
  ns.Options.set(ns.db, "showInInstance", true)
  local function go(instance)
    where.instance = instance
    fire(ctx, "PLAYER_ENTERING_WORLD", false, false)
  end
  W.hide()
  go("The Stonevault")
  h.eq(W.isShown(), true)
  go(nil)
  h.eq(W.isShown(), false)
  -- closed by hand inside: leaving does nothing
  go("The Stonevault")
  W.hide()
  go(nil)
  h.eq(W.isShown(), false)
  -- shown by hand before: leaving keeps it shown
  W.show()
  go("The Stonevault")
  go(nil)
  h.eq(W.isShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Hide in cities hides while resting and only undoes its own hiding", function()
  local ctx = boot()
  local resting = false
  ctx.env.IsResting = function() return resting end
  startWorld(ctx, false)
  local ns, W = ctx.ns, ctx.ns.UI.Window
  ns.Options.set(ns.db, "hideInCities", true)
  h.eq(W.isShown(), true)
  resting = true
  fire(ctx, "PLAYER_UPDATE_RESTING")
  h.eq(W.isShown(), false)
  h.eq(ctx.env.AnotherLedgerDB.window.hidden, false) -- the player's own state is kept
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING")
  h.eq(W.isShown(), true)
  -- opened by hand in the city: stays open when leaving and entering again
  resting = true
  fire(ctx, "PLAYER_UPDATE_RESTING")
  W.show()
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING")
  h.eq(W.isShown(), true)
  -- a combat-hidden window is left alone
  ns.Options.set(ns.db, "combatHide", true)
  fire(ctx, "PLAYER_REGEN_DISABLED")
  h.eq(W.isShown(), false)
  resting = true
  fire(ctx, "PLAYER_UPDATE_RESTING")
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING")
  h.eq(W.isShown(), false)
  fire(ctx, "PLAYER_REGEN_ENABLED")
  h.eq(W.isShown(), true)
  h.eq(ctx.errors, {})
end)

-- A loot window: slots = { { link, qty, guid } or { money = copper, guid } }.
local MOB = "Creature-0-3110-0-12-2546-000012ABCD"
local function lootWindowEnv(ctx, slots)
  local env = ctx.env
  env.GetNumLootItems = function() return #slots end
  env.GetLootSlotType = function(i) return slots[i].money and 2 or 1 end
  env.GetLootSlotLink = function(i) return slots[i].link end
  env.GetLootSlotInfo = function(i) return 134400, "x", slots[i].qty or 0 end
  env.GetLootSourceInfo = function(i) return slots[i].guid, slots[i].money or slots[i].qty end
end

h.test("wiring: cleared loot slots are credited to their mob, once per corpse", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local OTHER = "|cffffffff|Hitem:2592::::::::60:::::::::|h[Wool Cloth]|h|r"
  lootWindowEnv(ctx, { { link = LINK, qty = 3, guid = MOB }, { link = OTHER, qty = 1, guid = MOB },
    { money = 250, guid = MOB } })
  ctx.env.C_TooltipInfo = { GetHyperlink = function(l)
    if l == "unit:" .. MOB then return { lines = { { leftText = "Kobold Vermin" } } } end
  end }
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  fire(ctx, "LOOT_SLOT_CLEARED", 3)
  fire(ctx, "LOOT_CLOSED") -- slot 2 was left in the corpse
  local m = ns.session.mobs["npc:2546"]
  h.eq(m.items[2589], 3)
  h.eq(m.items[2592], nil)
  h.eq(m.gold, 250)
  h.eq(m.looted, 1)
  h.eq(m.name, "Kobold Vermin")
  -- clearing after the window closed credits nothing
  fire(ctx, "LOOT_SLOT_CLEARED", 2)
  h.eq(m.items[2592], nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a fast loot addon empties the window on LOOT_READY; the mob still gets its loot", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local slots = { { link = LINK, qty = 3, guid = MOB }, { money = 250, guid = MOB } }
  lootWindowEnv(ctx, slots)
  -- the addon takes everything on LOOT_READY: the slots clear before LOOT_OPENED
  fire(ctx, "LOOT_READY", true)
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  fire(ctx, "LOOT_SLOT_CLEARED", 2)
  for i = #slots, 1, -1 do slots[i] = nil end
  fire(ctx, "LOOT_OPENED", true)
  fire(ctx, "LOOT_CLOSED")
  local m = ns.session.mobs["npc:2546"]
  h.eq(type(m), "table")
  h.eq(m.items[2589], 3)
  h.eq(m.gold, 250)
  h.eq(m.looted, 1)
  -- the next corpse, looted by hand (LOOT_READY, then LOOT_OPENED, then the clicks)
  local SECOND = "Creature-0-3110-0-12-2546-000012ABCE"
  slots[1] = { link = LINK, qty = 2, guid = SECOND }
  fire(ctx, "LOOT_READY", false)
  fire(ctx, "LOOT_OPENED", false)
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  fire(ctx, "LOOT_CLOSED")
  h.eq(m.items[2589], 5)
  h.eq(m.looted, 2)
  ns.UI.Ledger.setTab("history")
  ns.UI.Ledger.setSubtab("mobs")
  local found = false
  for _, r in ipairs(ns.UI.Ledger.view.rows) do
    if r.mobKey == "npc:2546" then found = true end
  end
  h.eq(found, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: drop chances count what each corpse held and show in the item row tooltip", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local OTHER = "|cffffffff|Hitem:2592::::::::60:::::::::|h[Wool Cloth]|h|r"
  local corpses = { "Creature-0-3110-0-12-2546-000012AB01", "Creature-0-3110-0-12-2546-000012AB02",
    "Creature-0-3110-0-12-2546-000012AB03", "Creature-0-3110-0-12-2546-000012AB04" }
  for i, guid in ipairs(corpses) do
    local slots = { { link = LINK, qty = 1, guid = guid } }
    if i == 1 then slots[2] = { link = OTHER, qty = 1, guid = guid } end -- wool left in the first corpse
    lootWindowEnv(ctx, slots)
    fire(ctx, "LOOT_READY", false)
    fire(ctx, "LOOT_OPENED", false)
    fire(ctx, "LOOT_SLOT_CLEARED", 1)
    fire(ctx, "LOOT_CLOSED")
  end
  local m = ns.session.mobs["npc:2546"]
  h.eq(m.seen, 4); h.eq(m.drops[2589], 4); h.eq(m.drops[2592], 1)
  h.eq(m.items[2592], nil) -- left behind: no value, but it counts for the chance
  local L = ns.UI.Ledger
  L.setTab("history")
  L.setSubtab("mobs")
  L.toggleMob("npc:2546")
  local row = L.view.rows[2]
  h.eq(row.id, 2589)
  local lines = table.concat(ns.UI.Rows.tooltipLines(row, ns.Money.format), "\n")
  h.eq(lines:find("Drop chance: 100% (4 of 4)", 1, true) ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: item tooltips list the mobs that drop the item with their chance", function()
  local ctx = boot()
  local onItem
  ctx.env.Enum = { TooltipDataType = { Item = 0 } }
  ctx.env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    if kind == 0 then onItem = fn end
  end }
  startWorld(ctx, false)
  local ns = ctx.ns
  h.eq(type(onItem), "function")
  local function tooltipFor(link)
    local tip = { lines = {} }
    function tip:GetItem() return "Linen Cloth", link end
    function tip:AddLine(t) self.lines[#self.lines + 1] = t end
    function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " = " .. r end
    function tip:Show() end
    onItem(tip)
    return table.concat(tip.lines, "\n")
  end
  h.eq(tooltipFor(LINK), "") -- nothing known yet
  local corpses = { "Creature-0-3110-0-12-2546-000012AB01", "Creature-0-3110-0-12-2546-000012AB02" }
  for i, guid in ipairs(corpses) do
    lootWindowEnv(ctx, i == 1 and { { link = LINK, qty = 1, guid = guid } } or { { money = 10, guid = guid } })
    fire(ctx, "LOOT_READY", false)
    fire(ctx, "LOOT_OPENED", false)
    fire(ctx, "LOOT_SLOT_CLEARED", 1)
    fire(ctx, "LOOT_CLOSED")
  end
  local text = tooltipFor(LINK)
  h.eq(text:find(ns.L["AnotherLedger drop chance"], 1, true) ~= nil, true)
  h.eq(text:find("NPC 2546 = 50% (1 of 2)", 1, true) ~= nil, true)
  -- it stays after Reset (History) and goes with the option off
  slash(ctx, "reset")
  h.eq(tooltipFor(LINK):find("50% (1 of 2)", 1, true) ~= nil, true)
  ns.Options.set(ns.db, "itemTooltipDrops", false)
  h.eq(tooltipFor(LINK), "")
  h.eq(ctx.errors, {})
end)

h.test("wiring: mob loot counts with the clock stopped and is saved with the session", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  slash(ctx, "stop")
  h.eq(ns.session.running, false)
  lootWindowEnv(ctx, { { link = LINK, qty = 2, guid = MOB }, { money = 100, guid = MOB } })
  fire(ctx, "LOOT_READY", true)
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  fire(ctx, "LOOT_SLOT_CLEARED", 2)
  fire(ctx, "LOOT_OPENED", true)
  fire(ctx, "LOOT_CLOSED")
  local m = ns.session.mobs["npc:2546"]
  h.eq(m.items[2589], 2); h.eq(m.gold, 100); h.eq(m.looted, 1)
  -- the session itself counted nothing
  h.eq(next(ns.session.items), nil)
  -- Reset keeps the mob loot in History, so History > Mobs still lists it
  slash(ctx, "reset")
  local history = ctx.env.AnotherLedgerCharDB.history
  h.eq(#history, 1)
  h.eq(history[1].mobs["npc:2546"].items[2589], 2)
  ns.UI.Ledger.setTab("history")
  ns.UI.Ledger.setSubtab("mobs")
  h.eq(ns.UI.Ledger.view.rows[1].mobKey, "npc:2546")
  h.eq(ctx.errors, {})
end)

h.test("wiring: loot is credited without kills; unknown names get a fallback", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  lootWindowEnv(ctx, { { link = LINK, qty = 2, guid = MOB } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  h.eq(ns.session.mobs["npc:2546"].items[2589], 2)
  h.eq(ns.session.mobs["npc:2546"].name, nil) -- History > Mobs shows "NPC 2546"
  -- a name plate seen later names it
  ctx.env.UnitGUID = function() return MOB end
  ctx.env.UnitName = function() return "Kobold Vermin" end
  fire(ctx, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  h.eq(ns.session.mobs["npc:2546"].name, "Kobold Vermin")
  h.eq(ctx.errors, {})
end)

h.test("wiring: secret unit names and GUIDs are dropped unread", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local SECRET_NAME, SECRET_GUID = "Secret Name", "Creature-0-1-0-1-9999-0000000001"
  ctx.env.issecretvalue = function(v) return v == SECRET_NAME or v == SECRET_GUID end
  -- the unit tooltip's first line is secret: no name, no error
  ctx.env.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = SECRET_NAME } } }
  end }
  lootWindowEnv(ctx, { { link = LINK, qty = 2, guid = MOB } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  h.eq(ns.session.mobs["npc:2546"].items[2589], 2)
  h.eq(ns.session.mobs["npc:2546"].name, nil)
  -- a secret name plate name or GUID names nothing
  ctx.env.UnitGUID = function() return MOB end
  ctx.env.UnitName = function() return SECRET_NAME end
  fire(ctx, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  ctx.env.UnitGUID = function() return SECRET_GUID end
  ctx.env.UnitName = function() return "Kobold Vermin" end
  fire(ctx, "NAME_PLATE_UNIT_ADDED", "nameplate2")
  fire(ctx, "UNIT_SPELLCAST_SENT", "player", SECRET_NAME)
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  h.eq(ns.session.mobs["npc:2546"].name, nil)
  h.eq(ns.session.mobs["npc:9999"], nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: History > Mobs lists the mobs of History and the running session", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns, Ledger = ctx.ns, ctx.ns.UI.Ledger
  local subs = ns.UI.Tabs.subtabs("history")
  h.eq(subs[3].key, "mobs")
  lootWindowEnv(ctx, { { link = LINK, qty = 3, guid = MOB } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  Ledger.setTab("history")
  Ledger.setSubtab("mobs")
  h.eq(Ledger.currentSort(), "ah")
  h.eq(#Ledger.view.rows, 1)
  h.eq(Ledger.view.rows[1].mobKey, "npc:2546")
  h.eq(Ledger.view.headerInfo, "1 mob, all chars") -- Zones: all characters is on by default
  Ledger.list.onRowClick(Ledger.view.rows[1], "LeftButton", "f")
  h.eq(Ledger.mobOpen, "npc:2546")
  h.eq(Ledger.view.rows[2].id, 2589)
  h.eq(ctx.ns.UI.FilterBar.sortLabel("perLoot", ns.UI.Tabs.sorts("history", "mobs")), ns.L["Per loot"])
  h.eq(ctx.errors, {})
end)

h.test("wiring: automatic show and hide keep the player's hidden choice", function()
  local ctx = boot()
  local resting = false
  ctx.env.IsResting = function() return resting end
  startWorld(ctx, false)
  local ns, W = ctx.ns, ctx.ns.UI.Window
  ns.Options.set(ns.db, "showOnLoot", true)
  ns.Options.set(ns.db, "hideInCities", true)
  W.hide()
  h.eq(ctx.env.AnotherLedgerDB.window.hidden, true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT) -- first item: shown
  resting = true
  fire(ctx, "PLAYER_UPDATE_RESTING") -- city: hidden
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING") -- out again: shown
  h.eq(W.isShown(), true)
  W.endDrag() -- any later save
  h.eq(ctx.env.AnotherLedgerDB.window.hidden, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Hide in cities during combat keeps the window hidden after combat", function()
  local ctx = boot()
  local resting = false
  ctx.env.IsResting = function() return resting end
  startWorld(ctx, false)
  local ns, W = ctx.ns, ctx.ns.UI.Window
  ns.Options.set(ns.db, "hideInCities", true)
  ns.Options.set(ns.db, "combatHide", true)
  fire(ctx, "PLAYER_REGEN_DISABLED")
  resting = true
  fire(ctx, "PLAYER_UPDATE_RESTING") -- reached the city in combat
  fire(ctx, "PLAYER_REGEN_ENABLED")
  h.eq(W.isShown(), false)
  resting = false
  fire(ctx, "PLAYER_UPDATE_RESTING")
  h.eq(W.isShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Open on first loot in combat waits for the combat to end", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns, W = ctx.ns, ctx.ns.UI.Window
  ns.Options.set(ns.db, "showOnLoot", true)
  ns.Options.set(ns.db, "combatHide", true)
  W.hide()
  fire(ctx, "PLAYER_REGEN_DISABLED")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(W.isShown(), false)
  fire(ctx, "PLAYER_REGEN_ENABLED")
  h.eq(W.isShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Destroy values Never also drops the destroy value saved at loot time", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ctx.env.TSM_API = { GetCustomPriceValue = function(src)
    if src:find("Destroy", 1, true) then return 50000 end
    return 100
  end }
  ctx.env.C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "", 1, 4, 1 end
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ns.session.items[2589].price.de, 50000) -- Always at loot time
  ns.Options.set(ns.db, "destroyMode", "never")
  local L = ns.UI.Ledger
  L.setTab("session")
  L.refresh()
  local row
  for _, r in ipairs(L.view.rows) do if r.id == 2589 then row = r end end
  h.eq(row.deTotal, nil)
  h.eq(row.bestTotal, ns.Core.sessionValue(ns.session, true))
  local value = ns.Core.sessionValue(ns.session, true)
  slash(ctx, "reset")
  h.eq(ctx.env.AnotherLedgerCharDB.history[1].best, value)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a short session kept at login runs again and dates from the login", function()
  local ctx = boot()
  local afk = false
  ctx.env.UnitIsAFK = function() return afk end
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.now = ctx.now + 30
  slash(ctx, "stop")
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
  local again = boot({ db = db, chardb = chardb, now = ctx.now + 7 * 86400 })
  startWorld(again, false)
  local s = again.ns.session
  h.eq(s.running, true)
  h.eq(s.startedAt, again.now)
  h.eq(again.ns.Session.elapsed(s, again.now), 30) -- its time so far still counts
  fire(again, "CHAT_MSG_LOOT", LOOT)
  h.eq(s.items[2589].qty, 6)
  -- an AFK-paused short session runs again too
  again.ns.Options.set(again.ns.db, "afkPause", true)
  again.env.UnitIsAFK = function() return true end
  fire(again, "PLAYER_FLAGS_CHANGED", "player")
  h.eq(s.running, false)
  fire(again, "PLAYER_LOGOUT")
  local third = boot({ db = db, chardb = chardb, now = again.now + 86400 })
  startWorld(third, false)
  h.eq(third.ns.session.running, true)
  h.eq(third.ns.session.afkPaused, nil)
  h.eq(third.ns.session.items[2589].qty, 6)
  h.eq(again.errors, {})
  h.eq(third.errors, {})
end)

h.test("wiring: an empty short session starts over at login and on an instance split", function()
  local ctx = boot()
  startWorld(ctx, false)
  ctx.now = ctx.now + 30
  fire(ctx, "PLAYER_LOGOUT")
  local db, chardb = ctx.env.AnotherLedgerDB, ctx.env.AnotherLedgerCharDB
  local again = boot({ db = db, chardb = chardb, now = ctx.now + 86400 })
  local where = { zone = "Dornogal" }
  again.env.GetRealZoneText = function() return where.zone end
  again.env.GetInstanceInfo = function()
    if where.instance then return where.instance, "party", 2, "Heroic" end
    return where.zone, "none", 0, ""
  end
  startWorld(again, false)
  local ns = again.ns
  h.eq(ns.Session.elapsed(ns.session, again.now), 0)
  ns.Options.set(ns.db, "instanceSession", true)
  again.now = again.now + 40
  where.instance = "The Stonevault"
  fire(again, "PLAYER_ENTERING_WORLD", false, false)
  h.eq(ns.Session.elapsed(ns.session, again.now), 0)
  h.eq(again.errors, {})
end)

h.test("wiring: a gathering node is named by the gathering cast, without a tooltip lookup", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local NODE = "GameObject-0-3110-0-12-1731-000012ABCF"
  local lookups = 0
  ctx.env.C_TooltipInfo = { GetHyperlink = function() lookups = lookups + 1 end }
  fire(ctx, "UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-3-1", 2575)
  lootWindowEnv(ctx, { { link = LINK, qty = 2, guid = NODE } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  fire(ctx, "LOOT_CLOSED")
  h.eq(ns.session.mobs["obj:1731"].name, "Copper Vein")
  h.eq(lookups, 0)
  -- a cast long before the loot window names nothing
  local NODE2 = "GameObject-0-3110-0-12-1732-000012ABCA"
  fire(ctx, "UNIT_SPELLCAST_SENT", "player", "Tin Vein", "Cast-3-2", 2575)
  ctx.now = ctx.now + 120
  lootWindowEnv(ctx, { { link = LINK, qty = 1, guid = NODE2 } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  h.eq(ns.session.mobs["obj:1732"].name, nil) -- shown as "Object 1732"
  h.eq(lookups, 0)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a mob's coin counts your share of it in a group", function()
  local ctx = boot()
  local money = 10000
  ctx.env.GetMoney = function() return money end
  startWorld(ctx, false)
  local ns = ctx.ns
  lootWindowEnv(ctx, { { money = 300, guid = MOB } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  money = money + 100 -- split three ways
  fire(ctx, "LOOT_CLOSED")
  h.eq(ns.session.gold, 100)
  h.eq(ns.session.mobs["npc:2546"].gold, 100)
  h.eq(ns.session.mobs["npc:2546"].looted, 1)
  -- solo: the whole coin
  local MOB2 = "Creature-0-3110-0-12-2546-000012ABCE"
  lootWindowEnv(ctx, { { money = 300, guid = MOB2 } })
  fire(ctx, "LOOT_OPENED")
  fire(ctx, "LOOT_SLOT_CLEARED", 1)
  money = money + 300
  fire(ctx, "LOOT_CLOSED")
  h.eq(ns.session.mobs["npc:2546"].gold, 400)
  h.eq(ctx.errors, {})
end)

h.test("wiring: price rules are reused until an option changes; professions until they change", function()
  local ctx = boot()
  ctx.env.UnitName = function() return "Me" end
  ctx.env.GetRealmName = function() return "Realm" end
  startWorld(ctx, false)
  local ns = ctx.ns
  local r = ns.prices:_rules()
  h.eq(ns.prices:_rules() == r, true)
  ns.Options.set(ns.db, "ahCut", false)
  h.eq(ns.prices:_rules() == r, false)
  ctx.env.TSM_API = { GetCustomPriceValue = function(src)
    if src:find("Destroy", 1, true) then return 50000 end
    return 100
  end }
  ctx.env.C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "", 1, 4, 1 end
  ns.Options.set(ns.db, "destroyMode", "any")
  ns.db.professions = { ["Alt-Realm"] = { enchanting = true } }
  h.eq(ns.prices:lookup(2589).de, 50000)
  ns.db.professions["Alt-Realm"].enchanting = nil -- not through the game: still the known set
  h.eq(ns.prices:lookup(2589).de, 50000)
  ctx.env.GetProfessions = function() return nil end
  fire(ctx, "SKILL_LINES_CHANGED")
  h.eq(ns.prices:lookup(2589).de, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: an empty profession read at login keeps the saved professions", function()
  local ctx = boot()
  ctx.env.UnitName = function() return "Me" end
  ctx.env.GetRealmName = function() return "Realm" end
  startWorld(ctx, false)
  ctx.ns.db.professions["Me-Realm"] = { enchanting = true }
  fire(ctx, "PLAYER_LOGOUT")
  local again = boot({ db = ctx.env.AnotherLedgerDB, chardb = ctx.env.AnotherLedgerCharDB, now = ctx.now + 60 })
  again.env.UnitName = function() return "Me" end
  again.env.GetRealmName = function() return "Realm" end
  again.env.GetProfessions = function() return nil end -- not loaded yet
  startWorld(again, false)
  h.eq(again.ns.db.professions["Me-Realm"], { enchanting = true })
  fire(again, "SKILL_LINES_CHANGED") -- the game's own news: dropped
  h.eq(again.ns.db.professions["Me-Realm"], {})
  h.eq(again.errors, {})
end)

h.test("wiring: no combat log event is registered (forbidden for addons on this client)", function()
  local ctx = boot()
  startWorld(ctx, false)
  for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_EVENT" }) do
    h.eq(ctx.ns.Core.events[event], nil, event)
  end
  h.eq(ctx.errors, {})
end)

-- ---------------------------------------------------------------------------
-- AnotherLedger scan

-- A fake auction house: `rows` = { { qty, buyout, itemID, link }, ... } for the
-- full read; `commodity[itemID]` / `items[itemID]` = { full = bool, list } for
-- the search results.
local function fakeAuctionHouse(ctx, rows)
  local ah = { replicated = 0, commodity = {}, items = {} }
  ah.api = {
    ReplicateItems = function() ah.replicated = ah.replicated + 1 end,
    GetNumReplicateItems = function() return #rows end,
    GetReplicateItemInfo = function(i)
      local r = rows[i + 1]
      return "Item", 1, r[1], 1, true, 1, 1, 0, 0, r[2], 0, false, nil, nil, nil, 1, r[3], true
    end,
    GetReplicateItemLink = function(i) return rows[i + 1][4] end,
    HasFullCommoditySearchResults = function(id) return ah.commodity[id].full end,
    GetNumCommoditySearchResults = function(id) return #ah.commodity[id].list end,
    GetCommoditySearchResultInfo = function(id, i) return ah.commodity[id].list[i] end,
    HasFullItemSearchResults = function(key) return ah.items[key.itemID].full end,
    GetNumItemSearchResults = function(key) return #ah.items[key.itemID].list end,
    GetItemSearchResultInfo = function(key, i) return ah.items[key.itemID].list[i] end,
  }
  ctx.env.C_AuctionHouse = ah.api
  ctx.env.GetRealmName = function() return "Realm" end
  return ah
end

local function printedWith(ctx, text)
  for _, line in ipairs(ctx.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local function scanWorld(rows)
  local ctx = bootDeferred()
  local ah = fakeAuctionHouse(ctx, rows or { { 1, 1000, 5, nil } })
  startWorld(ctx, false)
  ctx.runTimers()
  ctx.printed = {}
  return ctx, ah
end

h.test("wiring: /al scan reads the auction house and prices items", function()
  local ctx, ah = scanWorld({ { 1, 1000, 5, nil }, { 2, 3000, 5, nil } })
  fire(ctx, "AUCTION_HOUSE_SHOW")
  slash(ctx, "scan")
  h.eq(ah.replicated, 1)
  h.eq(ctx.env.AnotherLedgerCharDB.scanAt, ctx.now)
  fire(ctx, "REPLICATE_ITEM_LIST_UPDATE")
  ctx.runTimers(); ctx.runTimers()
  local r = ctx.ns.prices:lookup(5)
  h.eq(r.ahSource, "AnotherLedger scan"); h.eq(r.ahGross, 1000)
  h.eq(printedWith(ctx, "Scan done: 1 items priced"), true)
  h.eq(ctx.ns.Core.scanState().running, false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a second scan within 15 minutes waits", function()
  local ctx, ah = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  slash(ctx, "scan")
  fire(ctx, "REPLICATE_ITEM_LIST_UPDATE")
  ctx.runTimers(); ctx.runTimers()
  ctx.now = ctx.now + 60
  slash(ctx, "scan")
  h.eq(ah.replicated, 1)
  h.eq(printedWith(ctx, "The game allows the next full scan in 14m."), true)
  h.eq(ctx.ns.Core.scanState().waitLeft, 840)
end)

h.test("wiring: /al scan needs the auction house open", function()
  local ctx, ah = scanWorld()
  slash(ctx, "scan")
  h.eq(ah.replicated, 0)
  h.eq(printedWith(ctx, "Open the auction house to scan."), true)
end)

h.test("wiring: closing the auction house stops the scan once", function()
  local rows = {}
  for i = 1, 4500 do rows[i] = { 1, 100, 5, nil } end
  local ctx = scanWorld(rows)
  fire(ctx, "AUCTION_HOUSE_SHOW")
  slash(ctx, "scan")
  fire(ctx, "REPLICATE_ITEM_LIST_UPDATE")
  ctx.runTimers() -- the 60 s check and the first chunk
  fire(ctx, "AUCTION_HOUSE_CLOSED")
  h.eq(printedWith(ctx, "Scan stopped: the auction house was closed. 1 items priced."), true)
  local before = #ctx.printed
  ctx.runTimers()
  fire(ctx, "REPLICATE_ITEM_LIST_UPDATE")
  ctx.runTimers()
  h.eq(#ctx.printed, before)
  h.eq(ctx.ns.prices:lookup(5).ahSource, "AnotherLedger scan")
  h.eq(ctx.ns.Scan.bucket(ctx.ns.db, ctx.ns.Scan.currentRealmKey()).lastFull, nil)
end)

h.test("wiring: no answer within 60 s restores the wait", function()
  local ctx = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  slash(ctx, "scan")
  ctx.runTimers()
  h.eq(printedWith(ctx, "The game did not answer the scan. Try again later."), true)
  h.eq(ctx.env.AnotherLedgerCharDB.scanAt, nil)
  h.eq(ctx.ns.Core.scanState().running, false)
end)

h.test("wiring: a full commodity search is recorded, a partial one not", function()
  local ctx, ah = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  ah.commodity[7] = { full = false, list = { { unitPrice = 50, quantity = 10 } } }
  fire(ctx, "COMMODITY_SEARCH_RESULTS_UPDATED", 7)
  h.eq(ctx.ns.prices:lookup(7).ahSource == "AnotherLedger scan", false)
  ah.commodity[7].full = true
  fire(ctx, "COMMODITY_SEARCH_RESULTS_UPDATED", 7)
  h.eq(ctx.ns.prices:lookup(7).ahGross, 50)
end)

h.test("wiring: a full item search is recorded per variant", function()
  local ctx, ah = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  local link = "|Hitem:50::::::::60::::2:4802:1477::::::|h[Sword]|h"
  ah.items[50] = { full = true, list = { { buyoutAmount = 9000, quantity = 1, itemLink = link }, { quantity = 1, itemLink = link } } }
  fire(ctx, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 50 })
  h.eq(ctx.ns.prices:lookup(50, link).ahGross, 9000)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a battle pet search is not recorded", function()
  local ctx, ah = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  ah.items[82800] = { full = true, list = { { buyoutAmount = 50000000, quantity = 1, itemLink = "|Hbattlepet:39:1:3:150:10:10:0|h[Pet]|h" } } }
  fire(ctx, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 82800, battlePetSpeciesID = 39 })
  h.eq(next(ctx.ns.Scan.bucket(ctx.ns.db, ctx.ns.Scan.currentRealmKey(), true).items), nil)
end)

h.test("wiring: /al scan waits while the realm is not known yet", function()
  local ctx, ah = scanWorld()
  ctx.env.GetRealmName = function() return nil end
  fire(ctx, "AUCTION_HOUSE_SHOW")
  slash(ctx, "scan")
  h.eq(ah.replicated, 0)
  h.eq(printedWith(ctx, "The realm is not known yet. Try again in a moment."), true)
  h.eq(ctx.env.AnotherLedgerCharDB.scanAt, nil)
end)

h.test("wiring: with TSM loaded scanning still works and the scan answers what TSM lacks", function()
  local ctx = bootDeferred()
  local ah = fakeAuctionHouse(ctx, { { 1, 1000, 5, nil } })
  ctx.env.TSM_API = { GetCustomPriceValue = function(_, item) return item == "i:9" and 777 or nil end }
  startWorld(ctx, false)
  ctx.runTimers()
  local S = ctx.ns.Scan
  fire(ctx, "AUCTION_HOUSE_SHOW")
  slash(ctx, "scan")
  h.eq(ah.replicated, 1)
  ah.commodity[7] = { full = true, list = { { unitPrice = 50, quantity = 10 } } }
  fire(ctx, "COMMODITY_SEARCH_RESULTS_UPDATED", 7)
  h.eq(S.bucket(ctx.ns.db, S.currentRealmKey()).items[7] ~= nil, true)
  S.record(S.bucket(ctx.ns.db, S.currentRealmKey(), true).items, 5, 2000, 2000, ctx.now)
  h.eq(ctx.ns.prices:lookup(5).ahGross, 2000) -- Auto: TSM has none, the scan answers
  h.eq(ctx.ns.prices:lookup(9).ahSource, "TSM")
  -- No reminder while TSM is loaded.
  h.eq(printedWith(ctx, "more than a day old"), false)
end)

h.test("wiring: a selected price addon that is not loaded acts as Auto", function()
  local ctx = scanWorld()
  local S = ctx.ns.Scan
  S.record(S.bucket(ctx.ns.db, S.currentRealmKey(), true).items, 5, 2000, 2000, ctx.now)
  ctx.ns.db.settings.priceSource = "tsm"
  h.eq(ctx.ns.prices:lookup(5).ahGross, 2000)
  ctx.env.TSM_API = { GetCustomPriceValue = function() return 300 end }
  h.eq(ctx.ns.prices:lookup(5).ahGross, 300) -- TSM back: the choice counts again
  ctx.env.TSM_API = { GetCustomPriceValue = function() return nil end }
  h.eq(ctx.ns.prices:lookup(5).ahSource, "cache") -- only TSM may answer
end)

h.test("wiring: the scan reminder shows once per login, and not when off", function()
  local ctx = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  fire(ctx, "AUCTION_HOUSE_CLOSED")
  fire(ctx, "AUCTION_HOUSE_SHOW")
  local n = 0
  for _, line in ipairs(ctx.printed) do if line:find("more than a day old", 1, true) then n = n + 1 end end
  h.eq(n, 1)
  local off = scanWorld()
  off.ns.db.settings.scanReminder = false
  fire(off, "AUCTION_HOUSE_SHOW")
  h.eq(printedWith(off, "more than a day old"), false)
end)

h.test("wiring: the no price addon hint stays quiet with scan prices", function()
  local ctx = scanWorld()
  local S = ctx.ns.Scan
  ctx.ns.db.priceHintShown = nil
  h.eq(ctx.ns.Core.priceAddonHint(ctx.env, ctx.ns.db, function() end), true)
  ctx.ns.db.priceHintShown = nil
  S.record(S.bucket(ctx.ns.db, S.currentRealmKey(), true).items, 5, 2000, 2000, ctx.now)
  h.eq(ctx.ns.Core.priceAddonHint(ctx.env, ctx.ns.db, function() end), false)
  h.eq(ctx.ns.db.priceHintShown, nil)
end)

h.test("wiring: old scan prices are pruned at login", function()
  local ctx = bootDeferred()
  fakeAuctionHouse(ctx, {})
  ctx.env.AnotherLedgerDB = { scan = { ["EU-7-Realm"] = { items = { [5] = "1,2,3" } } } }
  ctx.now = 30 * 86400
  startWorld(ctx, false)
  h.eq(ctx.env.AnotherLedgerDB.scan["EU-7-Realm"], nil)
end)

h.test("wiring: the scan button shows on the auction house and starts a scan", function()
  local ctx, ah = scanWorld()
  ctx.env.AuctionHouseFrame = newFake(ctx.env)
  fire(ctx, "AUCTION_HOUSE_SHOW")
  local b = ctx.ns.UI.ScanButton.frame
  h.eq(type(b), "table"); h.eq(b:IsShown(), true)
  h.eq(b:GetText(), "AnotherLedger scan")
  b._scripts.OnClick(b, "LeftButton")
  h.eq(ah.replicated, 1)
  h.eq(b:GetText(), "Reading 0%")
  fire(ctx, "AUCTION_HOUSE_CLOSED")
  h.eq(b:IsShown(), false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the scan button comes when the auction house window loads late", function()
  local ctx = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW") -- the game's auction house UI is not loaded yet
  h.eq(ctx.ns.UI.ScanButton.frame, false)
  ctx.env.AuctionHouseFrame = newFake(ctx.env)
  fire(ctx, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
  local b = ctx.ns.UI.ScanButton.frame
  h.eq(type(b), "table"); h.eq(b:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the scan button retries on the next frame", function()
  local ctx = scanWorld()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  ctx.env.AuctionHouseFrame = newFake(ctx.env)
  ctx.runTimers()
  h.eq(type(ctx.ns.UI.ScanButton.frame), "table")
end)

h.test("wiring: the scan button is drawn above the auction house's own panels", function()
  local ctx = scanWorld()
  local parent = newFake(ctx.env)
  parent:SetFrameLevel(5)
  ctx.env.AuctionHouseFrame = parent
  fire(ctx, "AUCTION_HOUSE_SHOW")
  h.eq(ctx.ns.UI.ScanButton.frame:GetFrameLevel() >= 5 + ctx.ns.Theme.sizes.scanButtonLevel, true)
end)

h.test("wiring: the scan button also shows while TSM is loaded", function()
  local ctx = bootDeferred()
  fakeAuctionHouse(ctx, {})
  ctx.env.TSM_API = { GetCustomPriceValue = function() return nil end }
  ctx.env.AuctionHouseFrame = newFake(ctx.env)
  startWorld(ctx, false)
  ctx.runTimers()
  fire(ctx, "AUCTION_HOUSE_SHOW")
  local b = ctx.ns.UI.ScanButton.frame
  h.eq(b ~= false and b:IsShown(), true)
end)

h.test("wiring: a bronze button looks pressed while the mouse is held down", function()
  local ctx = scanWorld()
  ctx.env.AuctionHouseFrame = newFake(ctx.env)
  fire(ctx, "AUCTION_HOUSE_SHOW")
  local b = ctx.ns.UI.ScanButton.frame
  h.eq(type(b.fill), "table")
  b._scripts.OnMouseDown(b, "LeftButton")
  h.eq(b.look, "pressed")
  b._scripts.OnMouseUp(b, "LeftButton")
  h.eq(b.look, "normal")
  h.eq(ctx.errors, {})
end)

-- ---------------------------------------------------------------------------
-- Trade section: mail, auction house calls, chat and the trade window

local function tradeWorld(withRealm)
  local ctx = bootDeferred()
  local env = ctx.env
  env.hooksecurefunc = function(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...) local r = { orig(...) }; fn(...); return (table.unpack or unpack)(r) end
  end
  env.C_AuctionHouse = {
    PostItem = function() end, PostCommodity = function() end, CancelAuction = function() end,
    GetNumOwnedAuctions = function() return 1 end,
    GetOwnedAuctionInfo = function(i) return { auctionID = 77, itemLink = "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r", quantity = 3 } end,
  }
  env.C_Item = env.C_Item or {}
  env.C_Item.GetItemLink = function(loc) return loc.link end
  env.C_Item.GetItemInfoInstant = function(name) if name == "Bolt" then return 5 end end
  if withRealm ~= false then env.GetRealmName = function() return "Realm" end end
  env.UnitName = function(unit) return unit == "NPC" and "Partner" or "Me" end
  env.ERR_TRADE_COMPLETE = "Trade complete."
  env.ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
  env.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
  env.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
  env.AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
  env.mails = {}
  env.GetInboxNumItems = function() return #env.mails end
  env.GetInboxHeaderInfo = function(i)
    local m = env.mails[i]
    return nil, nil, m.sender, m.subject, m.money, 0, m.daysLeft, m.link ~= nil
  end
  env.GetInboxInvoiceInfo = function(i)
    local m = env.mails[i]
    if not m.invoice then return nil end
    return m.invoice, m.name, m.who, m.bid, m.bid, 0, m.cut, 0, 0, 0, m.count
  end
  env.GetInboxItemLink = function(i) return env.mails[i].link end
  env.GetInboxItem = function(i) return env.mails[i].name, 5, nil, env.mails[i].count end
  startWorld(ctx, false)
  ctx.runTimers()
  return ctx
end

local function tradeLog(ctx)
  local b = ctx.ns.Trade.bucket(ctx.ns.db, ctx.ns.Scan.currentRealmKey())
  return b and b.log or {}, b
end

local SALE_MAIL = { sender = "Auction House", subject = "Auction successful: Bolt", money = 380, daysLeft = 29.5,
  invoice = "seller", name = "Bolt", who = "Buyer", bid = 400, cut = 20, count = 4 }

h.test("wiring: a sale mail is recorded once", function()
  local ctx = tradeWorld()
  ctx.env.mails[1] = SALE_MAIL
  fire(ctx, "MAIL_INBOX_UPDATE")
  fire(ctx, "MAIL_INBOX_UPDATE")
  local log = tradeLog(ctx)
  h.eq(#log, 1)
  h.eq(log[1].kind, "sale"); h.eq(log[1].gold, 400); h.eq(log[1].cut, 20); h.eq(log[1].who, "Buyer")
  h.eq(log[1].id, 5); h.eq(log[1].n, 4)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a sale mail emptied unopened (Open All) is recorded from its subject, once", function()
  local ctx = tradeWorld()
  ctx.env.C_AuctionHouse.PostCommodity({ link = "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r" }, 1, 10, 100)
  -- Unopened: the client gives no invoice yet.
  ctx.env.mails[1] = { sender = "Auction House", subject = "Auction successful: Bolt (4)", money = 380, daysLeft = 29.5 }
  fire(ctx, "MAIL_INBOX_UPDATE")
  local log = tradeLog(ctx)
  h.eq(#log, 2); h.eq(log[2].kind, "sale"); h.eq(log[2].key, 5); h.eq(log[2].n, 4)
  h.eq(log[2].gold, 400); h.eq(log[2].cut, 20)
  -- Opened before it is emptied: the invoice comes, still one sale.
  local m = ctx.env.mails[1]
  m.invoice, m.name, m.who, m.bid, m.cut, m.count = "seller", "Bolt", "Buyer", 400, 20, 4
  fire(ctx, "MAIL_INBOX_UPDATE")
  ctx.env.mails[1] = nil
  fire(ctx, "MAIL_INBOX_UPDATE")
  local _, b = tradeLog(ctx)
  h.eq(#b.log, 2)
  h.eq(next(b.mails), nil) -- taken: forgotten, so an equal later mail counts
  h.eq(ctx.errors, {})
end)

h.test("wiring: an expired auction mail is recorded with its item", function()
  local ctx = tradeWorld()
  ctx.env.mails[1] = { sender = "Auction House", subject = "Auction expired: Bolt", money = 0, daysLeft = 29,
    link = "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r", name = "Bolt", count = 6 }
  fire(ctx, "MAIL_INBOX_UPDATE")
  local log = tradeLog(ctx)
  h.eq(#log, 1); h.eq(log[1].kind, "expire"); h.eq(log[1].n, 6); h.eq(log[1].key, 5)
  h.eq(ctx.errors, {})
end)

local function openTrade(ctx, playerLink, playerCount, targetMoney)
  local env = ctx.env
  fire(ctx, "TRADE_SHOW")
  env.GetTradePlayerItemLink = function(i) if i == 1 then return playerLink end end
  env.GetTradePlayerItemInfo = function(i) if i == 1 and playerLink then return "Bolt", nil, playerCount end end
  env.GetTradeTargetItemLink = function() return nil end
  env.GetTradeTargetItemInfo = function() return nil end
  env.GetPlayerTradeMoney = function() return 0 end
  env.GetTargetTradeMoney = function() return targetMoney end
  fire(ctx, "TRADE_ACCEPT_UPDATE", 1, 1)
end

h.test("wiring: a finished gold-for-items trade is a trade sale", function()
  local ctx = tradeWorld()
  openTrade(ctx, "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r", 3, 5000)
  fire(ctx, "UI_INFO_MESSAGE", 0, "Trade complete.")
  fire(ctx, "TRADE_CLOSED")
  local log = tradeLog(ctx)
  h.eq(#log, 1); h.eq(log[1].kind, "tsale"); h.eq(log[1].gold, 5000); h.eq(log[1].n, 3)
  h.eq(log[1].who, "Partner"); h.eq(log[1].char, "Me")
  h.eq(ctx.errors, {})
end)

h.test("wiring: a cancelled trade saves nothing", function()
  local ctx = tradeWorld()
  openTrade(ctx, "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r", 3, 5000)
  fire(ctx, "TRADE_CLOSED")
  ctx.runTimers() -- the second after closing passes
  fire(ctx, "UI_INFO_MESSAGE", 0, "Trade complete.") -- a later, unrelated message
  fire(ctx, "TRADE_SHOW")
  h.eq(#tradeLog(ctx), 0)
  h.eq(ctx.errors, {})
end)

h.test("wiring: posting a commodity logs a post, cancelling logs a cancel", function()
  local ctx = tradeWorld()
  local api = ctx.env.C_AuctionHouse
  api.PostCommodity({ link = "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r" }, 1, 20, 50)
  api.CancelAuction(77)
  local log = tradeLog(ctx)
  h.eq(#log, 2)
  h.eq(log[1].kind, "post"); h.eq(log[1].n, 20); h.eq(log[1].gold, 1000); h.eq(log[1].name, "Bolt")
  h.eq(log[2].kind, "cancel"); h.eq(log[2].n, 3)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the sold chat line marks the sale", function()
  local ctx = tradeWorld()
  fire(ctx, "CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Bolt.")
  local _, b = tradeLog(ctx)
  h.eq(#b.pending, 1); h.eq(b.pending[1].name, "Bolt")
  h.eq(ctx.errors, {})
end)

h.test("wiring: nothing is recorded while the realm key is unknown", function()
  local ctx = tradeWorld(false)
  ctx.env.mails[1] = SALE_MAIL
  fire(ctx, "MAIL_INBOX_UPDATE")
  h.eq(ctx.ns.db.trade == nil or next(ctx.ns.db.trade) == nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a trade whose complete message comes right after closing still counts", function()
  local ctx = tradeWorld()
  openTrade(ctx, "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r", 1, 900)
  fire(ctx, "TRADE_CLOSED")
  fire(ctx, "UI_INFO_MESSAGE", 0, "Trade complete.")
  h.eq(#tradeLog(ctx), 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: the Trade tab shows a recorded sale, the period hides old ones", function()
  local ctx = tradeWorld()
  ctx.env.mails[1] = SALE_MAIL
  fire(ctx, "MAIL_INBOX_UPDATE")
  local Ledger, TP = ctx.ns.UI.Ledger, ctx.ns.UI.TradePeriod
  Ledger.setTab("trade")
  Ledger.setSubtab("items")
  Ledger.refresh()
  h.eq(#Ledger.view.rows, 1); h.eq(Ledger.view.rows[1].value, 380)
  h.eq(TP.button:IsShown(), true); h.eq(TP.button:GetText(), "30 days")
  ctx.now = ctx.now + 10 * 86400
  TP.set("7")
  h.eq(ctx.env.AnotherLedgerDB.tradePeriod, "7")
  h.eq(#Ledger.view.rows, 0)
  Ledger.setSubtab("log")
  Ledger.refresh()
  h.eq(#Ledger.view.rows, 1); h.eq(TP.button:IsShown(), false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: History > Mobs shows the Mobs / Nodes switch, the Trade period hides", function()
  local ctx = boot()
  startWorld(ctx, false)
  local Ledger, MK, TP = ctx.ns.UI.Ledger, ctx.ns.UI.MobKind, ctx.ns.UI.TradePeriod
  Ledger.setTab("history")
  Ledger.setSubtab("mobs")
  Ledger.refresh()
  h.eq(MK.button:IsShown(), true); h.eq(MK.button:GetText(), "All")
  h.eq(TP.button:IsShown(), false)
  MK.set("nodes")
  h.eq(ctx.env.AnotherLedgerDB.mobKind, "nodes")
  h.eq(MK.button:GetText(), "Nodes")
  Ledger.setSubtab("sessions")
  Ledger.refresh()
  h.eq(MK.button:IsShown(), false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a row switch's menu marks the current choice and picks another", function()
  local ctx = boot()
  startWorld(ctx, false)
  local menus = captureMenus(ctx)
  local Ledger, MK = ctx.ns.UI.Ledger, ctx.ns.UI.MobKind
  Ledger.setTab("history")
  Ledger.setSubtab("mobs")
  Ledger.refresh()
  MK.button._scripts.OnClick(MK.button)
  local menu = menus[#menus]
  h.eq(#menu, 3)
  for _, it in ipairs(menu) do
    h.eq(it.kind, "radio")
    h.eq(type(it.checked), "function") -- the client menu calls it for every radio
  end
  h.eq(menuItem(menu, "All").checked(), true)
  h.eq(menuItem(menu, "Nodes").checked(), false)
  menuItem(menu, "Nodes").click()
  h.eq(ctx.env.AnotherLedgerDB.mobKind, "nodes")
  h.eq(menuItem(menu, "Nodes").checked(), true)
  h.eq(MK.button:GetText(), "Nodes")
  h.eq(ctx.errors, {})
end)

h.test("wiring: an auction won mail is a purchase in the Log and in Items, once", function()
  local ctx = tradeWorld()
  ctx.env.mails[1] = { sender = "Auction House", subject = "Auction won: Bolt", money = 0, daysLeft = 29.5,
    invoice = "buyer", name = "Bolt", who = "Seller", bid = 900, count = 3,
    link = "|cffffffff|Hitem:5::::::::|h[Bolt]|h|r" }
  fire(ctx, "MAIL_INBOX_UPDATE")
  fire(ctx, "MAIL_INBOX_UPDATE") -- read again: still one purchase
  local log = tradeLog(ctx)
  h.eq(#log, 1); h.eq(log[1].kind, "buy"); h.eq(log[1].key, 5); h.eq(log[1].gold, 900); h.eq(log[1].n, 3)
  local Ledger = ctx.ns.UI.Ledger
  Ledger.setTab("trade")
  Ledger.setSubtab("log")
  Ledger.refresh()
  h.eq(Ledger.view.rows[1].value, -900)
  Ledger.setSubtab("items")
  Ledger.refresh()
  h.eq(#Ledger.view.rows, 1); h.eq(Ledger.view.rows[1].value, -900)
  h.eq(ctx.errors, {})
end)

h.test("wiring: a reagent link with a quality icon matches its sale mail by name", function()
  local ctx = tradeWorld()
  ctx.env.C_AuctionHouse.PostCommodity({ link = "|cffffffff|Hitem:8::::::::|h[Ore |A:Professions-ChatIcon-Quality-Tier2:17:17::1|a]|h|r" }, 1, 5, 100)
  ctx.env.mails[1] = { sender = "Auction House", subject = "Auction successful: Ore", money = 480, daysLeft = 29.5,
    invoice = "seller", name = "Ore", who = "Buyer", bid = 500, cut = 25, count = 5 }
  fire(ctx, "MAIL_INBOX_UPDATE")
  local log, b = tradeLog(ctx)
  h.eq(log[1].name, "Ore"); h.eq(log[2].key, 8); h.eq(#b.posts, 0)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Zones keeps the saved History's sums and adds new loot and resets", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, ns = ctx.ns.UI.Ledger, ctx.ns
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset") -- one saved session
  L.setTab("history")
  L.setSubtab("zones")
  L.refresh()
  local saved = L.view.totals.best
  h.eq(saved > 0, true)
  h.eq(type(L.view.rows[1]), "table")
  fire(ctx, "CHAT_MSG_LOOT", LOOT) -- the running session adds to it
  L.refresh()
  h.eq(L.view.totals.best, 2 * saved)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  L.refresh()
  h.eq(L.view.totals.best, 3 * saved)
  slash(ctx, "reset") -- saved now: three times the loot, nothing running
  L.refresh()
  h.eq(L.view.totals.best, 3 * saved)
  ns.Core.deleteHistory(1)
  L.refresh()
  h.eq(L.view.totals.best, saved)
  h.eq(ctx.errors, {})
end)

h.test("wiring: /al stats prints the saved data parts, Mob data kept drops old mob data", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  slash(ctx, "reset")
  local before = #ctx.printed
  slash(ctx, "stats")
  h.eq(#ctx.printed - before, 7)
  h.eq(ctx.printed[before + 1]:find("Saved data: about", 1, true) ~= nil, true)
  local all = table.concat(ctx.printed, "\n", before + 1)
  h.eq(all:find("History: ", 1, true) ~= nil, true)
  h.eq(all:find("sessions: 1,", 1, true) ~= nil, true)
  -- Mob data kept: a session older than the cut loses its mob data, not itself.
  local e = ns.chardb.history[1]
  e.mobs = { ["npc:1"] = { kind = "npc", looted = 1, gold = 0, items = {} } }
  e.startedAt = ctx.now - 40 * 86400
  ns.Options.set(ns.db, "mobDataDays", 30)
  h.eq(e.mobs, nil)
  h.eq(#ns.chardb.history, 1)
  h.eq(ctx.errors, {})
end)

h.test("wiring: Hide Vendor tags blanks only the Vendor tag", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local R = ns.UI.Rows
  local vendorRow = { name = "Cloth", quantity = 2, bestKind = "vendor", vendorEach = 5, value = 10 }
  local ahRow = { name = "Ore", quantity = 1, bestKind = "ah", ahEach = 50, value = 50 }
  h.eq(R.rowText(vendorRow).hideTag, false)
  ns.Options.set(ns.db, "hideVendorTag", true)
  h.eq(R.rowText(vendorRow).hideTag, true)
  h.eq(R.rowText(vendorRow).source, "vendor")
  h.eq(R.rowText(ahRow).hideTag, false)
  h.eq(ctx.errors, {})
end)

h.test("wiring: item tooltips show the price trend from TSM, else from the scan", function()
  local ctx = boot()
  local onItem
  ctx.env.Enum = { TooltipDataType = { Item = 0 } }
  ctx.env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    if kind == 0 then onItem = fn end
  end }
  local tsm = { DBMarket = 1120, DBHistorical = 1000 }
  ctx.env.TSM_API = { GetCustomPriceValue = function(src) return tsm[src] end }
  ctx.env.GetRealmName = function() return "Realm" end
  startWorld(ctx, false)
  local ns = ctx.ns
  local function tooltipFor(link)
    local tip = { lines = {} }
    function tip:GetItem() return "Linen Cloth", link end
    function tip:AddLine(t) self.lines[#self.lines + 1] = t end
    function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " = " .. r end
    function tip:Show() end
    onItem(tip)
    return table.concat(tip.lines, "\n")
  end
  h.eq(tooltipFor(LINK):find("AnotherLedger price trend = +12% vs 60 days", 1, true) ~= nil, true)
  -- Without TSM: the scan's newest day against the one before.
  ctx.env.TSM_API = nil
  h.eq(tooltipFor(LINK), "")
  local bucket = ns.Scan.bucket(ns.db, ns.Scan.currentRealmKey(), true)
  h.eq(type(bucket), "table")
  ctx.now = 20 * 86400
  ns.Scan.record(bucket.items, 2589, 1000, 900, ctx.now - 86400)
  ns.Scan.record(bucket.items, 2589, 900, 900, ctx.now)
  h.eq(tooltipFor(LINK):find("AnotherLedger price trend = -10% vs earlier days", 1, true) ~= nil, true)
  ns.Options.set(ns.db, "itemTooltipTrend", false)
  h.eq(tooltipFor(LINK), "")
  h.eq(ctx.errors, {})
end)

h.test("wiring: a watched item alerts on loot, also with the clock stopped", function()
  local ctx = boot()
  local played, screen = 0, {}
  ctx.env.PlaySound = function() played = played + 1 end
  ctx.env.SOUNDKIT = { RAID_WARNING = 8959 }
  ctx.env.UIErrorsFrame = { AddMessage = function(_, text) screen[#screen + 1] = text end }
  startWorld(ctx, false)
  local ns = ctx.ns
  slash(ctx, "watch")
  h.eq(ctx.printed[#ctx.printed]:find("watch list is empty", 1, true) ~= nil, true)
  slash(ctx, "watch " .. LINK)
  h.eq(ns.db.watched[2589] ~= nil, true)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(played, 1)
  h.eq(#screen, 1)
  h.eq(screen[1]:find("watched item looted", 1, true) ~= nil, true)
  -- by part of a name, with the clock stopped (the session does not count it)
  slash(ctx, "unwatch 2589")
  h.eq(ns.db.watched[2589], nil)
  slash(ctx, "watch li")
  h.eq(ctx.printed[#ctx.printed]:find("at least 3 letters", 1, true) ~= nil, true)
  slash(ctx, "watch linen")
  h.eq(ns.db.watchedNames.linen, "linen")
  slash(ctx, "stop")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(played, 2)
  slash(ctx, "watch")
  h.eq(ctx.printed[#ctx.printed]:find("\"linen\"", 1, true) ~= nil, true)
  slash(ctx, "unwatch Linen")
  h.eq(ns.db.watchedNames.linen, nil)
  -- the row menu adds and removes it
  slash(ctx, "start")
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local L = ns.UI.Ledger
  L.setTab("session")
  local menu = L.rowMenu(L.view.rows[1])
  local watch
  for _, e in ipairs(menu) do if e.text == "Watch this item" then watch = e end end
  h.eq(watch ~= nil, true)
  watch.onClick()
  h.eq(ns.db.watched[2589] ~= nil, true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: switching border restyles the window without stacking frames", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns, win = ctx.ns, ctx.ns.UI.Window.frame
  h.eq(win._backdrop.edgeFile, ns.Theme.textures.frameBorder)
  ns.Options.pick(ns.db, "skinBorder", "bevel")
  h.eq(win._backdrop.edgeFile, nil)
  h.eq(#win.skinEdges, 5); h.eq(win.skinEdges[1].top:IsShown(), true)
  local first = win.skinEdges[1].top
  ns.Options.pick(ns.db, "skinBorder", "round")
  h.eq(win._backdrop.edgeFile, ns.Theme.textures.frameBorder)
  h.eq(win.skinEdges[1].top:IsShown(), false)
  ns.Options.pick(ns.db, "skinBorder", "gilded")
  h.eq(win.skinEdges[1].top, first) -- reused, not stacked
  h.eq(win.skinEdges[3].top:IsShown(), true)
  h.eq(win.skinStuds[1]:IsShown(), true)
  ns.Options.pick(ns.db, "skinBorder", "thin")
  h.eq(win.skinEdges[3].top:IsShown(), false); h.eq(win.skinStuds[1]:IsShown(), false)
  h.eq(win._backdrop.bgFile, ns.Theme.textures.parchment)
  h.eq(ctx.errors, {})
end)

h.test("wiring: opacity and brightness reach the edge lines", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Options.pick(ns.db, "skinBorder", "thin")
  local top = ns.UI.Window.frame.skinEdges[2].top
  h.eq(top._vertex[4], 1)
  ns.Options.pick(ns.db, "alpha", 0)
  h.eq(top._vertex[4], 0)
  ns.Options.pick(ns.db, "alpha", 1)
  local before = top._vertex[1]
  ns.Options.pick(ns.db, "brightness", 2)
  h.eq(top._vertex[1] > before, true)
end)

h.test("wiring: each button style shows its own parts", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local b = ns.UI.Widgets.button(ns.UI.Window.frame, "Test", 40)
  h.eq(b.fill.top:IsShown(), true)
  ns.Options.pick(ns.db, "skinButtons", "raised")
  h.eq(b.fill.top:IsShown(), false); h.eq(b.raise.top:IsShown(), true)
  h.eq(b.raise.top._vertex[1] > b.raise.bottom._vertex[1], true)
  ns.Options.pick(ns.db, "skinButtons", "flat")
  h.eq(b.fill.top:IsShown(), false); h.eq(b.raise.top:IsShown(), false)
  h.eq(b.fill.inner:IsShown(), false)
  ns.Options.pick(ns.db, "skinButtons", "bronze")
  h.eq(b.fill.top:IsShown(), true); h.eq(b.fill.inner:IsShown(), true); h.eq(b.raise.top:IsShown(), false)
end)

h.test("wiring: styled lines follow the Lines pick", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local W, T = ns.UI.Widgets, ns.Theme
  local r = W.rule(ns.UI.Window.frame, T.colors.rowSeparator, "BORDER")
  h.eq(r._texture, T.textures.rowHighlight)
  ns.Options.pick(ns.db, "skinLines", "groove")
  h.eq(r.groove:IsShown(), true)
  ns.Options.pick(ns.db, "skinLines", "dotted")
  h.eq(r._texture, T.textures.skinDotted); h.eq(r.groove:IsShown(), false)
  ns.Options.pick(ns.db, "skinLines", "gold")
  h.eq(r._texture, T.textures.rowHighlight)
end)

h.test("wiring: every skin applies with the window open, in both layouts", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local ns = ctx.ns
  for _, s in ipairs(ns.Theme.skins) do
    ns.Options.pick(ns.db, "skin", s.id)
    h.eq(ns.Theme.style.border, s.border)
    h.eq(ns.Theme.style.lines, s.lines)
    slash(ctx, "compact"); slash(ctx, "compact")
  end
  h.eq(ctx.errors, {})
end)

h.test("wiring: row separators, dividers and tab lines follow the Lines pick", function()
  local ctx = boot()
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local ns = ctx.ns
  local W = ns.UI.Widgets
  ns.Options.pick(ns.db, "skinLines", "groove")
  local rules = 0
  for region, t in pairs(W.tracked) do
    if t[1] == "rule" then
      rules = rules + 1
      h.eq(region.groove ~= false, true)
    end
  end
  h.eq(rules >= 4, true) -- separators, Top finds divider, compact divider, tab base lines
end)

h.test("wiring: square tabs on a non-round border, rounded on Round", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  local tabs = ns.UI.Ledger.tabs
  local b = tabs.buttons.session
  h.eq(b.skin._backdrop.edgeFile, ns.Theme.textures.tabBorder)
  ns.Options.pick(ns.db, "skinBorder", "bevel")
  h.eq(b.skin._backdrop.edgeFile, ns.Theme.textures.rowHighlight)
  ns.Options.pick(ns.db, "skinBorder", "round")
  h.eq(b.skin._backdrop.edgeFile, ns.Theme.textures.tabBorder)
end)

h.test("wiring: sunken list shows in full only", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns, win = ctx.ns, ctx.ns.UI.Window.frame
  h.eq(win.listBox:IsShown(), false)
  ns.Options.pick(ns.db, "skinListBox", true)
  h.eq(win.listBox:IsShown(), true)
  slash(ctx, "compact"); h.eq(win.listBox:IsShown(), false)
  slash(ctx, "compact"); h.eq(win.listBox:IsShown(), true)
  ns.Options.pick(ns.db, "skinListBox", false)
  h.eq(win.listBox:IsShown(), false)
end)

h.test("wiring: a profile with another skin restyles at once", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Profiles.create(ns.db, "Forge", { skin = "forge", skinBorder = "bevel", skinBackground = "grain",
    skinButtons = "raised", skinLines = "groove", skinListBox = true })
  ns.Profiles.activate(ns.db, ns.chardb, "Forge")
  h.eq(ns.Theme.style.buttons, "raised")
  -- An old saved Background value is ignored: the fill stays flat.
  h.eq(ns.UI.Window.frame._backdrop.bgFile, ns.Theme.textures.parchment)
  h.eq(ns.UI.Window.frame._backdrop.edgeFile, nil)
  h.eq(ns.UI.Window.frame.listBox:IsShown(), true)
  h.eq(ctx.errors, {})
end)

h.test("wiring: an unedited skin survives export and import", function()
  local ctx = boot()
  startWorld(ctx, false)
  local ns = ctx.ns
  ns.Options.pick(ns.db, "skin", "forge")
  local line = ns.Profiles.encode(ns.db.settings)
  local settings = ns.Profiles.decode(line)
  ns.Profiles.create(ns.db, "Imported", settings)
  ns.Profiles.activate(ns.db, ns.chardb, "Imported")
  h.eq(ns.Options.get(ns.db, "skinBorder"), "bevel")
  h.eq(ns.Options.get(ns.db, "skinListBox"), true)
  h.eq(ns.Options.skinEdited(ns.db.settings), false)
  h.eq(ns.Theme.style.buttons, "raised")
end)

h.test("wiring: the sunken list box sits above the window and below the list", function()
  local ctx = boot()
  startWorld(ctx, false)
  local win = ctx.ns.UI.Window.frame
  h.eq(win.listBox:GetFrameLevel() > win:GetFrameLevel(), true)
  h.eq(win.listArea:GetFrameLevel() > win.listBox:GetFrameLevel(), true)
end)

h.test("wiring: Pause while traveling rests the clock on flights and transports", function()
  local ctx = boot()
  local state = { taxi = false, x = 0, speed = 0 }
  ctx.env.UnitOnTaxi = function() return state.taxi end
  ctx.env.UnitPosition = function() return 0, state.x, 0, 1 end
  ctx.env.GetUnitSpeed = function() return state.speed end
  startWorld(ctx, false)
  local ns = ctx.ns
  local H = ns.UI.Header.instance
  slash(ctx, "compact")
  h.eq(ns.Options.get(ns.db, "travelPause"), true)
  ns.Core.heartbeat()
  h.eq(ns.session.resting, nil)
  -- A flight path
  state.taxi = true
  fire(ctx, "PLAYER_CONTROL_LOST")
  h.eq(ns.session.resting, "travel")
  h.eq(H.pausedText:GetText(), ns.L["Traveling"])
  ctx.now = ctx.now + 100
  h.eq(ns.Session.elapsed(ns.session, ctx.now), 0)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  h.eq(ns.session.items[2589].qty, 3) -- loot still counts
  state.taxi = false
  fire(ctx, "PLAYER_CONTROL_GAINED")
  h.eq(ns.session.resting, nil)
  -- Standing on a boat: carried 60 yards in 5 seconds
  ctx.now = ctx.now + 5
  ns.Core.heartbeat()
  state.x = 60
  ctx.now = ctx.now + 5
  ns.Core.heartbeat()
  h.eq(ns.session.resting, "travel")
  -- Arrived: standing still again
  ctx.now = ctx.now + 5
  ns.Core.heartbeat()
  h.eq(ns.session.resting, nil)
  -- Running on foot is no ride
  state.speed = 7
  state.x = 95
  ctx.now = ctx.now + 5
  ns.Core.heartbeat()
  h.eq(ns.session.resting, nil)
  -- A stopped clock stays stopped on a flight; option off: the flight counts
  slash(ctx, "stop")
  state.taxi = true
  fire(ctx, "PLAYER_CONTROL_LOST")
  h.eq(ns.session.running, false)
  slash(ctx, "start")
  h.eq(ns.session.resting, "travel")
  ns.Options.set(ns.db, "travelPause", false)
  h.eq(ns.session.resting, nil)
  h.eq(ctx.errors, {})
end)

h.test("wiring: item tooltips show the TSM sale info, off with TSM sale info", function()
  local ctx = boot()
  local onItem
  ctx.env.Enum = { TooltipDataType = { Item = 0 } }
  ctx.env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    if kind == 0 then onItem = fn end
  end }
  local tsm = { ["DBRegionSaleRate * 1000"] = 250, ["DBRegionSoldPerDay * 100"] = 500, DBMarket = 900 }
  ctx.env.TSM_API = { GetCustomPriceValue = function(src) return tsm[src] end }
  startWorld(ctx, false)
  local ns = ctx.ns
  local function tooltipFor(link)
    local tip = { lines = {} }
    function tip:GetItem() return "Linen Cloth", link end
    function tip:AddLine(t) self.lines[#self.lines + 1] = t end
    function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " = " .. r end
    function tip:Show() end
    onItem(tip)
    return (table.concat(tip.lines, " / "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  local text = tooltipFor(LINK)
  h.eq(text:find(ns.L["TSM sale info"] .. " = Sells okay, Low volume", 1, true) ~= nil, true)
  ns.Options.set(ns.db, "showMarket", false)
  h.eq(tooltipFor(LINK):find(ns.L["TSM sale info"], 1, true), nil)
  h.eq(ctx.errors, {})
end)
