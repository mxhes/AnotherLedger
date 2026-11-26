local h = ...
local ns = h.load({ "Util.lua", "Theme.lua" })
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
  for _, k in ipairs({ "summary", "summaryMarker", "topHeader", "topRow" }) do
    h.eq(type(T.fonts[k]), "string", "fonts." .. k)
  end
  for _, k in ipairs({ "hint", "scrollTrack", "scrollThumb" }) do
    h.eq(type(T.colors[k]), "table", "colors." .. k)
  end
  for _, k in ipairs({ "minWidth", "minHeight", "rowHeight", "iconSize", "scrollbarWidth",
    "scrollThumbHeight", "padding", "headerHeight", "headerRowHeight", "footerHeight",
    "buttonHeight", "buttonGap", "timerWidth", "topHeaderHeight", "topRowHeight", "gripSize",
    "gripInset", "dividerHeight", "footerRowHeight", "footerNoteHeight",
    "minListRows", "summaryCharPx", "markerCharPx", "backdropTile", "backdropEdge", "backdropInset" }) do
    h.eq(type(T.sizes[k]), "number", "sizes." .. k)
  end
  for _, k in ipairs({ "flashNormal", "flashStrong" }) do
    h.eq(type(T.durations[k]), "number", "durations." .. k)
  end
  for _, k in ipairs({ "toggle", "reset", "hide", "options" }) do
    h.eq(type(T.widths.header[k]), "number", "widths.header." .. k)
  end
  for _, k in ipairs({ "quality", "min", "sort" }) do
    h.eq(type(T.widths.filter[k]), "number", "widths.filter." .. k)
  end
  h.eq(T.sizes.footerHeight, 72)
  h.eq(T.sizes.topHeaderHeight, 22)
  h.eq(T.sizes.topRowHeight, 20)
  h.eq(T.sizes.rowHeight, 30)
  h.eq(T.sizes.iconSize, 20)
  h.eq(T.sizes.iconSize < T.sizes.rowHeight, true)
  h.eq(T.sizes.headerHeight, 3 * T.sizes.headerRowHeight)
  h.eq(T.sizes.minWidth, 350)
  h.eq(T.sizes.minHeight, 388)
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

h.test("quality colors are Blizzard's", function()
  local want = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff" }
  for q = 0, 7 do
    h.eq(T.colorToHex({ T.qualityColor(q) }), want[q], "quality " .. q)
  end
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
  h.eq(T.fonts.topHeader, "GameFontHighlightLarge")
end)

-- Color presets (Theme.presets): snapshot of today's look before any preset runs.
local BEFORE = {}
for k, c in pairs(T.colors) do BEFORE[k] = T.colorToHex(c) end

h.test("every preset sets every color", function()
  local ids = {}
  for _, p in ipairs(T.presets) do
    ids[#ids + 1] = p.id
    h.eq(type(p.label), "string", p.id .. " label")
    for key in pairs(T.colors) do
      if T.FIXED_COLORS[key] then
        h.eq(p.colors[key], nil, p.id .. " must not set " .. key)
      else
        h.eq(T.hexToRGB(p.colors[key]) ~= nil, true, p.id .. "." .. key)
      end
    end
    for key in pairs(p.colors) do h.eq(type(T.colors[key]), "table", p.id .. " unknown key " .. key) end
  end
  h.eq(table.concat(ids, ","), "anotherledger,blizzard,midnight,polaris,tsm")
end)

h.test("anotherledger preset is today's look", function()
  local p = T.preset("anotherledger")
  for key, hex in pairs(BEFORE) do
    if not T.FIXED_COLORS[key] then h.eq(p.colors[key], hex, key) end
  end
end)

local function hexContrast(a, b)
  local r1, g1, b1 = T.hexToRGB(a)
  local r2, g2, b2 = T.hexToRGB(b)
  return T.contrast(r1, g1, b1, r2, g2, b2)
end

h.test("presets are readable on their own panel", function()
  for _, p in ipairs(T.presets) do
    local c, panel = p.colors, p.colors.panelTint
    local function need(key, min, bg)
      local ratio = hexContrast(c[key], bg or panel)
      h.eq(ratio >= min, true, string.format("%s.%s %.2f < %s", p.id, key, ratio, min))
    end
    need("ink", 7)
    for _, k in ipairs({ "hint", "gold", "stale", "columnTitle", "best", "dailyFarm", "tabText" }) do need(k, 4.5) end
    for _, k in ipairs({ "tagVendor", "tagAh", "tagDe", "marketGood", "marketOk", "marketBad" }) do need(k, 3) end
    need("goldLine", 3)
    need("buttonText", 4.5, c.buttonFill)
    need("buttonWarnText", 3, c.buttonFill)
    for _, k in ipairs({ "moneyGold", "moneySilver", "moneyCopper" }) do
      h.eq(hexContrast(T.colorToHex(T.colors[k]), panel) >= 3, true, p.id .. " " .. k)
    end
    for q = 0, 7 do
      h.eq(hexContrast(T.colorToHex({ T.qualityColor(q) }), panel) >= 3, true, p.id .. " quality " .. q)
    end
  end
end)

h.test("tooltip colors readable on the game tooltip", function()
  local bg = T.colorToHex(T.TOOLTIP_BG)
  for _, p in ipairs(T.presets) do
    for _, k in ipairs({ "tipTitle", "tipSection", "tipLabel", "tipValue", "tipNote", "tipWarn", "tipHint" }) do
      h.eq(hexContrast(p.colors[k], bg) >= 4.5, true, p.id .. "." .. k)
    end
  end
end)

h.test("applyPreset changes colors in place and keeps alpha", function()
  local d = T.colors.divider
  local a = d[4]
  local changed = T.applyPreset("midnight")
  h.eq(T.colors.divider == d, true)
  h.eq(T.colorToHex(d), T.preset("midnight").colors.divider)
  h.eq(d[4], a)
  h.eq(changed[d], true)
  h.eq(changed[T.colors.moneyGold], nil)
  T.applyPreset("nope") -- unknown: the AnotherLedger look
  h.eq(T.colorToHex(T.colors.panelTint), BEFORE.panelTint)
end)

h.test("Theme.skins: every skin names a valid choice for each part", function()
  local ids = {}
  for _, s in ipairs(T.skins) do
    ids[#ids + 1] = s.id
    for part, list in pairs(T.skinParts) do
      local ok = false
      for _, v in ipairs(list) do if v == s[part] then ok = true end end
      h.eq(ok, true, s.id .. "." .. part)
    end
    h.eq(type(s.listBox), "boolean")
  end
  h.eq(ids, { "modern", "classic", "forge", "slate" })
  h.eq(T.skin("modern").font, T.fontFiles.inter); h.eq(T.skin("modern").preset, "polaris")
  h.eq(T.preset("polaris") ~= nil, true)
  h.eq(T.skin("forge").border, "bevel"); h.eq(T.skin("nope"), nil)
end)

h.test("Theme.style starts as Modern; setStyle validates", function()
  h.eq(T.style, { border = "rounded", buttons = "flat", lines = "zebra", listBox = true, tabs = "pills" })
  h.eq(T.setStyle("tabs", "folder"), true); h.eq(T.setStyle("tabs", "round"), false); T.setStyle("tabs", "pills")
  h.eq(T.setStyle("border", "bevel"), true); h.eq(T.style.border, "bevel")
  h.eq(T.setStyle("border", "wavy"), false); h.eq(T.style.border, "bevel")
  h.eq(T.setStyle("listBox", "yes"), false); h.eq(T.setStyle("listBox", true), true)
  h.eq(T.setStyle("colour", "x"), false)
  T.setStyle("border", "round"); T.setStyle("listBox", false)
end)

h.test("Theme.backdropSpec: round keeps today's edge, others have no edge file", function()
  local r = T.backdropSpec("round")
  h.eq(r.edgeFile, T.textures.frameBorder); h.eq(r.bgFile, T.textures.parchment)
  h.eq(r.insets.left, T.sizes.backdropInset)
  local b = T.backdropSpec("bevel")
  h.eq(b.edgeFile, nil); h.eq(b.bgFile, T.textures.parchment); h.eq(b.tileSize, T.sizes.backdropTile)
  h.eq(T.skinParts.background, nil) -- flat only until textured backgrounds come
end)

h.test("Theme.edgeRects per border", function()
  local d = T.skinScales.edgeDark
  h.eq(T.edgeRects("round"), {})
  h.eq(T.edgeRects("thin"), { { inset = 0, shade = d }, { inset = 1, shade = 1 } })
  local l = T.skinScales.edgeLight
  -- Bevel: dark outline, a light highlight, a 2 px body, a dark inner line.
  h.eq(T.edgeRects("bevel"), { { inset = 0, shade = d }, { inset = 1, shade = l }, { inset = 2, shade = 1 },
    { inset = 3, shade = 1 }, { inset = 4, shade = d } })
end)

h.test("Theme.lineColors: groove has two shades, plain loses the gold, alpha kept", function()
  local c, panel = { 1, 0.82, 0.2, 0.2 }, T.colors.panelTint
  local m, s = T.lineColors("gold", c, panel); h.eq(m, c); h.eq(s, nil)
  m, s = T.lineColors("groove", c, panel)
  h.eq(m[1] < c[1] and s[2] >= c[2], true); h.eq(m[4], 0.2); h.eq(s[4], 0.2)
  m = T.lineColors("plain", c, panel)
  h.eq(math.abs(m[1] - m[3]) < math.abs(c[1] - c[3]), true); h.eq(m[4], 0.2)
end)

h.test("Theme: every addon texture exists on disk", function()
  local prefix = "Interface\\AddOns\\AnotherLedger\\"
  for key, path in pairs(T.textures) do
    if path:sub(1, #prefix) == prefix then
      local file = "AnotherLedger/" .. path:sub(#prefix + 1):gsub("\\", "/") .. ".tga"
      local f = io.open(file, "rb")
      h.eq(f ~= nil, true, key .. " -> " .. file)
      if f then f:close() end
    end
  end
end)

h.test("rgbToHsv / hsvToRgb round trip", function()
  local function near3(r, g, b, er, eg, eb, what)
    h.near(r, er, 1e-6, what .. " r"); h.near(g, eg, 1e-6, what .. " g"); h.near(b, eb, 1e-6, what .. " b")
  end
  local hh, s, v = T.rgbToHsv(1, 0, 0)
  h.near(hh, 0, 1e-9); h.near(s, 1, 1e-9); h.near(v, 1, 1e-9)
  hh, s, v = T.rgbToHsv(0.5, 0.5, 0.5)
  h.near(hh, 0, 1e-9); h.near(s, 0, 1e-9); h.near(v, 0.5, 1e-9)
  for _, c in ipairs({ { 0.2, 0.6, 0.4 }, { 0.9, 0.1, 0.7 }, { 0.3, 0.3, 0.8 }, { 1, 0.8, 0 }, { 0, 0, 0 } }) do
    local r, g, b = T.hsvToRgb(T.rgbToHsv(c[1], c[2], c[3]))
    near3(r, g, b, c[1], c[2], c[3], table.concat(c, ","))
  end
end)

h.test("withSaturation keeps hue and value", function()
  local r, g, b = T.withSaturation(1, 0, 0, 0)
  h.near(r, 1, 1e-9); h.near(g, 1, 1e-9); h.near(b, 1, 1e-9)
  r, g, b = T.withSaturation(0.5, 0.5, 0.5, 1)
  h.near(r, 0.5, 1e-9); h.near(g, 0, 1e-9); h.near(b, 0, 1e-9)
  r, g, b = T.withSaturation(0.5, 0.5, 0.5, 1, 1 / 3) -- a grey takes the given hue
  h.near(r, 0, 1e-9); h.near(g, 0.5, 1e-9); h.near(b, 0, 1e-9)
  local hh, s = T.rgbToHsv(T.withSaturation(0.2, 0.6, 0.4, 0.25))
  local h0 = T.rgbToHsv(0.2, 0.6, 0.4)
  h.near(hh, h0, 1e-6); h.near(s, 0.25, 1e-6)
  r = T.withSaturation(1, 0, 0, 7) -- clamped
  h.near(r, 1, 1e-9)
end)
