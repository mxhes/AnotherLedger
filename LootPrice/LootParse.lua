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

function LootParse.itemID(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("|Hitem:(%d+)")
  return id and tonumber(id) or nil
end

ns.LootParse = LootParse
