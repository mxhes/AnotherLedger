local ADDON, ns = ...

-- LootLedger scan: the addon's own auction house prices, for players without
-- TSM or Auctionator. Pure: the client calls of a scan are injected (see
-- Scan.newReader); Core wires the events and Sources/Scan.lua answers the
-- price lookups.
local Scan = {
  MARKET_SHARE = 0.15, -- the market value averages the cheapest 15% of the listed units
}

-- ---------------------------------------------------------------------------
-- Listing math

-- Market value and lowest unit price of one item's listings
-- ({ { unit = copper, qty = n }, ... }, any order). The cheapest share is
-- counted in units (at least one), so one big cheap stack weighs by its size.
-- Nothing for an empty list.
function Scan.listingValues(listings)
  if type(listings) ~= "table" or #listings == 0 then return end
  local sorted, total = {}, 0
  for i, l in ipairs(listings) do
    sorted[i] = l
    total = total + l.qty
  end
  table.sort(sorted, function(a, b) return a.unit < b.unit end)
  local want = math.max(1, math.floor(total * Scan.MARKET_SHARE + 0.5))
  local taken, sum = 0, 0
  for _, l in ipairs(sorted) do
    local n = math.min(l.qty, want - taken)
    sum = sum + l.unit * n
    taken = taken + n
    if taken >= want then break end
  end
  return math.floor(sum / taken), sorted[1].unit
end

ns.Scan = Scan
