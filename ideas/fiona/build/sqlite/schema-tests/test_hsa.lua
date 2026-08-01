-- Tests for the hsa table. Uses lsqlite3 (Cache-tier binding that
-- ships with Caspian) via the helpers module.

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local h = require("helpers")

local sqlite3 = require("lsqlite3")

-- Convenience: run a statement, raise on any error other than DONE/OK.
local function exec(db, sql)
	local ok = db:exec(sql)

	if ok ~= sqlite3.OK then
		error(db:errmsg())
	end
end

-- ------------------------------------------------------------
-- Positive tests — valid rows accepted
-- ------------------------------------------------------------

h.test("root row exists", function()
	local db = h.fresh_db()

	for row in db:nrows("select hsa_pk, type, st, value from hsa where hsa_pk = 1") do
		h.assert_eq(row.hsa_pk, 1, "root hsa_pk")
		h.assert_eq(row.type, "h", "root type")
		h.assert_eq(row.st, nil, "root st")
		h.assert_eq(row.value, nil, "root value")
		return
	end

	error("root row not found")
end)

h.test("insert hash", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")
end)

h.test("insert array", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('a')")
end)

h.test("insert string scalar", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'hello')")
end)

h.test("insert string scalar empty", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', '')")
end)

h.test("insert string scalar with numeric content (still a string)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', '42')")
end)

h.test("insert number scalar (integer)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 42)")
end)

h.test("insert number scalar (float)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 3.14)")
end)

h.test("insert number scalar (negative integer)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', -5)")
end)

h.test("insert number scalar (negative float)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', -3.14)")
end)

h.test("insert number scalar (zero)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'n', 0)")
end)

h.test("insert boolean zero", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'b', 0)")
end)

h.test("insert boolean one", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'b', 1)")
end)

h.test("insert null scalar", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 'u', null)")
end)

h.test("delete non-root row", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")
	local new_pk = db:last_insert_rowid()
	exec(db, "delete from hsa where hsa_pk = " .. new_pk)

	for row in db:nrows("select count(*) as c from hsa where hsa_pk = " .. new_pk) do
		h.assert_eq(row.c, 0, "row deleted")
		return
	end
end)

-- ------------------------------------------------------------
-- Negative tests — type column
-- ------------------------------------------------------------

h.test("reject type null", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type) values (null)") end,
		"NOT NULL", "type null")
end)

h.test("reject type unknown value 'x'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type) values ('x')") end,
		"CHECK", "type x")
end)

h.test("reject type uppercase 'H'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type) values ('H')") end,
		"CHECK", "type H")
end)

h.test("reject type empty string", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type) values ('')") end,
		"CHECK", "type empty")
end)

h.test("reject type multi-letter", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type) values ('hs')") end,
		"CHECK", "type multi-letter")
end)

-- ------------------------------------------------------------
-- Negative tests — st column
-- ------------------------------------------------------------

h.test("reject st unknown value 'x'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'x', 'hi')") end,
		"CHECK", "st x")
end)

h.test("reject st uppercase 'B'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'B', 1)") end,
		"CHECK", "st B")
end)

h.test("reject st empty string", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', '', 'hi')") end,
		"CHECK", "st empty")
end)

-- ------------------------------------------------------------
-- Negative tests — type/st correspondence
-- ------------------------------------------------------------

h.test("reject scalar without st", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, value) values ('s', 'hi')") end,
		"CHECK", "type=s requires st")
end)

h.test("reject hash with st", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st) values ('h', 's')") end,
		"CHECK", "type=h forbids st")
end)

h.test("reject array with st", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st) values ('a', 'n')") end,
		"CHECK", "type=a forbids st")
end)

-- ------------------------------------------------------------
-- Negative tests — boolean value
-- ------------------------------------------------------------

h.test("reject boolean value=2", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'b', 2)") end,
		"CHECK", "boolean value=2")
end)

h.test("reject boolean value=-1", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'b', -1)") end,
		"CHECK", "boolean value=-1")
end)

h.test("reject boolean value='true' (text)", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'b', 'true')") end,
		"CHECK", "boolean value='true'")
end)

h.test("reject boolean value=null", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'b', null)") end,
		"CHECK", "boolean value=null")
end)

h.test("reject boolean value=0.5 (float)", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'b', 0.5)") end,
		"CHECK", "boolean value=0.5")
end)

-- ------------------------------------------------------------
-- Negative tests — null-scalar value
-- ------------------------------------------------------------

h.test("reject null scalar with value=0", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'u', 0)") end,
		"CHECK", "null scalar with value=0")
end)

h.test("reject null scalar with value=''", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'u', '')") end,
		"CHECK", "null scalar with empty string")
end)

h.test("reject null scalar with text 'null'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'u', 'null')") end,
		"CHECK", "null scalar with text 'null'")
end)

-- ------------------------------------------------------------
-- Negative tests — number-scalar value
-- ------------------------------------------------------------

h.test("reject number scalar with text '42'", function()
	-- typeof('42') = 'text', not 'integer' — text-that-parses-as-number rejected.
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'n', '42')") end,
		"CHECK", "number scalar with text '42'")
end)

h.test("reject number scalar with text 'hello'", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'n', 'hello')") end,
		"CHECK", "number scalar with text 'hello'")
end)

h.test("reject number scalar with null", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 'n', null)") end,
		"CHECK", "number scalar with null")
end)

-- ------------------------------------------------------------
-- Negative tests — string-scalar value
-- ------------------------------------------------------------

h.test("reject string scalar with integer value", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 's', 42)") end,
		"CHECK", "string scalar with integer")
end)

h.test("reject string scalar with float value", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 's', 3.14)") end,
		"CHECK", "string scalar with float")
end)

h.test("reject string scalar with null", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, st, value) values ('s', 's', null)") end,
		"CHECK", "string scalar with null")
end)

-- ------------------------------------------------------------
-- Negative tests — hash/array value
-- ------------------------------------------------------------

h.test("reject hash with value", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, value) values ('h', 42)") end,
		"CHECK", "hash with value")
end)

h.test("reject array with value", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "insert into hsa (type, value) values ('a', 'hello')") end,
		"CHECK", "array with value")
end)

-- ------------------------------------------------------------
-- Negative tests — immutability trigger
-- ------------------------------------------------------------

h.test("reject update of type", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")
	h.assert_raises(function() exec(db, "update hsa set type = 'a' where hsa_pk = 2") end,
		"immutable", "update type")
end)

h.test("reject update of st", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'hi')")
	h.assert_raises(function() exec(db, "update hsa set st = 'n' where hsa_pk = 2") end,
		"immutable", "update st")
end)

h.test("reject update of value", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type, st, value) values ('s', 's', 'hi')")
	h.assert_raises(function() exec(db, "update hsa set value = 'bye' where hsa_pk = 2") end,
		"immutable", "update value")
end)

h.test("reject update of the root row", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "update hsa set type = 'a' where hsa_pk = 1") end,
		"immutable", "update root row")
end)

-- ------------------------------------------------------------
-- Negative tests — root preservation
-- ------------------------------------------------------------

h.test("reject delete of the root row", function()
	local db = h.fresh_db()
	h.assert_raises(function() exec(db, "delete from hsa where hsa_pk = 1") end,
		"root", "delete root")
end)

h.test("reject blanket delete (includes root)", function()
	local db = h.fresh_db()
	exec(db, "insert into hsa (type) values ('h')")
	h.assert_raises(function() exec(db, "delete from hsa") end,
		"root", "delete all")
end)
