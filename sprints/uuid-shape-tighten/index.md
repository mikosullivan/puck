~~~vibecode
{"doc": "sprint-index", "sprint": "uuid-shape-tighten",
	"role": "Decision record: IMPLEMENTED. Tightened the `object_pk` shape CHECK. The earlier two-clause check accepted 36 hyphens because `LIKE`'s `_` matches any character and the negated character class allowed `-` globally. Replaced with per-segment `substr` + `not glob '*[^0-9a-f]*'` checks so each hex segment actually contains hex. Source: ChatGPT second-pass § 2.",
	"status": "implemented"}
~~~

# uuid-shape-tighten

Second-pass § 2. Closed.

## What landed

Column CHECK on `object_pk` in [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql):

~~~sql
check (
	length(object_pk) = 36
	and substr(object_pk, 9,  1) = '-'
	and substr(object_pk, 14, 1) = '-'
	and substr(object_pk, 19, 1) = '-'
	and substr(object_pk, 24, 1) = '-'
	and substr(object_pk, 1,  8)  not glob '*[^0-9a-f]*'
	and substr(object_pk, 10, 4)  not glob '*[^0-9a-f]*'
	and substr(object_pk, 15, 4)  not glob '*[^0-9a-f]*'
	and substr(object_pk, 20, 4)  not glob '*[^0-9a-f]*'
	and substr(object_pk, 25, 12) not glob '*[^0-9a-f]*'
)
~~~

Each of the five hex segments has its own `not glob '*[^0-9a-f]*'` check that reads only lowercase hex characters as valid — no hyphens or anything else can slip in. The four hyphen positions are explicit equality checks.

DEFAULT unchanged — the existing generator was already producing hex-in-segments; verified against the tighter CHECK during promotion.

Existing tests in [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua) under "Object pk shape and DEFAULT" all continue to pass. Two new tests added:

- 36 hyphens rejected (the specific case ChatGPT tested).
- Hyphen inside a hex segment rejected (`abcd-f01-2345-4678-9abc-def012345678`).

Sprint kept as a record.
