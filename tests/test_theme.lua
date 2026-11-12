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
