# Edmund

~~~json
{"vibecode": {"codename": "Edmund", "delivers": "caspian-with-json-serialization",
"plan_detail_level": "enriched_roadmap_entry_not_full_phase_plan",
"will_be_detailed_after": "digory_ships",
"goal":
"caspian_can_serialize_a_hash_or_a_primitive_to_a_json_string_via_to_json_method",
"medium": "caspian_source_text", "candidate_fixture":
"{name: 'Picard', rank: 'Captain'}.to_json", "candidate_expected_return":
"{\"name\":\"Picard\",\"rank\":\"Captain\"}",
"covers_candidates": ["to_json_method_added_to_string_class",
"to_json_method_added_to_hash_class",
"json_encoder_reuse_from_caspian_json_lua_existing_module",
"round_trip_property_check_against_json_parse_already_in_engine"],
"reuses_from_prior": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "engine_run", "engine_caspianj_property",
"engine_parse_caspian", "hash_class_from_digory",
"json_encode_from_caspian_json_lua"],
"deferred_to_later": ["from_json_parsing_into_caspian_objects",
"pretty_print_option", "custom_serialization_for_user_defined_classes",
"streaming_serialization_for_large_structures",
"array_class_and_to_json_on_arrays"]}}
~~~

Edmund closes the loop on hashes by giving them a serialization story.
With Edmund in place, Caspian programs can produce JSON output —
unlocking real interop with external systems and (more importantly for
the roadmap) giving [Bryton](../../caspian/packages/bryton/index.md)
a credible Xeme-emission story.

**Reuses existing infrastructure.** `caspian.json.encode` (already in
the engine) does the actual JSON formatting. Edmund's work is mostly
about wiring: registering `to_json` methods on the built-in classes,
making sure ordered hashes serialize with their keys in order, and
proving round-trip equivalence with `caspian.json.parse` (added in
Aslan phase 1).

**Candidate fixture:**
`{name: 'Picard', rank: 'Captain'}.to_json` returning
`{"name":"Picard","rank":"Captain"}`. The round-trip check —
`caspian.json.parse(result)` deep-equals the original hash — is the
load-bearing assertion.

**Key design decisions:**

- **Method ownership.** `to_json` lives on each built-in class, not on
  a universal "object" base — Edmund registers it on string, hash,
  number, null, true, and false. Every built-in class is owned by the
  existing `stdlib` role (same pattern as Aslan/Digory); no new role
  is introduced. Arrays are deferred (not in Digory's scope, so not
  in Edmund's either). Alternative: now that Digory added
  method_missing, `to_json` could be implemented as a generic
  class-level handler rather than per-class registration. Per-class
  is simpler for Edmund's narrow surface; revisit if/when more
  built-in classes appear.

- **`materialize` expands to cover number, null, true, false.** Today
  it handles only string and hash. Edmund adds four small branches so
  a JSON encoder is actually complete — anything less can't round-trip
  a realistic hash. Every materialized value follows the same shape
  `{type, owning_role, payload}`, with `type` being the UNS-prefixed
  class name and `payload` carrying the actual value:

  | CaspianJ expression | type | payload |
  |---|---|---|
  | `{value: "hello"}` | `"puck.uno/string"` | `"hello"` (Lua string) |
  | `{value: 42}` | `"puck.uno/number"` | `42` (Lua number) |
  | `{value: <json-null>}` | `"puck.uno/null"` | `caspian.json.null` (sentinel) |
  | `{value: true}` | `"puck.uno/true"` | `true` (Lua boolean) |
  | `{value: false}` | `"puck.uno/false"` | `false` (Lua boolean) |
  | `{hash: [[k, v], ...]}` | `"puck.uno/hash"` | `caspian.json.new_hash()` |

  Null's payload is the actual `caspian.json.null` sentinel — not Lua
  nil, which would silently disappear from the value table. Per-call
  uniqueness comes for free: each `materialize` call allocates a fresh
  value table, so two materializations of `null` are distinct objects
  even though their payloads are the same singleton sentinel. The
  full platter-model treatment for null/true/false (a sticky platter
  directly under shadow carrying `puck.uno/null` or `puck.uno/false`,
  engine-only stickiness enforcement) is out of scope for Edmund — it
  arrives with the platter model.

- **JSON null handling.** The `caspian.json.null` sentinel survives
  round-trip through `caspian.json.parse` / `caspian.json.encode`. The
  current `materialize` branch `if expr.value ~= nil` treats the
  sentinel as truthy and falls into the wrong arm — Edmund adds an
  explicit check **before** the type-dispatch:

  ```lua
  if expr.value == caspian.json.null then
      return { type = "puck.uno/null",
               owning_role = top_frame().role,
               payload     = caspian.json.null }
  end
  ```

- **No null literal in user source.** `null` as a Caspian-source token
  is a separate question. Edmund only needs to handle JSON null in
  CaspianJ; whether user code can write `null` in `.casp` files is
  out of scope.

- **Round-trip vs string equality.** Direct string equality on
  serialized JSON is fragile (whitespace, key order ambiguity in
  non-ordered consumers). The test asserts both: the literal string
  for the canonical form, AND `parse(encode(x)) deep_equals x`.

**Definition of done (Edmund)** — to be detailed when Digory ships and
Edmund is selected. Expected shape:

1. `engine.materialize` recognizes number, null, true, and false
   literals in addition to string and hash. Each produces a value
   `{type, owning_role, payload}` with the UNS-prefixed class name
   and an actual payload (no Lua nil, no payload-omitted shapes).
2. `to_json` method registered on every built-in class (string, hash,
   number, null, true, false), owned by the `stdlib` role.
3. Fixture transpiles, dispatches, returns a string value.
4. Returned string deep-equals the expected literal JSON.
5. `caspian.json.parse(result)` deep-equals the original hash
   (round-trip).
6. Hash key order preserved through serialization.

---

<a id="drinian-impact"></a>
## Drinian impact

Edmund adds `to_json` methods to existing classes but introduces no
new persistent state. The hash being serialized is a working value
(Lua local during evaluation, not in
[`engine.state`](aslan.md#data-structures-lua-tables)); the JSON
string the encoder produces is another working value, eventually
handed to the harness as the dispatch return.

A snapshot mid-`.to_json` call:

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
      "method": "to_json",
      "chain": {"log": {}, "misc": {}},
      "locals": {}
    }
  ]
}
```

— same hash shape Aslan established, same shape that has held through
Bree / Corin / Digory. **The first slice where the Drinian hash
grows new top-level fields is [Frank](frank.md)**, when `argv` joins
it as program state visible via `%argv`.

---

<a id="testing"></a>
## Testing

~~~json
{"vibecode": {"section": "testing", "test_directory":
"tests/caspian/edmund/", "fixture_path":
"tests/caspian/fixtures/picard_to_json.casp",
"framework": "support_runner_and_assert",
"phase_0_tests": ["TE.0.1"],
"phase_1_tests": ["TE.1", "TE.2", "TE.3", "TE.4", "TE.5",
"TE.6", "TE.7", "TE.8", "TE.9"],
"load_bearing_test":
"TE.6_round_trip_parse_encode_deep_equals_original"}}
~~~

Tests for Edmund sit under `tests/caspian/edmund/` using
`support/runner` + `support/assert`. TE.6 (round-trip) is the
load-bearing assertion — string-equality on serialized JSON is
fragile (whitespace, key-order ambiguity in non-ordered consumers),
so the test that proves correctness is `parse(encode(x)) deep_equal x`,
not just `encode(x) == "..."`.

<a id="edmund-phase-0-test"></a>
### Phase 0 test

| ID | Level | Verifies |
|---|---|---|
| TE.0.1 | unit | Source pipeline (`tokenize` → `parse` → `transpile`) completes for the Edmund fixture `{name: 'Picard', rank: 'Captain'}.to_json`; current transpiler output recorded as Phase 1 baseline |

<a id="edmund-phase-1-tests"></a>
### Phase 1 tests

| ID | Level | Verifies | How |
|---|---|---|---|
| TE.1 | unit | Transpiler emits canonical `.to_json` method call | `assert.deep_equal(engine.parse_caspian(...), {{ {hash={...}}, "to_json" }})` |
| TE.2 | unit | Bootstrap registers `to_json` on every primitive class | `engine.classes["puck.uno/string"].methods.to_json`, `engine.classes["puck.uno/hash"].methods.to_json`, `["puck.uno/number"]`, `["puck.uno/null"]`, `["puck.uno/true"]`, `["puck.uno/false"]` — all functions |
| TE.3 | unit | `materialize` produces correct value for each new literal type | Pass `{value: 42}`, `{value: caspian.json.null}`, `{value: true}`, `{value: false}` to `engine.materialize`; assert each returns the expected `{type, payload}` pair |
| TE.4 | unit | `to_json` on a string returns a JSON-quoted string | Hand-build a string value `{type="puck.uno/string", payload="hi"}`, call `to_json`, assert result payload is `"\"hi\""` |
| TE.5 | unit | `to_json` on a hash preserves insertion order | Hand-build `{c:1, a:2}`, call `to_json`, assert the result payload is exactly `{"c":1,"a":2}` (insertion order), NOT `{"a":2,"c":1}` (alphabetical) |
| TE.6 | unit | Round-trip: `parse(encode(x)) deep_equal x` | Construct a hash value containing string, number, null, true, and false leaves; serialize via `to_json`; parse the result via `caspian.json.parse`; assert `deep_equal` to the original payload structure |
| TE.7 | integration | End-to-end via source file | Stage the parsed fixture on `engine.caspianj` and call `engine.run()`; result has `payload == "{\"name\":\"Picard\",\"rank\":\"Captain\"}"` |
| TE.8 | regression | Aslan–Digory fixtures still pass | All prior canonical fixtures still produce their expected outputs |
| TE.9 | unit | Each null materialization is a distinct value table | `m1 = materialize({value=caspian.json.null}); m2 = materialize({value=caspian.json.null})`; assert `m1 ~= m2` (distinct tables) but `m1.payload == m2.payload` (same singleton sentinel) |

<a id="edmund-test-layout"></a>
### Test layout

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/picard_to_json.casp` | Edmund source fixture |
| `tests/caspian/edmund/` | Phase 0 + Phase 1 tests |
| `tests/caspian/run.lua` | Extended to require Edmund test modules |
| `tests/caspian/transpiler/test_*.lua` | Updated only for AST nodes realigned in Edmund (typically none — `.to_json` is a regular method call) |
