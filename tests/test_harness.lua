local h = ...

h.test("eq compares tables deeply", function()
  h.eq({ 1, { a = 2 } }, { 1, { a = 2 } })
  local ok = pcall(h.eq, { 1 }, { 2 })
  assert(ok == false, "eq must fail on different tables")
end)

h.test("near compares numbers within eps", function()
  h.near(1.0, 1.0000001)
  assert(pcall(h.near, 1, 2) == false, "near must fail")
end)

h.test("load shares ns", function()
  local ns = h.load({ "tests/fixtures/ns_probe.lua" })
  h.eq(ns.probe, true)
  h.eq(ns.addonName, "LootLedger")
end)
