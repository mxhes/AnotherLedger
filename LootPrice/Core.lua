local ADDON, ns = ...

local Core = {}
ns.Core = Core

local PREFIX = "|cff33ff99LootPrice|r: "
local REFRESH_THROTTLE = 0.2
local KEY_RETRY_SECONDS = 10

local keyState = { key = nil }
local setupDone = false -- session/prices/UI are created once per Lua session
local compiled -- LootParse patterns, built once from the real globals
local compiledMoney -- LootParse money patterns, built lazily likewise
local refreshPending = false

local function say(msg)
  print(PREFIX .. msg)
end

local function refreshUI()
  if ns.UI and ns.UI.refresh then ns.UI.refresh() end
end

-- ---------------------------------------------------------------------------
-- Pure-ish helpers (take the global environment as a parameter, testable)

-- Region/game-mode cache key, or nil while either part is unavailable.
-- Both engine calls may be missing on the Forever client, hence pcall.
function Core.evalKey(env)
  local region, modeID
  -- UNVERIFIED (check in client): GetCurrentRegionName exists and returns a region string.
  if type(env.GetCurrentRegionName) == "function" then
    local ok, v = pcall(env.GetCurrentRegionName)
    if ok then region = v end
  end
  -- UNVERIFIED (check in client): C_GameRules.GetCurrentGameModeRecordID exists on Forever.
  local rules = env.C_GameRules
  if type(rules) == "table" and type(rules.GetCurrentGameModeRecordID) == "function" then
    local ok, v = pcall(rules.GetCurrentGameModeRecordID)
    if ok then modeID = v end
  end
  return ns.Prices.cacheKey(region, modeID)
end

-- Lazily re-evaluates a nil key (the game mode may be unknown right after
-- login), at most once per KEY_RETRY_SECONDS. `state` = { key, tried }.
function Core.keyFromState(state, env, now)
  if state.key == nil and (state.tried == nil or now - state.tried >= KEY_RETRY_SECONDS) then
    state.tried = now
    state.key = Core.evalKey(env)
  end
  return state.key
end

-- Builds the Prices object over `env` (_G in the client). `getKey` returns the
-- current cache key; the TSM source string is read live from db.settings.
function Core.buildPrices(env, db, now, getKey)
  local Sources = ns.Sources
  return ns.Prices.new({
    sources = {
      Sources.TSM.new(env, function() return db.settings.tsmSource end),
      Sources.Auctionator.new(env),
    },
    vendor = function(itemID) return Sources.Vendor.get(env, itemID) end,
    cache = db.cache,
    key = getKey,
    now = now,
  })
end

-- Real-format item link for fake/demo items.
function Core.makeLink(itemID, name, colorHex)
  return string.format("|cff%s|Hitem:%d::::::::60:::::::::|h[%s]|h|r", colorHex, itemID, name)
end

-- Demo loot: { id, name, color, qty, ahPrice (copper or nil), stale (bool) }
Core.DEMO_ITEMS = {
  { 2589, "Linen Cloth", "ffffff", 23, 55, false },
  { 2592, "Wool Cloth", "ffffff", 14, 130, false },
  { 3356, "Kingsblood", "ffffff", 6, 1500, true },
  { 2318, "Light Leather", "ffffff", 9, nil, false },
  { 4306, "Silk Cloth", "ffffff", 11, 900, false },
  { 7910, "Star Ruby", "1eff00", 2, 38000, false },
}

-- Originals of the cache entries demo overwrote (NOT persisted):
-- demoBackup[key] = { created = bool, items = { [itemID] = entry or false },
--                     seeded = { [itemID] = the fake entry demo wrote } }
Core.demoBackup = nil

local function copyEntry(e)
  if type(e) ~= "table" then return e end
  local c = {}
  for k, v in pairs(e) do c[k] = v end
  return c
end

function Core.seedDemoCache(db, key, now)
  if not key then return end
  Core.demoBackup = Core.demoBackup or {}
  local bucket = db.cache[key]
  local backup = Core.demoBackup[key]
  if not backup then
    backup = { created = type(bucket) ~= "table", items = {}, seeded = {} }
    Core.demoBackup[key] = backup
  end
  if type(bucket) ~= "table" then
    bucket = {}
    db.cache[key] = bucket
  end
  for _, d in ipairs(Core.DEMO_ITEMS) do
    if d[5] then
      if backup.items[d[1]] == nil then
        backup.items[d[1]] = bucket[d[1]] ~= nil and copyEntry(bucket[d[1]]) or false
      end
      local fake = { price = d[5], seenAt = d[6] and now - 14 * 3600 or now }
      bucket[d[1]] = fake
      backup.seeded[d[1]] = copyEntry(fake)
    end
  end
end

-- Puts back the cache entries demo replaced and drops the fake ones.
function Core.restoreDemoCache(db)
  local all = Core.demoBackup
  Core.demoBackup = nil
  if not all or not db or type(db.cache) ~= "table" then return end
  for key, backup in pairs(all) do
    local bucket = db.cache[key]
    if type(bucket) == "table" then
      for id, orig in pairs(backup.items) do
        local cur, fake = bucket[id], backup.seeded[id]
        -- Only revert entries that still are the demo's fake; a real write wins.
        if type(cur) == "table" and type(fake) == "table"
            and cur.price == fake.price and cur.seenAt == fake.seenAt then
          if orig == false then bucket[id] = nil else bucket[id] = orig end
        end
      end
      if backup.created and next(bucket) == nil then db.cache[key] = nil end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Loot capture

function Core.recordLoot(link, qty)
  local itemID = ns.LootParse.itemID(link)
  if not itemID or not ns.session then return end
  if not ns.Session.add(ns.session, itemID, link, qty, time()) then return end
  local unitValue
  if ns.prices then
    local info = ns.prices:lookup(itemID)
    unitValue = info.ah or info.vendor
  end
  if ns.UI and ns.UI.flash then
    -- flash refreshes the ledger itself
    ns.UI.flash(itemID, ns.View.flashLevel(unitValue, qty))
  else
    refreshUI()
  end
end

-- Raw gold (looted or quest money), copper > 0. Refreshes the UI on success.
function Core.recordGold(copper)
  if not ns.session then return end
  if not ns.Session.addGold(ns.session, copper, time()) then return end
  refreshUI()
end

local function onMoneyMessage(text)
  if not compiledMoney then compiledMoney = ns.LootParse.compileMoney(_G) end
  local copper = ns.LootParse.parseMoney(compiledMoney, text)
  if copper then Core.recordGold(copper) end
end

local function onLootMessage(text)
  if not compiled then compiled = ns.LootParse.compile(_G) end
  local link, qty = ns.LootParse.parse(compiled, text)
  if link then Core.recordLoot(link, qty) end
end

local function requestRefresh()
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(REFRESH_THROTTLE, function()
    refreshPending = false
    refreshUI()
  end)
end

-- ---------------------------------------------------------------------------
-- Slash commands

local HELP = {
  "/lp - toggle the window",
  "/lp show | hide - show or hide the window",
  "/lp start | stop - start or stop the session clock",
  "/lp reset - clear the session",
  "/lp keep on|off - keep the session across logins",
  "/lp tsm <source> - TSM price source (e.g. DBMarket)",
  "/lp demo - add fake sample loot, gold and temporary fake AH prices (UI check only)",
  "Note: an AH age tag can look fresh when the price source serves old scan data.",
}

local function windowCall(name)
  local w = ns.UI and ns.UI.Window
  if w and type(w[name]) == "function" then w[name]() end
end

local function demo()
  if not ns.session then return end
  if not ns.session.running then
    say("session is stopped - press Start first.")
    return
  end
  local now = time()
  Core.seedDemoCache(ns.db, keyState.key, now)
  for _, d in ipairs(Core.DEMO_ITEMS) do
    Core.recordLoot(Core.makeLink(d[1], d[2], d[3]), d[4])
  end
  Core.recordGold(1240) -- 12s 40c (8s 40c looted + 4s quest)
  say("added demo loot.")
end

-- Session actions shared by the slash commands and the header buttons.
function Core.startSession()
  if not ns.session then return end
  ns.Session.start(ns.session, time())
  say("session started.")
  refreshUI()
end

function Core.stopSession()
  if not ns.session then return end
  ns.Session.stop(ns.session, time())
  say("session stopped.")
  refreshUI()
end

function Core.resetSession()
  Core.restoreDemoCache(ns.db)
  if not ns.session then return end
  ns.Session.reset(ns.session, time())
  say("session reset.")
  refreshUI()
end

local handlers = {
  toggle = function() windowCall("toggle") end,
  show = function() windowCall("show") end,
  hide = function() windowCall("hide") end,
  start = Core.startSession,
  stop = Core.stopSession,
  reset = function()
    -- Same path as the Reset button: asks first when the session is large.
    if ns.UI and ns.UI.Header then
      ns.UI.Header.requestReset()
    else
      Core.resetSession()
    end
  end,
  keep = function(arg)
    local v = arg and arg:lower()
    if v ~= "on" and v ~= "off" then
      say("usage: /lp keep on|off (currently " .. (ns.db.settings.keepSession and "on" or "off") .. ")")
      return
    end
    ns.db.settings.keepSession = (v == "on")
    say("keep session across logins: " .. v)
  end,
  tsm = function(arg)
    if not arg then
      say("TSM source: " .. tostring(ns.db.settings.tsmSource))
      return
    end
    ns.db.settings.tsmSource = arg
    say("TSM source: " .. arg)
    refreshUI()
  end,
  demo = demo,
  help = function()
    for _, line in ipairs(HELP) do say(line) end
  end,
}

local function onSlash(msg)
  local cmd, arg = ns.Slash.parse(msg)
  local fn = handlers[cmd]
  if not fn then
    handlers.help()
    return
  end
  if not ns.session and cmd ~= "help" then
    say("not ready yet.")
    return
  end
  fn(arg)
end

-- ---------------------------------------------------------------------------
-- Events

local events = {}

function events.ADDON_LOADED(name)
  if name ~= ADDON then return end
  LootPriceDB = ns.DB.applyDefaults(LootPriceDB, ns.DB.defaults)
  LootPriceCharDB = ns.DB.applyDefaults(LootPriceCharDB, {})
  ns.db = LootPriceDB
  ns.chardb = LootPriceCharDB
end

-- The session is created on the first PLAYER_ENTERING_WORLD of the Lua
-- session: a real login starts fresh (unless "keep" is on), a /reload
-- (isReloadingUi) always keeps it. Later firings (zone changes, instances)
-- only re-evaluate the cache key.
function events.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
  keyState.key = Core.evalKey(_G)
  keyState.tried = time()
  if setupDone or not ns.db then return end
  setupDone = true
  local keep = ns.db.settings.keepSession or isReloadingUi
  ns.session = ns.Session.login(ns.chardb.session, keep, time())
  ns.chardb.session = ns.session
  ns.prices = Core.buildPrices(_G, ns.db, time, function()
    return Core.keyFromState(keyState, _G, time())
  end)
  if ns.UI and ns.UI.Ledger then ns.UI.Ledger.init() end
  refreshUI()
end

function events.CHAT_MSG_LOOT(text)
  if ns.session then onLootMessage(text) end
end

function events.CHAT_MSG_MONEY(text)
  if ns.session then onMoneyMessage(text) end
end

-- moneyReward is copper; 0, nil and non-numbers are ignored by Session.addGold.
function events.QUEST_TURNED_IN(questID, xpReward, moneyReward)
  if ns.session then Core.recordGold(moneyReward) end
end

-- Only items in the ledger matter; the event fires for every item query.
function events.GET_ITEM_INFO_RECEIVED(itemID)
  if ns.session and ns.session.items[itemID] then requestRefresh() end
end

function events.PLAYER_LOGOUT()
  Core.restoreDemoCache(ns.db)
  if ns.session then
    ns.Session.suspend(ns.session, time())
    ns.chardb.session = ns.session
  end
end

Core.events = events

function Core.init()
  local frame = CreateFrame("Frame")
  for event in pairs(events) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function(_, event, ...)
    local fn = events[event]
    if fn then fn(...) end
  end)
  Core.frame = frame

  SLASH_LOOTPRICE1 = "/lp"
  SLASH_LOOTPRICE2 = "/lootprice"
  SlashCmdList["LOOTPRICE"] = onSlash
end

if type(_G.CreateFrame) == "function" then Core.init() end
