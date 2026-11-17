# LootLedger checklist

What still has to be confirmed in the Forever client, and the release steps.
Open: settings profiles, color presets and the review fixes (2026-11-17), below.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

- Rename to LootLedger: the addon shows as LootLedger in the AddOns list and
  options; `/ll` and `/lootledger` work; key bindings are under
  LootLedger. Renaming `SavedVariables/LootPrice.lua` to `LootLedger.lua`
  (account and character) brings History, lists and profiles over
  (`UNVERIFIED` in `Core.lua`, `ADDON_LOADED`).
- Color presets: each of the five looks right in the window, compact window,
  options window and tooltips; Parchment turns the outline on and its light
  text reads on the tan (the dark-text version smeared under the outline).
- Rare and epic items now use the game's exact colors (darker blue and purple
  than before): still readable on the dark presets.
- Options window: all seven tabs (Window, Prices, List, Session, History,
  Look, Profiles) fit, also in German, and the window is wider only when
  needed. Text and number boxes line up with the dropdowns. Dragging it on an
  empty spot moves it; it reopens there, also after a /reload.
- Review fixes (2026-11-17): the Bank tab says "Not scanned yet." before the
  first visit; switching full / compact keeps the corner nearest the screen
  edge in place (try top left and bottom right); History opens newest first
  and its sort no longer changes the Session sort; History and Zones show the
  footer; Bags / Bank / History show their count in the header without
  covering the title; Hover Profile lists the characters (log in on a second
  character first); Session summary in chat prints on Reset.
- Profiles: switch, New, Copy, Rename, Delete (with the popup), and after a
  /reload and a relog the character keeps its profile; a second character
  starts on Default.
- Import box: pasting a long exported line (Ctrl+V) works, the Import button
  asks for a name, overwriting asks first, a wrong line gives a chat message.
- First login after the update: options are back to defaults, History kept,
  Zones: all characters, Minimap button and the minimap button's place stay.
