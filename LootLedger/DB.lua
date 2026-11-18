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
    -- options with `account = true` are stored in LootLedgerDB.account; their
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
    -- Raw gold (Util.rawGold): "row" (in Total and its own row), "total" (in
    -- Total only), "apart" (its own row, not in Total) or "off".
    rawGold = "row",
    refreshSeconds = 30,
    staleHours = 12,
    -- Value rules (Prices.best / Prices lookup rules): AH values after the
    -- 5% fee, the percent an AH value must beat vendor by (0 = any), and when
    -- destroy values count: always / any (a character of mine can) / self / never.
    ahCut = true,
    ahMinGain = 0,
    destroyMode = "always",
    alertGold = 0,
    alertSound = false,
    -- Crafted items and items received at a merchant / mailbox / trade / AH
    -- count as loot only with this on.
    countCrafted = false,
    showCurrencies = true,
    -- Daily farm strip and the minimum recorded time of a place it may pick.
    dailyFarm = true,
    dailyFarmMinutes = 20,
    -- The Daily farm only picks places whose map fits your level.
    dailyFarmLevel = false,
    -- Top finds block under the footer table.
    showTopFinds = true,
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
    -- The window shows itself on a session's first loot / in instances and
    -- hides while resting in a city.
    showOnLoot = false,
    showInInstance = false,
    hideInCities = false,
    -- Stop the clock (not the loot) while resting in a city or inn.
    cityPause = true,
    -- A chat line with the length, place and worth of each saved session.
    sessionChat = false,
    instanceSession = false,
    -- A new session per zone, after this many minutes in the new zone.
    zoneSession = false,
    zoneSessionMinutes = 2,
    -- A session shorter than this (minutes) continues instead of going to
    -- History on a zone / instance split or a login; 0 = off.
    minSessionMinutes = 2,
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
    colorPreset = "lootledger",
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
  sort = "ah", -- sort of the item lists (Session, Bags, Bank)
  -- Views with their own sort (History Sessions / Zones): { ["history/zones"] = "perHour" }.
  sorts = {},
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
  -- Destroy professions per character: { ["Name-Realm"] = { enchanting = true, ... } }
  -- (Core.noteProfessions; option Destroy values).
  professions = {},
}

-- Per-character defaults (LootLedgerCharDB): the last bank scan for the Bank tab.
-- `history` (finished sessions, newest first, see History.lua) is this
-- character's list in LootLedgerDB.histories while logged in; it is only
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

-- Once: the account-wide options and the minimap angle move out of the old
-- settings table (which profiles replace) to LootLedgerDB.account and
-- LootLedgerDB.minimapAngle, keeping the player's values.
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

-- The old checkboxes "Count raw gold" (includeGold) and "Show raw gold row"
-- (showFooterGold) of a profile's settings become the dropdown rawGold, with
-- the same footer; the old keys are dropped.
function DB.migrateSettings(settings)
  if type(settings) ~= "table" then return settings end
  local oldCounted, oldRow = settings.includeGold, settings.showFooterGold
  if settings.rawGold == nil and (type(oldCounted) == "boolean" or type(oldRow) == "boolean") then
    -- A missing checkbox was on (both defaulted to true).
    local counted, row = oldCounted ~= false, oldRow ~= false
    if counted then
      settings.rawGold = row and "row" or "total"
    else
      settings.rawGold = row and "apart" or "off"
    end
  end
  settings.includeGold, settings.showFooterGold = nil, nil
  return settings
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
