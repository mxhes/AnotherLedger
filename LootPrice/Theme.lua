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
  ink = { 0.20, 0.12, 0.05, 1 },
  stale = { 0.85, 0.45, 0.10, 1 },
  gold = { 0.70, 0.52, 0.05, 1 },
  flashNormal = { 1.00, 0.85, 0.30, 0.35 },
  flashStrong = { 1.00, 0.60, 0.10, 0.60 },
  panelTint = { 0.86, 0.76, 0.54, 0.97 },
  hint = { 0.5, 0.5, 0.5, 1 },
  scrollTrack = { 0.20, 0.12, 0.05, 0.15 },
  scrollThumb = { 0.20, 0.12, 0.05, 0.6 },
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
-- Darker variants readable on the parchment tint.
local DARK = {
  [0] = { 0.38, 0.38, 0.38 },
  [1] = { 0.20, 0.12, 0.05 },
  [2] = { 0.05, 0.50, 0.00 },
  [3] = { 0.00, 0.25, 0.60 },
  [4] = { 0.42, 0.10, 0.65 },
  [5] = { 0.70, 0.30, 0.00 },
  [6] = { 0.55, 0.42, 0.10 },
  [7] = { 0.00, 0.45, 0.62 },
}

function Theme.qualityColor(quality, onParchment)
  local set = onParchment and DARK or BRIGHT
  local c = set[quality]
  if type(quality) ~= "number" or not c then c = set[1] end
  return c[1], c[2], c[3]
end

ns.Theme = Theme
