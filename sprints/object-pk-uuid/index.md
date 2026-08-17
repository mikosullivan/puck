~~~vibecode
{"doc": "sprint-index", "sprint": "object-pk-uuid",
	"role": "Landed CHECK on `objects.object_pk` enforcing the general UUID shape (8-4-4-4-12 lowercase hex) plus a tightened DEFAULT that produces a proper v4 UUID (version bit at position 15, variant bit at position 20). Loose about version/variant — accepts non-v4 UUIDs — but strict about case (lowercase only) so the same conceptual UUID can't sit under two distinct PKs. Sources: issue #1669 (CHECK shape), issue #1670 (DEFAULT forces v4 bits).",
	"status": "pre-integration — sprint schema + tests complete; shipping untouched"}
~~~

# object-pk-uuid

Hole #6 from the ChatGPT critique. Two independent looseness points, now both closed:

## Design decisions (landed)

**Issue #1669 — CHECK on shape.** Enforce the general 8-4-4-4-12 hex UUID form. Not picky about version/variant bits (v1, v3, v7, etc. still valid). **Lowercase only** — SQLite's default TEXT collation is binary, so `'ABCDEF...'` and `'abcdef...'` are two distinct PKs. Requiring lowercase means the same conceptual UUID can't accidentally get stored twice under different cases.

**Issue #1670 — DEFAULT forces v4 bits.** Position 15 → `'4'` (version); position 20 → one of `8/9/a/b` (variant). Cost was minor: two extra sub-expressions in the DEFAULT.

## The change

Two changes on the `objects.object_pk` column:

```sql
object_pk text primary key
    default (
        lower(
            substr(hex(randomblob(4)), 1, 8) || '-' ||
            substr(hex(randomblob(2)), 1, 4) || '-' ||
            '4' || substr(hex(randomblob(2)), 1, 3) || '-' ||
            substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 1, 3) || '-' ||
            substr(hex(randomblob(6)), 1, 12)
        )
    )
    check (object_pk like '________-____-____-____-____________'
        and object_pk not glob '*[^0-9a-f-]*'),
```

Two clauses in the CHECK:

- **`like '________-____-____-____-____________'`** — length = 36, hyphens at positions 9/14/19/24.
- **`not glob '*[^0-9a-f-]*'`** — no character other than lowercase hex or hyphen.

Combined, the CHECK enforces "8-4-4-4-12 lowercase hex with hyphens" without needing regex.

## Status

**Pre-integration.** Sprint schema at [sprints/object-pk-uuid/src/schema.sql](https://puck.uno/sprints/object-pk-uuid/src/schema.sql); tests at [sprints/object-pk-uuid/tests/test_object_pk_uuid.lua](https://puck.uno/sprints/object-pk-uuid/tests/test_object_pk_uuid.lua) (12 passing). Shipping untouched.

## Integration

Column-definition edit to `objects.object_pk` in shipping's `src/engine/cvm/schema.sql`. Tests promote to `tests/main/lua/engine/test_schema.lua`.

**Downstream test impact:** shipping's [tests/main/lua/engine/test_cvm.lua](https://puck.uno/tests/main/lua/engine/test_cvm.lua) uses the sentinel `'no-such-uuid-0000-0000-000000000000'` in the "cannot insert a parent_role pointing at a nonexistent row" test. That sentinel now fails the CHECK before reaching the FK / must-be-role check. Either swap the sentinel for a compliant-shape-but-nonexistent UUID (e.g., `'00000000-0000-4000-8000-000000000000'`) or accept the different error string. Neither approach is more correct — the sentinel test still verifies rejection, just at a different layer.
