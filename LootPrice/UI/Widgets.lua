local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Building blocks shared by the UI files: themed buttons and texts, flat
-- colored lines, the window backdrop, tooltips and a small context menu.
-- Client-only; every WoW global is touched inside functions only.
local Widgets = {}
ns.UI.Widgets = Widgets

local MENU_FRAME = "LootPriceMenu" -- global name of the legacy dropdown frame

-- ---------------------------------------------------------------------------
-- Colors

-- Sets the text color of a FontString from a theme color {r, g, b[, a]}.
function Widgets.setTextColor(fontString, color)
  fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- ---------------------------------------------------------------------------
-- Regions

-- Single-line FontString in a theme font and color.
function Widgets.text(parent, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  Widgets.setTextColor(fs, color)
  return fs
end

-- Flat texture tinted with a theme color (lines, separators, dividers).
-- `alpha` overrides the color's own alpha.
function Widgets.line(parent, color, layer, alpha)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK")
  tex:SetTexture(ns.Theme.textures.rowHighlight)
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
  return tex
end

-- Standard panel button with the theme's per-state fonts (a FontString font
-- would be reset on state changes).
function Widgets.button(parent, label, width)
  local T = ns.Theme
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  if width then
    b:SetSize(width, T.sizes.buttonHeight)
  else
    b:SetHeight(T.sizes.buttonHeight)
  end
  b:SetText(label or "")
  b:SetNormalFontObject(T.fonts.button)
  b:SetHighlightFontObject(T.fonts.buttonHighlight)
  b:SetDisabledFontObject(T.fonts.buttonDisabled)
  return b
end

-- The dark leather backdrop of the ledger window and the options panel.
function Widgets.applyBackdrop(frame)
  local T = ns.Theme
  local inset = T.sizes.backdropInset
  frame:SetBackdrop({
    bgFile = T.textures.parchment,
    edgeFile = T.textures.frameBorder,
    tile = true,
    tileSize = T.sizes.backdropTile,
    edgeSize = T.sizes.backdropEdge,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
  local bg, border = T.colors.panelTint, T.colors.panelBorder
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

-- ---------------------------------------------------------------------------
-- Tooltips

-- Item tooltip for a link (or "item:<id>" string). Returns whether it is shown.
function Widgets.showItemTooltip(owner, link, anchor)
  if not GameTooltip or not link then return false end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(link)
  GameTooltip:Show()
  return true
end

function Widgets.showTextTooltip(owner, text, anchor)
  if not GameTooltip or not text then return false end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:SetText(text)
  GameTooltip:Show()
  return true
end

function Widgets.hideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

function Widgets.tooltipOwnedBy(owner)
  return GameTooltip ~= nil and GameTooltip:IsOwned(owner) and true or false
end

-- ---------------------------------------------------------------------------
-- Context menu (feature-detected at call time)
--
-- entries = { { text, isChecked = function() -> bool, onClick = function() }, ... }
-- kind = "checkbox" (independent toggles, the menu stays open) or "radio"
-- (pick one, the menu closes).

local function openModernMenu(anchor, entries, kind)
  -- UNVERIFIED (check in client): MenuUtil.CreateContextMenu, CreateCheckbox /
  -- CreateRadio and MenuResponse.Refresh.
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    for _, entry in ipairs(entries) do
      if kind == "checkbox" then
        root:CreateCheckbox(entry.text, entry.isChecked, function()
          entry.onClick()
          return MenuResponse and MenuResponse.Refresh or nil
        end)
      else
        root:CreateRadio(entry.text, entry.isChecked, entry.onClick)
      end
    end
  end)
end

local legacyMenu
local function openLegacyMenu(anchor, entries, kind)
  if not legacyMenu then
    legacyMenu = CreateFrame("Frame", MENU_FRAME, UIParent, "UIDropDownMenuTemplate")
  end
  UIDropDownMenu_Initialize(legacyMenu, function()
    for _, entry in ipairs(entries) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.text
      info.checked = entry.isChecked()
      info.func = entry.onClick
      if kind == "checkbox" then
        info.isNotRadio = true
        info.keepShownOnClick = true
      end
      UIDropDownMenu_AddButton(info)
    end
  end, "MENU")
  ToggleDropDownMenu(1, nil, legacyMenu, anchor, 0, 0)
end

function Widgets.openMenu(anchor, entries, kind)
  if MenuUtil and MenuUtil.CreateContextMenu then
    openModernMenu(anchor, entries, kind)
  else
    openLegacyMenu(anchor, entries, kind)
  end
end
