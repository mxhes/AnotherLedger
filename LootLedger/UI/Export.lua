local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Copy box for the CSV exports (/lp export [session | zones], or the button in
-- the options): a movable frame with a scrolling, multi-line edit box whose
-- text is selected, ready for Ctrl+C. The same frame is the paste box of the
-- profile import (Export.edit: editable, with an Import button). Client-only;
-- every WoW global is touched inside functions only.
local Export = {}
ns.UI.Export = Export

local L_TITLE = L["History export (CSV)"]
local L_SESSION_TITLE = L["Session export (CSV)"]
local L_ZONES_TITLE = L["Zones export (CSV)"]
local L_HINT = L["Ctrl+C copies the selected text. Esc closes."]
local L_PASTE_HINT = L["Ctrl+V pastes a profile line. Esc closes."]
local L_IMPORT = L["Import"]
local WIDTH, HEIGHT = 520, 360

local function build()
  local T = ns.Theme
  local W = ns.UI.Widgets
  local frame = CreateFrame("Frame", "LootLedgerExport", UIParent, "BackdropTemplate")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  W.applyBackdrop(frame)

  local title = W.text(frame, T.fonts.title, T.colors.gold, "LEFT")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
  title:SetText(L_TITLE)
  frame.titleText = title

  local close = W.iconButton(frame, "close", T.widths.header.hide, function() frame:Hide() end)
  frame.close = close
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  local hint = W.text(frame, T.fonts.small, T.colors.hint, "LEFT")
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
  hint:SetText(L_HINT)
  frame.hint = hint

  -- Import button (paste mode only): hands the typed text to frame.onAccept.
  local import = W.button(frame, L_IMPORT, 80)
  import:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 6)
  import:SetScript("OnClick", function()
    if frame.onAccept then frame.onAccept(frame.edit:GetText() or "") end
  end)
  import:Hide()
  frame.importButton = import
  frame.mode = "copy"
  frame.onAccept = false

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 30)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(T.fonts.small)
  edit:SetWidth(WIDTH - 50)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- Read-only in copy mode: typing puts the export text back.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and frame.mode == "copy" and frame.text then
      self:SetText(frame.text)
      self:HighlightText()
    end
  end)
  scroll:SetScrollChild(edit)
  frame.edit = edit

  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LootLedgerExport") end
  frame:Hide()
  return frame
end

-- Shows `text` selected in the copy box, titled `title` (default: the History
-- export title).
function Export.show(text, title)
  if not Export.frame then Export.frame = build() end
  local frame = Export.frame
  frame.titleText:SetText(title or L_TITLE)
  frame.mode, frame.onAccept = "copy", false
  frame.hint:SetText(L_HINT)
  frame.importButton:Hide()
  frame.text = text or ""
  frame.edit:SetText(frame.text)
  frame:Show()
  frame.edit:SetFocus()
  frame.edit:HighlightText()
end

-- The paste box: empty and editable, titled `title`; the Import button calls
-- `onAccept(text)`.
function Export.edit(title, onAccept)
  if not Export.frame then Export.frame = build() end
  local frame = Export.frame
  frame.titleText:SetText(title or "")
  frame.mode, frame.onAccept = "edit", onAccept
  frame.hint:SetText(L_PASTE_HINT)
  frame.importButton:Show()
  frame.text = ""
  frame.edit:SetText("")
  frame:Show()
  frame.edit:SetFocus()
end

function Export.hide()
  if Export.frame then Export.frame:Hide() end
end

local function ignored()
  return ns.Core and ns.Core.ignoredItems() or nil
end

-- The History of this character as CSV, in the copy box.
function Export.history()
  local list = ns.chardb and ns.chardb.history
  local formatDate = ns.UI.Ledger and ns.UI.Ledger.formatDate
  Export.show(ns.History.csv(type(list) == "table" and list or {}, formatDate, ignored()))
end

-- View options for an export: the window's (prices, item names, gold), no
-- filter: an export has every item.
local function exportOpts()
  local opts = {}
  local Ledger = ns.UI.Ledger
  local base = Ledger and Ledger.viewOptions and Ledger.viewOptions() or {}
  for k, v in pairs(base) do opts[k] = v end
  opts.filter, opts.sort, opts.now = nil, "ah", time()
  opts.ignored = ignored()
  return opts
end

-- The running session's items as CSV.
function Export.session()
  if not ns.session then return end
  local view = ns.View.build(ns.session, exportOpts())
  Export.show(ns.View.itemsCsv(view.rows), L_SESSION_TITLE)
end

-- The History Zones places (every subzone, of every character with the
-- option "accountZones", plus the running session) as CSV.
function Export.zones()
  local opts = exportOpts()
  local entries = {}
  local list = ns.Core and ns.Core.zoneHistory() or (ns.chardb and ns.chardb.history) or {}
  for i, e in ipairs(list) do entries[i] = e end
  local s = ns.session
  if type(s) == "table" then
    entries[#entries + 1] = { live = true, items = s.items, places = s.places, gold = s.gold,
      zones = ns.Session.zoneSnapshot(s, opts.now) }
  end
  Export.show(ns.View.zonesCsv(entries, opts), L_ZONES_TITLE)
end
