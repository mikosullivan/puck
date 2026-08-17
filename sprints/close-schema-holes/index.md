~~~vibecode
{"doc": "sprint-index", "sprint": "close-schema-holes",
	"role": "Sprint to close constraint gaps in the CVM schema — places where a convention exists (hashes use keys, arrays use idx, parent_frame is a frame, etc.) but the schema doesn't enforce it. Starting known-holes list is seven items sourced from a ChatGPT critique of the schema (issue #1663); more may surface as we work.",
	"status": "active — known-holes list open"}
~~~

# close-schema-holes

Sprint to tighten the CVM schema — closing places where a shape convention is documented and relied on by the write layer but not enforced by triggers or checks. The schema should reject convention violations at write time (loud, specific) rather than silently accepting them and letting the read layer trip on bad data.

## Reference pages

- [initialized](./initialized) — snapshot of `objects` at initialized state (schema installed, three seed role rows, nothing else). Full column set.
- [role-rules](./role-rules) — report of what the schema currently enforces on role records; baseline for sprint decisions about role-related holes.
- [critique](./critique) — full text of the ChatGPT schema-invariant review from issue #1663.

Guiding principle (from the [critique](./critique)):

> If SQLite accepts the transaction, the resulting database represents a valid CVM program state.

## Known holes

Sourced from the ChatGPT critique in issue #1663 (full text at [critique.md](./critique)). Grouped by the critique's recommended priority. Each hole gets a trigger + specific error id + test in [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua).

### Fix first

1. ~~**Hash / array key semantics not enforced.**~~ **Landed in sprint.** Two triggers (`refs_hash_key_required`, `refs_array_key_forbidden`) enforce `parent.primitive = 'h' ⇒ key not null` and `parent.primitive = 'a' ⇒ key null`. Sprint schema at [sprints/close-schema-holes/src/schema.sql](https://puck.uno/sprints/close-schema-holes/src/schema.sql); tests at [sprints/close-schema-holes/tests/test_hash_array_keys.lua](https://puck.uno/sprints/close-schema-holes/tests/test_hash_array_keys.lua). See [critique § 1](./critique#1-hash-and-array-reference-key-semantics-are-not-enforced).

2. **`parent_frame` doesn't require its target to be a frame.** The `parent_frame` FK checks that the row *holding* the pointer is a frame, but not that the row it *points at* is one. Existing gc-cycle triggers assume it is. See [critique § 2](./critique#2-parent_frame-does-not-require-its-target-to-be-a-frame). **Severity: critical** — this is the strongest hole because later logic depends on the missing invariant.

### Investigate and probably fix

3. ~~**`stmt_idx` has no upper bound relative to ast.**~~ **Landed in sprint** (issue #1665). Two triggers (`frames_stmt_idx_within_ast_bounds` for INSERT + `_on_update` for UPDATE OF stmt_idx) enforce `stmt_idx <= max(json_array_length(ast), 1)`. Empty ast → `{0, 1}` (born + cap-terminal); length-N ast → `{0..N}`. Sprint schema at [sprints/close-schema-holes/src/schema.sql](https://puck.uno/sprints/close-schema-holes/src/schema.sql); tests at [sprints/close-schema-holes/tests/test_stmt_idx_bounds.lua](https://puck.uno/sprints/close-schema-holes/tests/test_stmt_idx_bounds.lua). See [critique § 4](./critique#4-stmt_idx-has-no-upper-bound-relative-to-ast).

### Make explicit design decisions

4. **What kinds of objects may be roles?** `role_parent` currently accepts any primitive, including scalars and frames. Core roles are hashes; if that's the intended type constraint, encode it. Otherwise document that any primitive may be a role. See [critique § 3](./critique#3-roles-can-be-arbitrary-primitive-types). **Severity: design-dependent.**

5. **`scopes` ref ownership.** Currently any container can carry a `key = 'scopes'` ref. If scopes belong to a specific structural object (frame bucket), enforce the parent side. Partially addressed by fixing hole #1. See [critique § 5](./critique#5-the-special-scopes-reference-is-not-fully-restricted-to-its-intended-context). **Severity: medium / design-dependent.**

6. **`object_pk` isn't constrained to UUIDs.** Default generates UUID-shape; caller can supply any text (`'banana'` accepted). Also the default doesn't force UUIDv4 version/variant bits. Decide whether the pk shape is opaque-text or actually-a-UUID. See [critique § 6](./critique#6-object_pk-is-not-actually-constrained-to-uuids). **Severity: low / design-dependent.**

## Pattern for each hole

Per hole:

- **Trigger** with a specific error id (per [[feedback_error_id_format]] — `<snake_id>: <message>`).
- **Test** in [tests/main/lua/engine/test_schema.lua](https://puck.uno/tests/main/lua/engine/test_schema.lua) that exercises the reject path.
- **One-line note** in the schema comment near the affected column.

## Status

**Active.** Six known holes remaining. Suspect there are more — will keep adding as they surface.
