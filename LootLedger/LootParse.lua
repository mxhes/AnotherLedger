local ADDON, ns = ...

local LootParse = {}

-- Multiples first: a plain "%s." pattern would otherwise swallow "...x5".
-- `kind` tells Core where the item came from: "loot" (looted), "pushed" (put
-- into the bags: quest rewards, but also purchases and mail) or "created"
-- (crafted or conjured).
local KEYS = {
  { "LOOT_ITEM_SELF_MULTIPLE", "loot" },
  { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "pushed" },
  { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "created" },
  { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "loot" },
  { "LOOT_ITEM_SELF", "loot" },
  { "LOOT_ITEM_PUSHED_SELF", "pushed" },
  { "LOOT_ITEM_CREATED_SELF", "created" },
  { "LOOT_ITEM_BONUS_ROLL_SELF", "loot" },
}

-- Turns a GlobalStrings format ("You receive loot: %sx%d.") into an anchored Lua pattern.
local function toPattern(fmt)
  local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  local hasQty = p:find("%%d", 1, true) ~= nil
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$", hasQty
end

function LootParse.compile(G)
  local compiled = {}
  for _, k in ipairs(KEYS) do
    local fmt = G[k[1]]
    if type(fmt) == "string" then
      local pattern, hasQty = toPattern(fmt)
      compiled[#compiled + 1] = { pattern = pattern, hasQty = hasQty, kind = k[2] }
    end
  end
  return compiled
end

-- Returns itemLink, quantity, kind ("loot" / "pushed" / "created") for the
-- player's own item loot messages, else nil.
function LootParse.parse(compiled, msg)
  if type(msg) ~= "string" then return nil end
  for _, entry in ipairs(compiled) do
    local link, qty = msg:match(entry.pattern)
    if link and link:find("|Hitem:", 1, true) then
      if entry.hasQty then return link, tonumber(qty), entry.kind end
      return link, 1, entry.kind
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Raw gold (CHAT_MSG_MONEY)

-- Guild forms first: their "(%s deposited ...)" tail would otherwise be
-- swallowed by the plain "You loot %s" pattern.
-- LOOT_MONEY_SPLIT_GUILD: "Your share of the loot is %s. (%s deposited to
-- guild bank)".
local MONEY_KEYS = { "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT_GUILD", "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" }
local MONEY_UNITS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }

-- Turns the money message formats plus the three amount templates into
-- patterns (the unit patterns unanchored: they are searched inside the amount
-- text). Missing globals are skipped.
function LootParse.compileMoney(G)
  local compiled = { messages = {}, units = {} }
  for _, key in ipairs(MONEY_KEYS) do
    if type(G[key]) == "string" then
      compiled.messages[#compiled.messages + 1] = (toPattern(G[key]))
    end
  end
  for _, u in ipairs(MONEY_UNITS) do
    if type(G[u[1]]) == "string" then
      local anchored = toPattern(G[u[1]])
      compiled.units[#compiled.units + 1] = { pattern = anchored:sub(2, -2), mult = u[2] }
    end
  end
  return compiled
end

-- "1 Gold, 23 Silver, 4 Copper" (any subset, each unit at most once) -> copper.
-- Each unit is searched in the text; whatever is left between the amounts must
-- be a separator (no ASCII letters or digits), whatever the client language
-- puts there.
local function moneyText(compiled, text)
  local total, used, any = 0, {}, false
  for _, u in ipairs(compiled.units) do
    local s, e, n = text:find(u.pattern)
    if s then
      for i = s, e do
        if used[i] then return nil end
        used[i] = true
      end
      total = total + tonumber(n) * u.mult
      any = true
    end
  end
  if not any then return nil end
  local rest = {}
  for i = 1, #text do
    if not used[i] then rest[#rest + 1] = text:sub(i, i) end
  end
  if table.concat(rest):find("%w") then return nil end
  return total
end

-- Returns the copper amount of the player's own money message (the first
-- amount only for the guild bank form), else nil. 0 copper is not income.
function LootParse.parseMoney(compiled, msg)
  if type(compiled) ~= "table" or type(msg) ~= "string" then return nil end
  for _, pattern in ipairs(compiled.messages) do
    local text = msg:match(pattern)
    if text then
      local copper = moneyText(compiled, text)
      if copper and copper > 0 then return copper end
      return nil
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Currencies (CHAT_MSG_CURRENCY)

local CURRENCY_KEYS = { "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" }

function LootParse.compileCurrency(G)
  local compiled = {}
  for _, key in ipairs(CURRENCY_KEYS) do
    if type(G[key]) == "string" then
      local pattern, hasQty = toPattern(G[key])
      compiled[#compiled + 1] = { pattern = pattern, hasQty = hasQty }
    end
  end
  return compiled
end

-- Returns currencyID, link, quantity of the player's own currency message, else nil.
function LootParse.parseCurrency(compiled, msg)
  if type(compiled) ~= "table" or type(msg) ~= "string" then return nil end
  for _, entry in ipairs(compiled) do
    local link, qty = msg:match(entry.pattern)
    if link then
      local id = tonumber(link:match("|Hcurrency:(%d+)") or "")
      if not id then return nil end
      qty = entry.hasQty and tonumber(qty) or 1
      if not qty or qty <= 0 then return nil end
      return id, link, qty
    end
  end
  return nil
end

function LootParse.itemID(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("|Hitem:(%d+)")
  return id and tonumber(id) or nil
end

-- The key an item is stored and priced under: the item ID (a number) for a
-- plain item, "<itemID>:<bonus IDs, sorted>" for an item with bonus IDs
-- (gear of different item levels, sockets, ...). Accepts a link or an item
-- string ("item:..."); returns key, itemID or nil.
-- The bonus ID count is the 13th field after the item ID in an item link.
local NUM_BONUS_FIELD = 13
function LootParse.itemKey(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("item:([%-%d:]+)")
  if not body then return nil end
  local fields, pos = {}, 1
  while true do
    local cut = body:find(":", pos, true)
    fields[#fields + 1] = body:sub(pos, cut and cut - 1 or #body)
    if not cut then break end
    pos = cut + 1
  end
  local id = tonumber(fields[1])
  if not id then return nil end
  local n = tonumber(fields[NUM_BONUS_FIELD]) or 0
  if n <= 0 then return id, id end
  local bonus = {}
  for i = 1, n do
    local b = tonumber(fields[NUM_BONUS_FIELD + i])
    if b then bonus[#bonus + 1] = b end
  end
  if #bonus == 0 then return id, id end
  table.sort(bonus)
  return id .. ":" .. table.concat(bonus, ":"), id
end

ns.LootParse = LootParse
