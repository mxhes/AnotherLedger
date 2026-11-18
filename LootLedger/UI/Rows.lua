local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Scrolling item rows with a pooled set of row frames and a loot flash.
-- Client-only parts touch WoW globals inside functions only; the helpers at
-- the top (rowText, visibleCount, clampOffset, offsetFor) are pure.
local Rows = {}
ns.UI.Rows = Rows

-- User-visible strings (translated through ns.L, Locale.lua).
local TEXT = {
  QTY = ns.L["x"],
  BOUND = ns.L["bound"],
  UNPRICED = "?",
  WORTHLESS = "\226\128\147", -- en dash: an item nothing pays for
  EACH = ns.L[" each"],
  KEPT = ns.L["(kept)"],
  AH_CUT = ns.L[" (after 5% AH cut)"],
}

-- The source tag after a row's value and the tooltip line of each value.
Rows.SOURCES = { "vendor", "ah", "de" }
local SOURCE_TEXT = { vendor = ns.L["Vendor"], ah = ns.L["Auction"], de = ns.L["Destroy"] }
local SOURCE_LABEL = { vendor = ns.L["Vendor: "], ah = ns.L["AH: "], de = ns.L["Destroy: "] }
local SOURCE_COLOR = { vendor = "tagVendor", ah = "tagAh", de = "tagDe" }
Rows.SOURCE_TEXT, Rows.SOURCE_COLOR = SOURCE_TEXT, SOURCE_COLOR

-- TSM sale info levels (View.marketLevels): text and Theme color of each.
local MARKET = {
  good = { ns.L["Sells well"], "marketGood" },
  ok = { ns.L["Sells okay"], "marketOk" },
  bad = { ns.L["Sells poorly"], "marketBad" },
  high = { ns.L["High volume"], "marketGood" },
  medium = { ns.L["Medium volume"], "marketOk" },
  low = { ns.L["Low volume"], "marketBad" },
}
local MARKET_SEP = ", "

local WHEEL_STEP = 2
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark

-- ---------------------------------------------------------------------------
-- Pure helpers

-- Line 2 under the name: the sale rate and volume levels of the row, e.g.
-- "Sells well, Low volume", each part in its level color (plain text without
-- `colors`). nil when the row has neither level.
function Rows.marketText(row, colors)
  local parts = {}
  for _, lv in ipairs({ row.rateLevel or false, row.volumeLevel or false }) do
    local m = lv and MARKET[lv]
    if m then
      local c = colors and colors[m[2]]
      parts[#parts + 1] = c and (ns.Money.colorCode(c) .. m[1] .. "|r") or m[1]
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, MARKET_SEP)
end

-- Unpriced = no AH price and not bound (the footer's count and History's);
-- such a row still shows its vendor / DE value, marked "?".
local function isUnpriced(row)
  return row.ahEach == nil and not row.bound and not row.isCurrency and row.bestLineTotal == nil
end

-- The texts one row shows: line 1 name, quantity, the counted value (the row's
-- `value`, best of vendor / AH / DE) and its source tag; line 2 the row's
-- `detail` (History sessions, Zones places) or the TSM sale info.
-- `formatMoney` defaults to the colored coin format (Money.formatColored);
-- the tests pass Money.format for plain text.
--   { name, qty, amount, copper (the amount as a number when it is money,
--     for the coin columns), source ("vendor" / "ah" / "de" / nil), sourceText,
--     unpriced, tag (age of a cached AH value), tagStale, market, isDetail }
-- Rows with their own total (History / Zones places, `bestLineTotal`) show it
-- without a source; currencies show no amount; a row without a quantity
-- (sessions, places) shows none. `unitPrice` (default: the option
-- "unitPrice") shows one item's value on a stack of several.
function Rows.rowText(row, formatMoney, unitPrice)
  formatMoney = formatMoney or ns.Money.formatColored
  if unitPrice == nil then unitPrice = ns.Util.setting("unitPrice", false) end
  local qty = row.quantity and (TEXT.QTY .. tostring(row.quantity)) or ""
  if row.isCurrency then
    return { name = row.name or "", qty = qty, amount = "", source = nil, sourceText = nil,
      unpriced = false, tag = nil, tagStale = false }
  end
  local amount, source, copper
  if row.worthless then
    amount = TEXT.WORTHLESS
  elseif row.bestLineTotal ~= nil then
    copper = row.bestLineTotal
  elseif row.bestKind ~= nil then
    source = row.bestKind
    local each = row[source .. "Each"]
    if unitPrice and (row.quantity or 0) > 1 and type(each) == "number" then
      copper = math.floor(each + 0.5)
    else
      copper = row.value or 0
    end
  elseif row.bound then
    amount = TEXT.BOUND
  else
    amount = TEXT.UNPRICED
  end
  if copper ~= nil then amount = formatMoney(copper) end
  -- The age tag belongs to a cached AH price, so only when that value counts.
  local tag, tagStale = nil, false
  if source == "ah" and row.ahFromCache and type(row.ahAge) == "number" then
    tag = "(" .. ns.Prices.formatAge(row.ahAge) .. ")"
    tagStale = row.stale and true or false
  end
  -- Bags / Bank: an item on the keep list says so after its name, quietly.
  local name = row.name or ""
  -- History Zones: the Daily farm's place gets the strip's star before its name.
  if row.daily and ns.Theme then
    name = "|T" .. ns.Theme.textures.dailyFarm .. ":0|t " .. name
  end
  if row.kept then
    local hint = ns.Theme and ns.Theme.colors.hint
    name = name .. " " .. (hint and (ns.Money.colorCode(hint) .. TEXT.KEPT .. "|r") or TEXT.KEPT)
  end
  return {
    name = name,
    qty = qty,
    amount = amount,
    copper = copper,
    source = source,
    sourceText = source and SOURCE_TEXT[source] or nil,
    unpriced = isUnpriced(row),
    market = row.detail or Rows.marketText(row, ns.Theme and ns.Theme.colors),
    isDetail = row.detail ~= nil,
    tag = tag,
    tagStale = tagStale,
  }
end

-- Tooltip lines of a row: every known value ("Vendor: 1s (50c each)"). Per
-- unit only with qty > 1. Without `formatMoney` (the colored coins) the label
-- takes its source color (Theme.sourceColor); plain text otherwise.
function Rows.tooltipLines(row, formatMoney)
  local colored = formatMoney == nil
  formatMoney = formatMoney or ns.Money.formatColored
  local lines = {}
  if type(row) ~= "table" or row.isCurrency then return lines end
  local multi = (row.quantity or 0) > 1
  for _, src in ipairs(Rows.SOURCES) do
    local total, each = row[src .. "Total"], row[src .. "Each"]
    if type(total) == "number" then
      local label = SOURCE_LABEL[src]
      local c = colored and ns.Theme.sourceColor(src)
      if c then label = ns.Money.colorCode(c) .. label .. "|r" end
      local line = label .. formatMoney(total)
      if multi and type(each) == "number" then line = line .. " (" .. formatMoney(each) .. TEXT.EACH .. ")" end
      if src == "ah" and row.ahCut then line = line .. TEXT.AH_CUT end
      lines[#lines + 1] = line
    end
  end
  return lines
end

-- The texts of a view row are built once and reused while it scrolls.
local function textOf(row)
  local text = row.text
  if not text then
    text = Rows.rowText(row)
    row.text = text
  end
  return text
end

-- Worst-case sample strings measured at runtime (plain text: color escapes
-- are not drawn, so they do not count toward the width).
local SAMPLE_AMOUNT = 1234567890 -- copper: "123456g 78s 90c" (or with coin icons)
local SAMPLE_TAG = "(999d)"
local SAMPLE_QTY = "x9999"

local positive = ns.Util.isPositive

-- Resolves the widths: a measured value (+ padding) when valid, else the fixed
-- Theme fallback. Returns widths and whether any fallback was used.
local function resolveWidths(measured)
  local S = ns.Theme.sizes
  local m = type(measured) == "table" and measured or {}
  local pad = S.rowMeasurePad
  local fb = false
  local function pick(v, fallback)
    if positive(v) then return v + pad end
    fb = true
    return fallback
  end
  local widths = {
    source = pick(m.source, S.rowSourceW),
    tag = pick(m.tag, S.rowTagW),
    amount = pick(m.amount, S.rowVendorColW),
    qty = pick(m.qtyWorst, S.rowQtyW),
  }
  return widths, fb
end

-- Gap between an amount and its source tag: rowLabelGap plus the overhang of
-- an outlined text (Theme.sizes.textOverhang, 0 without an outline).
function Rows.labelGap()
  local S = ns.Theme.sizes
  return S.rowLabelGap + (S.textOverhang or 0)
end

-- WORST-CASE geometry, used only for the window's minimum width: `measured` =
-- {source, tag, amount, qtyWorst} real widths of the worst case strings (source:
-- the widest source tag with its frame; nil/0 fields use the Theme fallbacks).
-- The worst-case block is widest amount + gap + source tag + tag gap + age tag;
-- `required` = rowNameMin + gap +
-- blockW (the width of the row content that always fits). The rows themselves
-- are laid out with the adaptive Rows.blockLayout.
function Rows.worstCase(measured)
  local S = ns.Theme.sizes
  local wd, fallback = resolveWidths(measured)
  local labelW = wd.source
  local blockW = wd.amount + Rows.labelGap() + labelW + S.rowTagGap + wd.tag
  return {
    required = S.rowNameMin + S.rowNameGap + blockW,
    fallback = fallback,
    blockW = blockW,
    labelW = labelW,
    amountW = wd.amount,
    tagW = wd.tag,
    qtyW = wd.qty,
  }
end

-- Adaptive right block for the rows currently rendered: the amount column, the
-- source tag column right of it, then the age tag. Inputs are RAW measured
-- widths (no padding): sourceW = widest source tag (with its frame), amountMaxW
-- = widest amount among the rendered rows, tagMaxW = widest age tag (nil/0 = no
-- rendered row shows a tag: no tag width and no tag gap). nil/0 widths use the
-- Theme fallbacks. The block's right edge is always contentWidth (flush right);
-- it grows leftwards with longer amounts, but never so far that the name column
-- drops below rowNameMin (then the amount clips on the right).
-- Returns {blockW, blockX, amountX, amountW, labelX (source tag), labelW,
-- nameX, nameW, tagGap, tagW, rightEdge}.
function Rows.blockLayout(contentWidth, sourceW, amountMaxW, tagMaxW)
  local S = ns.Theme.sizes
  local pad = S.rowMeasurePad
  local labelW = positive(sourceW) and sourceW + pad or S.rowSourceW
  local amountW = positive(amountMaxW) and amountMaxW + pad or S.rowVendorColW
  local hasTag = positive(tagMaxW)
  local tagW = hasTag and tagMaxW + pad or 0
  local tagGap = hasTag and S.rowTagGap or 0
  local blockW = amountW + Rows.labelGap() + labelW + tagGap + tagW
  local gap = S.rowNameGap
  local w = contentWidth
  if not positive(w) then w = S.rowNameMin + gap + blockW end
  blockW = math.min(blockW, math.max(0, w - S.rowNameMin - gap))
  local blockX = w - blockW
  return {
    rightEdge = w,
    blockW = blockW,
    blockX = blockX,
    amountX = blockX,
    amountW = amountW,
    labelX = blockX + amountW + Rows.labelGap(),
    labelW = labelW,
    nameX = 0,
    nameW = math.max(0, blockX - gap),
    tagGap = tagGap,
    tagW = tagW,
  }
end

-- Width of a row's framed source tag box: the widest tag (`sourceW`, measured
-- with its frame) for every row, so the boxes line up and the texts sit
-- centered; before that is measured, the own text (`textW`) plus the frame.
function Rows.sourceBoxWidth(sourceW, textW)
  local S = ns.Theme.sizes
  local own = (positive(textW) and textW or S.rowSourceW) + 2 * S.rowTagPad
  if positive(sourceW) then return math.max(sourceW, own) end
  return own
end

local function round(v) return math.floor(v + 0.5) end

-- Geometry of a source tag box in whole screen pixels, for a tag font of
-- `fontPx` pixels: { height, textTop (the text line's offset from the box
-- top) }. The box is the font plus rowTagPadY (+ tagPadExtra with an
-- outline) px above and below, one pixel
-- taller when the letters (rowTagCapRatio of the font; the tags have no
-- descenders) would otherwise sit half a pixel off the middle. nil without a
-- font size.
function Rows.sourceBoxPixels(fontPx)
  if not positive(fontPx) then return nil end
  local S = ns.Theme.sizes
  local h = round(fontPx) + 2 * (S.rowTagPadY + (S.tagPadExtra or 0))
  local letters = round(fontPx * S.rowTagCapRatio)
  if (h - letters) % 2 == 1 then h = h + 1 end
  return { height = h, textTop = round((h - fontPx) / 2) }
end
-- Width of the name FontString: its natural width, but at most what is left
-- of the name column once the quantity (and its gap) is reserved, so a long
-- name is clipped (ellipsis) and the quantity stays visible.
function Rows.nameFit(nameColW, qtyW, natural)
  local avail = math.max(1, (nameColW or 0) - (qtyW or 0) - ns.Theme.sizes.rowQtyGap)
  if positive(natural) then return math.min(natural + 1, avail) end
  return avail
end

-- Left inset of a row's text: after the icon, or near the left edge when the
-- option "showIcons" is off.
function Rows.showIcons()
  return ns.Util.setting("showIcons", true)
end

function Rows.textLeft()
  local S = ns.Theme.sizes
  if not Rows.showIcons() then return S.rowTextLeftNoIcon end
  return S.rowIconInset + S.iconSize + S.rowIconGap
end

-- Window width needed so the row fits with the measured font: row content
-- width + text inset + right inset + window chrome.
function Rows.requiredRowWidth(measured)
  local S = ns.Theme.sizes
  local c = Rows.worstCase(measured)
  return c.required + Rows.textLeft() + S.rowRightInset + S.rowChrome
end

-- How many whole rows fit in `height` (at least 1).
function Rows.visibleCount(height, rowHeight)
  if type(height) ~= "number" or height ~= height then return 1 end
  return math.max(1, math.floor(height / rowHeight))
end

-- Keeps a 0-based scroll offset inside [0, total - visible].
function Rows.clampOffset(offset, total, visible)
  if type(offset) ~= "number" or offset ~= offset then return 0 end
  local maxOffset = math.max(0, total - visible)
  if offset < 0 then return 0 end
  if offset > maxOffset then return maxOffset end
  return math.floor(offset)
end

-- Smallest offset change that brings the 1-based `index` into view.
function Rows.offsetFor(index, offset, visible, total)
  if type(index) ~= "number" then return Rows.clampOffset(offset, total, visible) end
  if index <= offset then
    offset = index - 1
  elseif index > offset + visible then
    offset = index - visible
  end
  return Rows.clampOffset(offset, total, visible)
end

-- ---------------------------------------------------------------------------
-- Client-only

local function theme() return ns.Theme end

-- Pure. What the item tooltip shows: the row's real item link, or an item
-- string built from the id when no link is known; nil for an unusable row.
function Rows.tooltipLink(row)
  if type(row) ~= "table" then return nil end
  if type(row.link) == "string" and row.link ~= "" then return row.link end
  if type(row.id) == "number" and row.id > 0 then
    return (row.isCurrency and "currency:" or "item:") .. row.id
  end
  return nil
end

-- The item tooltip of the row, or its hint text (History rows) without an item.
-- Item tooltip plus the row's values (Rows.tooltipLines), else the row hint.
local function showTooltip(f)
  local W = ns.UI.Widgets
  if W.showItemTooltip(f, f.tooltipLink) then
    local lines = f.tooltipLines
    if GameTooltip and lines and #lines > 0 then
      local c = ns.Theme.colors.tipValue
      for _, line in ipairs(lines) do GameTooltip:AddLine(line, c[1], c[2], c[3]) end
      GameTooltip:Show()
    end
    return true
  end
  return W.showTextTooltip(f, f.tooltipText)
end

-- A modified click (Shift: link in chat, Ctrl: try on, as the game's bags)
-- on a real item or currency link. Returns whether the game handled it.
function Rows.modifiedClick(link)
  if type(link) ~= "string" or link == "" then return false end
  if type(IsModifiedClick) ~= "function" or not IsModifiedClick() then return false end
  if type(HandleModifiedItemClick) ~= "function" then return false end
  return HandleModifiedItemClick(link) and true or false
end

local function itemIcon(itemID)
  local icon
  if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
  return icon or QUESTION_MARK
end

-- Through Widgets when loaded, so a color option recolors the text live.
local function setColor(fs, c)
  local W = ns.UI.Widgets
  if W and W.setTextColor then W.setTextColor(fs, c) else fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function setRGB(fs, r, g, b)
  local W = ns.UI.Widgets
  if W and W.setTextRGB then W.setTextRGB(fs, r, g, b, 1) else fs:SetTextColor(r, g, b, 1) end
end

local NONE = {}

-- Framed source tag (Vendor / Auction / Destroy) of the list rows and the
-- compact drops: four edges in the source color and the text centered both
-- ways. Every size and offset is whole screen pixels, so once the box itself
-- is placed with Widgets.snapPoint every edge is equally thin. Shown with
-- Rows.setSourceTag.
function Rows.sourceTag(parent)
  local T, W = theme(), ns.UI.Widgets
  local box = CreateFrame("Frame", nil, parent)
  box.edges = {}
  -- The edges draw above the text, so a thick outline never hides them.
  for i = 1, 4 do
    local edge = W.line(box, T.colors.ink, "OVERLAY", T.alphas.sourceTagEdge)
    if edge.SetDrawLayer then edge:SetDrawLayer("OVERLAY", 7) end
    box.edges[i] = edge
  end
  box.edgePx, box.textTop = false, false
  local text = box:CreateFontString(nil, "OVERLAY", T.fonts.sourceTag)
  text:SetJustifyH("CENTER")
  text:SetJustifyV("TOP")
  text:SetWordWrap(false)
  box.text = text
  return box
end

-- Anchors the four edges again when their thickness changed.
local function placeEdges(box, px)
  if box.edgePx == px then return end
  box.edgePx = px
  local top, bottom, left, right = box.edges[1], box.edges[2], box.edges[3], box.edges[4]
  top:ClearAllPoints()
  top:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  top:SetHeight(px)
  bottom:ClearAllPoints()
  bottom:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(px)
  -- The sides run between the top and bottom edge, so no corner is drawn twice.
  left:ClearAllPoints()
  left:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -px)
  left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, px)
  left:SetWidth(px)
  right:ClearAllPoints()
  right:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -px)
  right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, px)
  right:SetWidth(px)
end

-- The natural width of a FontString's text, also when its box is narrower.
local function textWidth(fs)
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if positive(w) then return w end
  return fs:GetStringWidth()
end

-- Shows the tag of `source` ("vendor" / "ah" / "de") in its color, as wide as
-- `widest` (the widest tag with its frame, so tags line up; nil = its own
-- width). Hidden (1 px wide) without a source.
function Rows.setSourceTag(box, source, widest)
  local text = source and SOURCE_TEXT[source]
  if not text then
    box:SetWidth(1)
    box:Hide()
    return
  end
  local T, W = theme(), ns.UI.Widgets
  local S = T.sizes
  local c = T.colors[SOURCE_COLOR[source]] or T.colors.ink
  box.text:SetText(text)
  W.setTextColor(box.text, c)
  for _, edge in ipairs(box.edges) do W.setLineColor(edge, c, T.alphas.sourceTagEdge) end
  -- p = one screen pixel in UI units (1 when unknown: then all in units).
  local p = W.pixelSize(box) or 1
  placeEdges(box, math.max(1, round(S.rowTagEdge / p)) * p)
  local _, size = box.text:GetFont()
  local g = Rows.sourceBoxPixels(positive(size) and size / p or nil)
  local height = g and g.height * p or S.rowTagHeight
  local width = math.ceil(Rows.sourceBoxWidth(widest, textWidth(box.text)) / p - 0.01) * p
  box:SetSize(width, height)
  -- The text line across the box at a whole pixel offset from its top, moved
  -- right by tagTextShift px with an outline (the client centers outlined
  -- text a little too far left).
  local top = g and g.textTop * p or 0
  local shift = (S.tagTextShift or 0) * p
  local key = top .. ":" .. shift
  if box.textTop ~= key then
    box.textTop = key
    box.text:ClearAllPoints()
    box.text:SetPoint("TOPLEFT", box, "TOPLEFT", shift, -top)
    box.text:SetPoint("TOPRIGHT", box, "TOPRIGHT", shift, -top)
    if not g then box.text:SetPoint("BOTTOM", box, "BOTTOM", 0, 0) end
    box.text:SetJustifyV(g and "TOP" or "MIDDLE")
  end
  box:Show()
end

local function validWidth(w)
  return type(w) == "number" and w > 0
end

-- Rows.blockLayout for a row of width `w`, from the current block measurement
-- of the list (widest amount / tag of the rendered rows).
local function blockFor(owner, w)
  local S = theme().sizes
  local m = owner.measured or NONE
  local bm = owner.blockMeasure or NONE
  return Rows.blockLayout(w - Rows.textLeft() - S.rowRightInset,
    m.source, bm.amount, bm.tag)
end

-- Anchors `region` by one point at (x, y) from the same point of `f`.
local function place(region, f, point, x, y)
  region:ClearAllPoints()
  region:SetPoint(point, f, point, x, y)
end

-- Places the FontStrings of a row. `block` is the shared Rows.blockLayout
-- result when the list lays out all rows at once; a row that is resized on its
-- own computes it.
local function layoutRow(f, block)
  local w = f:GetWidth()
  if not validWidth(w) then return end
  local S = theme().sizes
  local owner = f.owner or NONE
  local c = block or blockFor(owner, w)
  local x0, inset = Rows.textLeft(), S.rowLineInset

  -- Name and quantity share the left column; the quantity always stays visible.
  place(f.name, f, "TOPLEFT", x0 + c.nameX, -inset)
  f.name:SetWidth(0) -- auto width, to read the natural text width
  local qtyW = f.qty:GetStringWidth()
  if not positive(qtyW) then
    local m = owner.measured or NONE
    qtyW = m.qtyWorst and m.qtyWorst + S.rowMeasurePad or S.rowQtyW
  end
  f.name:SetWidth(Rows.nameFit(c.nameW, qtyW, f.name:GetStringWidth()))
  f.qty:ClearAllPoints()
  f.qty:SetPoint("LEFT", f.name, "RIGHT", S.rowQtyGap, 0)
  -- Line 2 of the name column: the sale info, clipped to the column.
  place(f.market, f, "BOTTOMLEFT", x0 + c.nameX, inset)
  f.market:SetWidth(math.max(1, c.nameW))

  -- Right block, top line: the counted value (right-aligned in its column),
  -- its framed source tag, then the age tag or the "?" mark.
  place(f.amount, f, "TOPLEFT", x0 + c.amountX, -inset)
  f.amount:SetWidth(math.max(1, c.amountW))
  -- On whole screen pixels, so its frame is equally thin on every row.
  ns.UI.Widgets.snapPoint(f.srcBox, "LEFT", f.amount, "RIGHT", Rows.labelGap(), 0)
  f.tag:ClearAllPoints()
  f.tag:SetPoint("LEFT", f.srcBox, "RIGHT", c.tagGap > 0 and c.tagGap or S.rowTagGap, 0)
end

local function createRow(parent, owner)
  local T = theme()
  local f = CreateFrame("Frame", nil, parent)
  f.owner = owner
  f:SetHeight(T.sizes.rowHeight)

  local flash = f:CreateTexture(nil, "BACKGROUND")
  flash:SetAllPoints(f)
  flash:SetTexture(T.textures.rowHighlight)
  flash:Hide()
  local ag = flash:CreateAnimationGroup()
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0)
  fade:SetSmoothing("OUT")
  ag:SetScript("OnFinished", function() flash:Hide() end)
  f.flash, f.flashGroup, f.flashFade = flash, ag, fade

  -- Separator inside the bottom pixel row (no extra height); hidden on the last row.
  local sep = f:CreateTexture(nil, "BORDER")
  sep:SetTexture(T.textures.rowHighlight)
  local sc = T.colors.rowSeparator
  sep:SetVertexColor(sc[1], sc[2], sc[3], sc[4])
  sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", T.sizes.rowSeparatorInset, 0)
  sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.separator = sep

  local border = f:CreateTexture(nil, "ARTWORK")
  border:SetSize(T.sizes.iconSize, T.sizes.iconSize)
  border:SetPoint("LEFT", f, "LEFT", T.sizes.rowIconInset, 0)
  border:SetColorTexture(1, 1, 1, 1)
  local icon = f:CreateTexture(nil, "OVERLAY")
  icon:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.iconBorder, f.icon = border, icon

  local name = f:CreateFontString(nil, "OVERLAY", T.fonts.body)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)

  local qty = f:CreateFontString(nil, "OVERLAY", T.fonts.body)
  qty:SetJustifyH("LEFT")
  qty:SetWordWrap(false)
  setColor(qty, T.colors.ink)

  -- Auto-width, left-justified (the tag anchors to the AH amount's right end).
  local function line2()
    local fs = f:CreateFontString(nil, "OVERLAY", T.fonts.rowSmall)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    setColor(fs, T.colors.ink)
    return fs
  end
  local tag = line2()
  -- The value in coin columns (UI/Coins.lua), lined up with the other rows.
  local amount = ns.UI.Coins.new(f, T.fonts.rowSmall, T.colors.ink)
  f.market = line2()

  -- Framed source tag (Vendor / Auction / Destroy).
  f.srcBox = Rows.sourceTag(f)

  f.name, f.qty, f.amount, f.tag = name, qty, amount, tag
  f:SetScript("OnSizeChanged", function(self) layoutRow(self) end)

  -- Item tooltip while the mouse is over the row.
  f:EnableMouse(true)
  f:SetScript("OnEnter", showTooltip)
  -- Shift / Ctrl-click: the game's link-in-chat / try-on; otherwise History
  -- and Zones rows open (list.onRowClick is set by the controller).
  f:SetScript("OnMouseUp", function(self, button)
    if not self.row or Rows.modifiedClick(self.row.link) then return end
    local o = self.owner
    if o and o.onRowClick then o.onRowClick(self.row, button, self) end
  end)
  f:SetScript("OnLeave", ns.UI.Widgets.hideTooltip)
  return f
end

local function stopFlash(f)
  f.flashGroup:Stop()
  f.flash:Hide()
end

local function fillRow(f, row)
  local T = theme()
  local t = textOf(row)
  local r, g, b = T.qualityColor(row.quality)
  f.name:SetText(t.name)
  -- History day / week headings: the titles color.
  if row.isHeading then setColor(f.name, T.colors.gold) else setRGB(f.name, r, g, b) end
  f.qty:SetText(t.qty)
  ns.UI.Coins.set(f.amount, t.copper, t.amount)
  f.market:SetText(t.market or "")
  setColor(f.market, t.isDetail and T.colors.hint or T.colors.ink)
  -- Source tag: framed, in its source color, as wide as the widest tag (the
  -- boxes line up); hidden without a source.
  Rows.setSourceTag(f.srcBox, t.source, ((f.owner and f.owner.measured) or NONE).source)
  -- After the tag: the age of a cached AH value, else "?" on an unpriced row.
  local tagText = t.tag or (t.unpriced and t.source and TEXT.UNPRICED) or nil
  f.tag:SetText(tagText or "")
  f.hasTag = tagText ~= nil
  setColor(f.tag, (t.tagStale and T.colors.stale) or (t.tag == nil and t.unpriced and T.colors.marketOk) or T.colors.ink)
  local icons = Rows.showIcons()
  f.iconBorder:SetShown(icons)
  f.icon:SetShown(icons)
  if icons then
    f.iconBorder:SetColorTexture(r, g, b, 1)
    f.icon:SetTexture(row.icon or (row.isCurrency and QUESTION_MARK) or itemIcon(row.id))
  end
  f.row = row
  f.tooltipLink = Rows.tooltipLink(row)
  f.tooltipLines = Rows.tooltipLines(row)
  f.tooltipText = row.hint
  -- A hovered row that now shows another item (or fresh data) updates its tooltip.
  local W = ns.UI.Widgets
  if W.tooltipOwnedBy(f) then
    if f.tooltipLink then showTooltip(f) else W.hideTooltip() end
  end
end

-- Takes a pooled row frame out of use.
local function releaseRow(f)
  f.rowKey = nil
  stopFlash(f)
  f:Hide()
end

-- Attaches the scrolling list to `area`. Returns the list object.
-- `onMeasure(measured)` is called whenever a re-measure changes the widths.
function Rows.attach(area, onMeasure)
  local T = theme()
  local list = { area = area, data = {}, offset = 0, pool = {}, shown = 0,
    blockMeasure = { amount = 0, tag = 0 } }

  -- Offscreen probes with the same font objects as the row's texts.
  local probe = area:CreateFontString(nil, "OVERLAY", T.fonts.rowSmall)
  probe:SetAlpha(0)
  probe:SetWordWrap(false)
  local qtyProbe = area:CreateFontString(nil, "OVERLAY", T.fonts.body)
  qtyProbe:SetAlpha(0)
  qtyProbe:SetWordWrap(false)
  local srcProbe = area:CreateFontString(nil, "OVERLAY", T.fonts.sourceTag)
  srcProbe:SetAlpha(0)
  srcProbe:SetWordWrap(false)
  local function width(text, p)
    p = p or probe
    p:SetText(text)
    local w = p:GetStringWidth()
    if positive(w) then return w end
    return nil
  end
  -- Widest of several texts; nil while any of them cannot be measured.
  local function widest(p, ...)
    local best = 0
    for i = 1, select("#", ...) do
      local w = width((select(i, ...)), p)
      if not w then return nil end
      if w > best then best = w end
    end
    return best
  end

  -- Measures the real string widths; fields stay nil while the font is not
  -- ready (the layout then uses the Theme fallbacks and Render retries).
  function list:Measure()
    local srcW = widest(srcProbe, SOURCE_TEXT.vendor, SOURCE_TEXT.ah, SOURCE_TEXT.de)
    local m = {
      -- The widest source tag with its frame, so the tags line up.
      source = srcW and srcW + 2 * T.sizes.rowTagPad or nil,
      tag = width(SAMPLE_TAG),
      amount = width(ns.Money.format(SAMPLE_AMOUNT)),
      qtyWorst = width(SAMPLE_QTY, qtyProbe),
    }
    local old = self.measured
    self.measured = m
    -- The compact drops line their tags up with the same width.
    Rows.widestSource = m.source
    self.measureFallback = not (m.source and m.tag and m.amount and m.qtyWorst)
    local changed = old and (old.source ~= m.source
      or old.tag ~= m.tag or old.amount ~= m.amount or old.qtyWorst ~= m.qtyWorst)
    if changed and onMeasure then onMeasure(m) end
    return m
  end
  list:Measure()

  local content = CreateFrame("Frame", nil, area)
  content:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -T.sizes.scrollbarWidth - 2, 0)
  list.content = content

  -- What an empty list says (view.empty), centered in the list area.
  local emptyText = area:CreateFontString(nil, "OVERLAY", T.fonts.small)
  emptyText:SetPoint("LEFT", area, "LEFT", 12, 0)
  emptyText:SetPoint("RIGHT", area, "RIGHT", -12, 0)
  emptyText:SetJustifyH("CENTER")
  emptyText:SetWordWrap(true)
  setColor(emptyText, T.colors.hint)
  emptyText:Hide()
  list.emptyText = emptyText
  list.empty = false

  local bar = CreateFrame("Slider", nil, area)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(T.sizes.scrollbarWidth)
  bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", -1, -1)
  bar:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 1)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(bar)
  local tc = T.colors.scrollTrack
  track:SetColorTexture(tc[1], tc[2], tc[3], tc[4])
  bar:SetThumbTexture(T.textures.rowHighlight)
  local thumb = bar:GetThumbTexture()
  thumb:SetSize(T.sizes.scrollbarWidth, T.sizes.scrollThumbHeight)
  local thc = T.colors.scrollThumb
  thumb:SetVertexColor(thc[1], thc[2], thc[3], thc[4])
  bar:Hide()
  list.bar = bar

  local function visible() return Rows.visibleCount(area:GetHeight(), T.sizes.rowHeight) end

  -- Height and place of the pooled row frame at list position `i`.
  local function placeRow(f, i)
    local y = -(i - 1) * T.sizes.rowHeight
    f:SetHeight(T.sizes.rowHeight)
    -- Whole screen pixels: every separator equally thin.
    f.separator:SetHeight(ns.UI.Widgets.pixels(f, T.sizes.rowSeparator))
    f.iconBorder:SetSize(T.sizes.iconSize, T.sizes.iconSize)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
  end

  -- The pooled row frame for list position `i`, created on first use.
  local function rowFrame(i)
    local f = list.pool[i]
    if not f then
      f = createRow(content, list)
      placeRow(f, i)
      list.pool[i] = f
    end
    return f
  end

  -- Theme.sizes or the fonts changed: measure again (onMeasure updates the
  -- window minimum), give every pooled row its new height and place, redraw.
  function list:Relayout()
    self:Measure()
    if onMeasure then onMeasure(self.measured) end
    for i, f in ipairs(self.pool) do
      placeRow(f, i)
      -- A FontString given the same text again may keep its old width; empty
      -- texts make the redraw measure them in the new font (an outline).
      for _, fs in ipairs({ f.name, f.qty, f.tag, f.market, f.srcBox.text }) do fs:SetText("") end
      ns.UI.Coins.clear(f.amount)
    end
    self:Render()
  end

  function list:Render()
    if self.measureFallback then self:Measure() end
    local n = visible()
    local total = #self.data
    self.offset = Rows.clampOffset(self.offset, total, n)
    local filled = math.min(n, total - self.offset) -- rows that show data

    -- Pass 1: fill the rows and find the widest age tag among them; the
    -- amounts are laid out together in coin columns (their width).
    local tagMax = 0
    local cells = {}
    for i = 1, filled do
      local f = rowFrame(i)
      local row = self.data[self.offset + i]
      local key = row.key or row.id
      if f.rowKey ~= key then stopFlash(f) end
      f.rowKey = key
      fillRow(f, row)
      f.separator:SetShown(self.offset + i < total)
      f:Show()
      cells[i] = f.amount
      if f.hasTag then
        local tw = f.tag:GetStringWidth() or 0
        if tw <= 0 then tw = T.sizes.rowTagW end
        if tw > tagMax then tagMax = tw end
      end
    end

    -- Pass 2: one shared block layout for every rendered row.
    local amountMax = ns.UI.Coins.align(cells)
    self.blockMeasure.amount, self.blockMeasure.tag = amountMax, tagMax
    if filled > 0 then
      local w = self.pool[1]:GetWidth()
      local block = validWidth(w) and blockFor(self, w) or nil
      for i = 1, filled do layoutRow(self.pool[i], block) end
    end

    for i = filled + 1, #self.pool do releaseRow(self.pool[i]) end
    self.shown = n

    local maxOffset = math.max(0, total - n)
    self.syncing = true
    bar:SetMinMaxValues(0, maxOffset)
    bar:SetValue(self.offset)
    self.syncing = false
    bar:SetShown(maxOffset > 0)
    local say = total == 0 and self.empty
    if say then emptyText:SetText(say) end
    emptyText:SetShown(say and true or false)
  end

  -- `empty`: the text shown while `rows` is empty (none when nil).
  function list:SetData(rows, empty)
    self.data = rows or {}
    self.empty = type(empty) == "string" and empty or false
    self:Render()
  end

  function list:SetOffset(offset)
    self.offset = offset
    self:Render()
  end

  -- `key` is the row key (LootParse.itemKey).
  function list:ScrollToItem(key)
    local idx = ns.View.indexOf(self.data, key)
    if not idx then return end
    local offset = Rows.offsetFor(idx, self.offset, visible(), #self.data)
    if offset == self.offset then return end -- already in view
    self.offset = offset
    self:Render()
  end

  -- Items scrolled out of view have no frame: ignored.
  function list:Flash(key, level)
    local c = (level == "strong") and T.colors.flashStrong or T.colors.flashNormal
    for i = 1, self.shown do
      local f = self.pool[i]
      if f and f:IsShown() and f.rowKey == key then
        f.flashGroup:Stop()
        f.flash:SetColorTexture(c[1], c[2], c[3], c[4])
        f.flashFade:SetDuration(level == "strong" and T.durations.flashStrong or T.durations.flashNormal)
        f.flash:Show()
        f.flashGroup:Play()
      end
    end
  end

  area:EnableMouseWheel(true)
  area:SetScript("OnMouseWheel", function(_, delta)
    list:SetOffset(list.offset - delta * WHEEL_STEP)
  end)
  bar:SetScript("OnValueChanged", function(_, value)
    if list.syncing then return end
    value = math.floor(value + 0.5)
    if value ~= list.offset then list:SetOffset(value) end
  end)
  area:HookScript("OnSizeChanged", function() list:Render() end)
  area:HookScript("OnShow", function() list:Render() end)

  list:Render()
  return list
end
