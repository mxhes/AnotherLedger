local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Drop chances in the game's item tooltips (bags, chat links, the loot
-- window, other addons' lists): which mobs and nodes drop the item and how
-- often, from the History > Mobs data (View.dropIndex, View.dropTooltipLines).
-- Option "itemTooltipDrops". Client-only; every WoW global is touched inside
-- functions only.
local ItemTooltip = {}
ns.UI.ItemTooltip = ItemTooltip

-- The index is built again only when its data changed: the History lists
-- (History.combine's key), the running session's mob table or Core.mobsVersion
-- (a loot window was read).
local cache = { key = nil, index = nil }

function ItemTooltip.index()
  local Core = ns.Core
  if not Core then return nil end
  local list, listKey = Core.zoneHistory()
  local session = ns.session
  local mobs = type(session) == "table" and not session.demo and session.mobs or nil
  local key = tostring(listKey) .. "|" .. tostring(mobs) .. "|" .. tostring(Core.mobsVersion or 0)
  if cache.key ~= key then
    local entries = {}
    for i, e in ipairs(type(list) == "table" and list or {}) do entries[i] = e end
    if type(mobs) == "table" then entries[#entries + 1] = { live = true, mobs = mobs } end
    cache.key, cache.index = key, ns.View.dropIndex(entries)
  end
  return cache.index
end

-- Adds the lines for the item with `link` to `tooltip`. Returns whether it did.
function ItemTooltip.add(tooltip, link)
  if not (ns.db and ns.Options and ns.Options.get(ns.db, "itemTooltipDrops")) then return false end
  if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then return false end
  local id = ns.LootParse.itemID(link)
  if not id then return false end
  local ignored = type(ns.db.ignored) == "table" and ns.db.ignored or {}
  if ignored[id] then return false end
  local lines = ns.View.dropTooltipLines(ItemTooltip.index(), id)
  if not lines then return false end
  local C = ns.Theme.colors
  tooltip:AddLine(" ")
  for _, l in ipairs(lines) do
    if l.heading then
      tooltip:AddLine(l.left, C.tipSection[1], C.tipSection[2], C.tipSection[3])
    elseif l.more then
      tooltip:AddLine(l.left, C.tipNote[1], C.tipNote[2], C.tipNote[3])
    else
      tooltip:AddDoubleLine(l.left, l.right, C.tipLabel[1], C.tipLabel[2], C.tipLabel[3],
        C.tipValue[1], C.tipValue[2], C.tipValue[3])
    end
  end
  if type(tooltip.Show) == "function" then tooltip:Show() end -- resize to the new lines
  return true
end

local function linkOf(tooltip)
  if type(tooltip.GetItem) ~= "function" then return nil end
  local ok, _, link = pcall(tooltip.GetItem, tooltip)
  return ok and link or nil
end

-- Hooks every item tooltip once (login). The retail engine's
-- TooltipDataProcessor covers all tooltips; without it, the OnTooltipSetItem
-- script of the game's item tooltips.
-- UNVERIFIED (check in client): TooltipDataProcessor.AddTooltipPostCall with
-- Enum.TooltipDataType.Item, and tooltip:GetItem() returning the link there.
local hooked = false

function ItemTooltip.init()
  if hooked then return end
  local function onItem(tooltip)
    if type(tooltip) ~= "table" then return end
    ItemTooltip.add(tooltip, linkOf(tooltip))
  end
  local TDP = TooltipDataProcessor
  local types = Enum and Enum.TooltipDataType
  if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" and type(types) == "table" and types.Item then
    TDP.AddTooltipPostCall(types.Item, onItem)
    hooked = true
    return
  end
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if type(tip) == "table" and type(tip.HookScript) == "function" then
      tip:HookScript("OnTooltipSetItem", onItem)
      hooked = true
    end
  end
end
