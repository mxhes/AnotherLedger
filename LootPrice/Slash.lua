local ADDON, ns = ...

local L = ns.L

-- Slash commands (/lp, /lootprice). A command is one Slash.define call:
--
--   Slash.define({
--     name = "reset",                          -- /lp reset
--     help = L["/lp reset - clear the session"],  -- optional line of /lp help
--     needsSession = true,                     -- default: refuse before login is done
--     run  = function(arg) ... end,            -- arg: text after the command, or nil
--   })
--
-- The built-in commands look everything else up at call time, so this file
-- has no load-order needs beyond Util.
local Slash = {}

local say = ns.Util.say

local HELP_NOTE = L["Note: an AH age tag can look fresh when the price source serves old scan data."]
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
    say(L["not ready yet."])
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

-- Settings changed by a command go through the option registry (validation,
-- apply) and show up in an open options panel.
local function setOption(key, value)
  local v = ns.Options.set(ns.db, key, value)
  local panel = ns.UI and ns.UI.OptionsPanel
  if panel and panel.refreshAll then panel.refreshAll() end
  return v
end

local function windowCall(name)
  local window = ns.UI and ns.UI.Window
  if window and type(window[name]) == "function" then window[name]() end
end

Slash.define({
  name = "toggle",
  help = L["/lp - toggle the window"],
  run = function() windowCall("toggle") end,
})

Slash.define({
  name = "show",
  help = L["/lp show | hide - show or hide the window"],
  run = function() windowCall("show") end,
})

Slash.define({ name = "hide", run = function() windowCall("hide") end })

Slash.define({
  name = "start",
  help = L["/lp start | stop - start or stop the session clock"],
  run = function() ns.Core.startSession() end,
})

Slash.define({ name = "stop", run = function() ns.Core.stopSession() end })

Slash.define({
  name = "reset",
  help = L["/lp reset - clear the session"],
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
  help = L["/lp keep on|off - keep the session across logins"],
  run = function(arg)
    local value = arg and arg:lower()
    if value ~= "on" and value ~= "off" then
      say(L["usage: /lp keep on|off (currently "] .. (ns.Options.get(ns.db, "keepSession") and "on" or "off") .. ")")
      return
    end
    setOption("keepSession", value == "on")
    say(L["keep session across logins: "] .. value)
  end,
})

Slash.define({
  name = "tsm",
  help = L["/lp tsm <source> - TSM price source (e.g. DBMarket)"],
  run = function(arg)
    if not arg then
      say(L["TSM source: "] .. tostring(ns.Options.get(ns.db, "tsmSource")))
      return
    end
    -- The option's apply redraws the window.
    say(L["TSM source: "] .. tostring(setOption("tsmSource", arg)))
  end,
})

Slash.define({
  name = "export",
  help = L["/lp export - copy the History as CSV"],
  run = function()
    if ns.UI and ns.UI.Export then ns.UI.Export.history() end
  end,
})

Slash.define({ name = "help", needsSession = false, run = Slash.printHelp })

ns.Slash = Slash
