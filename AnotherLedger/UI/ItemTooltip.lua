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

local L = ns.L
local L_TREND = L["AnotherLedger price trend"]
local L_TREND_TSM = L["%s vs 60 days"]
local L_TREND_SCAN = L["%s vs earlier days"]

-- A change of this fraction or more is colored (up green, down red).
ItemTooltip.TREND_COLOR_FROM = 0.05

-- Pure. The trend line for `change` (a fraction, +0.12 = 12% up) from
-- `source` ("tsm" or "scan"): left text, right text, Theme.colors key.
function ItemTooltip.trendLine(change, source)
  local pct = math.floor(math.abs(change) * 100 + 0.5)
  local sign = pct == 0 and "" or (change > 0 and "+" or "-")
  local text = string.format(source == "tsm" and L_TREND_TSM or L_TREND_SCAN, sign .. pct .. "%")
  local color = "tipValue"
  if change >= ItemTooltip.TREND_COLOR_FROM then
    color = "marketGood"
  elseif change <= -ItemTooltip.TREND_COLOR_FROM then
    color = "marketBad"
  end
  return L_TREND, text, color
end

local L_SALE = L["TSM sale info"]

-- Pure. The sale info text of a price lookup `info` (saleRate, soldPerDay)
-- with the level cutoffs `cutoffs` (UI.Ledger.marketCutoffs), e.g. "Sells
-- okay, Low volume" in the level colors; nil without cutoffs or TSM data.
function ItemTooltip.marketText(info, cutoffs, colors)
  if type(info) ~= "table" or type(cutoffs) ~= "table" then return nil end
  local rate, volume = ns.View.marketLevels(info.saleRate, info.soldPerDay, cutoffs)
  if not (rate or volume) then return nil end
  return ns.UI.Rows.marketText({ rateLevel = rate, volumeLevel = volume }, colors)
end

local function saleText(id, link)
  local UI, Core = ns.UI, ns.Core
  if not (UI.Ledger and UI.Ledger.marketCutoffs and UI.Rows and Core and Core.lookupPrice) then return nil end
  local cutoffs = UI.Ledger.marketCutoffs(ns.db)
  if not cutoffs then return nil end
  return ItemTooltip.marketText(Core.lookupPrice(id, link), cutoffs, ns.Theme.colors)
end

local function option(key)
  return ns.db and ns.Options and ns.Options.get(ns.db, key) and true or false
end

-- Adds the lines for the item with `link` to `tooltip`: the TSM sale info
-- (option "showMarket"), the price trend (option "itemTooltipTrend") and the
-- drop chances (option "itemTooltipDrops"). Returns whether it added any.
function ItemTooltip.add(tooltip, link)
  if not (ns.db and ns.Options) then return false end
  if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then return false end
  local id = ns.LootParse.itemID(link)
  if not id then return false end
  local ignored = type(ns.db.ignored) == "table" and ns.db.ignored or {}
  if ignored[id] then return false end
  local change, source
  if option("itemTooltipTrend") and ns.Core and ns.Core.priceTrend then
    change, source = ns.Core.priceTrend(_G, ns.db, id, link, time())
  end
  local lines = option("itemTooltipDrops") and ns.View.dropTooltipLines(ItemTooltip.index(), id) or nil
  local sale = saleText(id, link)
  if not (change or lines or sale) then return false end
  local C = ns.Theme.colors
  tooltip:AddLine(" ")
  if sale then
    tooltip:AddDoubleLine(L_SALE, sale, C.tipLabel[1], C.tipLabel[2], C.tipLabel[3],
      C.tipValue[1], C.tipValue[2], C.tipValue[3])
  end
  if change then
    local left, right, color = ItemTooltip.trendLine(change, source)
    local c = C[color] or C.tipValue
    tooltip:AddDoubleLine(left, right, C.tipLabel[1], C.tipLabel[2], C.tipLabel[3], c[1], c[2], c[3])
  end
  for _, l in ipairs(lines or {}) do
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
-- Client API: TooltipDataProcessor.AddTooltipPostCall with
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
