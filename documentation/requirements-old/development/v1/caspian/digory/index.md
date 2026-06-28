# Digory

~~~vibecode
{"vibecode": {"codename": "Digory", "delivers": "caspian-with-hashes",
"plan_detail_level": "enriched_roadmap_entry_not_full_phase_plan",
"will_be_detailed_after": "corin_ships",
"goal":
"caspian_can_construct_a_hash_literal_read_a_key_and_iterate_in_insertion_order",
"medium": "caspian_source_text", "candidate_fixture":
"{name: 'Picard'}.name", "candidate_expected_return": "Picard",
"alt_fixture_for_iteration_check":
"{name: 'Picard', rank: 'Captain'}.each($k, $v) do; puts $k; end",
"covers_candidates": ["hash_class_registration",
"hash_literal_materialization_preserving_insertion_order",
"key_access_method_name_tbd_bracket_or_get",
"hash_class_each_for_iteration",
"transpiler_realignment_for_hash_literal_shape"],
"reuses_from_prior": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "engine_run", "engine_parse_caspian",
"engine_caspianj_property", "json_parser_ordered_hash_support",
"bwc_dispatch_if_iteration_fixture_chosen"],
"deferred_to_later": ["hash_mutation_methods_set_delete",
"hash_equality_semantics", "hash_with_non_string_keys_if_ever",
"arrays_as_separate_class"]}}
~~~

Digory introduces the hash data structure. The minimum: a hash literal
evaluates, a key lookup returns the value, and the harness observes the
result. Order preservation is load-bearing because Puck hashes have
significant key order (per [caspianj.md](../../caspian/caspianj.md)
"Hash key order").

**Why this is its own slice rather than bundled with Corin.** Hashes
have their own non-trivial design questions — the key-access method
shape (`$h.name` vs `$h['name']` vs `$h.get('name')`), iteration
semantics, order preservation. Bundling them with stdout obscures both.

**Candidate fixture:** `{name: 'Picard'}.name` returning `"Picard"`.
This is the simplest possible hash exercise — one key, one access.
Iteration (`.each`) is plausibly a Digory stretch goal but probably
belongs in Edmund or later if it complicates the slice.

**Key risks (to confirm during planning):**

- **Hash key-access via method_missing.** `$h.name` and `$h['name']`
  both produce method calls (`[$h, "name"]` and `[$h, "[]", "name"]`
  respectively); for `$h.name`, lookup fails on the hash class's
  explicit methods table and falls through to `method_missing`, which
  reads the bucket. Digory adds method_missing semantics to
  `engine.lookup_method` — small, general-purpose, reusable by future
  classes.
- **Ordered-hash plumbing.** `caspian.json.new_hash` already provides
  ordered storage; the engine has to use it consistently for
  hash-literal materialization. Mixing plain Lua tables and ordered
  hashes is a source of subtle bugs.
- **Hash class registration.** Engine grows a second built-in class
  (string was the first); the bootstrap path becomes "classes table
  has N entries" rather than "one class for strings only."
- **Transpiler shape for hash literals.** Per caspianj.md, hash
  literals serialize as `{"hash": [[key, expr], ...]}` (array of
  pairs, preserving insertion order). The current transpiler emits
  the unordered-object shape `{"hash": {"key": expr, ...}}` — Digory
  realigns it to canonical.

**Definition of done (Digory)** — to be detailed when Corin ships and
Digory is selected. Expected shape:

1. Source fixture parses and transpiles to canonical hash form.
2. Hash class registered in bootstrap, owned by an engine role.
3. Hash literal materializes preserving insertion order.
4. Key access returns the expected value.
5. Harness observes the returned value.

---

## Drinian impact

Digory introduces the hash data structure, but the
[Drinian state hash](aslan.md#data-structures-lua-tables) shape
doesn't change. Hash literals and their materialized values are
working state per
[drinian.md's working-state carve-out](../../caspian/drinian/index.md#v1-0-scope) —
they live in Lua locals during evaluation, not in `engine.state`.
The hash class itself joins `engine.classes` (bootstrap metadata,
outside the state hash) and gets its own owning role in
`engine.roles` (likewise).

A snapshot mid-fixture, during the `.name` method call on
`{name: 'Picard'}`:

```json
{
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    },
    {
      "action": "method_call",
      "role": "stdlib",
      "receiver_type": "puck.uno/hash",
      "method": "name",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

Same hash shape Aslan established. Per
[roles.md § Implementation growth path](../../../caspian/roles.md#implementation-growth-path),
the hash class is owned by the existing `stdlib` role (same pattern as
the string class from Aslan) — no new role is introduced. The `method`
field reads `"name"` because the canonical statement for `$h.name` is
`[$h, "name"]`. The dispatch path is **method_missing** (settled
2026-05-28): hash class registers no per-key methods; instead, when
`engine.lookup_method` fails to find `"name"`, it falls through to a
`method_missing(receiver, name, args)` handler on the class, and
hash's handler returns the bucket value for that key.

---

## Testing

~~~vibecode
{"vibecode": {"section": "testing", "test_directory":
"tests/caspian/digory/", "fixture_path":
"tests/caspian/fixtures/picard_hash.casp",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TD.0.1"],
"phase_1_tests": ["TD.1", "TD.2", "TD.3", "TD.4", "TD.5", "TD.6", "TD.7"],
"load_bearing_test": "TD.3_insertion_order_preservation"}}
~~~

Tests for Digory sit under `tests/caspian/digory/` using
`support/runner` + `support/assert`. TD.3 (insertion-order
preservation) is the load-bearing assertion — Puck hashes have
significant key order, so a hash that round-trips its keys in any
other sequence is broken regardless of the rest passing.

### Phase 0 test

| ID | Level | Verifies |
|---|---|---|
| TD.0.1 | unit | Source pipeline (`tokenize` → `parse` → `transpile`) completes for the Digory fixture string `{name: 'Picard'}.name`; current transpiler output captured as Phase 1 baseline |

### Phase 1 tests

| ID | Level | Verifies | How |
|---|---|---|---|
| TD.1 | unit | Transpiler emits canonical hash-literal form | `assert.deep_equal(engine.parse_caspian("{name: 'Picard'}.name"), {{ {hash={{"name", {value="Picard"}}}}, "name" }})` |
| TD.2 | unit | Bootstrap registers hash class | `engine.classes["puck.uno/hash"]` exists; `engine.classes["puck.uno/hash"].owning_role == engine.state.roles.stdlib`; the chosen key-access entry point is a function |
| TD.3 | unit | Hash literal materializes preserving insertion order | Construct `{c:1, a:2, b:3}` and walk the hash's stored key order; expect `["c", "a", "b"]`, NOT `["a", "b", "c"]` |
| TD.4 | unit | Key access returns expected value via method_missing | Hand-build the canonical hash value; dispatch `[hash, "name"]`; `engine.lookup_method` falls through to `puck.uno/hash`'s `method_missing` which returns the bucket value; assert payload `== "Picard"` |
| TD.5 | unit | Role transition observed during key access | Spy on the access path records the top-of-stack frame's `role` at call time; assert it was `stdlib` (the hash class's owning role), not `user` |
| TD.6 | integration | End-to-end via source file | Stage the parsed fixture on `engine.caspianj` and call `engine.run()`; result has `payload == "Picard"` |
| TD.7 | regression | Prior fixtures still pass | Aslan `hello_world.caspj` (stage via `json.parse` + `engine.run`), Bree `hello_world.casp` (stage via `engine.parse_caspian` + `engine.run`), Corin `puts_hello.casp` (stage + set `engine.std` + `engine.run`) all still produce their expected outputs |

### Test layout

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/picard_hash.casp` | Digory source fixture |
| `tests/caspian/digory/` | Phase 0 + Phase 1 tests |
| `tests/caspian/run.lua` | Extended to require Digory test modules |
| `tests/caspian/transpiler/test_*.lua` | Updated only for hash-literal AST nodes realigned in Digory |
