# LootLedger checklist

What still has to be confirmed in the Forever client, and the release steps.
Open: settings profiles and color presets (2026-11-17), below.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

- Rename to LootLedger: the addon shows as LootLedger in the AddOns list and
  options; `/lp`, `/ll` and `/lootledger` work; key bindings are under
  LootLedger. Renaming `SavedVariables/LootPrice.lua` to `LootLedger.lua`
  (account and character) brings History, lists and profiles over
  (`UNVERIFIED` in `Core.lua`, `ADDON_LOADED`).
- Color presets: each of the five looks right in the window, compact window,
  options window and tooltips; Parchment turns the outline on and its light
  text reads on the tan (the dark-text version smeared under the outline).
- Rare and epic items now use the game's exact colors (darker blue and purple
  than before): still readable on the dark presets.
- Options window: all six tabs fit (also in German) and the window is wider
  only when needed.
- Profiles: switch, New, Copy, Rename, Delete (with the popup), and after a
  /reload and a relog the character keeps its profile; a second character
  starts on Default.
- Import box: pasting a long exported line (Ctrl+V) works, the Import button
  asks for a name, overwriting asks first, a wrong line gives a chat message.
- First login after the update: options are back to defaults, History kept,
  Zones: all characters, Minimap button and the minimap button's place stay.
