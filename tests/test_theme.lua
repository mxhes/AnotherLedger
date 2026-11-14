local h = ...
local ns = h.load({ "Theme.lua" })
local T = ns.Theme

h.test("Theme has required keys", function()
  for _, k in ipairs({ "parchment", "frameBorder", "rowHighlight", "resizeGrip" }) do
    h.eq(type(T.textures[k]), "string", "textures." .. k)
  end
  for _, k in ipairs({ "title", "body", "number" }) do
    h.eq(type(T.fonts[k]), "string", "fonts." .. k)
  end
  for _, k in ipairs({ "ink", "stale", "gold", "sectionTitle", "flashNormal", "flashStrong", "panelTint" }) do
    h.eq(type(T.colors[k]), "table", "colors." .. k)
  end
  for _, k in ipairs({ "title", "body", "number", "small", "button", "buttonHighlight",
    "buttonDisabled", "file" }) do
    h.eq(type(T.fonts[k]), "string", "fonts." .. k)
  end
  for _, k in ipairs({ "summary", "summaryMarker", "blockLabel", "topHeader", "topRow" }) do
    h.eq(type(T.fonts[k]), "string", "fonts." .. k)
  end
  for _, k in ipairs({ "hint", "scrollTrack", "scrollThumb" }) do
    h.eq(type(T.colors[k]), "table", "colors." .. k)
  end
  for _, k in ipairs({ "minWidth", "minHeight", "rowHeight", "iconSize", "scrollbarWidth",
    "scrollThumbHeight", "padding", "headerHeight", "headerRowHeight", "footerHeight",
    "buttonHeight", "buttonGap", "timerWidth", "topHeaderHeight", "topRowHeight", "gripSize",
    "gripInset", "dividerHeight", "footerLabelHeight", "footerLabelGap", "footerItemsHeight",
    "footerGoldHeight", "footerTotalHeight", "minListRows", "summaryCharPx", "markerCharPx", "backdropTile", "backdropEdge", "backdropInset" }) do
    h.eq(type(T.sizes[k]), "number", "sizes." .. k)
  end
  for _, k in ipairs({ "flashNormal", "flashStrong" }) do
    h.eq(type(T.durations[k]), "number", "durations." .. k)
  end
  for _, k in ipairs({ "start", "stop", "reset", "hide", "options" }) do
    h.eq(type(T.widths.header[k]), "number", "widths.header." .. k)
  end
  for _, k in ipairs({ "quality", "min", "sort" }) do
    h.eq(type(T.widths.filter[k]), "number", "widths.filter." .. k)
  end
  h.eq(T.sizes.footerHeight, 158)
  h.eq(T.sizes.topHeaderHeight, 22)
  h.eq(T.sizes.topRowHeight, 20)
  h.eq(T.sizes.rowHeight, 40)
  h.eq(T.sizes.headerHeight, 3 * T.sizes.headerRowHeight)
  h.eq(T.sizes.minWidth, 350)
  h.eq(T.sizes.minHeight, 514)
end)

for _, onParchment in ipairs({ true, false }) do -- the second argument is ignored now
  h.test("qualityColor in range, parchment=" .. tostring(onParchment), function()
    for q = 0, 7 do
      local r, g, b = T.qualityColor(q, onParchment)
      for _, v in ipairs({ r, g, b }) do
        h.eq(type(v), "number")
        h.eq(v >= 0 and v <= 1, true)
      end
    end
  end)
end

h.test("qualityColor out of range falls back to quality 1", function()
  for _, p in ipairs({ true, false }) do
    local r1, g1, b1 = T.qualityColor(1, p)
    h.eq({ T.qualityColor(99, p) }, { r1, g1, b1 })
    h.eq({ T.qualityColor(-1, p) }, { r1, g1, b1 })
    h.eq({ T.qualityColor(nil, p) }, { r1, g1, b1 })
  end
end)

local function contrast(a, b)
  return T.contrast(a[1], a[2], a[3], b[1], b[2], b[3])
end

h.test("Theme.contrast is the WCAG ratio", function()
  local function near(a, b) return math.abs(a - b) < 0.01 end
  h.eq(near(T.contrast(0, 0, 0, 1, 1, 1), 21), true)
  h.eq(near(T.contrast(1, 1, 1, 0, 0, 0), 21), true)
  h.eq(near(T.contrast(0.5, 0.5, 0.5, 0.5, 0.5, 0.5), 1), true)
  -- #777 on white is the well-known 4.48.
  h.eq(near(T.contrast(0x77 / 255, 0x77 / 255, 0x77 / 255, 1, 1, 1), 4.48), true)
end)

h.test("panelTint is a dark warm leather brown", function()
  local t = T.colors.panelTint
  h.eq(t[1] >= 0.13 and t[1] <= 0.18, true)
  h.eq(t[2] >= 0.09 and t[2] <= 0.13, true)
  h.eq(t[3] >= 0.05 and t[3] <= 0.08, true)
  h.eq(t[1] > t[2] and t[2] > t[3], true)
  h.eq(t[4] > 0.9 and t[4] <= 1, true)
  local b = T.colors.panelBorder
  h.eq(b[1] > t[1] and b[2] > t[2] and b[3] > t[3], true)
  h.eq(b[1] > b[2] and b[2] > b[3], true)
end)

h.test("text, coin and quality colors are readable on the dark panel", function()
  local tint = T.colors.panelTint
  h.eq(contrast(T.colors.ink, tint) >= 7, true, "ink")
  for _, k in ipairs({ "hint", "stale", "gold", "moneyGold", "moneySilver", "moneyCopper" }) do
    h.eq(contrast(T.colors[k], tint) >= 4.5, true, k)
  end
  for q = 0, 7 do
    local r, g, b = T.qualityColor(q, true)
    h.eq(contrast({ r, g, b }, tint) >= 3, true, "quality " .. q)
  end
  h.eq(contrast(T.colors.goldLine, tint) >= 3, true, "goldLine")
  -- The divider is goldLine at partial alpha: blend over the panel first.
  local d = T.colors.divider
  local mix = {}
  for i = 1, 3 do mix[i] = d[i] * d[4] + tint[i] * (1 - d[4]) end
  h.eq(contrast(mix, tint) >= 3, true, "divider")
end)

h.test("coin colors are the game's", function()
  local function hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
      math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
  end
  h.eq(hex(T.colors.moneyGold), "ffd100")
  h.eq(hex(T.colors.moneySilver), "c7c7cf")
  h.eq(hex(T.colors.moneyCopper), "eda55f")
end)

h.test("row separator: 1 px, subtle but visible on the panel", function()
  local s, tint = T.colors.rowSeparator, T.colors.panelTint
  h.eq(type(s), "table")
  h.eq(T.sizes.rowSeparator, 1)
  h.eq(T.sizes.rowSeparator < T.sizes.rowHeight, true)
  h.eq(s[4] >= 0.15 and s[4] <= 0.30, true, "alpha")
  local a = s[4]
  local mix = {}
  for i = 1, 3 do mix[i] = s[i] * a + tint[i] * (1 - a) end
  h.eq(contrast(mix, tint) >= 1.3, true, "contrast")
end)

h.test("scaleColor multiplies rgb, clamps and keeps alpha", function()
  h.eq(T.scaleColor({ 0.5, 0.25, 1, 0.8 }, 0.5), { 0.25, 0.125, 0.5, 0.8 })
  h.eq(T.scaleColor({ 0.5, 0.5, 0.5 }, 3), { 1, 1, 1, 1 })
  h.eq(T.scaleColor({ 0.5, 0.5, 0.5 }, -1), { 0, 0, 0, 1 })
  h.eq(T.scaleColor({ 0.5, 0.5, 0.5, 1 }, "x"), { 0.5, 0.5, 0.5, 1 })
end)

h.test("button text and section titles are white", function()
  h.eq(T.colors.sectionTitle, { 1, 1, 1, 1 })
  h.eq(T.fonts.button, "GameFontHighlightSmall")
  h.eq(T.fonts.blockLabel, "GameFontHighlightLarge")
  h.eq(T.fonts.topHeader, "GameFontHighlightLarge")
end)
