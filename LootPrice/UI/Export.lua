local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Copy box for the History CSV export (/lp export, or the button in the
-- options): a movable frame with a scrolling, multi-line edit box whose text
-- is selected, ready for Ctrl+C. Client-only; every WoW global is touched
-- inside functions only.
local Export = {}
ns.UI.Export = Export

local L_TITLE = L["History export (CSV)"]
local L_HINT = L["Ctrl+C copies the selected text. Esc closes."]
local WIDTH, HEIGHT = 520, 360

local function build()
  local T = ns.Theme
  local W = ns.UI.Widgets
  local frame = CreateFrame("Frame", "LootPriceExport", UIParent, "BackdropTemplate")
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

  local close = W.closeButton(frame, T.widths.header.hide, function() frame:Hide() end)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  local hint = W.text(frame, T.fonts.small, T.colors.hint, "LEFT")
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
  hint:SetText(L_HINT)

  -- UNVERIFIED (check in client): UIPanelScrollFrameTemplate exists on Forever.
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 30)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(T.fonts.small)
  edit:SetWidth(WIDTH - 50)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- Read-only: typing puts the export text back.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and frame.text then
      self:SetText(frame.text)
      self:HighlightText()
    end
  end)
  scroll:SetScrollChild(edit)
  frame.edit = edit

  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LootPriceExport") end
  frame:Hide()
  return frame
end

-- Shows `text` selected in the copy box.
function Export.show(text)
  if not Export.frame then Export.frame = build() end
  local frame = Export.frame
  frame.text = text or ""
  frame.edit:SetText(frame.text)
  frame:Show()
  frame.edit:SetFocus()
  frame.edit:HighlightText()
end

-- The History of this character as CSV, in the copy box.
function Export.history()
  local list = ns.chardb and ns.chardb.history
  local formatDate = ns.UI.Ledger and ns.UI.Ledger.formatDate
  Export.show(ns.History.csv(type(list) == "table" and list or {}, formatDate))
end
