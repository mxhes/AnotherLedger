# LootPrice checklist

What still has to be confirmed in the Forever client, and the release steps.
Already seen working in the game (2026-11-15): the window, tabs and rows; the
compact layout and header; Daily farm, History and Zones with their tooltips;
the options panel, font list, size dropdowns and coin icons.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Before release

- [x] `## Interface:` in `LootPrice/LootPrice.toc` is 16001
  (`/dump select(4, GetBuildInfo())`).
- [ ] CI: `test` passes under Lua 5.1 and 5.4; the manual `package-dry-run`
  zip holds one `LootPrice/` folder with the `.toc` and `Libs/` (LibStub,
  CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0); the external URLs in
  `LootPrice/.pkgmeta` are unverified.
- [ ] CurseForge: create the project, add `## X-Curse-Project-ID` to the `.toc`
  and the `CF_API_KEY` CI variable.
- [ ] Price APIs: `TSM_API.GetCustomPriceValue("DBMarket", "i:<itemID>")`,
  `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)`, and the
  disenchant value `TSM_API.GetCustomPriceValue("Destroy", "i:<itemID>")`.
- [ ] Run the checks below once on fresh saved variables (delete
  `LootPriceDB` / `LootPriceCharDB` for one launch).

## Session and loot

- [ ] Keep session on: logout / login keeps the session; off: a real relog
  starts fresh (and saves the old one to History), `/reload` keeps it.
- [ ] Price cache key: `GetCurrentRegionName()` and
  `C_GameRules.GetCurrentGameModeRecordID()` return values.
- [ ] Two drops of one gear item with different item levels are two rows, each
  priced as its variant (`TSM_API.ToItemString(link)`,
  `Auctionator.API.v1.GetAuctionPriceByItemLink`; the bonus ID count is the
  13th field of an item link, `/dump` one to check).
- [ ] A quest item lands in the **Quest items** group of History > Zones
  (`C_Item.GetItemInfoInstant` gives class ID 12 as its 6th value).
- [ ] A soulbound or quest item shows its vendor value (or `bound`) and is not
  counted as unpriced (`GetItemInfo` bind type 1 / 4 / 7 / 8 / 9).
- [ ] A currency gain adds a currency row with icon and tooltip
  (`CHAT_MSG_CURRENCY`, `C_CurrencyInfo.GetCurrencyInfo`).
- [ ] Crafting and buying add nothing with **Crafted and bought** off and count
  with it on; quest reward items always count (`MERCHANT_*`, `MAIL_*`,
  `TRADE_*`, `AUCTION_HOUSE_*` events exist).
- [ ] `/lp demo`: sample rows, 12s 40c of raw gold, an old-price tag; reset
  removes the sample prices.

## Raw gold

- [ ] Gold from a creature and from a container lands in Raw gold, once.
- [ ] Backstop: with the money message unparsed (e.g. another client
  language), looted gold still counts once (`LOOT_OPENED`, `LOOT_CLOSED`,
  `GetMoney`; the money arrives before `LOOT_CLOSED` + 1 s).
- [ ] Group play: a split (`Your share of the loot is ...`) counts once.
  **Open:** shared group gold was reported as not counted. A likely cause was
  the split with a guild share (`LOOT_MONEY_SPLIT_GUILD`, `Your share of the
  loot is X. (Y deposited to guild bank)`), which is parsed now; check that it
  exists (`/dump LOOT_MONEY_SPLIT_GUILD`) and counts X.
- [ ] A quest with a gold reward adds it to Raw gold (`QUEST_TURNED_IN`).
- [ ] Money texts match the client's globals (`/dump YOU_LOOT_MONEY,
  LOOT_MONEY_SPLIT, GOLD_AMOUNT`), also in a client language other than
  English (unit separator ", " is assumed).

## Places and sessions

- [ ] **Session per instance**: entering and leaving a dungeon each save a
  History entry; a loading screen in the open world does not.
- [ ] A dungeon shows as one place in Zones, `Name (Difficulty)`, also when
  the loot of the first pull comes right after the loading screen
  (`GetDifficultyInfo(difficultyID)` gives the name first; UNVERIFIED in
  `Core.lua`).
- [ ] With the clock stopped, loot and gold are not counted and the chat says
  so once; Start counts again.
- [ ] History rows show `Today 20:21`, `Yesterday`, a weekday, then the date
  (German: `15.11.2026`); length, place and item count on line 2 fit in a
  narrow window. Zones rows show time, gold per hour and item count on line 2.
- [ ] Empty lists show their text centered (a fresh session, a stopped clock,
  a search that matches nothing, Bank before the first visit).
- [ ] **Pause when AFK**: `/afk` stops the clock, coming back restarts it
  (`PLAYER_FLAGS_CHANGED`, `UnitIsAFK`).
- [ ] Waypoint on a map that allows no pin (a cave sub-map) without TomTom:
  none is set and chat says `No waypoint could be set.`
- [ ] Shift-click on a row or a Top find links the item in chat, Ctrl-click
  tries it on (`IsModifiedClick`, `HandleModifiedItemClick`).
- [ ] Right-click on a History session opens a menu with its date as title,
  **Add note**, **Merge with the older session** (not on the oldest) and
  **Delete** (`MenuUtil` `CreateTitle` / `CreateButton`); Merge joins the two
  rows into one (items, gold, time, places and Zones added up, the opened
  session stays open) and `/lp undo` splits them again; Delete removes it at
  once and `/lp undo` brings it back; **Clear History**
  and lowering **History kept** ask first (`StaticPopup_Show`).
- [ ] **Add note**: the popup has a text box (`hasEditBox`, the box found via
  `GetEditBox()` or `editBox`), Enter saves, Esc closes; the note shows after
  the date, in the tooltip and is found by the search; German umlauts are
  kept.
- [ ] Right-click an item row: **Ignore this item** hides it from every tab,
  total and the compact window; **Ignored items** in the options lists it and
  a click counts it again.
- [ ] Quality menu: the presets (e.g. `Uncommon and better`) set the boxes
  below them and close the menu.
- [ ] `/lp export`, `/lp export session`, `/lp export zones` and **Export
  History**: the copy box (`UIPanelScrollFrameTemplate`) shows the CSV
  selected, Ctrl+C copies it, Esc closes it.
- [ ] Key bindings: Esc > Options > Key Bindings lists LootPrice under AddOns
  (`Bindings.xml`, `category="ADDONS"`) with three keys; each works, also in
  combat.
- [ ] **Session goal (gold)**: compact shows `Session 312g / 500g`, the Session
  footer `Goal 62%`; reaching it prints one chat line (and the sound with
  **Alert sound**). **Session goal (minutes)** prints when the clock gets
  there, with the window closed too (`C_Timer.NewTicker`).
- [ ] Compact: hovering the gold per hour shows the breakdown, and the window
  can still be dragged from there.
- [ ] Account-wide History: after logging in on two characters, History >
  Zones and the Daily strip show both characters' places (off with **Zones:
  all characters**); each character's Sessions list stays its own; an old
  per-character History shows up after the first login with this version
  (`UnitName`, `GetRealmName`).
- [ ] Switching tabs and back keeps each list's scroll position.

## Bank

- [ ] Forever has character bank tabs (`Enum.BagIndex.CharacterBankTab_1`) or
  the old bank; the right one is scanned, the reagent bank where it exists;
  moving items in the bank updates the scan (`PLAYERBANKSLOTS_CHANGED`).
- [ ] Container constants match (`/dump BANK_CONTAINER, NUM_BAG_SLOTS,
  NUM_REAGENTBAG_SLOTS, NUM_BANKBAGSLOTS`), and
  `C_Container.GetContainerItemInfo` returns `{ itemID, stackCount, hyperlink }`.

## Option behavior

- [ ] **Hide in combat**: the window hides in combat and returns after; one
  closed by hand stays closed; turning the option off mid-combat brings it back.
- [ ] **Drop alert** prints a chat line, **Alert sound** plays
  `SOUNDKIT.UI_EPICLOOT_TOAST`.
- [ ] **AH price source** switches the prices live and survives `/reload`.
- [ ] **Start hidden**, **Lock window** and **Scale** work after `/reload`.
- [ ] **Snap to grid**: dropping the window near an Edit Mode grid line snaps
  its edge or center onto it, also at another Scale and after changing the grid
  spacing in Edit Mode (`EditModeManagerFrame.Grid.gridSpacing` /
  `GetAccountSettingValue(Enum.EditModeAccountSetting.GridSpacing)`; UNVERIFIED
  in `UI/Window.lua`).
- [ ] **Source tags** (Vendor / Auction / Destroy) in the list all have the
  same box width with the text centered in it.
- [ ] **Button background** set to a light color (yellow): button labels and
  the layout arrow turn dark and stay readable.
- [ ] Options panel: the number and text boxes have the window's input look
  (no game input frame); **Opacity** and **Brightness** change the options
  window as well (re-check on the current build).
- [ ] **Colors**: clicking a swatch opens the game's color picker
  (`ColorPickerFrame:SetupColorPickerAndShow`, `GetColorRGB`; UNVERIFIED in
  `Widgets.pickColor`) above the options panel; dragging recolors the window,
  tooltips and options live, Cancel restores the old color, right-click sets
  the default, **Reset colors** resets all; the colors survive `/reload`.
- [ ] The **LootPrice** page under Esc > Options > AddOns
  (`Settings.RegisterCanvasLayoutCategory`) shows the same tabs and values as
  the panel.

## Minimap, broker, libraries

- [ ] Minimap button: left click toggles, right click opens the options,
  dragging moves it and the place survives `/reload`; **Reset minimap button**
  brings it back.
- [ ] Packaged build: the button is LibDBIcon's and the broker shows in Titan
  Panel / ElvUI; a copy without `Libs/` loads without Lua errors and shows the
  own button.

## Language

- [ ] German client: texts are German and nothing clips (options labels,
  tooltips, footer, `Zerstören` / `Auktion` tags).
