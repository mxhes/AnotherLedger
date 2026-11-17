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
    -- Minimap button shown (account-wide, like historyLimit and accountZones:
    -- options with `account = true` are stored in LootPriceDB.account; their
    -- defaults stay here).
    minimapButton = true,
    lockWindow = false,
    snapToGrid = true,
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
    -- A new session per zone, after this many minutes in the new zone.
    zoneSession = false,
    zoneSessionMinutes = 2,
    -- Session goals: gold (best value + raw gold) and minutes; 0 = off.
    goalGold = 0,
    goalMinutes = 0,
    -- List rows show the value of one item instead of the stack.
    unitPrice = false,
    -- History Zones and the Daily farm use the History of every character.
    accountZones = true,
    -- Font size in px of the list text, the totals and the section titles (applied live).
    -- Typeface: "default" (the WoW font) or a font file path.
    fontFace = "default",
    -- Outline ("none" / "OUTLINE" / "THICKOUTLINE") and shadow of all text.
    fontOutline = "none",
    fontShadow = true,
    fontSizeRows = 12,
    fontSizeTotals = 12,
    fontSizeTitles = 16,
    -- Colors ("rrggbb", Options COLOR_OPTIONS): text, titles / totals, hints,
    -- the Vendor / Auction / Destroy sources, tooltip labels, window background
    -- and border, button fill. They match Theme.colors.
    colorPreset = "lootprice",
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
  -- Account-wide options (Options.define `account = true`): { [key] = value }.
  account = {},
  -- Place of the own minimap button on the rim in degrees (0 = right,
  -- counter-clockwise; the default is bottom left).
  minimapAngle = 225,
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
  -- The ignore list: { [itemID] = item name } (Core.ignoredItems).
  ignored = {},
  -- The keep list: { [itemID] = item name } (Core.keptItems): Bags and Bank
  -- split their total into kept and sellable.
  kept = {},
  -- Every character's History: { ["Name-Realm"] = list } (Core.linkHistory).
  histories = {},
}

-- Per-character defaults (LootPriceCharDB): the last bank scan for the Bank tab.
-- `history` (finished sessions, newest first, see History.lua) is this
-- character's list in LootPriceDB.histories while logged in; it is only
-- written here by versions before the account-wide History.
DB.charDefaults = {
  bank = { scannedAt = 0, items = {} },
  history = {},
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
-- Once: the account-wide options and the minimap angle move out of the old
-- settings table (which profiles replace) to LootPriceDB.account and
-- LootPriceDB.minimapAngle, keeping the player's values.
local ACCOUNT_KEYS = { "historyLimit", "accountZones", "minimapButton" }
function DB.migrateAccount(db)
  if type(db) ~= "table" or db.accountMigrated == true then return end
  if type(db.account) ~= "table" then db.account = {} end
  local old = type(db.settings) == "table" and db.settings or {}
  for _, key in ipairs(ACCOUNT_KEYS) do
    if old[key] ~= nil and db.account[key] == nil then db.account[key] = old[key] end
  end
  if type(old.minimapAngle) == "number" then db.minimapAngle = old.minimapAngle end
  db.accountMigrated = true
end

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
