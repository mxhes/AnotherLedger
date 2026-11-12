local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Scrolling item rows with a pooled set of row frames and a loot flash.
-- Client-only parts touch WoW globals inside functions only; the helpers at
-- the top (rowText, visibleCount, clampOffset, offsetFor) are pure.
local Rows = {}
ns.UI.Rows = Rows

-- User-visible strings (single place to localize later).
local L = {
  VENDOR = "Vendor: ",
  AH = "AH: ",
  QTY = "x",
}

local WHEEL_STEP = 2
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark

-- ---------------------------------------------------------------------------
-- Pure helpers

function Rows.rowText(row)
  local tag, tagStale = nil, false
  if row.ahFromCache and type(row.ahAge) == "number" then
    tag = "(" .. ns.Prices.formatAge(row.ahAge) .. ")"
    tagStale = row.stale and true or false
  end
  return {
    name = row.name or "",
    qty = L.QTY .. tostring(row.quantity or 0),
    vendorText = L.VENDOR .. ns.Money.format(row.vendorTotal),
    ahText = L.AH .. ns.Money.format(row.ahTotal),
    tag = tag,
    tagStale = tagStale,
  }
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

local function itemIcon(itemID)
  local icon
  -- UNVERIFIED (check in client): C_Item.GetItemIconByID exists on Forever.
  if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
  return icon or QUESTION_MARK
end

local function setColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function createRow(parent)
  local T = theme()
  local f = CreateFrame("Frame", nil, parent)
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

  local border = f:CreateTexture(nil, "ARTWORK")
  border:SetSize(T.sizes.iconSize, T.sizes.iconSize)
  border:SetPoint("LEFT", f, "LEFT", 2, 0)
  border:SetColorTexture(1, 1, 1, 1)
  local icon = f:CreateTexture(nil, "OVERLAY")
  icon:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.iconBorder, f.icon = border, icon

  local qty = f:CreateFontString(nil, "OVERLAY", T.fonts.number)
  qty:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -3)
  qty:SetJustifyH("RIGHT")
  setColor(qty, T.colors.ink)

  local name = f:CreateFontString(nil, "OVERLAY", T.fonts.body)
  name:SetPoint("TOPLEFT", border, "TOPRIGHT", 5, 0)
  name:SetPoint("RIGHT", qty, "LEFT", -4, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)

  local tag = f:CreateFontString(nil, "OVERLAY", T.fonts.body)
  tag:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 3)
  tag:SetJustifyH("RIGHT")

  local ah = f:CreateFontString(nil, "OVERLAY", T.fonts.body)
  ah:SetPoint("BOTTOMRIGHT", tag, "BOTTOMLEFT", -3, 0)
  ah:SetJustifyH("RIGHT")
  setColor(ah, T.colors.ink)

  local vendor = f:CreateFontString(nil, "OVERLAY", T.fonts.body)
  vendor:SetPoint("BOTTOMLEFT", border, "BOTTOMRIGHT", 5, 0)
  vendor:SetJustifyH("LEFT")
  setColor(vendor, T.colors.ink)

  f.name, f.qty, f.vendor, f.ah, f.tag = name, qty, vendor, ah, tag
  return f
end

local function stopFlash(f)
  f.flashGroup:Stop()
  f.flash:Hide()
end

local function fillRow(f, row)
  local T = theme()
  local t = Rows.rowText(row)
  local r, g, b = T.qualityColor(row.quality, true)
  f.name:SetText(t.name)
  f.name:SetTextColor(r, g, b)
  f.qty:SetText(t.qty)
  f.vendor:SetText(t.vendorText)
  f.ah:SetText(t.ahText)
  f.tag:SetText(t.tag or "")
  setColor(f.tag, t.tagStale and T.colors.stale or T.colors.ink)
  local br, bg, bb = T.qualityColor(row.quality, false)
  f.iconBorder:SetColorTexture(br, bg, bb, 1)
  f.icon:SetTexture(itemIcon(row.id))
end

-- Attaches the scrolling list to `area`. Returns the list object.
function Rows.attach(area)
  local T = theme()
  local list = { area = area, data = {}, offset = 0, pool = {}, shown = 0 }

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

  function list:Render()
    local n = visible()
    local total = #self.data
    self.offset = Rows.clampOffset(self.offset, total, n)
    for i = 1, n do
      local f = self.pool[i]
      if not f then
        f = createRow(content)
        f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * T.sizes.rowHeight)
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * T.sizes.rowHeight)
        self.pool[i] = f
      end
      local row = self.data[self.offset + i]
      if row then
        if f.itemID ~= row.id then stopFlash(f) end
        f.itemID = row.id
        fillRow(f, row)
        f:Show()
      else
        f.itemID = nil
        stopFlash(f)
        f:Hide()
      end
    end
    for i = n + 1, #self.pool do
      local f = self.pool[i]
      f.itemID = nil
      stopFlash(f)
      f:Hide()
    end
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

  function list:ScrollToItem(itemID)
    local idx = ns.View.indexOf(self.data, itemID)
    if not idx then return end
    self.offset = Rows.offsetFor(idx, self.offset, visible(), #self.data)
    self:Render()
  end

  -- Items scrolled out of view have no frame: ignored.
  function list:Flash(itemID, level)
    local c = (level == "strong") and T.colors.flashStrong or T.colors.flashNormal
    for i = 1, self.shown do
      local f = self.pool[i]
      if f and f:IsShown() and f.itemID == itemID then
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
