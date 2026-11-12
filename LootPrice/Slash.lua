local ADDON, ns = ...

local Slash = {}

-- Returns command (lowercased) and argument (original case, or nil).
function Slash.parse(msg)
  if type(msg) ~= "string" then msg = "" end
  msg = msg:match("^%s*(.-)%s*$")
  if msg == "" then return "toggle", nil end
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if rest == "" then rest = nil end
  return cmd:lower(), rest
end

ns.Slash = Slash
