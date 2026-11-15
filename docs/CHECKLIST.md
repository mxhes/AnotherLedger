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

- [ ] Gold from a creature and from a container lands in Raw gold.
- [ ] Group play: a split (`Your share of the loot is ...`) counts once.
  **Open:** shared group gold was reported as not counted; the guild-bank form
  (`... (Y deposited to guild bank)`) is not parsed yet.
- [ ] A quest with a gold reward adds it to Raw gold (`QUEST_TURNED_IN`).
- [ ] Money texts match the client's globals (`/dump YOU_LOOT_MONEY,
  LOOT_MONEY_SPLIT, GOLD_AMOUNT`), also in a client language other than
  English (unit separator ", " is assumed).

## Places and sessions

- [ ] **Session per instance**: entering and leaving a dungeon each save a
  History entry; a loading screen in the open world does not.
- [ ] **Pause when AFK**: `/afk` stops the clock, coming back restarts it
  (`PLAYER_FLAGS_CHANGED`, `UnitIsAFK`).
- [ ] Waypoint on a map that allows no pin (a cave sub-map) without TomTom:
  none is set and chat says `No waypoint could be set.`
- [ ] `/lp export` and **Export History**: the copy box
  (`UIPanelScrollFrameTemplate`) shows the CSV selected, Ctrl+C copies it, Esc
  closes it.

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
  tooltips, footer, `Entzaubern` / `Auktion` tags).
