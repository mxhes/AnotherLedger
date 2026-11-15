local ADDON, ns = ...

local L = ns.L

-- Rich tooltips (Daily farm, History sessions, Zones places), built as data so
-- the content stays pure and testable: a gold title, then lines of a kind.
-- Tooltip.render turns one into GameTooltip calls with the theme's colors
-- (Widgets.showTextTooltip runs them); Tooltip.text flattens it to plain text.
--
--   pair     label left, text right           (tan label, white text)
--   money    label left, coins right [(x/h)]  (coins in the game colors; a
--            Vendor / AH line's label in its source color)
--   rate     label left, coins/h right
--   labelled "Label: text" on one wrapping line
--   para     a white paragraph that wraps (an option's description)
--   section  a gold sub-heading
--   note     a quiet tan line
--   warn     a red line (slow sellers)
--   hint     a green click hint; the first one comes after a blank line
local Tooltip = {}
ns.Tooltip = Tooltip

local L_PER_HOUR = L["/h"]

function Tooltip.new(title) return { title = title, lines = {} } end

local function add(tip, line)
  tip.lines[#tip.lines + 1] = line
  return line
end

function Tooltip.pair(tip, label, text) return add(tip, { kind = "pair", label = label, text = text }) end

-- `source` ("vendor" / "ah" / "de", optional): the label takes that source's
-- color (Theme.sourceColor) instead of the label color.
function Tooltip.money(tip, label, copper, perHour, source)
  return add(tip, { kind = "money", label = label, copper = copper, perHour = perHour, source = source })
end

-- `strong`: the label is a name (a runner-up place), drawn in the value color.
function Tooltip.rate(tip, label, perHour, strong)
  return add(tip, { kind = "rate", label = label, perHour = perHour, strong = strong or nil })
end

function Tooltip.labelled(tip, label, text) return add(tip, { kind = "labelled", label = label, text = text }) end
function Tooltip.section(tip, text) return add(tip, { kind = "section", text = text }) end
function Tooltip.para(tip, text) return add(tip, { kind = "para", text = text }) end
function Tooltip.note(tip, text) return add(tip, { kind = "note", text = text }) end
function Tooltip.warn(tip, text) return add(tip, { kind = "warn", text = text }) end
function Tooltip.hint(tip, text) return add(tip, { kind = "hint", text = text }) end

local function round(v) return math.floor(v + 0.5) end

-- The right-hand text of a money / rate line.
local function moneyText(line, fmt)
  if line.kind == "rate" then return fmt(round(line.perHour or 0)) .. L_PER_HOUR end
  local text = fmt(line.copper or 0)
  if line.perHour then text = text .. "  (" .. fmt(round(line.perHour)) .. L_PER_HOUR .. ")" end
  return text
end

local function rightText(line, fmt)
  if line.kind == "pair" then return line.text or "" end
  return moneyText(line, fmt)
end

local DOUBLE = { pair = true, money = true, rate = true }

-- Plain text: the title, then one line each (label and value joined), money in
-- Money.format. A string passes through.
function Tooltip.text(tip)
  if type(tip) ~= "table" then return tip end
  local fmt = ns.Money.format
  local out = {}
  if tip.title then out[#out + 1] = tip.title end
  for _, line in ipairs(tip.lines) do
    if DOUBLE[line.kind] then
      local sep = line.label:match("%s$") and "" or " "
      out[#out + 1] = line.label .. sep .. rightText(line, fmt)
    elseif line.kind == "labelled" then
      out[#out + 1] = line.label .. line.text
    else
      out[#out + 1] = line.text
    end
  end
  return table.concat(out, "\n")
end

-- The GameTooltip calls for `tip`, in order:
--   { op = "line", text, color, wrap } -> AddLine
--   { op = "double", left, right, lc, rc } -> AddDoubleLine
-- The first line is the title (GameTooltip draws it in the header font).
function Tooltip.render(tip)
  local C = ns.Theme.colors
  local fmt = ns.Money.formatColored
  local ops = {}
  local function op(o) ops[#ops + 1] = o end
  if tip.title then op({ op = "line", text = tip.title, color = C.tipTitle }) end
  local hinted = false
  for _, line in ipairs(tip.lines) do
    local kind = line.kind
    if DOUBLE[kind] then
      local lc = line.strong and C.tipValue or (line.source and ns.Theme.sourceColor(line.source)) or C.tipLabel
      op({ op = "double", left = line.label, right = rightText(line, fmt), lc = lc, rc = C.tipValue })
    elseif kind == "labelled" then
      op({ op = "line", text = ns.Money.colorCode(C.tipLabel) .. line.label .. "|r" .. line.text,
        color = C.tipValue, wrap = true })
    elseif kind == "para" then
      op({ op = "line", text = line.text, color = C.tipValue, wrap = true })
    elseif kind == "section" then
      op({ op = "line", text = line.text, color = C.tipSection })
    elseif kind == "note" then
      op({ op = "line", text = line.text, color = C.tipNote })
    elseif kind == "warn" then
      op({ op = "line", text = line.text, color = C.tipWarn, wrap = true })
    elseif kind == "hint" then
      if not hinted and #ops > 0 then op({ op = "line", text = " " }) end
      hinted = true
      op({ op = "line", text = line.text, color = C.tipHint })
    end
  end
  return ops
end
