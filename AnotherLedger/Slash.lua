local ADDON, ns = ...

local L = ns.L

-- Slash commands (/al, /anotherledger). A command is one Slash.define call:
--
--   Slash.define({
--     name = "reset",                          -- /al reset
--     help = L["/al reset - clear the session"],  -- optional line of /al help
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

local commands = {} -- definitions in order (the order of /al help)
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

-- Runs the text typed after /al. An unknown command prints the help.
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

-- Key bindings (Bindings.xml runs these commands): the names in the game's
-- key bindings window, under AddOns.
Slash.BINDINGS = {
  BINDING_HEADER_ANOTHERLEDGER = "AnotherLedger",
  BINDING_NAME_ANOTHERLEDGER_TOGGLE = L["Show / hide the window"],
  BINDING_NAME_ANOTHERLEDGER_COMPACT = L["Compact / full window"],
  BINDING_NAME_ANOTHERLEDGER_CLOCK = L["Start / stop the session clock"],
  BINDING_NAME_ANOTHERLEDGER_SCAN = L["Scan the auction house"],
}

-- Registers the slash commands and the key binding names with the client.
function Slash.register()
  SLASH_ANOTHERLEDGER1 = "/al"
  SLASH_ANOTHERLEDGER2 = "/anotherledger"
  SlashCmdList["ANOTHERLEDGER"] = Slash.run
  for name, text in pairs(Slash.BINDINGS) do _G[name] = text end
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
  help = L["/al - toggle the window"],
  run = function() windowCall("toggle") end,
})

Slash.define({
  name = "show",
  help = L["/al show | hide - show or hide the window"],
  run = function() windowCall("show") end,
})

Slash.define({ name = "hide", run = function() windowCall("hide") end })

Slash.define({
  name = "start",
  help = L["/al start | stop | clock - start, stop or switch the session clock"],
  run = function() ns.Core.startSession() end,
})

Slash.define({ name = "stop", run = function() ns.Core.stopSession() end })

Slash.define({
  name = "clock",
  run = function()
    if ns.session.running then ns.Core.stopSession() else ns.Core.startSession() end
  end,
})

Slash.define({
  name = "compact",
  help = L["/al compact - switch between the compact and the full window"],
  run = function()
    if ns.UI and ns.UI.Ledger and ns.UI.Ledger.frame then ns.UI.Ledger.toggleMode() end
  end,
})

Slash.define({
  name = "reset",
  help = L["/al reset - clear the session"],
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
  help = L["/al keep on|off - keep the session across logins"],
  run = function(arg)
    local value = arg and arg:lower()
    if value ~= "on" and value ~= "off" then
      say(L["usage: /al keep on|off (currently "] .. (ns.Options.get(ns.db, "keepSession") and "on" or "off") .. ")")
      return
    end
    setOption("keepSession", value == "on")
    say(L["keep session across logins: "] .. value)
  end,
})

Slash.define({
  name = "tsm",
  help = L["/al tsm <source> - TSM price source (e.g. DBMarket)"],
  run = function(arg)
    if not arg then
      say(L["TSM source: "] .. tostring(ns.Options.get(ns.db, "tsmSource")))
      return
    end
    -- The option's apply redraws the window.
    say(L["TSM source: "] .. tostring(setOption("tsmSource", arg)))
  end,
})

-- What /al export copies: the History list (default), the running session's
-- items, the History Zones places or the History Mobs.
local EXPORTS = { history = "history", session = "session", zones = "zones", mobs = "mobs" }

Slash.define({
  name = "scan",
  help = L["/al scan - read the whole auction house"],
  run = function()
    if ns.Core and ns.Core.scanCommand then ns.Core.scanCommand() end
  end,
})

Slash.define({
  name = "export",
  help = L["/al export [session | zones | mobs] - copy the History (or the session, Zones or Mobs) as CSV"],
  run = function(arg)
    local Export = ns.UI and ns.UI.Export
    if not Export then return end
    local what = EXPORTS[arg and arg:lower() or "history"]
    if not what then
      say(L["usage: /al export [session | zones | mobs]"])
      return
    end
    Export[what]()
  end,
})

Slash.define({
  name = "undo",
  help = L["/al undo - take back the last delete or merge in History"],
  run = function() ns.Core.undoDelete() end,
})

local L_WATCH_USAGE = L["usage: /al watch <item link, item ID or part of a name>; /al unwatch <the same>"]
local L_WATCHING = L["watching %s: you hear a sound and see a line when you loot it."]
local L_WATCH_SHORT = L["give at least 3 letters of the name, an item link or an item ID."]
local L_UNWATCHED = L["no longer watching %s."]
local L_NOT_WATCHED = L["%s is not on the watch list."]
local L_WATCH_LIST = L["watch list: %s"]
local L_WATCH_EMPTY = L["the watch list is empty. /al watch <item link, item ID or part of a name> adds to it."]

-- The item of a /al watch argument: an item link or an item ID gives
-- (itemID, its name or nil); else nil (a name text).
local function watchTarget(arg)
  local key, itemID = ns.LootParse.itemKey(arg)
  if key and itemID then return itemID, arg:match("%[(.-)%]") end
  local id = tonumber(arg)
  if id and id > 0 and id == math.floor(id) then return id, nil end
  return nil
end

local function watchListText()
  local Core = ns.Core
  local parts = {}
  for _, item in ipairs(Core.watchedList()) do parts[#parts + 1] = item.name end
  local texts = {}
  for _, text in pairs(Core.watchedNames()) do texts[#texts + 1] = "\"" .. text .. "\"" end
  table.sort(texts)
  for _, t in ipairs(texts) do parts[#parts + 1] = t end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

Slash.define({
  name = "watch",
  help = L["/al watch <item | part of a name> - sound and screen line when you loot it; /al watch lists them"],
  run = function(arg)
    local Core = ns.Core
    if not arg or arg:match("^%s*$") then
      local list = watchListText()
      say(list and string.format(L_WATCH_LIST, list) or L_WATCH_EMPTY)
      return
    end
    local id, name = watchTarget(arg)
    if id then
      Core.watchItem(id, name)
      say(string.format(L_WATCHING, arg))
    elseif Core.watchName(arg) then
      say(string.format(L_WATCHING, "\"" .. arg:match("^%s*(.-)%s*$") .. "\""))
    else
      say(L_WATCH_SHORT)
    end
  end,
})

Slash.define({
  name = "unwatch",
  run = function(arg)
    local Core = ns.Core
    if not arg or arg:match("^%s*$") then
      say(L_WATCH_USAGE)
      return
    end
    local id = watchTarget(arg)
    local done
    if id then done = Core.unwatchItem(id) else done = Core.unwatchName(arg) end
    say(string.format(done and L_UNWATCHED or L_NOT_WATCHED, arg))
  end,
})

Slash.define({
  name = "stats",
  help = L["/al stats - how much of the saved files each part takes"],
  run = function()
    if not ns.Stats then return end
    for _, line in ipairs(ns.Stats.lines(ns.Stats.collect(ns.db, ns.chardb))) do say(line) end
  end,
})

Slash.define({ name = "help", needsSession = false, run = Slash.printHelp })

ns.Slash = Slash
