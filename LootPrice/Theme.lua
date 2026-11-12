local ADDON, ns = ...

-- All look-and-feel values live here so the art can be swapped in one place.
local Theme = {}

Theme.textures = {
  -- No certain retail leather path; a flat tile tinted with colors.panelTint.
  parchment = "Interface\\Buttons\\WHITE8X8",
  frameBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
  rowHighlight = "Interface\\Buttons\\WHITE8X8",
  resizeGrip = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
}

Theme.fonts = {
  title = "GameFontNormal",
  body = "GameFontHighlight",
  number = "GameFontHighlight",
  small = "GameFontHighlightSmall",
  -- Summary (totals bar, Top finds): about 12 pt; markers stay small.
  summary = "GameFontHighlight",
  summaryMarker = "GameFontHighlightSmall",
  topHeader = "GameFontNormal",
  topRow = "GameFontHighlight",
  button = "GameFontNormalSmall",
  buttonHighlight = "GameFontHighlightSmall",
  buttonDisabled = "GameFontDisableSmall",
  file = "Fonts\\FRIZQT__.TTF",
}

-- Dark leather look: a dark warm brown panel with light text and the real,
-- bright game coin / quality colors. tests/test_theme.lua pins the contrast.
Theme.colors = {
  -- Body text: light cream.
  ink = { 0.93, 0.87, 0.72, 1 },
  -- Age tag of stale prices: bright orange (ff8a4a).
  stale = { 1.00, 0.54, 0.29, 1 },
  -- "Top finds" header: the in-game gold (ffd100).
  gold = { 1.00, 0.82, 0.00, 1 },
  -- Bright gold for lines (divider, edge, filter underline); not for text.
  goldLine = { 1.00, 0.82, 0.20, 1 },
  -- Divider between Top finds and the list (goldLine at partial alpha).
  divider = { 1.00, 0.82, 0.20, 0.85 },
  -- Row flash: soft warm glow, strong one brighter (alpha highlight on dark).
  flashNormal = { 1.00, 0.90, 0.60, 0.22 },
  flashStrong = { 1.00, 0.80, 0.35, 0.45 },
  -- Dark warm leather brown.
  panelTint = { 0.15, 0.10, 0.06, 0.97 },
  -- Border tint (a shade lighter and warmer than the panel so the frame reads).
  panelBorder = { 0.55, 0.42, 0.24, 1 },
  -- Real game coin colors.
  moneyGold = { 1.00, 0.82, 0.00, 1 },   -- ffd100
  moneySilver = { 0.780, 0.780, 0.812, 1 }, -- c7c7cf
  moneyCopper = { 0.929, 0.647, 0.373, 1 }, -- eda55f
  hint = { 0.68, 0.63, 0.55, 1 },
  scrollTrack = { 0.93, 0.87, 0.72, 0.10 },
  scrollThumb = { 0.93, 0.87, 0.72, 0.45 },
}

-- Seconds a looted row's flash takes to fade.
Theme.durations = {
  flashNormal = 1.0,
  flashStrong = 2.2,
}

Theme.sizes = {
  minWidth = 350,
  minHeight = 240,
  rowHeight = 28,
  iconSize = 24,
  scrollbarWidth = 10,
  scrollThumbHeight = 24,
  padding = 8,
  headerHeight = 56,
  headerRowHeight = 28,
  footerHeight = 38,
  buttonHeight = 20,
  buttonGap = 2,
  timerWidth = 54,
  topHeaderHeight = 18,
  topRowHeight = 20,
  dividerHeight = 2,
  -- Estimated average glyph widths in FRIZQT (px) of the 12 pt summary font and
  -- the 10 pt marker font; Summary.footerWorstWidth() budgets with them.
  summaryCharPx = 6.6,
  markerCharPx = 5.5,
  gripSize = 16,
  -- Ledger row geometry (Rows.columnLayout). textLeft = icon inset 2 + icon 24
  -- + gap 5; rowRightInset is the shared right edge of quantity and AH column.
  rowTextLeft = 31,
  rowRightInset = 4,
  -- Window chrome around the row area: 2 * (padding 8 + 4) + scrollbar 10 + 2.
  rowChrome = 36,
  rowQtyW = 36,
  rowVendorLabelW = 40,
  rowLabelGap = 2,
  rowVendorColW = 84,
  rowGapMid = 6,
  rowAhLabelW = 20,
  rowTagW = 36,
  rowAhColW = 84,
  -- Extra width goes to each amount column up to this much, the rest to the
  -- gap between the vendor column and the AH label (never to the labels).
  rowColExtraMax = 20,
  -- Line 2 uses fonts.small (10 pt, ~5.5 px per glyph = markerCharPx).
  -- Worst-case budget at minWidth 350 (content width 350 - 36 - 31 - 4 = 279):
  -- amount "123456g 78s 90c" = 15 chars * 5.5 = 82.5 -> column 84;
  -- "Vendor:" 7 * 5.5 = 38.5 -> 40; "AH:" 3 * 5.5 = 16.5 -> 20;
  -- tag "(999d)" 6 * 5.5 = 33 -> 36.
  -- Sum 40 + 2 + 84 + 6 + 20 + 36 + 84 = 272 <= 279 (7 px spare).
  gripInset = 4,
  backdropTile = 16,
  backdropEdge = 24,
  backdropInset = 6,
}

-- Button / box widths of the two header rows. Row 1 at the 350 px minimum is
-- 326 px wide (350 - 2 * (padding 8 + 4)): buttons 38 + 34 + 40 + 20 = 132
-- plus three 2 px gaps = 138, timer 54, leaving ~134 px for the title (~95 px).
-- Row 2: quality 70 + min 44 + sort 78 + three 2 px gaps (plus ~8 px of
-- inset) = ~206, leaving ~120 px for the flexible search box.
-- minWidth 350 comes from the footer (see Summary.footerWorstWidth): the
-- 12 pt totals bar needs 157 px per half, so 2 * 157 + 8 px center gap + 24 px
-- window inset = 346, rounded up.
Theme.widths = {
  header = { start = 38, stop = 34, reset = 40, hide = 20 },
  filter = { quality = 70, min = 44, sort = 78 },
}

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

-- onParchment is accepted for old callers and ignored: the panel is dark, so
-- one bright set serves everywhere.
function Theme.qualityColor(quality, onParchment)
  local c = QUALITY[quality]
  if type(quality) ~= "number" or not c then c = QUALITY[1] end
  return c[1], c[2], c[3]
end

ns.Theme = Theme
