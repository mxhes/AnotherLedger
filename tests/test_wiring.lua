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
    SLASH_LOOTPRICE2 = true, LootPriceWindow = true, LootPriceFilterMenu = true,
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
