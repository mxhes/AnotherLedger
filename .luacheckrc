-- luacheck config (https://github.com/lunarmodules/luacheck), run in GitLab CI
-- (job `lint`) and locally with `luacheck AnotherLedger`. It checks the addon
-- code for leaked or misspelled globals, unused variables and overwritten
-- values. A new WoW API the code reads goes in `read_globals`; a global the
-- addon writes goes in `globals`.

std = "lua51"
max_line_length = false
exclude_files = { "AnotherLedger/Libs/" }

ignore = {
  "212",      -- unused argument (handlers keep the full event signature)
  "211/ADDON", -- `local ADDON, ns = ...` at the top of every file
  "421",      -- shadowing a local
  "431",      -- shadowing an upvalue
  "432",      -- shadowing an upvalue argument
}

-- Globals the addon sets: saved variables (and the LootLedger ones it
-- migrates), the slash command and the client's popup / slash tables.
globals = {
  "AnotherLedgerDB", "AnotherLedgerCharDB", "LootPriceDB", "LootPriceCharDB",
  "SLASH_ANOTHERLEDGER1", "SLASH_ANOTHERLEDGER2",
  "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
  "ColorPickerFrame", -- its fallback fields (old color picker)
}

-- WoW API the addon reads.
read_globals = {
  -- Lua extras of the client
  "date", "time",
  -- namespaces
  "C_AuctionHouse", "C_CurrencyInfo", "C_Item", "C_Timer", "Enum", "MenuUtil",
  "MenuResponse", "Settings", "SOUNDKIT", "TooltipDataProcessor",
  -- frames
  "EditModeManagerFrame", "GameTooltip", "ItemRefTooltip",
  "UIParent",
  -- functions
  "CreateColor", "CreateFrame", "GetCursorPosition", "GetInboxHeaderInfo",
  "GetInboxInvoiceInfo", "GetInboxItem", "GetInboxItemLink", "GetInboxNumItems",
  "GetItemInfo", "GetItemInfoInstant", "GetMoney", "GetNumLootItems",
  "GetPlayerTradeMoney", "GetRealmName", "GetTargetTradeMoney", "GetTime",
  "GetTradePlayerItemInfo", "GetTradePlayerItemLink", "GetTradeTargetItemInfo",
  "GetTradeTargetItemLink", "HandleModifiedItemClick", "InterfaceOptions_AddCategory",
  "IsModifiedClick", "IsResting", "IsShiftKeyDown", "MouseIsOver", "PlaySound",
  "StaticPopup_Show", "ToggleDropDownMenu", "UIDropDownMenu_AddButton",
  "UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize", "UnitGUID",
  "UnitIsAFK", "UnitLevel", "UnitName", "UnitOnTaxi", "geterrorhandler",
  "hooksecurefunc", "UnitPosition", "GetUnitSpeed", "IsFalling",
  -- global strings
  "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_SOLD_MAIL_SUBJECT",
  "ERR_AUCTION_SOLD_S", "ERR_TRADE_COMPLETE",
}
