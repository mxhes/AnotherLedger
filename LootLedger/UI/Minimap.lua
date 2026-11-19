local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Minimap button: left click shows / hides the ledger window, right click
-- opens the options panel, drag moves it around the minimap rim. Shown unless
-- the option "minimapButton" is off (Options.lua). Client-only; every WoW
-- global is touched inside functions only.
local Minimap = {}
ns.UI.Minimap = Minimap

local SIZE = 31
local RIM_PADDING = 5 -- distance of the button center outside the minimap edge

-- ---------------------------------------------------------------------------
-- Pure helpers

-- Offset (x, y) of the button center from the minimap center, for an angle in
-- degrees (0 = right, counter-clockwise) on a circle of `radius`.
function Minimap.offset(angle, radius)
  local rad = math.rad(angle)
  return math.cos(rad) * radius, math.sin(rad) * radius
end

-- Angle in degrees (0..360) of the point (dx, dy) seen from the center.
function Minimap.angleOf(dx, dy)
  if dx == 0 and dy == 0 then return 0 end
  local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  return math.deg(atan2(dy, dx)) % 360
end

-- ---------------------------------------------------------------------------
-- Button

-- The angle lives in LootLedgerDB.minimapAngle (not in a profile).
local function settings() return ns.db end

local function place(button)
  local s = settings()
  local map = _G.Minimap
  local radius = map:GetWidth() / 2 + RIM_PADDING
  local x, y = Minimap.offset((s and s.minimapAngle) or 225, radius)
  button:ClearAllPoints()
  button:SetPoint("CENTER", map, "CENTER", x, y)
end

local function dragUpdate(button)
  local map = _G.Minimap
  local mx, my = map:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = map:GetEffectiveScale()
  local s = settings()
  if s then s.minimapAngle = Minimap.angleOf(cx / scale - mx, cy / scale - my) end
  place(button)
end

local function showTooltip(button)
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText("LootLedger")
  GameTooltip:AddLine(L["Left click: show / hide the window"], 1, 1, 1)
  GameTooltip:AddLine(L["Right click: options"], 1, 1, 1)
  GameTooltip:AddLine(L["Drag: move the button"], 1, 1, 1)
  GameTooltip:Show()
end

local function build()
  local button = CreateFrame("Button", "LootLedgerMinimapButton", _G.Minimap)
  button:SetSize(SIZE, SIZE)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.Theme.textures.logo)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", button, "CENTER", 0, 0)
  if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      if ns.UI.OptionsPanel then ns.UI.OptionsPanel.toggle() end
    elseif ns.UI.Window then
      ns.UI.Window.toggle()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", dragUpdate)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  place(button)
  return button
end

-- Option "minimapReset": back to the default place on the rim.
function Minimap.resetPosition()
  if ns.UI.Broker and ns.UI.Broker.resetIcon() then return end
  local s = settings()
  if s then s.minimapAngle = ns.DB.defaults.minimapAngle end
  if Minimap.button then place(Minimap.button) end
end

-- Shows or hides the button; builds it on first use. With LibDBIcon loaded
-- (UI/Broker.lua) that library draws the button instead.
function Minimap.setShown(shown)
  if ns.UI.Broker and ns.UI.Broker.setIconShown(shown) then return end
  if not shown then
    if Minimap.button then Minimap.button:Hide() end
    return
  end
  if not _G.Minimap then return end
  if not Minimap.button then Minimap.button = build() end
  Minimap.button:Show()
end
