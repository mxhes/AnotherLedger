local ADDON, ns = ...

-- Slash commands (/lp, /lootprice). A command is one Slash.define call:
--
--   Slash.define({
--     name = "reset",                          -- /lp reset
--     help = "/lp reset - clear the session",  -- optional line of /lp help
--     needsSession = true,                     -- default: refuse before login is done
--     run  = function(arg) ... end,            -- arg: text after the command, or nil
--   })
--
-- The built-in commands look everything else up at call time, so this file
-- has no load-order needs beyond Util.
local Slash = {}

local say = ns.Util.say

local HELP_NOTE = "Note: an AH age tag can look fresh when the price source serves old scan data."
local DEFAULT_COMMAND = "toggle"

local commands = {} -- definitions in order (the order of /lp help)
local byName = {}

function Slash.define(command)
  assert(type(command) == "table" and type(command.name) == "string", "command needs a name")
  assert(type(command.run) == "function", "command needs a run function")
  if not byName[command.name] then commands[#commands + 1] = command end
  byName[command.name] = command
  return command
end

-- Returns command (lowercased) and argument (original case, or nil).
function Slash.parse(msg)
  if type(msg) ~= "string" then msg = "" end
  msg = msg:match("^%s*(.-)%s*$")
  if msg == "" then return DEFAULT_COMMAND, nil end
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  if rest == "" then rest = nil end
  return cmd:lower(), rest
end

function Slash.printHelp()
  for _, command in ipairs(commands) do
    if command.help then say(command.help) end
  end
  say(HELP_NOTE)
end

-- Runs the text typed after /lp. An unknown command prints the help.
function Slash.run(msg)
  local name, arg = Slash.parse(msg)
  local command = byName[name]
  if not command then
    Slash.printHelp()
    return
  end
  if command.needsSession ~= false and not ns.session then
    say("not ready yet.")
    return
  end
  command.run(arg)
end

-- Registers the slash commands with the client.
function Slash.register()
  SLASH_LOOTPRICE1 = "/lp"
  SLASH_LOOTPRICE2 = "/lootprice"
  SlashCmdList["LOOTPRICE"] = Slash.run
end

-- ---------------------------------------------------------------------------
-- Built-in commands

local function windowCall(name)
  local window = ns.UI and ns.UI.Window
  if window and type(window[name]) == "function" then window[name]() end
end

Slash.define({
  name = "toggle",
  help = "/lp - toggle the window",
  run = function() windowCall("toggle") end,
})

Slash.define({
  name = "show",
  help = "/lp show | hide - show or hide the window",
  run = function() windowCall("show") end,
})

Slash.define({ name = "hide", run = function() windowCall("hide") end })

Slash.define({
  name = "start",
  help = "/lp start | stop - start or stop the session clock",
  run = function() ns.Core.startSession() end,
})

Slash.define({ name = "stop", run = function() ns.Core.stopSession() end })

Slash.define({
  name = "reset",
  help = "/lp reset - clear the session",
  run = function()
    -- Same path as the Reset button: asks first when the session is large.
    if ns.UI and ns.UI.Header then
      ns.UI.Header.requestReset()
    else
      ns.Core.resetSession()
    end
  end,
})

Slash.define({
  name = "keep",
  help = "/lp keep on|off - keep the session across logins",
  run = function(arg)
    local settings = ns.db.settings
    local value = arg and arg:lower()
    if value ~= "on" and value ~= "off" then
      say("usage: /lp keep on|off (currently " .. (settings.keepSession and "on" or "off") .. ")")
      return
    end
    settings.keepSession = (value == "on")
    say("keep session across logins: " .. value)
  end,
})

Slash.define({
  name = "tsm",
  help = "/lp tsm <source> - TSM price source (e.g. DBMarket)",
  run = function(arg)
    local settings = ns.db.settings
    if not arg then
      say("TSM source: " .. tostring(settings.tsmSource))
      return
    end
    settings.tsmSource = arg
    say("TSM source: " .. arg)
    if ns.UI and ns.UI.refresh then ns.UI.refresh() end
  end,
})

Slash.define({ name = "help", needsSession = false, run = Slash.printHelp })

ns.Slash = Slash
