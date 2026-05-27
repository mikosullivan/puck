# Example 05: Loaded remote library

~~~json
{"vibecode": {"example": "loaded_remote_library",
	"shows": "skeletor_after_runtime_loading_a_puck_library_and_calling_a_method_on_it; demonstrates_trust_barrier_via_cross_role_chain_wipe",
	"shape": "srcs_mixes_file_and_uns_entries; roles_includes_loaded_library; chain_isolation_at_role_boundary",
	"key_idea": "loaded_library_is_structurally_identical_to_any_other_role_introducing_thing"}}
~~~

A program loads a remote Caspian library via `%puck` and calls a
method on it. Before the call, the user stashes an API token in
`%chain.misc` — the library MUST NOT be able to see it. The trust
barrier falls out of the existing cross-role chain wipe; no new
mechanism needed.

Caspian source (capture happens during the `to_html` call, inside
the loaded library — there's no user-source line to mark; the
library is doing the work):

~~~caspian
$markdown = %puck['markdown.uno/render']
%chain.misc.api_token = 'sk-secret-abc123'
$html = $markdown.to_html('# Hello')    # CAPTURED while inside to_html
puts $html
~~~

Paused inside `to_html` in the loaded library, after the library has
tokenized the input and started building output.

```json
{
  "srcs": {
    "a": {"file": "/home/miko/render_post.casp"},
    "b": {"uns": "markdown.uno/render/render.casp"}
  },
  "roles": {
    "user": {},
    "stdlib": {},
    "markdown.uno/render": {
      "loaded_from": "puck://markdown.uno/render",
      "loaded_at": ["a", 1],
      "trust": []
    }
  },
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "lexical_parent": null,
      "src": ["a", 3],
      "locals": {
        "markdown": {"class_ref": "Renderer", "src": ["a", 1]}
      },
      "chain": {
        "log": {},
        "misc": {
          "api_token": {"value": "sk-secret-abc123", "src": ["a", 2]}
        }
      }
    },
    {
      "action": "method_call",
      "role": "markdown.uno/render",
      "receiver_type": "Renderer",
      "method": "to_html",
      "lexical_parent": null,
      "src": ["b", 47],
      "locals": {
        "input": {"value": "# Hello", "src": ["a", 3]},
        "tokens": {"array": [
          {"value": "H1_OPEN", "src": ["b", 32]},
          {"value": "Hello", "src": ["b", 35]},
          {"value": "H1_CLOSE", "src": ["b", 38]}
        ], "src": ["b", 41]}
      }
    }
  ]
}
```

What to notice:

- **`srcs` registry has three entries with tagged kinds.** Entry `a`
  is `{"file": ...}` for the local script. Entry `b` is `{"uns": ...}`
  for the Puck-loaded library. The key declares the source kind, so
  consumers don't have to parse strings to distinguish them.
- **`roles` registry has three entries.** Two engine-bootstrap roles
  plus the runtime-loaded `markdown.uno/render` role. The library's
  role entry carries metadata: where it was loaded from, where in
  user code the load happened, and its trust web (empty).
- **The library's role name IS its UNS.** `markdown.uno/render` as a
  role name is fine — names are arbitrary strings, and UNS gives a
  globally unique identifier with no collision risk between loaded
  libraries.
- **The library's class is not visible in the snapshot.** Class
  registries are engine-private state, not part of Skeletor — see
  [skeletor.md § Classes are NOT in Skeletor](../../skeletor/skeletor.md#classes-not-in-skeletor).
  `Renderer` was registered when `%puck['markdown.uno/render']` ran
  at top level on line 1; the dispatcher knows about it because the
  engine's class registry knows about it, not because the snapshot
  shows it. Dispatch resolves `class_ref: "Renderer"` and
  `receiver_type: "Renderer"` by looking up "Renderer" in the
  engine's registry; the snapshot just shows the *name* being
  resolved.
- **Trust barrier is invisible by design — the chain shows it.**
  Frame 0 (user) has `chain.misc.api_token = "sk-secret-abc123"`.
  Frame 1 (the library's `to_html`) has `chain: {"log": {}, "misc": {}}`
  — empty. The library cannot reach the token by walking
  `%chain.misc.api_token`. Trust isolation is the role boundary's
  normal behavior, not a special remote-library feature.
- **`lexical_parent: null` on the library's frame.** The library's
  `to_html` was defined in the library's own top-level scope, which
  ran once when the library was loaded and then unwound. Its
  captured environment isn't on the live `call_stack`. In a full
  implementation this would point into a `captured_envs` sibling
  field; V1.0 leaves it `null` because escaped-closure environments
  aren't built yet.
- **`input`'s `src` is `["a", 3]`, not `["b", N]`.** The value was
  born as a literal on line 3 of the user's file, then passed across
  the role boundary. The library can see where its input originated.
  Open question: feature, or info leak across the trust barrier?
- **`tokens`'s `src` entries point to file `b`.** Values created
  inside the library carry the library's source location. The file
  key disambiguates from user-file lines.
