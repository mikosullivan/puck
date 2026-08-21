~~~vibecode
{"doc": "sprint-index", "sprint": "numbers",
	"role": "Enforce 'all numbers are floats' end-to-end. Started as a doc sweep over the Number spec's implementation-detail hedge; grew to a full CVM-schema shape change so the storage layer enforces the language rule instead of relying on convention. Delivered four typed scalar columns replacing a polymorphic blob, split `primitive` into `base` + `control`, renamed fields to prefix by control kind, dropped scalar_type from the Lua write API, and added a `scalars` read view. Schema at 12.0; four sprint-scoped test files (57 tests) cover the changes end-to-end.",
	"status": "design + implementation complete in the sprint; production integration pending"}
~~~

# numbers

Caspian's [Number spec](https://puck.uno/requirements/built-in-classes/primitives/number) says integers and floats are one type at the language level. Under this sprint's stronger rule — **numbers are just numbers, which is another way of saying they're all floats** — the internal representation collapses to float too. What that turned into: a schema redesign that enforces the rule structurally, plus the read/write API and docs to match.

## What landed

### Schema shape change

**Four typed scalar columns replace `scalar_value blob` + `scalar_type text`.** [schema.sql](https://puck.uno/sprints/numbers/src/engine/cvm/sqlite/schema.sql):

- `scalar_null integer check (scalar_null = 1)` — marker for the language-level null value (the `u` type). Distinct from "no scalar assigned" (all four value columns null).
- `scalar_string text` — string payload; TEXT affinity keeps numeric-looking strings from silently coercing.
- `scalar_number real check (typeof(scalar_number) = 'real')` — number payload. **REAL affinity forces integer inputs to float on the way in** — this is the load-bearing enforcement of "all numbers are floats," done by SQLite's affinity system rather than by client-side coercion.
- `scalar_bool integer check (scalar_bool in (0, 1))` — boolean payload; kept in its own column so the column name never lies about its contents.

Cross-column CHECKs enforce the state machine: non-'o' rows have all four columns null; 'o' rows have at most one column populated (zero = plain object, one = typed scalar).

**`primitive` column split into `base` + `control`.** The old five-value discriminator hid a real distinction: `'o'`, `'f'`, `'r'` are all "regular objects" (they can carry a bucket + stack); `'h'` and `'a'` are containers. The split names it:

- `base text not null check (base in ('o', 'h', 'a'))` — the row's underlying storage shape.
- `control text check (control is null or control in ('f', 'r')) check (control is null or base = 'o')` — an optional CVM control-plane role. Frames and roles are `base='o'` rows that additionally play a control role. A container-that-is-also-a-frame is a schema violation, enforced by the cross-column CHECK.

The awkward `primitive in ('o', 'f', 'r')` query — Miko's original discomfort — is now just `base = 'o'`.

**Fields prefixed by control kind.** Frame-only and role-only columns wear their control prefix, matching the existing `scalar_*` pattern:

| old            | new                 |
|----------------|---------------------|
| `core_role`    | `role_core`         |
| `parent_role`  | `role_parent`       |
| `ast`          | `frame_ast`         |
| `stmt_idx`     | `frame_stmt_idx`    |
| `process_cap`  | `frame_process_cap` |
| `parent_frame` | `frame_parent`      |
| `gc`           | `frame_gc`          |

`owner_role` stays unprefixed — it's a role-typed pointer on every row, not a role-only field. `engine_class` also stays unprefixed (the "engine class" naming isn't about the containing row's kind).

**Read shape: `scalars` view.** A derived view over the four scalar columns gives callers a `(object_pk, scalar_type, value)` read API. `scalar_type` is computed via `case` from which column is populated; `value` is a `coalesce` over the three data columns.

**Schema at 12.0.** Version bumped twice during the sprint (11.0 for the base/control split; 12.0 for the field renames). Column-migration is a shape change, not a compatible tweak.

### Lua-side changes

**Polymorphic `cvm:add_scalar(value, owner_role_pk)`.** [cvm/sqlite/init.lua](https://puck.uno/sprints/numbers/src/engine/cvm/sqlite/init.lua). One method, dispatched on `type(value)`: string → `scalar_string`, number → `scalar_number` (REAL affinity does the coerce), boolean → `scalar_bool` (`true`/`false` → `1`/`0`), nil → `scalar_null`. Any other Lua type raises `add_scalar_unsupported_value_type` with the type name in the error. The old `(scalar_type, scalar_value, owner_role)` signature is gone.

**`frame:set_local_to_scalar(name, value)`.** [cvm/sqlite/frame.lua](https://puck.uno/sprints/numbers/src/engine/cvm/sqlite/frame.lua). Dropped the `scalar_type` arg — the value is passed straight through to `add_scalar`, which knows the type from Lua.

**`variable-scalar` handler simplified.** [handlers/variable-scalar.lua](https://puck.uno/sprints/numbers/src/engine/handlers/variable-scalar.lua). The type-branching block is gone; handler passes `value_atom.v` verbatim.

**`engine.lua` forked** in the sprint. `insert_cap` and `insert_frame_0` prepared statements bind `(base, control, ...) values ('o', 'f', ...)`.

**`object.lua` + `frame.lua` wrappers** dispatch on `row.control == 'f'` instead of the old `row.primitive == 'f'`.

### Docs

- [built-in-classes/primitives/number](https://puck.uno/sprints/numbers/requirements/built-in-classes/primitives/number/) — the implementation-detail hedge closed; the "spec-dependent" hedge on `.integer?` for `5.0.integer?` closed (now unambiguously `true`); the misleading `.to_integer` / `.to_float` parenthetical dropped.
- [built-in-classes/object/structure](https://puck.uno/sprints/numbers/requirements/built-in-classes/object/structure/) — "raw integer or fractional bits" → "raw float bits."
- [x-equals-1](https://puck.uno/sprints/numbers/x-equals-1) — full walkthrough of `$x = 1` under the sprint's schema. Runs the program with `%process.stop` to expose the mid-run graph, shows the objects and refs tables row-by-row, calls out how `scalar_number = 1.0` lands (REAL affinity coerced the Lua integer input to float).
- [schema.svg](https://puck.uno/sprints/numbers/requirements/cvm/sqlite/schema.svg) — ER diagram updated in place (per its own vibecode's format-lock rule). All 17 body fields in schema-column order, `base` and `control` as separate rows, `frame_process_cap` newly rendered.

### Tests

Four sprint-scoped test files, **57 tests total, 0 failures**:

| file | tests | covers |
|---|---|---|
| [test_scalar_columns.lua](https://puck.uno/sprints/numbers/tests/test_scalar_columns.lua) | 26 | schema shape — columns / affinities / column CHECKs / cross-column constraints / immutability triggers / scalars view |
| [test_add_scalar.lua](https://puck.uno/sprints/numbers/tests/test_add_scalar.lua) | 10 | `cvm:add_scalar` — polymorphic dispatch, integer→REAL coercion, boolean 1/0, unsupported-type raises |
| [test_variable_scalar.lua](https://puck.uno/sprints/numbers/tests/test_variable_scalar.lua) | 11 | handler dispatch — match / no-match / guard raises / per-Lua-type routing / gc mark on frame |
| [test_x_equals_1.lua](https://puck.uno/sprints/numbers/tests/test_x_equals_1.lua) | 10 | end-to-end — `$x = 1` runs clean, `$x = 1\n%process.stop` exposes the mid-run graph, integer coercion visible on the wire, rebind path |

## What's outstanding

- **Wording pass remnants** (from the initial survey, some still open): Number spec line 43 ("Write `5` for the integer or `5.0` for the fractional form"), a few cross-doc "integer or fractional" phrases in [built-in-classes/primitives](https://puck.uno/requirements/built-in-classes/primitives) and [primitive-buckets](https://puck.uno/requirements/built-in-classes/primitives/primitive-buckets). Per the "integer as value-shape wording is fine" rule Miko articulated during the sweep, most read fine as-is; open whether a stricter sweep is wanted.
- **Float-variant tests** for the [syntax/operators](https://puck.uno/requirements/syntax/operators) and [syntax/variables-and-assignment](https://puck.uno/requirements/syntax/variables-and-assignment) test lists. Miko's direction was "keep the integer labels, add float variants" — the additions haven't been written.
- **Production integration.** Sprint is self-consistent but hasn't landed. Big surface: schema version bump, seven Lua files, all production tests referencing the old columns (`scalar_type` / `scalar_value` / `primitive`) need updates, production docs referencing those names, production ER diagram.

## Rationale notes

- **REAL affinity, not client-side coerce.** Alternative was a `+ 0.0` in `cvm:add_scalar`. Affinity-based enforcement wins because the invariant is a property of the storage, not of one code path — a future writer bypassing `add_scalar` still can't smuggle in an integer.
- **`scalar_null` as a distinct marker column.** Redundant-looking (a null scalar is a `primitive='o'` row with no other scalar column set), but load-bearing: without it, "object with no scalar assigned" collapses into "object holding an explicit null value." The marker preserves the distinction.
- **Separate `scalar_bool` rather than storing bools in `scalar_number`.** Column names should not lie about their contents. ~1 byte per row overhead for the NULL marker on non-bool rows; not free, but bought category-honesty in exchange.
- **`base` + `control` rather than one `primitive` column.** Cleans up the awkward `primitive in ('o', 'f', 'r')` predicate; makes "frames and roles are regular objects" a schema-level fact instead of a documentation footnote.
- **Method-name question** (whether `.integer?` / `.to_integer` need renaming under the sprint's rule) resolved: keep the names. `.integer?` is a value-shape predicate ("is this whole-valued"), not a type query. Same for `.to_integer` (truncate to whole).
