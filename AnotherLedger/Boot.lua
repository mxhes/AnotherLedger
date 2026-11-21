local ADDON, ns = ...

-- Loads last: wires Core's events (Core.lua, CoreScan.lua, CoreTrade.lua)
-- in the client. Outside it (tests) nothing happens.
if type(_G.CreateFrame) == "function" then ns.Core.init() end
