local ADDON, ns = ...

local LootParse = {}

-- Multiples first: a plain "%s." pattern would otherwise swallow "...x5".
local KEYS = {
  "LOOT_ITEM_SELF_MULTIPLE",
  "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
  "LOOT_ITEM_CREATED_SELF_MULTIPLE",
  "LOOT_ITEM_SELF",
  "LOOT_ITEM_PUSHED_SELF",
  "LOOT_ITEM_CREATED_SELF",
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
  for _, key in ipairs(KEYS) do
    local fmt = G[key]
    if fmt then
      local pattern, hasQty = toPattern(fmt)
      compiled[#compiled + 1] = { pattern = pattern, hasQty = hasQty }
    end
  end
  return compiled
end

-- Returns itemLink, quantity for the player's own item loot messages, else nil.
function LootParse.parse(compiled, msg)
  if type(msg) ~= "string" then return nil end
  for _, entry in ipairs(compiled) do
    local link, qty = msg:match(entry.pattern)
    if link and link:find("|Hitem:", 1, true) then
      if entry.hasQty then return link, tonumber(qty) end
      return link, 1
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Raw gold (CHAT_MSG_MONEY)

-- Guild form first: its "(%s deposited ...)" tail would otherwise be swallowed
-- by the plain "You loot %s" pattern.
local MONEY_KEYS = { "YOU_LOOT_MONEY_GUILD", "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" }
local MONEY_UNITS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }
local MONEY_SEPARATOR = ", "

-- Turns the money message formats plus the three amount templates into
-- anchored patterns. Missing globals are skipped.
function LootParse.compileMoney(G)
  local compiled = { messages = {}, units = {} }
  for _, key in ipairs(MONEY_KEYS) do
    if type(G[key]) == "string" then
      compiled.messages[#compiled.messages + 1] = (toPattern(G[key]))
    end
  end
  for _, u in ipairs(MONEY_UNITS) do
    if type(G[u[1]]) == "string" then
      compiled.units[#compiled.units + 1] = { pattern = (toPattern(G[u[1]])), mult = u[2] }
    end
  end
  return compiled
end

-- "1 Gold, 23 Silver, 4 Copper" (any subset, each unit at most once) -> copper.
local function moneyText(compiled, text)
  local total, seen = 0, {}
  local pos = 1
  while true do
    local cut = text:find(MONEY_SEPARATOR, pos, true)
    local part = text:sub(pos, cut and cut - 1 or #text)
    local matched = false
    for i, u in ipairs(compiled.units) do
      local n = part:match(u.pattern)
      if n and not seen[i] then
        seen[i] = true
        total = total + tonumber(n) * u.mult
        matched = true
        break
      end
    end
    if not matched then return nil end
    if not cut then break end
    pos = cut + #MONEY_SEPARATOR
  end
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

function LootParse.itemID(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("|Hitem:(%d+)")
  return id and tonumber(id) or nil
end

ns.LootParse = LootParse
