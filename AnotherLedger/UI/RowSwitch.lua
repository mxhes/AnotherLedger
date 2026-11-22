local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Switch buttons at the right end of the sub-tab row, each shown only on its
-- view, its choice saved in ns.db (account-wide):
--   TradePeriod: the Trade tab's Items period (7 days, 30 days, All), db.tradePeriod.
--   MobKind:     History > Mobs lists mobs and nodes, only mobs or only
--                nodes (All, Mobs, Nodes), db.mobKind.
-- Both sit at the same spot; never more than one is shown.
local RowSwitch = {}
ns.UI.RowSwitch = RowSwitch

local L = ns.L

-- spec = { field (ns.db key), default, order = { value, ... },
--   labels = { [value] = text }, kind (the view.kind it shows on), width (Theme.sizes key) }
function RowSwitch.new(spec)
  local S = { DEFAULT = spec.default }

  -- Pure. The saved choice, a known one or the default.
  function S.current(db)
    local v = type(db) == "table" and db[spec.field] or nil
    return spec.labels[v] and v or S.DEFAULT
  end

  -- Pure. The button text of a choice.
  function S.label(v) return spec.labels[v] or spec.labels[S.DEFAULT] end

  -- Every label the button can show (it fits the widest).
  function S.labels()
    local out = {}
    for i, v in ipairs(spec.order) do out[i] = spec.labels[v] end
    return out
  end

  function S.set(v)
    if not (spec.labels[v] and type(ns.db) == "table") then return end
    ns.db[spec.field] = v
    if ns.UI.Ledger and ns.UI.Ledger.refresh then ns.UI.Ledger.refresh() end
  end

  local function openMenu(button)
    local entries = {}
    for _, v in ipairs(spec.order) do
      entries[#entries + 1] = { text = spec.labels[v],
        isChecked = function() return S.current(ns.db) == v end,
        onClick = function() S.set(v) end }
    end
    ns.UI.Widgets.openMenu(button, entries)
  end

  local part = {}
  function part:Update(view)
    local b = S.button
    if not b then return end
    local shown = type(view) == "table" and view.kind == spec.kind
    b:SetShown(shown)
    if shown then b:SetText(S.label(S.current(ns.db))) end
  end

  -- Builds the button on `row` (the window's sub-tab row) and registers it.
  function S.attach(row)
    if S.button or not row then return end
    local width = ns.Theme.sizes[spec.width]
    local b = ns.UI.Widgets.button(row, S.label(S.current(ns.db)), width)
    ns.UI.Widgets.fitButton(b, S.labels(), width)
    b:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    b:SetScript("OnClick", function(self) openMenu(self) end)
    b:Hide()
    S.button = b
    ns.UI.Ledger.register(part)
  end

  return S
end

ns.UI.TradePeriod = RowSwitch.new({
  field = "tradePeriod", default = "30", order = { "7", "30", "all" },
  labels = { ["7"] = L["7 days"], ["30"] = L["30 days"], all = L["All"] },
  kind = "tradeItems", width = "tradePeriodWidth",
})

ns.UI.MobKind = RowSwitch.new({
  field = "mobKind", default = "all", order = { "all", "mobs", "nodes" },
  labels = { all = L["All"], mobs = L["Mobs"], nodes = L["Nodes"] },
  kind = "mobs", width = "tradePeriodWidth",
})

-- Both switches (Ledger.init attaches them, Ledger.measureHeader keeps room
-- for the wider one).
RowSwitch.all = { ns.UI.TradePeriod, ns.UI.MobKind }
