--[[
{
  "file":     "tests/caspian/digory/test_bootstrap_hash_class.lua",
  "test_id":  "TD.2",
  "verifies": "After engine.bootstrap, puck.uno/hash class is registered, owned by the stdlib role, with a method_missing handler (no explicit methods in Digory).",
  "level":    "unit"
}
]]
local runner  = require("support.runner")
local assert_ = require("support.assert")
local engine  = require("caspian.engine")

runner.suite("digory / TD.2 bootstrap_hash_class")

runner.test("engine.classes[puck.uno/hash] exists with stdlib role and method_missing", function()
    engine.bootstrap()
    local cls = engine.classes["puck.uno/hash"]
    assert_.not_nil(cls, "puck.uno/hash class not registered")
    assert_.equal(cls.name, "puck.uno/hash")
    assert_.equal(cls.owning_role, engine.state.roles.stdlib,
                  "hash class owning_role should be stdlib")
    assert_.equal(type(cls.method_missing), "function",
                  "hash class should have method_missing handler")
end)
