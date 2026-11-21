local h = ...

-- Text overflow in every language (English and each Locales/*.lua): the texts
-- that sit in a fixed space are estimated with Theme's average glyph widths
-- (charPx for 12 pt, smallCharPx for the 10 pt button font) and checked
-- against that space. The client measures the real widths (buttons fit their
-- labels, Ledger.measureHeader raises the window's minimum); this test keeps
-- every language inside the default window and the fixed columns.

local function locales()
  local out = { "enUS" }
  local isWindows = package.config:sub(1, 1) == "\\"
  local cmd = isWindows and "dir /b AnotherLedger\\Locales\\*.lua" or "ls AnotherLedger/Locales"
  local pipe = assert(io.popen(cmd))
  for name in pipe:lines() do
    local loc = name:gsub("\r", ""):match("^(%a%a%a%a)%.lua$")
    if loc then out[#out + 1] = loc end
  end
  pipe:close()
  table.sort(out)
  return out
end

local FILES = { "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "DB.lua", "Sources/Sources.lua",
  "Sources/TSM.lua", "Sources/Auctionator.lua", "Sources/Scan.lua", "Options.lua", "OptionsLook.lua",
  "UI/Widgets.lua", "UI/Header.lua", "UI/FilterBar.lua", "UI/Tabs.lua", "UI/RowSwitch.lua", "UI/Summary.lua" }

-- The addon loaded with the client language `loc`.
local function loadAs(loc)
  local files = { "Locale.lua" }
  if loc ~= "enUS" then files[2] = "Locales/" .. loc .. ".lua" end
  for _, f in ipairs(FILES) do files[#files + 1] = f end
  local saved = _G.GetLocale
  _G.GetLocale = function() return loc end
  local ok, ns = pcall(h.load, files)
  _G.GetLocale = saved
  assert(ok, ns)
  return ns
end

-- Glyphs of a UTF-8 text, in Latin letter widths: CJK (3-byte leads from
-- U+3000 on) count about twice; color codes count nothing.
local function glyphs(text)
  text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local n, i = 0, 1
  while i <= #text do
    local b = text:byte(i)
    if b < 0x80 then
      n, i = n + 1, i + 1
    elseif b < 0xE0 then
      n, i = n + 1, i + 2
    elseif b < 0xF0 then
      n, i = n + ((b >= 0xE3) and 1.8 or 1), i + 3
    else
      n, i = n + 2, i + 4
    end
  end
  return n
end

local function fail(problems, loc, what, text, w, room)
  problems[#problems + 1] = string.format("%s %s: %q is about %d px, room %d px", loc, what, text, math.ceil(w), math.floor(room))
end

local function checkLocale(loc, problems)
  local ns = loadAs(loc)
  local L, T, UI = ns.L, ns.Theme, ns.UI
  local S = T.sizes
  local big, small = S.charPx, S.smallCharPx
  local function est(text, px) return math.ceil(glyphs(text) * px) end
  local pad = S.buttonTextPad

  -- Option labels: short (the 24 character rule of the English ones); a
  -- button option's label and a closed dropdown's text (a choice's short
  -- text, Options.buttonText) inside the 150 px control.
  local control = T.options.control - 2 * pad
  for _, spec in ipairs(ns.Options.list()) do
    if glyphs(spec.label) > 24 then fail(problems, loc, "option label " .. spec.key, spec.label, est(spec.label, big), 24 * big) end
    if spec.type == "button" and est(spec.label, small) > control then
      fail(problems, loc, "option button " .. spec.key, spec.label, est(spec.label, small), control)
    end
    if spec.type == "dropdown" then
      local ok, choices = pcall(ns.Options.choices, spec)
      for _, c in ipairs(ok and type(choices) == "table" and choices or {}) do
        local text = ns.Options.buttonText(spec, c.value)
        if type(text) == "string" and est(text, small) > control then
          fail(problems, loc, "dropdown " .. spec.key, text, est(text, small), control)
        end
      end
    end
  end

  -- Header rows (fitted buttons, the widest title, the tab strips): inside the
  -- default window, so it never has to grow for a language.
  local function fit(base, texts)
    local widths = {}
    for i, t in ipairs(texts) do widths[i] = est(t, small) end
    return UI.Widgets.fitWidth(base, widths)
  end
  local function tabWidths(labels)
    local out = {}
    for i, label in ipairs(labels) do out[i] = UI.Tabs.buttonWidth(est(label, big)) end
    return out
  end
  local titleW = 0
  for _, title in ipairs(UI.Tabs.titles()) do titleW = math.max(titleW, est(title, big)) end
  local hw, fw = T.widths.header, T.widths.filter
  local rows = {
    row1 = UI.Header.rowNeed(titleW, fit(hw.toggle, { L["Start"], L["Stop"] }), fit(hw.reset, { L["Reset"] })),
    filters = UI.FilterBar.rowNeed(fit(fw.quality, { L["Quality"] .. " 8/8" }), fit(fw.sort, UI.FilterBar.sortTexts())),
  }
  local labels = {}
  for i, key in ipairs(UI.Tabs.KEYS) do labels[i] = UI.Tabs.label(key) end
  rows.tabs = UI.Tabs.rowNeed(tabWidths(labels))
  local period = math.max(fit(S.tradePeriodWidth, UI.TradePeriod.labels()), fit(S.tradePeriodWidth, UI.MobKind.labels()))
  for _, key in ipairs(UI.Tabs.KEYS) do
    local subs = UI.Tabs.subtabs(key)
    if subs then
      local subLabels = {}
      for i, sub in ipairs(subs) do subLabels[i] = sub.label end
      rows["subtabs " .. key] = UI.Tabs.rowNeed(tabWidths(subLabels)) + S.buttonGap * 3 + period
    end
  end
  local room = ns.DB.defaults.window.width - 2 * (S.padding + 4)
  for name, need in pairs(rows) do
    if need > room then fail(problems, loc, "header " .. name, name, need, room) end
  end

  -- Footer labels: the session table keeps 11 glyphs for its labels
  -- (Summary.tableWorstWidth); Bags and Bank have no per hour column, so
  -- their labels also get its 14.
  local SUMMARY = S.summaryCharPx
  for _, text in ipairs({ L["Items"], L["Raw gold"], L["Total"], L["Earned"], L["Spent"], L["Net"] }) do
    if glyphs(text) > 11 then fail(problems, loc, "footer label", text, est(text, SUMMARY), 11 * SUMMARY) end
  end
  for _, text in ipairs({ L["Kept"], L["Sellable"], L["Gold on hand"], L["Net worth"], L["All characters"] }) do
    if glyphs(text) > 25 then fail(problems, loc, "Bags footer label", text, est(text, SUMMARY), 25 * SUMMARY) end
  end
  -- Column titles over the value (15 glyphs) and per hour (14) columns.
  if glyphs(L["Value"]) > 15 then fail(problems, loc, "column title", L["Value"], est(L["Value"], SUMMARY), 15 * SUMMARY) end
  if glyphs(L["per hour"]) > 14 then fail(problems, loc, "column title", L["per hour"], est(L["per hour"], SUMMARY), 14 * SUMMARY) end
end

h.test("Overflow: every language fits the header, the option labels and the footer columns", function()
  local problems = {}
  for _, loc in ipairs(locales()) do checkLocale(loc, problems) end
  table.sort(problems)
  h.eq(problems, {})
end)

h.test("Overflow: the test sees every locale file", function()
  local list = locales()
  h.eq(list[1] ~= nil, true)
  local has = {}
  for _, loc in ipairs(list) do has[loc] = true end
  h.eq(has.enUS and has.deDE, true)
end)

h.test("Widgets.fitWidth: the theme width, wider for a longer label", function()
  local ns = loadAs("enUS")
  local W, pad = ns.UI.Widgets, ns.Theme.sizes.buttonTextPad
  h.eq(W.fitWidth(40, { 10, 20 }), 40)
  h.eq(W.fitWidth(40, { 60.2 }), math.ceil(60.2 + 2 * pad))
  h.eq(W.fitWidth(40, { 0 / 0, -3 }), 40)
  h.eq(W.fitWidth(40, nil), 40)
end)
