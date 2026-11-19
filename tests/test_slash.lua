local h = ...
local ns = h.load({ "Util.lua", "Slash.lua" })
local P = ns.Slash.parse

local function pair(msg)
  local c, a = P(msg)
  return { c, a }
end

h.test("Slash.parse basics", function()
  h.eq(pair(""), { "toggle" })
  h.eq(pair("   "), { "toggle" })
  h.eq(pair("show"), { "show" })
  h.eq(pair("  reset "), { "reset" })
  h.eq(pair("SHOW"), { "show" })
end)

h.test("Slash.parse arguments keep case", function()
  h.eq(pair("KEEP on"), { "keep", "on" })
  h.eq(pair("tsm DBMinBuyout"), { "tsm", "DBMinBuyout" })
  h.eq(pair("tsm   DBMarket  "), { "tsm", "DBMarket" })
  h.eq(pair("tsm first(DBMarket, DBMinBuyout)"), { "tsm", "first(DBMarket, DBMinBuyout)" })
end)

h.test("Slash.parse non-string", function()
  h.eq(pair(nil), { "toggle" })
end)

h.test("Slash.define / run: commands, session guard and help", function()
  local S = ns.Slash
  local said, got = {}, nil
  local realPrint = print
  print = function(msg) said[#said + 1] = msg end
  local ok, err = pcall(function()
    S.define({ name = "ping", help = "/al ping - test", run = function(arg) got = arg or true end })
    S.define({ name = "free", needsSession = false, run = function() got = "free" end })
    ns.session = nil
    S.run("ping")
    h.eq(got, nil)
    h.eq(said[#said]:find("not ready", 1, true) ~= nil, true)
    S.run("free"); h.eq(got, "free")
    ns.session = {}
    S.run("ping"); h.eq(got, true)
    S.run("  PING  Some Arg "); h.eq(got, "Some Arg")
    said = {}
    S.run("nonsense") -- unknown: prints the help
    local text = table.concat(said, "\n")
    h.eq(text:find("/al ping - test", 1, true) ~= nil, true)
    h.eq(text:find("/al reset", 1, true) ~= nil, true)
    h.eq(said[#said]:find("Note:", 1, true) ~= nil, true)
    ns.session = nil
    said = {}
    S.run("help") -- works before login
    h.eq(#said > 1, true)
  end)
  print = realPrint
  ns.session = nil
  if not ok then error(err, 0) end
end)
