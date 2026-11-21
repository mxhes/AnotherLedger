local ADDON, ns = ...

-- The Trade tab's views (pure, like View.lua; loads after it).

local L = ns.L
local View = ns.View
local I = View.internal
local num = ns.Util.isNumber
local lower = string.lower
local addGold = I.addGold
local byName = I.byName
local descending = I.descending
local descendingKnown = I.descendingKnown
local detailText = I.detailText
local searchNeedle = I.searchNeedle
local visible = I.visible

-- ---------------------------------------------------------------------------
-- Trade tab: Items (what sold, how well) and Log (every entry). Built from
-- Trade.itemStats and the Trade log; the rows reuse the History row look:
-- a second line and the gold in the coin column.

local L_SOLD_PCT = L["%d%% sold"]
local L_VS_MARKET = L["%s%d%% vs market"]
local L_TRADE_HEADER = L["%d sold, %d expired, %d cancelled"]
local L_NO_SALES = L["No sales yet. Sales show after you open your mailbox."]
local L_NO_TRADES = L["Nothing traded yet."]
local L_TRADE_SALES = L["Sales"]
local L_TRADE_PURCHASES = L["Purchases"]
local L_BOUGHT_N = L["%d bought"]
local L_MARKET_THEN = L["market %s"]
local L_NOT_COMPARED = L["market -"]
local TRADE_TIP_LINES = 10
local TRADE_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local TRADE_KINDS = {
  post = L["Posted"], cancel = L["Cancelled"], expire = L["Expired"], sale = L["Sold"], buy = L["Bought"],
  tsale = L["Trade sale"], tbuy = L["Trade purchase"], trade = L["Trade"],
}


local function percent(fraction)
  local p = math.floor(math.abs(fraction) * 100 + 0.5)
  return fraction < 0 and -p or p
end

local TRADE_SORTS = {
  gold = descending("value"),
  sold = descending("quantity"),
  rate = descendingKnown("rate"),
  vsMarket = descendingKnown("vsMarket"),
  name = byName,
}

-- Trade > Log: newest first (the log's own order on the same second).
local function newestEntry(a, b)
  local ta, tb = a.lastSeen or 0, b.lastSeen or 0
  if ta ~= tb then return ta > tb end
  return a.id < b.id
end
local TRADE_LOG_SORTS = { recent = newestEntry, gold = descending("value"), name = byName }

-- The filter bar on Trade rows: search and minimum value always, quality only
-- on rows of one item (a trade with a player has no quality).
local tradeFilter = {}
local function tradeVisible(row, filter, needle, oneItem)
  if not oneItem and type(filter) == "table" then
    tradeFilter.minValue = filter.minValue
    filter = tradeFilter
  end
  return visible(row, filter, needle)
end

local function dateOf(opts, t)
  local fn = opts.shortDate or opts.formatDate
  return fn and fn(t) or tostring(t)
end

local function perUnit(e) return math.floor((e.gold or 0) / math.max(1, e.n or 1) + 0.5) end
local function entryLabel(opts, e) return dateOf(opts, e.t) .. "  x" .. (e.n or 1) .. (e.who and ("  " .. e.who) or "") end

local function tradeHint(s, opts)
  local Tip = ns.Tooltip
  local tip = Tip.new(s.name or "?")
  if #s.sales > 0 then Tip.section(tip, L_TRADE_SALES) end
  for i = 1, math.min(#s.sales, TRADE_TIP_LINES) do
    local e = s.sales[i]
    local market = e.market and string.format(L_MARKET_THEN, ns.Money.format(e.market)) or L_NOT_COMPARED
    Tip.pair(tip, entryLabel(opts, e), ns.Money.format(perUnit(e)) .. "  " .. market)
  end
  local buys = s.buys or {}
  if #buys > 0 then Tip.section(tip, L_TRADE_PURCHASES) end
  for i = 1, math.min(#buys, TRADE_TIP_LINES) do
    Tip.pair(tip, entryLabel(opts, buys[i]), ns.Money.format(perUnit(buys[i])))
  end
  return tip
end

-- stats: Trade.itemStats. One row per item: sold in the quantity, the gold
-- earned less what auction purchases cost as its value, "75% sold", "+10% vs
-- market" and "4 bought" in the second line.
function View.buildTradeItems(stats, opts)
  opts = opts or {}
  local filter = opts.filter
  local needle = searchNeedle(filter)
  local rows, sold, expired, cancelled, bought, gold = {}, 0, 0, 0, 0, 0
  local earned, spent = 0, 0
  for _, s in ipairs(stats or {}) do
    local info = opts.itemInfo and s.id and opts.itemInfo(s.id) or nil
    if type(info) ~= "table" then info = nil end
    local name = (info and type(info.name) == "string" and info.name) or s.name or "?"
    local parts = {}
    if s.rate then parts[#parts + 1] = string.format(L_SOLD_PCT, percent(s.rate)) end
    if s.vsMarket then
      local p = percent(s.vsMarket)
      parts[#parts + 1] = string.format(L_VS_MARKET, p > 0 and "+" or "", p)
    end
    local nBought = s.bought or 0
    if nBought > 0 then parts[#parts + 1] = string.format(L_BOUGHT_N, nBought) end
    local net = (s.gold or 0) - (s.spent or 0)
    local row = {
      id = s.id, key = s.key or name, name = name, sortName = lower(name),
      quality = info and num(info.quality) and info.quality or 1, quantity = s.sold or 0,
      detail = detailText(parts), rate = s.rate, vsMarket = s.vsMarket,
      vendorTotal = 0, ahTotal = net, bestLineTotal = net, value = net,
      icon = info and info.icon or nil,
      hint = function() return tradeHint(s, opts) end,
    }
    -- The minimum value picks by amount, earned or spent (like the Log).
    row.value = math.abs(net)
    local shown = tradeVisible(row, filter, needle, true)
    row.value = net
    if shown then
      rows[#rows + 1] = row
      sold, expired, cancelled = sold + (s.sold or 0), expired + (s.expired or 0), cancelled + (s.cancelled or 0)
      bought, gold = bought + nBought, gold + net
      earned, spent = earned + (s.gold or 0), spent + (s.spent or 0)
    end
  end
  table.sort(rows, TRADE_SORTS[opts.sort] or TRADE_SORTS.gold)
  local view = { rows = rows, top = {}, kind = "tradeItems", history = true,
    totals = { vendor = 0, ah = gold, best = gold, earned = earned, spent = spent, unpriced = 0,
      filtered = View.isFiltered(filter) },
    empty = View.emptyText(rows, filter, L_NO_SALES),
    headerInfo = #rows > 0 and (string.format(L_TRADE_HEADER, sold, expired, cancelled)
      .. (bought > 0 and (", " .. string.format(L_BOUGHT_N, bought)) or "")) or nil }
  addGold(view, 0, false)
  return View.applyRates(view, 0)
end

-- The gold a log entry shows: earned for sales, paid out for purchases
-- (negative), what came in for other trades; nothing for posts and returns.
local function entryGold(e)
  if e.kind == "sale" or e.kind == "tsale" then return (e.gold or 0) - (e.cut or 0) end
  if e.kind == "buy" then return -(e.gold or 0) end
  if e.kind == "tbuy" then return -(e.goldOut or e.gold or 0) end
  if e.kind == "trade" then return e.goldIn or 0 end
  return 0
end

-- log: the Trade log (oldest first). One row per entry, newest first (or by
-- opts.sort: "gold", "name").
function View.buildTradeLog(log, opts)
  opts = opts or {}
  local filter = opts.filter
  local needle = searchNeedle(filter)
  local rows, earned, spent = {}, 0, 0
  for i = #(log or {}), 1, -1 do
    local e = log[i]
    local isTrade = e.kind == "tbuy" or e.kind == "trade"
    local name = isTrade and (e.who or "?") or (e.name or "?")
    local parts = { TRADE_KINDS[e.kind] or e.kind, dateOf(opts, e.t) }
    if not isTrade and e.who then parts[#parts + 1] = e.who end
    if e.char then parts[#parts + 1] = e.char end
    local gold = entryGold(e)
    local info = not isTrade and num(e.id) and opts.itemInfo and opts.itemInfo(e.id) or nil
    if type(info) ~= "table" then info = nil end
    local row = {
      id = -i, key = -i, name = name, sortName = lower(name),
      quality = info and num(info.quality) and info.quality or 1,
      quantity = (not isTrade) and e.n or nil, detail = detailText(parts),
      vendorTotal = 0, ahTotal = gold, bestLineTotal = gold, value = gold,
      icon = TRADE_ICON, lastSeen = e.t,
    }
    -- The minimum value picks by amount, paid out or earned.
    row.value = math.abs(gold)
    local shown = tradeVisible(row, filter, needle, not isTrade)
    row.value = gold
    if shown then
      rows[#rows + 1] = row
      if gold > 0 then earned = earned + gold else spent = spent - gold end
    end
  end
  table.sort(rows, TRADE_LOG_SORTS[opts.sort] or TRADE_LOG_SORTS.recent)
  -- Footer: what the listed entries brought in and paid out.
  local view = { rows = rows, top = {}, kind = "tradeLog", history = true,
    totals = { vendor = 0, ah = earned - spent, best = earned - spent, earned = earned, spent = spent, unpriced = 0,
      filtered = View.isFiltered(filter) },
    empty = View.emptyText(rows, filter, L_NO_TRADES) }
  addGold(view, 0, false)
  return View.applyRates(view, 0)
end

