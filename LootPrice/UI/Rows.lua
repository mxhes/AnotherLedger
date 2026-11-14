local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Scrolling item rows with a pooled set of row frames and a loot flash.
-- Client-only parts touch WoW globals inside functions only; the helpers at
-- the top (rowText, visibleCount, clampOffset, offsetFor) are pure.
local Rows = {}
ns.UI.Rows = Rows

-- User-visible strings (translated through ns.L, Locale.lua).
local L = {
  VENDOR = ns.L["Vendor: "],
  AH = ns.L["AH: "],
  DE = ns.L["DE: "],
  QTY = ns.L["x"],
  BOUND = ns.L["bound"],
}

local WHEEL_STEP = 2
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark

-- ---------------------------------------------------------------------------
-- Pure helpers

-- The fixed labels of the right block (set once per row frame).
Rows.LABELS = { vendor = L.VENDOR, ah = L.AH }

-- The texts one row shows. `formatMoney` defaults to the colored coin format
-- (Money.formatColored); the tests pass Money.format for plain text.
function Rows.rowText(row, formatMoney)
  formatMoney = formatMoney or ns.Money.formatColored
  local tag, tagStale = nil, false
  if row.ahFromCache and type(row.ahAge) == "number" then
    tag = "(" .. ns.Prices.formatAge(row.ahAge) .. ")"
    tagStale = row.stale and true or false
  end
  local qty = L.QTY .. tostring(row.quantity or 0)
  -- Currencies have a quantity only: no amounts and no labels.
  if row.isCurrency then
    return { name = row.name or "", qty = qty, vendorLabel = "", ahLabel = "", vendorAmount = "",
      ahAmount = "", deLabel = "", deAmount = "", tag = nil, tagStale = false }
  end
  local hasDE = row.deTotal ~= nil
  local ahAmount = formatMoney(row.ahTotal)
  -- A bound item cannot be sold on the AH: say so instead of "n/a".
  if row.ahTotal == nil and row.bound then ahAmount = L.BOUND end
  return {
    name = row.name or "",
    qty = qty,
    vendorLabel = L.VENDOR, ahLabel = L.AH,
    vendorAmount = formatMoney(row.vendorTotal),
    ahAmount = ahAmount,
    -- Disenchant line: empty for items that cannot be disenchanted.
    deLabel = hasDE and (row.deLabel or L.DE) or "",
    deAmount = hasDE and formatMoney(row.deTotal) or "",
    -- Which line holds the row's value (its label is highlighted).
    best = row.bestKind,
    tag = tag,
    tagStale = tagStale,
  }
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
local SAMPLE_AMOUNT = "123456g 78s 90c"
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
    vendorLabel = pick(m.vendorLabel, S.rowVendorLabelW),
    ahLabel = pick(m.ahLabel, S.rowAhLabelW),
    tag = pick(m.tag, S.rowTagW),
    amount = pick(m.amount, S.rowVendorColW),
    qty = pick(m.qtyWorst, S.rowQtyW),
  }
  return widths, fb
end

-- WORST-CASE geometry, used only for the window's minimum width: `measured` =
-- {vendorLabel, ahLabel, tag, amount, qtyWorst} real string widths of the worst
-- case strings (nil/0 fields use the Theme fallbacks). The worst-case block is
-- labels + gap + widest amount + tag gap + tag; `required` = rowNameMin + gap +
-- blockW (the width of the row content that always fits). The rows themselves
-- are laid out with the adaptive Rows.blockLayout.
function Rows.worstCase(measured)
  local S = ns.Theme.sizes
  local wd, fallback = resolveWidths(measured)
  local labelW = math.max(wd.vendorLabel, wd.ahLabel)
  local blockW = labelW + S.rowLabelGap + wd.amount + S.rowTagGap + wd.tag
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

-- Adaptive right block for the rows currently rendered. Inputs are RAW measured
-- widths (no padding): labelsW = widest label, amountMaxW = widest vendor/AH
-- amount among the rendered rows, tagMaxW = widest age tag (nil/0 = no rendered
-- row shows a tag: no tag width and no tag gap). nil/0 labels or amounts use the
-- Theme fallbacks. The block's right edge is always contentWidth (flush right);
-- it grows leftwards with longer amounts, but never so far that the name column
-- drops below rowNameMin (then the amount clips on the right).
-- Returns {blockW, blockX, labelX, amountX, nameX, nameW, tagGap, tagW, rightEdge}.
function Rows.blockLayout(contentWidth, labelsW, amountMaxW, tagMaxW)
  local S = ns.Theme.sizes
  local pad = S.rowMeasurePad
  local labelW = positive(labelsW) and labelsW + pad or math.max(S.rowVendorLabelW, S.rowAhLabelW)
  local amountW = positive(amountMaxW) and amountMaxW + pad or S.rowVendorColW
  local hasTag = positive(tagMaxW)
  local tagW = hasTag and tagMaxW + pad or 0
  local tagGap = hasTag and S.rowTagGap or 0
  local amountOff = labelW + S.rowLabelGap
  local blockW = amountOff + amountW + tagGap + tagW
  local gap = S.rowNameGap
  local w = contentWidth
  if not positive(w) then w = S.rowNameMin + gap + blockW end
  blockW = math.min(blockW, math.max(0, w - S.rowNameMin - gap))
  local blockX = w - blockW
  return {
    rightEdge = w,
    blockW = blockW,
    blockX = blockX,
    labelX = blockX,
    amountX = blockX + amountOff,
    nameX = 0,
    nameW = math.max(0, blockX - gap),
    tagGap = tagGap,
    tagW = tagW,
  }
end

-- Width of the name FontString: its natural width, but at most what is left
-- of the name column once the quantity (and its gap) is reserved, so a long
-- name is clipped (ellipsis) and the quantity stays visible.
function Rows.nameFit(nameColW, qtyW, natural)
  local avail = math.max(1, (nameColW or 0) - (qtyW or 0) - ns.Theme.sizes.rowQtyGap)
  if positive(natural) then return math.min(natural + 1, avail) end
  return avail
end

-- Window width needed so the row fits with the measured font: row content
-- width + text inset + right inset + window chrome.
function Rows.requiredRowWidth(measured)
  local S = ns.Theme.sizes
  local c = Rows.worstCase(measured)
  return c.required + S.rowTextLeft + S.rowRightInset + S.rowChrome
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
local function showTooltip(f)
  local W = ns.UI.Widgets
  return W.showItemTooltip(f, f.tooltipLink) or W.showTextTooltip(f, f.tooltipText)
end

local function itemIcon(itemID)
  local icon
  -- UNVERIFIED (check in client): C_Item.GetItemIconByID exists on Forever.
  if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
  return icon or QUESTION_MARK
end

local function setColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local NONE = {}

local function validWidth(w)
  return type(w) == "number" and w > 0
end

-- Rows.blockLayout for a row of width `w`, from the current block measurement
-- of the list (widest amount / tag of the rendered rows).
local function blockFor(owner, w)
  local S = theme().sizes
  local m = owner.measured or NONE
  local bm = owner.blockMeasure or NONE
  return Rows.blockLayout(w - S.rowTextLeft - S.rowRightInset,
    math.max(m.vendorLabel or 0, m.ahLabel or 0), bm.amount, bm.tag)
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
  local x0, inset = S.rowTextLeft, S.rowLineInset

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

  -- Right block: vendor on the top line, AH on the bottom line, DE between.
  local labelX, amountX = x0 + c.labelX, x0 + c.amountX
  place(f.vendorLabel, f, "TOPLEFT", labelX, -inset)
  place(f.vendor, f, "TOPLEFT", amountX, -inset)
  place(f.ahLabel, f, "BOTTOMLEFT", labelX, inset)
  place(f.ah, f, "BOTTOMLEFT", amountX, inset)
  local midY = -f:GetHeight() / 2
  f.deLabel:ClearAllPoints()
  f.deLabel:SetPoint("LEFT", f, "TOPLEFT", labelX, midY)
  f.de:ClearAllPoints()
  f.de:SetPoint("LEFT", f, "TOPLEFT", amountX, midY)
  f.tag:ClearAllPoints()
  f.tag:SetPoint("LEFT", f.ah, "RIGHT", c.tagGap, 0)
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
  sep:SetHeight(T.sizes.rowSeparator)
  sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", T.sizes.rowSeparatorInset, 0)
  sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.separator = sep

  local border = f:CreateTexture(nil, "ARTWORK")
  border:SetSize(T.sizes.iconSize, T.sizes.iconSize)
  border:SetPoint("LEFT", f, "LEFT", 2, 0)
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
  local vendorLabel, vendor = line2(), line2()
  local ahLabel, ah, tag = line2(), line2(), line2()
  local deLabel, de = line2(), line2()
  vendorLabel:SetText(Rows.LABELS.vendor)
  ahLabel:SetText(Rows.LABELS.ah)
  f.vendorLabel, f.ahLabel, f.deLabel, f.de = vendorLabel, ahLabel, deLabel, de

  f.name, f.qty, f.vendor, f.ah, f.tag = name, qty, vendor, ah, tag
  f:SetScript("OnSizeChanged", function(self) layoutRow(self) end)

  -- Item tooltip while the mouse is over the row.
  f:EnableMouse(true)
  f:SetScript("OnEnter", showTooltip)
  -- History rows open their session (list.onRowClick is set by the controller).
  f:SetScript("OnMouseUp", function(self)
    local o = self.owner
    if o and o.onRowClick and self.row then o.onRowClick(self.row) end
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
  f.name:SetTextColor(r, g, b)
  f.qty:SetText(t.qty)
  f.vendorLabel:SetText(t.vendorLabel or "")
  f.ahLabel:SetText(t.ahLabel or "")
  setColor(f.vendorLabel, t.best == "vendor" and T.colors.best or T.colors.ink)
  setColor(f.ahLabel, t.best == "ah" and T.colors.best or T.colors.ink)
  setColor(f.deLabel, t.best == "de" and T.colors.best or T.colors.ink)
  f.vendor:SetText(t.vendorAmount)
  f.ah:SetText(t.ahAmount)
  f.deLabel:SetText(t.deLabel)
  f.de:SetText(t.deAmount)
  f.tag:SetText(t.tag or "")
  f.hasTag = t.tag ~= nil
  setColor(f.tag, t.tagStale and T.colors.stale or T.colors.ink)
  f.iconBorder:SetColorTexture(r, g, b, 1)
  f.icon:SetTexture(row.icon or (row.isCurrency and QUESTION_MARK) or itemIcon(row.id))
  f.row = row
  f.tooltipLink = Rows.tooltipLink(row)
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
  local function width(text, p)
    p = p or probe
    p:SetText(text)
    local w = p:GetStringWidth()
    if positive(w) then return w end
    return nil
  end

  -- Measures the real string widths; fields stay nil while the font is not
  -- ready (the layout then uses the Theme fallbacks and Render retries).
  function list:Measure()
    local m = {
      vendorLabel = width(L.VENDOR),
      ahLabel = width(L.AH),
      tag = width(SAMPLE_TAG),
      amount = width(SAMPLE_AMOUNT),
      qtyWorst = width(SAMPLE_QTY, qtyProbe),
    }
    local old = self.measured
    self.measured = m
    self.measureFallback = not (m.vendorLabel and m.ahLabel and m.tag and m.amount and m.qtyWorst)
    local changed = old and (old.vendorLabel ~= m.vendorLabel or old.ahLabel ~= m.ahLabel
      or old.tag ~= m.tag or old.amount ~= m.amount or old.qtyWorst ~= m.qtyWorst)
    if changed and onMeasure then onMeasure(m) end
    return m
  end
  list:Measure()

  local content = CreateFrame("Frame", nil, area)
  content:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -T.sizes.scrollbarWidth - 2, 0)
  list.content = content

  local bar = CreateFrame("Slider", nil, area)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(T.sizes.scrollbarWidth)
  bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", -1, -1)
  bar:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 1)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  -- UNVERIFIED (check in client): Slider SetObeyStepOnDrag / GetThumbTexture exist.
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

  -- The pooled row frame for list position `i`, created on first use.
  local function rowFrame(i)
    local f = list.pool[i]
    if not f then
      local y = -(i - 1) * T.sizes.rowHeight
      f = createRow(content, list)
      f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
      f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
      list.pool[i] = f
    end
    return f
  end

  function list:Render()
    if self.measureFallback then self:Measure() end
    local n = visible()
    local total = #self.data
    self.offset = Rows.clampOffset(self.offset, total, n)
    local filled = math.min(n, total - self.offset) -- rows that show data

    -- Pass 1: fill the rows and find the widest amount / tag among them.
    local amountMax, tagMax = 0, 0
    for i = 1, filled do
      local f = rowFrame(i)
      local row = self.data[self.offset + i]
      local key = row.key or row.id
      if f.rowKey ~= key then stopFlash(f) end
      f.rowKey = key
      fillRow(f, row)
      f.separator:SetShown(self.offset + i < total)
      f:Show()
      local aw = math.max(f.vendor:GetStringWidth() or 0, f.ah:GetStringWidth() or 0)
      if aw > amountMax then amountMax = aw end
      if f.hasTag then
        local tw = f.tag:GetStringWidth() or 0
        if tw <= 0 then tw = T.sizes.rowTagW end
        if tw > tagMax then tagMax = tw end
      end
    end

    -- Pass 2: one shared block layout for every rendered row.
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
  end

  function list:SetData(rows)
    self.data = rows or {}
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
