local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Tab buttons in header row 3, between the filters and the list: Session
-- (loot), Bags (live bag contents) and Bank (last saved scan). valid, title and label are
-- pure; attach is client-only (every WoW global is touched inside functions).
local Tabs = {}
ns.UI.Tabs = Tabs

Tabs.KEYS = { "session", "bags", "bank", "history" }

local LABELS = { session = "Session", bags = "Bags", bank = "Bank", history = "History" }
local TITLES = { session = "Session Ledger", bags = "Bag Ledger", bank = "Bank Ledger", history = "Session History" }

function Tabs.valid(key)
  return LABELS[key] ~= nil
end

function Tabs.label(key)
  return LABELS[key] or LABELS.session
end

function Tabs.title(key)
  return TITLES[key] or TITLES.session
end

-- `row` is the header row to put the buttons in; `onSelect(key)` is called when
-- a tab button is clicked. Returns an object with SetSelected(key): the
-- selected tab's button is disabled (disabled font).
function Tabs.attach(row, onSelect)
  local T = ns.Theme
  local width = T.widths.tab
  local tabs = { buttons = {} }
  local previous
  for _, key in ipairs(Tabs.KEYS) do
    local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    b:SetSize(width, T.sizes.buttonHeight)
    b:SetText(Tabs.label(key))
    b:SetNormalFontObject(T.fonts.button)
    b:SetHighlightFontObject(T.fonts.buttonHighlight)
    b:SetDisabledFontObject(T.fonts.buttonDisabled)
    if previous then
      b:SetPoint("LEFT", previous, "RIGHT", T.sizes.buttonGap, 0)
    else
      b:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    b:SetScript("OnClick", function()
      if onSelect then onSelect(key) end
    end)
    tabs.buttons[key] = b
    previous = b
  end

  function tabs:SetSelected(key)
    for k, b in pairs(self.buttons) do b:SetEnabled(k ~= key) end
  end

  return tabs
end
