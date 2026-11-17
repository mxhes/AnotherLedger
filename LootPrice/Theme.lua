local ADDON, ns = ...

-- All look-and-feel values live here so the art can be swapped in one place.
local Theme = {}

Theme.textures = {
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
-- (the game's own file when the client refuses it).
Theme.fontFiles = {
  sourceTag = "Fonts\\ARIALN.TTF",
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
  -- Tab buttons (header row 3, 28 px high): body height, edge size and the
  -- height of the selected tab's glow.
  tabHeight = 24,
  tabEdge = 12,
  tabGlowHeight = 12,
  tabTextPad = 10, -- space left and right of a label wider than widths.tab
  tabLine = 1, -- the line under the tab row (open below the selected tab)
  buttonGap = 2,
  timerWidth = 54,
  topHeaderHeight = 22,
  topRowHeight = 20,
  dividerHeight = 2,
  -- Estimated average glyph widths in FRIZQT (px) of the 12 pt summary font and
  -- the 10 pt marker font; Summary.tableWorstWidth() budgets with them.
  summaryCharPx = 6.6,
  markerCharPx = 5.5,
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
  filter = { quality = 78, min = 44, sort = 78, clear = 18 },
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

-- Item quality 0..5 (poor..legendary) plus 6 artifact, 7 heirloom: the familiar
-- game colors (rare and epic brightened because the in-game ones are too dark
-- on the dark panel).
local QUALITY = {
  [0] = { 0.62, 0.62, 0.62 }, -- 9d9d9d
  [1] = { 1.00, 1.00, 1.00 }, -- ffffff
  [2] = { 0.12, 1.00, 0.00 }, -- 1eff00
  [3] = { 0.29, 0.61, 1.00 }, -- 4a9bff
  [4] = { 0.76, 0.36, 1.00 }, -- c25bff
  [5] = { 1.00, 0.50, 0.00 }, -- ff8000
  [6] = { 0.90, 0.80, 0.50 }, -- e6cc80
  [7] = { 0.00, 0.80, 1.00 }, -- 00ccff
}

-- Returns r, g, b; an unknown quality gets the common (white) color.
function Theme.qualityColor(quality)
  local c = QUALITY[quality]
  if type(quality) ~= "number" or not c then c = QUALITY[1] end
  return c[1], c[2], c[3]
end

ns.Theme = Theme
