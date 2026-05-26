# Edmund

~~~json
{"vibecode": {"codename": "Edmund", "delivers": "caspian-with-json-serialization",
"plan_detail_level": "enriched_roadmap_entry_not_full_phase_plan",
"will_be_detailed_after": "digory_ships",
"goal":
"caspian_can_serialize_a_hash_or_array_or_primitive_to_a_json_string_via_to_json_method",
"medium": "caspian_source_text", "candidate_fixture":
"{name: 'Picard', rank: 'Captain'}.to_json", "candidate_expected_return":
"{\"name\":\"Picard\",\"rank\":\"Captain\"}",
"covers_candidates": ["to_json_method_on_hash_class",
"to_json_method_on_string_class_already_present",
"to_json_method_on_array_class_if_arrays_landed_in_digory",
"json_encoder_reuse_from_caspian_json_lua_existing_module",
"round_trip_property_check_against_json_parse_added_in_aslan"],
"reuses_from_prior": ["bootstrap", "materialize", "lookup_method",
"transition", "dispatch", "engine_run_source", "hash_class_from_digory",
"json_encode_from_caspian_json_lua"],
"deferred_to_later": ["from_json_parsing_into_caspian_objects",
"pretty_print_option", "custom_serialization_for_user_defined_classes",
"streaming_serialization_for_large_structures"]}}
~~~

Edmund closes the loop on hashes by giving them a serialization story.
With Edmund in place, Caspian programs can produce JSON output —
unlocking real interop with external systems and (more importantly for
the roadmap) giving [Bryton](../../caspian/packages/bryton/bryton.md)
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

**Key risks (to confirm during planning):**

- **Method ownership.** `to_json` lives on each built-in class, not on
  a universal "object" base — Edmund registers it on string, hash, and
  (if landed) array. The plan should be explicit about which classes
  get it in this slice and which wait.
- **Number formatting.** `json.encode` distinguishes integer (`%.0f`)
  from float (`%.17g`). Caspian number type design touches this. If
  numbers haven't been formalized by Edmund, the slice scope narrows to
  what the fixture exercises (strings, hashes).
- **Null and missing-value handling.** `M.null` exists; user code has
  no way to construct it yet (no `null` literal exposed). Edmund should
  decide whether to expose it (probably no — defer).
- **Round-trip vs string equality.** Direct string equality on
  serialized JSON is fragile (whitespace, key order ambiguity in non-
  ordered consumers). The test asserts both: the literal string for
  the canonical form, AND `parse(encode(x)) deep_equals x`.

**Definition of done (Edmund)** — to be detailed when Digory ships and
Edmund is selected. Expected shape:

1. `to_json` method registered on string and hash classes (and array if
   present), owned by their existing class roles.
2. Fixture transpiles, dispatches, returns a string value.
3. Returned string deep-equals the expected literal JSON.
4. `caspian.json.parse(result)` deep-equals the original hash (round-
   trip).
5. Hash key order preserved through serialization.

---

<a id="skeletor-impact"></a>
## Skeletor impact

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
      "action":   "top_level",
      "role":   "user",
      "chain":  {"log": {}, "misc": {}},
      "locals": {}
    },
    {
      "action":          "method_call",
      "role":          "hash",
      "receiver_type": "hash",
      "method":        "to_json",
      "chain":         {"log": {}, "misc": {}},
      "locals":        {}
    }
  ]
}
```

— same hash shape Aslan established, same shape that has held through
Bree / Corin / Digory. **The first slice where the Skeletor hash
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
"TE.6", "TE.7", "TE.8"],
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
| TE.1 | unit | Transpiler emits canonical `.to_json` method call | `assert.deep_equal(caspian.transpile(...), {{ {hash={...}}, "to_json" }})` |
| TE.2 | unit | Bootstrap registers `to_json` on string class | `engine.classes.string.methods.to_json` is a function |
| TE.3 | unit | Bootstrap registers `to_json` on hash class | `engine.classes.hash.methods.to_json` is a function |
| TE.4 | unit | `to_json` on a string returns a JSON-quoted string | Hand-build a string value `{type="string", payload="hi"}`, call `to_json`, assert result payload is `"\"hi\""` |
| TE.5 | unit | `to_json` on a hash preserves insertion order | Hand-build `{c:1, a:2}`, call `to_json`, assert result payload starts `{"c":1,"a":2}` not `{"a":2,"c":1}` |
| TE.6 | unit | Round-trip: `parse(encode(x)) deep_equal x` | Construct a hash value, serialize via `to_json`, parse the result via `caspian.json.parse`, assert `deep_equal` to original payload structure |
| TE.7 | integration | End-to-end via source file | `engine.run_source("tests/caspian/fixtures/picard_to_json.casp")` returns a value with `payload == "{\"name\":\"Picard\",\"rank\":\"Captain\"}"` |
| TE.8 | regression | Aslan–Digory fixtures still pass | All prior canonical fixtures still produce their expected outputs |

<a id="edmund-test-layout"></a>
### Test layout

| Path | Contents |
|---|---|
| `tests/caspian/fixtures/picard_to_json.casp` | Edmund source fixture |
| `tests/caspian/edmund/` | Phase 0 + Phase 1 tests |
| `tests/caspian/run.lua` | Extended to require Edmund test modules |
| `tests/caspian/transpiler/test_*.lua` | Updated only for AST nodes realigned in Edmund (typically none — `.to_json` is a regular method call) |
