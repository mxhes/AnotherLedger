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
  for _, k in ipairs({ "ink", "stale", "gold", "flashNormal", "flashStrong", "panelTint" }) do
    h.eq(type(T.colors[k]), "table", "colors." .. k)
  end
  for _, k in ipairs({ "title", "body", "number", "small", "button", "buttonHighlight",
    "buttonDisabled", "file" }) do
    h.eq(type(T.fonts[k]), "string", "fonts." .. k)
  end
  for _, k in ipairs({ "hint", "scrollTrack", "scrollThumb" }) do
    h.eq(type(T.colors[k]), "table", "colors." .. k)
  end
  for _, k in ipairs({ "minWidth", "minHeight", "rowHeight", "iconSize", "scrollbarWidth",
    "scrollThumbHeight", "padding", "headerHeight", "headerRowHeight", "footerHeight",
    "buttonHeight", "buttonGap", "timerWidth", "topHeaderHeight", "topRowHeight", "gripSize",
    "gripInset", "backdropTile", "backdropEdge", "backdropInset" }) do
    h.eq(type(T.sizes[k]), "number", "sizes." .. k)
  end
  for _, k in ipairs({ "flashNormal", "flashStrong" }) do
    h.eq(type(T.durations[k]), "number", "durations." .. k)
  end
  for _, k in ipairs({ "start", "stop", "reset", "hide" }) do
    h.eq(type(T.widths.header[k]), "number", "widths.header." .. k)
  end
  for _, k in ipairs({ "quality", "min", "sort" }) do
    h.eq(type(T.widths.filter[k]), "number", "widths.filter." .. k)
  end
  h.eq(T.sizes.rowHeight, 28)
  h.eq(T.sizes.headerHeight, 2 * T.sizes.headerRowHeight)
  h.eq(T.sizes.minWidth, 320)
  h.eq(T.sizes.minHeight, 240)
end)

for _, onParchment in ipairs({ true, false }) do
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

-- WCAG relative luminance / contrast ratio against the parchment tint.
local function lin(c)
  if c <= 0.03928 then return c / 12.92 end
  return ((c + 0.055) / 1.055) ^ 2.4
end
local function lum(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
local function contrast(a, b)
  local x, y = lum(a), lum(b)
  if x < y then x, y = y, x end
  return (x + 0.05) / (y + 0.05)
end

h.test("panelTint is a darkened warm parchment brown", function()
  local t = T.colors.panelTint
  -- At least 25 % darker than the old 0.86 / 0.76 / 0.54 tint, still warm and not black.
  h.eq(t[1] <= 0.86 * 0.75 + 1e-9 and t[2] <= 0.76 * 0.75 + 1e-9 and t[3] <= 0.54 * 0.75 + 1e-9, true)
  h.eq(t[1] > t[2] and t[2] > t[3], true)
  h.eq(t[1] >= 0.4, true)
  h.eq(t[4] > 0.9 and t[4] <= 1, true)
end)

h.test("text colors stay readable on the parchment tint", function()
  local tint = T.colors.panelTint
  h.eq(contrast(T.colors.ink, tint) >= 5, true, "ink")
  for _, k in ipairs({ "gold", "stale", "hint", "moneyGold", "moneySilver", "moneyCopper" }) do
    h.eq(contrast(T.colors[k], tint) >= 2.8, true, k)
  end
  for q = 0, 7 do
    local r, g, b = T.qualityColor(q, true)
    h.eq(contrast({ r, g, b }, tint) >= 3, true, "quality " .. q)
  end
  -- Lines (divider, edge) only need to stand out, not to be read.
  h.eq(contrast(T.colors.goldLine, tint) >= 2, true, "goldLine")
end)

h.test("coin colors are distinct", function()
  local g, s, c = T.colors.moneyGold, T.colors.moneySilver, T.colors.moneyCopper
  h.eq(g[1] ~= s[1] or g[2] ~= s[2], true)
  h.eq(s[1] ~= c[1] or s[2] ~= c[2], true)
  h.eq(g[3] < s[3], true) -- gold is the yellow one
  h.eq(c[1] > c[2] and c[1] > c[3], true) -- copper is red-brown
end)
