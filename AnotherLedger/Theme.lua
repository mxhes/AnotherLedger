local ADDON, ns = ...

-- All look-and-feel values live here so the art can be swapped in one place.
local Theme = {}

Theme.textures = {
  -- The addon's logo (ledger book with the AL coin): minimap and broker icon.
  -- Drawn by tools/render_logo.py; no extension, the client finds the .tga.
  logo = "Interface\\AddOns\\AnotherLedger\\Media\\Logo",
  -- No certain retail leather path; a flat tile tinted with colors.panelTint.
  parchment = "Interface\\Buttons\\WHITE8X8",
  -- Rounded window edge (tinted with colors.panelBorder); the fill sits inside
  -- its curve (sizes.backdropInset), so the corners read round.
  frameBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  rowHighlight = "Interface\\Buttons\\WHITE8X8",
  -- Gold per hour graph in tooltips: one flat bar per stretch (Tooltip.barsText).
  graphBar = "Interface\\Buttons\\WHITE8X8",
  -- Daily farm strip: a star, tinted with colors.dailyFarm.
  dailyFarm = "Interface\\Common\\FavoritesIcon",
  -- History Mobs rows: a mob or a gathering node.
  mob = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  node = "Interface\\Icons\\Trade_Mining",
  resizeGrip = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
  -- Options button: a gear-like trade icon, present in every client.
  optionsIcon = "Interface\\Icons\\Trade_Engineering",
  -- Bronze buttons: a thin 1 px edge (tinted per state) and the icon glyphs.
  buttonEdge = "Interface\\Buttons\\WHITE8X8",
  iconGear = "Interface\\Icons\\Trade_Engineering",
  iconClose = "Interface\\Buttons\\UI-StopButton",
  buttonHighlight = "Interface\\Buttons\\ButtonHilight-Square",
  -- Mode button arrow: a plain white triangle pointing right (turned up / down
  -- by Widgets.arrowCoords, tinted with the button text color).
  arrow = "Interface\\ChatFrame\\ChatFrameExpandArrow",
  -- Thin rounded edge of the tab buttons (tinted with colors.tabBorder*).
  tabBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  -- Skins (Theme.skins): the addon's own textures, drawn by
  -- tools/render_skins.py; grey-scale, tinted with the theme colors.
  skinStud = "Interface\\AddOns\\AnotherLedger\\Media\\Skins\\Stud",
  skinDotted = "Interface\\AddOns\\AnotherLedger\\Media\\Skins\\Dotted",
  -- Backdrop edge strip of the Rounded border (1 unit line, rounded corners).
  skinRounded = "Interface\\AddOns\\AnotherLedger\\Media\\Skins\\Rounded",
}

Theme.fonts = {
  title = "GameFontNormal",
  body = "GameFontHighlight",
  number = "GameFontHighlight",
  small = "GameFontHighlightSmall",
  rowSmall = "GameFontHighlightSmall", -- second and third line of a list row
  -- Source tag (Vendor / Auction / Destroy): the row's small size in a narrow
  -- typeface (Theme.fontFiles), so the spelled-out words fit.
  sourceTag = "GameFontHighlightSmall",
  -- Summary (footer table, Top finds): about 12 pt; column titles and the notes
  -- line stay small.
  summary = "GameFontHighlight",
  summaryMarker = "GameFontHighlightSmall",
  topHeader = "GameFontHighlightLarge",
  -- Compact mode: the gold per hour (large) and the session total.
  -- Large (about 16 px), not Huge: with coin icons a Huge rate pushed the
  -- session total out of the window.
  compactBig = "GameFontNormalLarge",
  compactMid = "GameFontHighlight",
  tab = "GameFontHighlight", -- tab labels, white (dimmed through colors.tabText)
  topRow = "GameFontHighlight",
  button = "GameFontHighlightSmall", -- white; the disabled state stays gray
  buttonHighlight = "GameFontHighlightSmall",
  buttonDisabled = "GameFontDisableSmall",
  file = "Fonts\\FRIZQT__.TTF",
}

-- Font objects pinned to one typeface whatever the "fontFace" option says
-- (the game's own file when the client refuses it), and the addon's own
-- fonts (Media/Fonts; Inter is the Modern skin's font).
Theme.fontFiles = {
  sourceTag = "Fonts\\ARIALN.TTF",
  inter = "Interface\\AddOns\\AnotherLedger\\Media\\Fonts\\Inter-Regular.ttf",
  interSemiBold = "Interface\\AddOns\\AnotherLedger\\Media\\Fonts\\Inter-SemiBold.ttf",
}

-- Dark leather look: a dark warm brown panel with light text and the real,
-- bright game coin / quality colors. tests/test_theme.lua pins the contrast.
Theme.colors = {
  -- Body text: white. The colors the "Colors" options change (Options.lua,
  -- COLOR_OPTIONS) are overwritten in place by Theme.setColor; their defaults
  -- in DB.defaults.settings match these values (tests/test_options.lua).
  ink = { 1, 1, 1, 1 },
  -- Age tag of stale prices: bright orange (ff8a4a).
  stale = { 1.00, 0.54, 0.29, 1 },
  -- Section title (Top finds): white.
  sectionTitle = { 1, 1, 1, 1 },
  -- Label of the line that holds a row's value (best of vendor / AH / DE).
  best = { 1.00, 0.82, 0.00, 1 },
  -- Daily farm strip text (header row between the filters and the tabs).
  dailyFarm = { 1.00, 0.82, 0.00, 1 },
  -- The in-game gold (ffd100).
  gold = { 1.00, 0.82, 0.00, 1 },
  -- Bright gold for lines (divider, edge, filter underline); not for text.
  goldLine = { 1.00, 0.82, 0.20, 1 },
  -- Divider between the footer summaries and Top finds below them (goldLine at
  -- partial alpha). Window stack, top to bottom: header, list, footer, Top finds.
  divider = { 1.00, 0.82, 0.20, 0.85 },
  -- Row flash: soft warm glow, strong one brighter (alpha highlight on dark).
  -- Thin line between ledger rows: goldLine at low alpha (quiet but visible).
  rowSeparator = { 1.00, 0.82, 0.20, 0.20 },
  flashNormal = { 1.00, 0.90, 0.60, 0.22 },
  flashStrong = { 1.00, 0.80, 0.35, 0.45 },
  -- Dark warm leather brown.
  -- Fully opaque: the Opacity option scales this alpha, so 100% is solid.
  panelTint = { 0.15, 0.10, 0.06, 1 },
  -- Border tint (a shade lighter and warmer than the panel so the frame reads).
  panelBorder = { 0.55, 0.42, 0.24, 1 },
  -- Real game coin colors.
  moneyGold = { 1.00, 0.82, 0.00, 1 },   -- ffd100
  moneySilver = { 0.780, 0.780, 0.812, 1 }, -- c7c7cf
  moneyCopper = { 0.929, 0.647, 0.373, 1 }, -- eda55f
  hint = { 0.68, 0.63, 0.55, 1 },
  -- TSM sale info under the item name: good / high, ok / medium, bad / low.
  marketGood = { 0.45, 0.85, 0.35, 1 },
  marketOk = { 0.95, 0.80, 0.40, 1 },
  marketBad = { 0.95, 0.38, 0.32, 1 },
  -- Source tags of a row's value (frame and text) and the Vendor / AH /
  -- Destroy labels of tooltips: cream, blue, grey.
  tagVendor = { 0.93, 0.87, 0.72, 1 },
  tagAh = { 0.50, 0.82, 1.00, 1 },
  tagDe = { 0.70, 0.70, 0.70, 1 },
  -- Bronze dark buttons (Widgets.buttonColors) and input boxes.
  buttonFill = { 0.10, 0.07, 0.04, 0.95 },
  buttonEdge = { 0.55, 0.42, 0.24, 1 },
  buttonEdgeHover = { 1.00, 0.82, 0.20, 1 },
  buttonText = { 1, 1, 1, 1 },
  buttonTextDisabled = { 0.50, 0.46, 0.38, 1 },
  buttonWarnEdge = { 0.62, 0.24, 0.17, 1 },
  buttonWarnEdgeHover = { 0.90, 0.36, 0.26, 1 },
  buttonWarnText = { 1.00, 0.70, 0.62, 1 },
  inputFill = { 0.06, 0.04, 0.02, 0.95 },
  -- Column titles of the footer table (Value, /h): the hint color.
  columnTitle = { 0.68, 0.63, 0.55, 1 },
  -- Tab buttons: no fill of their own (they show the window background, so its
  -- opacity / brightness options apply), a thin tan edge on top and both sides,
  -- open at the bottom; the selected tab has a bright gold edge and a gold glow
  -- falling from its top edge. tabBorder is also the line under the tab row.
  tabBorder = { 0.62, 0.56, 0.45, 1 },
  tabBorderHover = { 0.86, 0.76, 0.52, 1 },
  tabBorderSelected = { 1.00, 0.82, 0.00, 1 },
  tabGlow = { 1.00, 0.84, 0.10, 0.55 },
  tabText = { 0.86, 0.86, 0.86, 1 },
  tabTextSelected = { 1, 1, 1, 1 },
  -- Rich tooltips (Tooltip.render): gold title and sub-headings, tan labels,
  -- white values (coins in the game colors), quiet notes, red warnings and
  -- green click hints, like the game's own tooltips.
  tipTitle = { 1.00, 0.82, 0.00, 1 },
  tipSection = { 1.00, 0.82, 0.00, 1 },
  tipLabel = { 0.80, 0.74, 0.62, 1 },
  tipValue = { 1, 1, 1, 1 },
  tipNote = { 0.68, 0.63, 0.55, 1 },
  tipWarn = { 0.95, 0.38, 0.32, 1 },
  tipHint = { 0.25, 0.90, 0.25, 1 },
  scrollTrack = { 0.93, 0.87, 0.72, 0.10 },
  scrollThumb = { 0.93, 0.87, 0.72, 0.45 },
}

-- ---------------------------------------------------------------------------
-- Color presets (option "colorPreset"): each sets every color above except the
-- fixed coin colors (item quality colors are fixed too, Theme.qualityColor).
-- Alphas stay as above. tests/test_theme.lua checks every preset is complete
-- and readable. The player's own presets (saved from the color options) are
-- kept by Options.lua in AnotherLedgerDB.colorPresets, on top of one of these.

Theme.FIXED_COLORS = { moneyGold = true, moneySilver = true, moneyCopper = true }
-- The game tooltip AnotherLedger tooltips are drawn on: near-black on every preset.
Theme.TOOLTIP_BG = { 0, 0, 0 }

-- Tooltip colors shared by the presets (the game tooltip stays dark).
local TIPS = {
  tipTitle = "ffd100", tipSection = "ffd100", tipLabel = "ccbd9e", tipValue = "ffffff",
  tipNote = "ada18c", tipWarn = "f26152", tipHint = "40e640",
}
local function withTips(colors, tips)
  for k, v in pairs(TIPS) do if colors[k] == nil then colors[k] = (tips and tips[k]) or v end end
  return colors
end

Theme.presets = {
  { id = "anotherledger", label = "AnotherLedger", colors = {} }, -- filled from Theme.colors below
  { id = "blizzard", label = "Blizzard", colors = withTips({
    ink = "ffffff", stale = "ff8a4a", sectionTitle = "ffffff", best = "ffd100", dailyFarm = "ffd100",
    gold = "ffd100", goldLine = "c9a04a", divider = "c9a04a", rowSeparator = "c9a04a",
    flashNormal = "ffe699", flashStrong = "ffcc59",
    panelTint = "120d0a", panelBorder = "8a6a33", hint = "a89c88", columnTitle = "a89c88",
    marketGood = "73d959", marketOk = "f2cc66", marketBad = "f26152",
    tagVendor = "eddeb8", tagAh = "80d1ff", tagDe = "b3b3b3",
    buttonFill = "5c0a05", buttonEdge = "bb8429", buttonEdgeHover = "ffd100", buttonText = "ffffff",
    buttonTextDisabled = "8a7e6a", buttonWarnEdge = "9e3d2b", buttonWarnEdgeHover = "e65c42",
    buttonWarnText = "ffb39e", inputFill = "0a0806",
    tabBorder = "8a6a33", tabBorderHover = "d4b06a", tabBorderSelected = "ffd100", tabGlow = "ffd61a",
    tabText = "dbdbdb", tabTextSelected = "ffffff", scrollTrack = "eddeb8", scrollThumb = "bb8429",
  }) },
  { id = "midnight", label = "Midnight", colors = withTips({
    ink = "ffffff", stale = "ff8a4a", sectionTitle = "ffffff", best = "ffd100", dailyFarm = "ffd100",
    gold = "ffd100", goldLine = "5b8fd9", divider = "5b8fd9", rowSeparator = "7fa6e0",
    flashNormal = "99c2ff", flashStrong = "66a3ff",
    panelTint = "081a2e", panelBorder = "3d5a80", hint = "9aa8bd", columnTitle = "9aa8bd",
    marketGood = "73d959", marketOk = "f2cc66", marketBad = "f26152",
    tagVendor = "e0e6f0", tagAh = "80d1ff", tagDe = "b3b3b3",
    buttonFill = "0d2440", buttonEdge = "3d5a80", buttonEdgeHover = "82c5ff", buttonText = "ffffff",
    buttonTextDisabled = "66758a", buttonWarnEdge = "9e3d2b", buttonWarnEdgeHover = "e65c42",
    buttonWarnText = "ffb39e", inputFill = "050f1c",
    tabBorder = "4d6a91", tabBorderHover = "82a8d9", tabBorderSelected = "82c5ff", tabGlow = "4d9fff",
    tabText = "d0d8e4", tabTextSelected = "ffffff", scrollTrack = "c0d0e8", scrollThumb = "82a8d9",
  }) },
  -- The Modern skin's colors: navy panel, amber titles, sky blue accents
  -- (the Superdesign board "AnotherLedger Modern skin").
  { id = "polaris", label = "Polaris", colors = withTips({
    ink = "ffffff", stale = "ff8a4a", sectionTitle = "ffffff", best = "e6ba66", dailyFarm = "e6ba66",
    gold = "e6ba66", goldLine = "5f6f99", divider = "2e3650", rowSeparator = "2e3650",
    flashNormal = "80d1ff", flashStrong = "4db8ff",
    panelTint = "1c2234", panelBorder = "3a4566", hint = "9aa8bd", columnTitle = "9aa8bd",
    marketGood = "73d959", marketOk = "f2cc66", marketBad = "f26152",
    tagVendor = "e0e6f0", tagAh = "80d1ff", tagDe = "b3b3b3",
    buttonFill = "232a40", buttonEdge = "2e3650", buttonEdgeHover = "80d1ff", buttonText = "ffffff",
    buttonTextDisabled = "66758a", buttonWarnEdge = "9e3d2b", buttonWarnEdgeHover = "e65c42",
    buttonWarnText = "ffb39e", inputFill = "161b2a",
    tabBorder = "2e3650", tabBorderHover = "4d5a80", tabBorderSelected = "80d1ff", tabGlow = "80d1ff",
    tabText = "9aa8bd", tabTextSelected = "ffffff", scrollTrack = "2e3650", scrollThumb = "4d5a80",
  }, { tipTitle = "e6ba66", tipSection = "e6ba66", tipLabel = "ccbd9e" }) },
  { id = "tsm", label = "TSM-style", colors = withTips({
    ink = "ffffff", stale = "ff8a4a", sectionTitle = "ffffff", best = "f0b429", dailyFarm = "f0b429",
    gold = "f0b429", goldLine = "dbb431", divider = "dbb431", rowSeparator = "8fa3a8",
    flashNormal = "f0c75e", flashStrong = "f0b429",
    panelTint = "192428", panelBorder = "3a4a50", hint = "9aa5a8", columnTitle = "9aa5a8",
    marketGood = "73d959", marketOk = "f2cc66", marketBad = "f26152",
    tagVendor = "e6e6e6", tagAh = "6cc4f0", tagDe = "b3b3b3",
    buttonFill = "0a1519", buttonEdge = "3a4a50", buttonEdgeHover = "f0b429", buttonText = "ffffff",
    buttonTextDisabled = "66767a", buttonWarnEdge = "9e3d2b", buttonWarnEdgeHover = "e65c42",
    buttonWarnText = "ffb39e", inputFill = "0f1a1d",
    tabBorder = "3a4a50", tabBorderHover = "8fa3a8", tabBorderSelected = "f0b429", tabGlow = "f0b429",
    tabText = "c8d0d2", tabTextSelected = "ffffff", scrollTrack = "c8d0d2", scrollThumb = "8fa3a8",
  }, { tipTitle = "f0b429", tipSection = "f0b429" }) },
}

do -- AnotherLedger = the colors above, so it can never drift from them.
  local own = Theme.presets[1].colors
  for key, c in pairs(Theme.colors) do
    if not Theme.FIXED_COLORS[key] then
      own[key] = string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    end
  end
end

-- Seconds a looted row's flash takes to fade.
Theme.durations = {
  flashNormal = 1.0,
  flashStrong = 2.2,
}

-- Opacity of regions tinted with a theme color whose own alpha is opaque.
Theme.alphas = {
  -- Frame of the source tags (Vendor / Auction / Destroy), in the tag's color.
  sourceTagEdge = 0.8,
}

Theme.sizes = {
  minWidth = 350,
  -- Window chrome 2 * 12 + header 84 (filters, buttons, tabs) + Top finds (3 rows) 88
  -- + 4 list rows (4 * 30) + footer 72 = 388 (tests/test_summary.lua recomputes it).
  minHeight = 388,
  minListRows = 4,
  -- Two text lines: name and Vendor, then Best (the better of AH and DE). The
  -- icon scales with the list text size (UI/Fonts.lua) like the row height.
  rowHeight = 30,
  iconSize = 20,
  scrollbarWidth = 10,
  scrollThumbHeight = 24,
  padding = 8,
  headerHeight = 84, -- three header rows: title/buttons, filters, tabs
  headerRowHeight = 28,
  -- Bronze buttons: edge thickness, fill inset, glyph padding of icon buttons.
  buttonEdge = 1,
  buttonInset = 1,
  iconButtonPad = 3,
  buttonTextPad = 6, -- a label longer than the button is cut off this far inside
  -- Mode button arrow: inset of the arrow texture inside its 20 px square.
  arrowPad = 4,
  -- Compact mode: default size and minimum; the title's double-click area.
  compactWidth = 260,
  compactHeight = 210,
  compactMinWidth = 240, -- title, clock, mode, gear and close in one row
  compactMinHeight = 190, -- >= UI.Compact.requiredHeight() (186)
  compactRowHeight = 16,
  -- Gold per hour graph in tooltips: height of the tallest bar and the
  -- width all bars share (each bar 2 to 10 px).
  graphHeight = 36,
  graphWidth = 180,
  compactDropsTop = 46, -- first drop row under the rate, total and divider
  compactGap = 4,
  -- The session goal's progress: a bar of this height over the divider under
  -- the rate (color `gold`), as long as the share of the goal reached.
  compactGoalBarHeight = 3,
  titleButtonWidth = 140,
  -- Star in front of the Daily farm strip.
  dailyFarmIcon = 16,
  -- Footer = the value table: a column-title line and the rows Items / Raw gold
  -- / Total, footerRowHeight each; footerHeight = 4 lines (the full session table).
  -- Summary.tableLayout gives the real height per view.
  footerRowHeight = 18,
  footerHeight = 72,
  -- Notes line under the table (filtered / unpriced / bank scan age), when shown.
  footerNoteHeight = 16,
  buttonHeight = 20,
  -- The AnotherLedger scan button on the auction house window (UI/ScanButton.lua):
  -- width, its offset below the window's bottom right corner and how many
  -- frame levels above the window it is drawn (nothing of the game's sits
  -- there; confirmed in the client).
  scanButtonWidth = 150,
  tradePeriodWidth = 80, -- the Trade tab's 7 days / 30 days / All button
  scanButtonX = -4,
  scanButtonY = -2,
  scanButtonLevel = 10,
  -- Tab buttons (header row 3, 28 px high): body height, edge size and the
  -- height of the selected tab's glow.
  tabHeight = 24,
  tabEdge = 12,
  tabGlowHeight = 12,
  tabUnderline = 2, -- the selected tab's underline (tabs "pills")
  tabTextPad = 10, -- space left and right of a label wider than widths.tab
  tabLine = 1, -- the line under the tab row (open below the selected tab)
  buttonGap = 2,
  timerWidth = 54,
  -- Extra width per glyph of an outlined font (option "fontOutline", seen in
  -- the client: Thick is about 1 px per letter wider than Thin). Added to the
  -- glyph estimates (summaryCharPx, markerCharPx) and the clock (8 glyphs).
  outlineGlyphPx = { OUTLINE = 1, THICKOUTLINE = 2 },
  -- Coin columns (UI/Coins.lua): space between the gold, silver and copper
  -- columns (about the space the one-line amounts had), and the line height
  -- of a cell while its font cannot be measured.
  coinGap = 3,
  coinHeight = 12,
  timerGlyphs = 8,
  -- An outlined text (with its coin icons) also draws a few px past the end
  -- the client measures (client screenshots: about 1 px Thin, 4 px Thick).
  -- Fonts.applySizes copies the current value to textOverhang, the room kept
  -- right of a right-aligned amount (rows, compact, footer).
  outlineOverhangPx = { OUTLINE = 2, THICKOUTLINE = 5 },
  textOverhang = 0,
  -- Source tags with an outline: the client centers the text a little too far
  -- left (screen px to move it right) and the outline needs more room above
  -- and below (screen px added to rowTagPadY). Copied by Fonts.applySizes to
  -- tagTextShift / tagPadExtra.
  outlineTagShiftPx = { OUTLINE = 2, THICKOUTLINE = 3 },
  outlineTagPadPx = { OUTLINE = 1, THICKOUTLINE = 1 },
  tagTextShift = 0,
  tagPadExtra = 0,
  topHeaderHeight = 22,
  topRowHeight = 20,
  dividerHeight = 2,
  -- Estimated average glyph widths in FRIZQT (px) of the 12 pt summary font and
  -- the 10 pt marker font; Summary.tableWorstWidth() budgets with them.
  summaryCharPx = 6.6,
  markerCharPx = 5.5,
  -- The same estimates for the overflow test (tests/test_overflow.lua): 12 pt
  -- fonts (titles, tabs, option labels) and the 10 pt button font. The client
  -- measures the real widths (Widgets.fitButton, Ledger.measureHeader).
  charPx = 6.6,
  smallCharPx = 5.5,
  gripSize = 16,
  -- Option "snapToGrid": how close (px) an edge or the center has to be to an
  -- Edit Mode grid line to snap onto it.
  gridSnapDistance = 12,
  -- Ledger row geometry (Rows.worstCase / Rows.blockLayout). Text inset with the
  -- icon (Rows.textLeft) = rowIconInset + iconSize + rowIconGap; rowRightInset is
  -- the right edge of the Vendor / Best block.
  rowIconInset = 2,
  rowIconGap = 5,
  -- Text inset of a row without its icon (option "showIcons" off).
  rowTextLeftNoIcon = 4,
  rowRightInset = 4,
  -- Window chrome around the row area: 2 * (padding 8 + 4) + scrollbar 10 + 2.
  rowChrome = 36,
  -- Space between the top/bottom row edge and the two text lines (3: the
  -- source tag's frame keeps clear of the separator above the row).
  rowLineInset = 3,
  -- Separator at the bottom edge of a row (inside the row height): thickness and
  -- left inset (= the icon's left edge).
  rowSeparator = 1,
  rowSeparatorInset = 2,
  -- Minimum width of the name column (name + quantity).
  rowNameMin = 90,
  -- Gap between the name column and the Vendor/AH block; between the name and
  -- the quantity; between the AH amount and its age tag.
  rowNameGap = 6,
  rowQtyGap = 4,
  rowTagGap = 3,
  -- Fixed FALLBACK widths, used only while the runtime font measurement
  -- (Rows.attach) returns nothing; measured widths + rowMeasurePad replace them.
  rowQtyW = 36,
  rowLabelGap = 2,
  rowVendorColW = 84,
  -- Source tag after the value (Vendor / AH / DE): fallback width with its
  -- frame, inner padding left / right; screen pixels above / below the text
  -- (Rows.sourceBoxPixels); height of the tag's letters as a share of the
  -- font size (Arial Narrow capitals with their soft top row, measured in the
  -- client), to center them on whole pixels; fallback height while the font
  -- size is unknown; frame thickness (rounded to whole screen pixels).
  rowSourceW = 52,
  rowTagPad = 3,
  rowTagPadY = 1,
  rowTagCapRatio = 0.77,
  rowTagHeight = 12,
  rowTagEdge = 1,
  rowTagW = 36,
  -- Padding added around each measured string width.
  rowMeasurePad = 2,
  gripInset = 4,
  -- Window edge: the game tooltip's proportions (16 px edge, fill inset 5 px),
  -- so the square fill stays hidden behind the rounded corners.
  backdropTile = 16,
  backdropEdge = 16,
  backdropInset = 5,
  -- Skins: the Gilded corner studs, and how far the Sunken list box reaches
  -- past the list (inside the window padding).
  studSize = 10,
  listBoxPad = 3,
  -- Rounded border: edge size of the strip (4 unit corner radius) and the
  -- fill inset under its 1 unit line.
  roundedEdge = 8,
  roundedInset = 1,
}

-- Button / box widths of the header rows. Row 1 at the 350 px minimum is
-- 326 px wide (350 - 2 * (padding 8 + 4)): buttons 38 (Start / Stop) + 40 (reset)
-- + 20 (mode) + 20 (options) + 20 (close) = 138 plus four 2 px gaps = 146, timer
-- 54 + 6 px gap, leaving ~120 px for the title (~95 px).
-- Row 2: quality 78 ("Quality 5/8") + min 44 + sort 78 + three 2 px gaps (plus
-- ~8 px of inset) = ~214, leaving ~112 px for the flexible search box, ~92 px
-- while the clear button (18 + 2) shows.
-- minWidth 350 is the header's budget above; the footer table needs less
-- (Summary.tableWorstWidth, ~278 px of the 326 px content width).
Theme.widths = {
  header = { toggle = 38, reset = 40, hide = 20, options = 20, mode = 20 },
  filter = { quality = 78, min = 44, sort = 78, clear = 18, searchMin = 60 },
  tab = 72, -- tab buttons in header row 3
}

-- Options window (UI/OptionsPanel.lua): two columns of options. Buttons,
-- dropdowns and sliders are `control` wide, not the whole column; the
-- column fits the longest label with its value ("Zone change delay: 15 min",
-- German too). The block heights per option type are Options.HEIGHTS.
Theme.options = {
  columnWidth = 210,
  columnGap = 16,
  titleHeight = 22, -- the window title above the tab row
  tabGap = 8, -- between the tab row and the options
  control = 150, -- width of a button, dropdown or slider
  controlTop = 17, -- a control under its label
  checkbox = 20,
  swatch = 16,
  numberBox = 80,
  boxHeight = 18,
  inactiveAlpha = 0.45, -- an option that does nothing right now (Options.inactive)
}

-- Pure. A color with r, g, b multiplied by `k` (clamped to 0..1); alpha kept.
function Theme.scaleColor(c, k)
  if type(k) ~= "number" or k ~= k then k = 1 end
  local function ch(v) return math.min(1, math.max(0, (v or 0) * k)) end
  return { ch(c[1]), ch(c[2]), ch(c[3]), c[4] or 1 }
end

-- Pure. "rrggbb" (a leading "#" allowed, any case) -> r, g, b in 0..1; nil
-- for anything else.
function Theme.hexToRGB(hex)
  if type(hex) ~= "string" then return nil end
  local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

-- Pure. A color {r, g, b[, a]} -> "rrggbb" (lower case; alpha left out).
function Theme.colorToHex(c)
  local function byte(v) return math.min(255, math.max(0, math.floor((v or 0) * 255 + 0.5))) end
  return string.format("%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

-- Pure. r, g, b (0..1) -> hue, saturation, value (all 0..1). Greys have hue 0.
function Theme.rgbToHsv(r, g, b)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local d = max - min
  local s = max > 0 and d / max or 0
  local h = 0
  if d > 0 then
    if max == r then
      h = ((g - b) / d) % 6
    elseif max == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h / 6
  end
  return h, s, max
end

-- Pure. hue, saturation, value (0..1; hue wraps) -> r, g, b (0..1).
function Theme.hsvToRgb(h, s, v)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p end
  if i == 1 then return q, v, p end
  if i == 2 then return p, v, t end
  if i == 3 then return p, q, v end
  if i == 4 then return t, p, v end
  return v, p, q
end

-- Pure. The color r, g, b with saturation `s` (0..1); hue and value kept.
-- `hue` (optional) is used for greys, which have none of their own.
function Theme.withSaturation(r, g, b, s, hue)
  local h, old, v = Theme.rgbToHsv(r, g, b)
  if old == 0 and hue then h = hue end
  s = math.min(1, math.max(0, s or 0))
  return Theme.hsvToRgb(h, s, v)
end

-- Sets the r, g, b of Theme.colors[key] from "rrggbb", in place (every UI part
-- holding the table sees the new color; alpha kept). Returns the table, or
-- nil for an unknown key or bad hex.
function Theme.setColor(key, hex)
  local c = Theme.colors[key]
  local r, g, b = Theme.hexToRGB(hex)
  if type(c) ~= "table" or not r then return nil end
  c[1], c[2], c[3] = r, g, b
  return c
end

-- The preset with this id, or nil.
function Theme.preset(id)
  for _, p in ipairs(Theme.presets) do
    if p.id == id then return p end
  end
  return nil
end

-- Sets every color of the preset `id` in place (alpha kept); an unknown id
-- gets the AnotherLedger look. Returns { [color table] = true } of the colors set
-- (for Widgets.recolor).
function Theme.applyPreset(id)
  local p = Theme.preset(id) or Theme.presets[1]
  local changed = {}
  for key, hex in pairs(p.colors) do
    local c = Theme.setColor(key, hex)
    if c then changed[c] = true end
  end
  return changed
end

-- ---------------------------------------------------------------------------
-- Skins (options "skin", "skinBorder", ...): the shape of the window border,
-- the buttons and the lines, and the Sunken list box. The window background
-- is flat (textured backgrounds are planned: tools/render_skins.py).
-- They never change colors: every style is tinted with Theme.colors.

-- The choices of each part, in option order.
Theme.skinParts = {
  border = { "rounded", "round", "bevel", "thin", "gilded" },
  buttons = { "bronze", "raised", "flat" },
  lines = { "zebra", "gold", "groove", "plain", "dotted" },
  tabs = { "pills", "folder" },
}

-- Modern is the default of new profiles; Classic is the look before it.
-- Modern also brings its font (option "fontFace") and color preset
-- ("colorPreset"): `font` / `preset`, set when the skin is picked.
Theme.skins = {
  { id = "modern", label = "Modern", border = "rounded", buttons = "flat",
    lines = "zebra", listBox = true, tabs = "pills",
    font = Theme.fontFiles.inter, preset = "polaris" },
  { id = "classic", label = "Classic", border = "round", buttons = "bronze",
    lines = "gold", listBox = false, tabs = "folder" },
  { id = "forge", label = "Forge", border = "bevel", buttons = "raised",
    lines = "groove", listBox = true, tabs = "folder" },
  { id = "slate", label = "Slate", border = "thin", buttons = "flat",
    lines = "plain", listBox = false, tabs = "folder" },
  { id = "gilded", label = "Gilded", border = "gilded", buttons = "bronze",
    lines = "dotted", listBox = false, tabs = "folder" },
}

-- How the styles shade the theme colors: the dark edge lines, the groove's
-- dark / light line, the raised buttons' light / dark edge, how far Plain
-- moves a line color toward grey and the panel, the Sunken list fill.
-- Strong on purpose: the dark presets swallow small differences (client).
Theme.skinScales = {
  edgeDark = 0.2, edgeLight = 1.7, grooveDark = 0.3, grooveLight = 2.0,
  raisedLight = 3.5, raisedDark = 0.3, plainMix = 0.5, listBox = 0.5,
  -- Zebra: every other row lifted toward the text color by this much.
  zebra = 0.04,
}

-- The active picks; the options write them with Theme.setStyle.
Theme.style = { border = "rounded", buttons = "flat", lines = "zebra", listBox = true, tabs = "pills" }

function Theme.skin(id)
  for _, s in ipairs(Theme.skins) do
    if s.id == id then return s end
  end
  return nil
end

-- Stores one pick; false (nothing stored) for an unknown part or value.
function Theme.setStyle(part, value)
  if part == "listBox" then
    if type(value) ~= "boolean" then return false end
    Theme.style.listBox = value
    return true
  end
  local list = Theme.skinParts[part]
  if not list then return false end
  for _, v in ipairs(list) do
    if v == value then
      Theme.style[part] = value
      return true
    end
  end
  return false
end

-- The SetBackdrop table of the window: Round keeps the tooltip edge; the
-- other borders are drawn as lines (Theme.edgeRects), so the fill reaches
-- the frame's edge.
function Theme.backdropSpec(border)
  local S = Theme.sizes
  local bg, tileSize = Theme.textures.parchment, S.backdropTile
  if border == "round" then
    local inset = S.backdropInset
    return { bgFile = bg, edgeFile = Theme.textures.frameBorder, tile = true, tileSize = tileSize,
      edgeSize = S.backdropEdge, insets = { left = inset, right = inset, top = inset, bottom = inset } }
  end
  -- Rounded: the addon's edge strip; the fill starts under the line, so its
  -- square corners stay inside the rounded ones.
  -- UNVERIFIED (check in client): the tile order and rotation of the strip
  -- (tools/render_skins.py rounded()) match the backdrop's edge drawing.
  if border == "rounded" then
    local inset = S.roundedInset
    return { bgFile = bg, edgeFile = Theme.textures.skinRounded, tile = true, tileSize = tileSize,
      edgeSize = S.roundedEdge, insets = { left = inset, right = inset, top = inset, bottom = inset } }
  end
  return { bgFile = bg, tile = true, tileSize = tileSize,
    insets = { left = 0, right = 0, top = 0, bottom = 0 } }
end

-- The line rectangles of a border: inset (px from the frame edge) and shade
-- (a factor on the border color). Round has none (the backdrop edge).
-- (Seen in the client: single 1 px lines in the border color barely show on
-- the dark panel, so Bevel and Gilded use light highlight lines and are
-- 5 / 6 px wide; all stay inside the 12 px content inset.)
function Theme.edgeRects(border)
  local d, l = Theme.skinScales.edgeDark, Theme.skinScales.edgeLight
  if border == "thin" then return { { inset = 0, shade = d }, { inset = 1, shade = 1 } } end
  if border == "bevel" then
    return { { inset = 0, shade = d }, { inset = 1, shade = l }, { inset = 2, shade = 1 },
      { inset = 3, shade = 1 }, { inset = 4, shade = d } }
  end
  if border == "gilded" then
    return { { inset = 0, shade = d }, { inset = 1, shade = l }, { inset = 2, shade = d },
      { inset = 3, shade = d }, { inset = 4, shade = l }, { inset = 5, shade = d } }
  end
  return {}
end

function Theme.edgeStuds(border)
  return border == "gilded"
end

-- Pure. `a` moved toward `b` by t (0..1); alpha of `a`.
function Theme.mix(a, b, t)
  local function m(i) return a[i] + (b[i] - a[i]) * t end
  return { m(1), m(2), m(3), a[4] or 1 }
end

-- The colors of a styled line (Widgets.rule) in `lines` style: the main line
-- and, for Groove, the light line under it. Plain takes the line color halfway
-- to grey (losing the gold) and then halfway to the panel. Alpha kept.
local GREY = { 0.5, 0.5, 0.5 }
function Theme.lineColors(lines, color, panel)
  local k = Theme.skinScales
  if lines == "groove" then
    return Theme.scaleColor(color, k.grooveDark), Theme.scaleColor(color, k.grooveLight)
  elseif lines == "plain" or lines == "zebra" then
    return Theme.mix(Theme.mix(color, GREY, k.plainMix), panel, k.plainMix), nil
  end
  return color, nil
end

-- The color of a value source ("vendor" / "ah" / "de"), or nil.
local SOURCE_COLORS = { vendor = "tagVendor", ah = "tagAh", de = "tagDe" }
function Theme.sourceColor(source)
  local key = SOURCE_COLORS[source]
  return key and Theme.colors[key] or nil
end

-- WCAG 2 contrast ratio (1..21) between two sRGB colors (components 0..1).
local function linear(c)
  if c <= 0.03928 then return c / 12.92 end
  return ((c + 0.055) / 1.055) ^ 2.4
end
local function luminance(r, g, b)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end
function Theme.contrast(r1, g1, b1, r2, g2, b2)
  local x, y = luminance(r1, g1, b1), luminance(r2, g2, b2)
  if x < y then x, y = y, x end
  return (x + 0.05) / (y + 0.05)
end

-- Text on a colored fill (a button background picked in the options): `color`
-- when it stands out enough (Theme.MIN_TEXT_CONTRAST), else a near-black or
-- white text, whichever reads better on `fill`. `dim`: the dimmed variant
-- (a disabled button).
Theme.MIN_TEXT_CONTRAST = 3
local DARK, LIGHT = { 0.08, 0.06, 0.04, 1 }, { 1, 1, 1, 1 }
local DARK_DIM, LIGHT_DIM = { 0.08, 0.06, 0.04, 0.55 }, { 1, 1, 1, 0.55 }
function Theme.readableOn(color, fill, dim)
  local r, g, b = fill[1], fill[2], fill[3]
  if Theme.contrast(color[1], color[2], color[3], r, g, b) >= Theme.MIN_TEXT_CONTRAST then return color end
  local dark = Theme.contrast(DARK[1], DARK[2], DARK[3], r, g, b) >= Theme.contrast(1, 1, 1, r, g, b)
  if dim then return dark and DARK_DIM or LIGHT_DIM end
  return dark and DARK or LIGHT
end

-- Item quality 0..5 (poor..legendary) plus 6 artifact, 7 heirloom: the game's
-- exact colors. Fixed: no color preset changes them.
local function rgb(hex)
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
local QUALITY = {
  [0] = rgb("9d9d9d"),
  [1] = rgb("ffffff"),
  [2] = rgb("1eff00"),
  [3] = rgb("0070dd"),
  [4] = rgb("a335ee"),
  [5] = rgb("ff8000"),
  [6] = rgb("e6cc80"),
  [7] = rgb("00ccff"),
}

-- Returns r, g, b; an unknown quality gets the common (white) color.
function Theme.qualityColor(quality)
  local c = QUALITY[quality]
  if type(quality) ~= "number" or not c then c = QUALITY[1] end
  return c[1], c[2], c[3]
end

ns.Theme = Theme
