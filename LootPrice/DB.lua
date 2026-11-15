local ADDON, ns = ...

local DB = {}

DB.defaults = {
  version = 1,
  cache = {},
  settings = {
    keepSession = false,
    tsmSource = "DBMarket",
    -- Options panel (see Options.lua): opacity 0..1 and brightness (1 = the
    -- theme color) of the window background / border, price source
    -- auto / tsm / auctionator, hide the window in combat.
    alpha = 1,
    brightness = 1,
    priceSource = "auto",
    combatHide = false,
    -- Past sessions kept in History: 0 = none, -1 = unlimited.
    historyLimit = 50,
    -- Minimap button: shown, and its place on the minimap rim in degrees
    -- (0 = right, counter-clockwise; the default is bottom left).
    minimapButton = true,
    minimapAngle = 225,
    lockWindow = false,
    windowScale = 1,
    startHidden = false,
    defaultSort = "ah",
    goldDisplay = "full",
    -- The game's coin icons in place of the g / s / c letters.
    coinIcons = true,
    includeGold = true,
    refreshSeconds = 30,
    staleHours = 12,
    alertGold = 0,
    alertSound = false,
    -- Crafted items and items received at a merchant / mailbox / trade / AH
    -- count as loot only with this on.
    countCrafted = false,
    showCurrencies = true,
    -- Daily farm strip and the minimum recorded time of a place it may pick.
    dailyFarm = true,
    dailyFarmMinutes = 20,
    -- Top finds block and the Raw gold row of the footer table.
    showTopFinds = true,
    showFooterGold = true,
    -- Compact mode: how many last drops it lists (0..4).
    compactDrops = 4,
    -- Item icon at the left of each list row.
    showIcons = true,
    -- New loot scrolls the Session list to its row.
    followLoot = true,
    -- TSM region sale info under the item name and its level cutoffs: sale
    -- rate (0..1) for good / ok, average sold per day for high / medium.
    showMarket = true,
    saleRateGood = 0.5,
    saleRateOk = 0.1,
    soldHigh = 100,
    soldMedium = 10,
    -- Pause the clock while AFK; a new session per dungeon / raid visit.
    afkPause = false,
    instanceSession = false,
    -- Font size in px of the list text, the totals and the section titles (applied live).
    -- Typeface: "default" (the WoW font) or a font file path.
    fontFace = "default",
    fontSizeRows = 12,
    fontSizeTotals = 12,
    fontSizeTitles = 16,
    -- Colors ("rrggbb", Options COLOR_OPTIONS): text, titles / totals, hints,
    -- the Vendor / Auction / Destroy sources, tooltip labels, window background
    -- and border, button fill. They match Theme.colors.
    colorText = "ffffff",
    colorTitles = "ffd100",
    colorHints = "ada18c",
    colorVendor = "eddeb8",
    colorAuction = "80d1ff",
    colorDestroy = "b3b3b3",
    colorTipLabels = "ccbd9e",
    colorBackground = "261a0f",
    colorBorder = "8c6b3d",
    colorButtons = "1a120a",
  },
  window = { point = "CENTER", x = 0, y = 0, width = 420, height = 440, hidden = false,
    compact = { width = 260, height = 210 } },
  mode = "full", -- layout: "full" (the ledger) or "compact" (the glance)
  filter = {
    qualities = { [0] = true, true, true, true, true, true, true, true },
    minValue = 0,
    search = "",
  },
  sort = "ah",
  tab = "session", -- last shown tab: session / bags / bank / history
  subtab = {}, -- last shown sub-tab per tab: { history = "sessions" / "zones" }
  -- LibDBIcon's saved state (hide, minimapPos) when that library draws the
  -- minimap button (UI/Broker.lua).
  minimapIcon = {},
}

-- Per-character defaults (LootPriceCharDB): the last bank scan for the Bank tab.
DB.charDefaults = {
  bank = { scannedAt = 0, items = {} },
  history = {}, -- finished sessions, newest first (see History.lua)
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- Fills missing keys of `saved` from `defaults` (recursively), replaces values
-- whose type differs from the default's, keeps unknown keys. Returns the table
-- to use; never mutates `defaults` and shares no tables with it.
function DB.applyDefaults(saved, defaults)
  if type(saved) ~= "table" then return copy(defaults) end
  for k, d in pairs(defaults) do
    local v = saved[k]
    if type(d) == "table" then
      if type(v) ~= "table" then
        saved[k] = copy(d)
      else
        DB.applyDefaults(v, d)
      end
    elseif type(v) ~= type(d) then
      saved[k] = d
    end
  end
  return saved
end

ns.DB = DB
