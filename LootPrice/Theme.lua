local ADDON, ns = ...

-- All look-and-feel values live here so the art can be swapped in one place.
local Theme = {}

Theme.textures = {
  -- No certain retail parchment path; a flat tile tinted with colors.panelTint.
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
  button = "GameFontNormalSmall",
  buttonHighlight = "GameFontHighlightSmall",
  buttonDisabled = "GameFontDisableSmall",
  file = "Fonts\\FRIZQT__.TTF",
}

Theme.colors = {
  ink = { 0.10, 0.06, 0.02, 1 },
  stale = { 0.46, 0.12, 0.00, 1 },
  gold = { 0.36, 0.23, 0.00, 1 },
  -- Bright gold for lines (divider, edge, filter underline); not for text.
  goldLine = { 1.00, 0.80, 0.20, 1 },
  flashNormal = { 1.00, 0.85, 0.30, 0.35 },
  flashStrong = { 1.00, 0.60, 0.10, 0.60 },
  -- Old tint was 0.86 / 0.76 / 0.54; now 72 % of it (about 28 % darker).
  panelTint = { 0.62, 0.55, 0.39, 0.97 },
  -- Coin colors (game gold / silver / copper, darkened to stay readable on the
  -- darker parchment; contrast >= 3 against panelTint).
  moneyGold = { 0.36, 0.23, 0.00, 1 },
  moneySilver = { 0.20, 0.20, 0.27, 1 },
  moneyCopper = { 0.42, 0.12, 0.02, 1 },
  hint = { 0.28, 0.22, 0.15, 1 },
  scrollTrack = { 0.10, 0.06, 0.02, 0.20 },
  scrollThumb = { 0.10, 0.06, 0.02, 0.6 },
}

-- Seconds a looted row's flash takes to fade.
Theme.durations = {
  flashNormal = 1.0,
  flashStrong = 2.2,
}

Theme.sizes = {
  minWidth = 320,
  minHeight = 240,
  rowHeight = 28,
  iconSize = 24,
  scrollbarWidth = 10,
  scrollThumbHeight = 24,
  padding = 8,
  headerHeight = 56,
  headerRowHeight = 28,
  footerHeight = 24,
  buttonHeight = 20,
  buttonGap = 2,
  timerWidth = 54,
  topHeaderHeight = 14,
  topRowHeight = 16,
  gripSize = 16,
  gripInset = 4,
  backdropTile = 16,
  backdropEdge = 24,
  backdropInset = 6,
}

-- Button / box widths of the two header rows. Row 1 at the 320 px minimum is
-- 296 px wide (320 - 2 * (padding 8 + 4)): buttons 38 + 34 + 40 + 20 = 132
-- plus three 2 px gaps = 138, timer 54, leaving ~104 px for the title (~95 px).
-- Row 2: quality 70 + min 44 + sort 78 + three 2 px gaps (plus ~8 px of
-- inset) = ~206, leaving ~90 px for the flexible search box.
Theme.widths = {
  header = { start = 38, stop = 34, reset = 40, hide = 20 },
  filter = { quality = 70, min = 44, sort = 78 },
}

-- Item quality 0..5 (poor..legendary) plus 6 artifact, 7 heirloom.
local BRIGHT = {
  [0] = { 0.62, 0.62, 0.62 },
  [1] = { 1.00, 1.00, 1.00 },
  [2] = { 0.12, 1.00, 0.00 },
  [3] = { 0.00, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 },
  [5] = { 1.00, 0.50, 0.00 },
  [6] = { 0.90, 0.80, 0.50 },
  [7] = { 0.00, 0.80, 1.00 },
}
-- Darker variants readable on the parchment tint (WCAG contrast against
-- colors.panelTint is at least 3 for every tier; tests/test_theme.lua checks).
-- The tint is mid-tone, so bright colors cannot reach 3: all text is dark.
local DARK = {
  [0] = { 0.25, 0.25, 0.25 },
  [1] = { 0.10, 0.06, 0.02 },
  [2] = { 0.00, 0.26, 0.00 },
  [3] = { 0.00, 0.10, 0.42 },
  [4] = { 0.28, 0.04, 0.46 },
  [5] = { 0.45, 0.14, 0.00 },
  [6] = { 0.34, 0.22, 0.02 },
  [7] = { 0.00, 0.24, 0.36 },
}

function Theme.qualityColor(quality, onParchment)
  local set = onParchment and DARK or BRIGHT
  local c = set[quality]
  if type(quality) ~= "number" or not c then c = set[1] end
  return c[1], c[2], c[3]
end

ns.Theme = Theme
