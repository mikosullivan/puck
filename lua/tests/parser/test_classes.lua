--[[
{
  "suite": "parser / classes",
  "covers": "class_def node: empty class, inherits, field, abstract, join, function, remote function, property"
}
]]
local runner = require("tests.support.runner")
local assert = require("tests.support.assert")
local ks     = require("kscript")

--[[ { "in": "src: string", "out": "AST node  (first statement)", "note": "parse helper; returns ast.stmts[1]" } ]]
local function stmt(src)
    local ast = ks.parse(src)
    return ast.stmts[1]
end

runner.suite("parser / classes")

runner.test("empty class", function()
    local n = stmt("class 'fleet.officer'\nend")
    assert.kind(n, "class_def")
    assert.equal(n.uns, "fleet.officer")
    assert.count(n.body, 0)
end)

runner.test("class with inherits", function()
    local n = stmt("class 'fleet.captain'\ninherits 'fleet.officer'\nend")
    assert.kind(n, "class_def")
    assert.count(n.body, 1)
    assert.kind(n.body[1], "inherits")
    assert.equal(n.body[1].uns, "fleet.officer")
end)

runner.test("class with field", function()
    local n = stmt("class 'fleet.officer'\nfield :name\nend")
    assert.kind(n, "class_def")
    assert.kind(n.body[1], "field_decl")
    assert.equal(n.body[1].name, "name")
end)

runner.test("class with multiple fields", function()
    local n = stmt("class 'fleet.officer'\nfield :name\nfield :rank\nend")
    assert.kind(n, "class_def")
    assert.count(n.body, 2)
    assert.kind(n.body[1], "field_decl")
    assert.kind(n.body[2], "field_decl")
    assert.equal(n.body[2].name, "rank")
end)

runner.test("class with abstract", function()
    local n = stmt("class 'fleet.base'\nabstract true\nend")
    assert.kind(n, "class_def")
    assert.kind(n.body[1], "abstract_decl")
    assert.is_true(n.body[1].value)
end)

runner.test("class with join", function()
    local n = stmt("class 'fleet.officer'\njoin :ship, :crew\nend")
    assert.kind(n, "class_def")
    assert.kind(n.body[1], "join_decl")
    assert.count(n.body[1].fields, 2)
    assert.equal(n.body[1].fields[1], "ship")
    assert.equal(n.body[1].fields[2], "crew")
end)

runner.test("class with function", function()
    local n = stmt("class 'fleet.officer'\nfunction $greet\nend\nend")
    assert.kind(n, "class_def")
    assert.kind(n.body[1], "func_def")
    assert.equal(n.body[1].name, "greet")
end)

runner.test("class with remote function", function()
    local n = stmt("class 'fleet.officer'\nremote function &save\nend\nend")
    assert.kind(n, "class_def")
    assert.kind(n.body[1], "func_def")
    assert.is_true(n.body[1].remote)
end)

runner.test("class with property", function()
    local n = stmt("class 'fleet.officer'\nproperty :full_name\nend")
    assert.kind(n, "class_def")
    assert.kind(n.body[1], "property_decl")
    assert.equal(n.body[1].name, "full_name")
end)
