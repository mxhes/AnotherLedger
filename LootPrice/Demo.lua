local ADDON, ns = ...

local L = ns.L

-- /lp demo: fake sample loot, raw gold and temporary fake AH prices, to check
-- the UI without farming. The fake prices overwrite entries of the saved
-- price cache; the originals are kept in memory and put back by Demo.restore
-- (on Reset and at logout), so nothing fake is ever saved.
local Demo = {}

-- Demo loot: { id, name, color, qty, ahPrice (copper or nil), stale (bool) }
Demo.ITEMS = {
  { 2589, "Linen Cloth", "ffffff", 23, 55, false },
  { 2592, "Wool Cloth", "ffffff", 14, 130, false },
  { 3356, "Kingsblood", "ffffff", 6, 1500, true },
  { 2318, "Light Leather", "ffffff", 9, nil, false },
  { 4306, "Silk Cloth", "ffffff", 11, 900, false },
  { 7910, "Star Ruby", "1eff00", 2, 38000, false },
}

Demo.GOLD = 1240 -- 12s 40c (8s 40c looted + 4s quest)

local STALE_AGE = 14 * 3600 -- age of the demo price that shows the stale tag

-- Originals of the cache entries demo overwrote (NOT persisted):
-- backup[key] = { created = bool, items = { [itemID] = entry or false },
--                 seeded = { [itemID] = the fake entry demo wrote } }
Demo.backup = nil

-- Whether fake prices are in the cache right now.
function Demo.active()
  return Demo.backup ~= nil
end

-- Real-format item link for fake/demo items.
function Demo.makeLink(itemID, name, colorHex)
  return string.format("|cff%s|Hitem:%d::::::::60:::::::::|h[%s]|h|r", colorHex, itemID, name)
end

local function copyEntry(e)
  if type(e) ~= "table" then return e end
  local c = {}
  for k, v in pairs(e) do c[k] = v end
  return c
end

-- Writes the fake AH prices into the cache bucket `key`, remembering what was
-- there. A nil key (region / game mode unknown) seeds nothing.
function Demo.seedCache(db, key, now)
  if not key then return end
  Demo.backup = Demo.backup or {}
  local bucket = db.cache[key]
  local backup = Demo.backup[key]
  if not backup then
    backup = { created = type(bucket) ~= "table", items = {}, seeded = {} }
    Demo.backup[key] = backup
  end
  if type(bucket) ~= "table" then
    bucket = {}
    db.cache[key] = bucket
  end
  for _, item in ipairs(Demo.ITEMS) do
    local id, price, isStale = item[1], item[5], item[6]
    if price then
      if backup.items[id] == nil then
        backup.items[id] = bucket[id] ~= nil and copyEntry(bucket[id]) or false
      end
      local fake = { price = price, seenAt = isStale and now - STALE_AGE or now }
      bucket[id] = fake
      backup.seeded[id] = copyEntry(fake)
    end
  end
end

-- Puts back the cache entries demo replaced and drops the fake ones.
function Demo.restoreCache(db)
  local all = Demo.backup
  Demo.backup = nil
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

-- Adds the demo loot and gold to the running session through the normal loot path.
function Demo.run()
  local Core, say = ns.Core, ns.Util.say
  if not ns.session.running then
    say(L["session is stopped - press Start first."])
    return
  end
  Demo.seedCache(ns.db, Core.cacheKey(), time())
  for _, item in ipairs(Demo.ITEMS) do
    Core.recordLoot(Demo.makeLink(item[1], item[2], item[3]), item[4])
  end
  Core.recordGold(Demo.GOLD)
  say(L["added demo loot."])
end

if ns.Slash then
  ns.Slash.define({
    name = "demo",
    help = L["/lp demo - add fake sample loot, gold and temporary fake AH prices (UI check only)"],
    run = Demo.run,
  })
end

ns.Demo = Demo
