# Loaded remote library

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_examples_remote_library",
	"role": "worked Drinian snapshot after runtime-loading a Puck library and calling a method on it; demonstrates the trust barrier via cross-role chain reset",
	"status": "draft — srcs mixes file and uns entries; roles registry includes the loaded library"
}}
~~~

A program loads a remote Caspian library via `%import` and calls a method on it. Before the call, the user stashes an API token in `%chain` — the library MUST NOT be able to see it. The trust barrier falls out of the existing cross-role chain reset described in [chain § Role boundaries reset everything](https://puck.uno/requirements/chain/#role-boundaries-reset-everything); no new mechanism needed.

Caspian source (capture happens during the `to_html` call, inside the loaded library — there's no user-source line to mark; the library is doing the work):

~~~caspian
$markdown = %('markdown.uno/render')
%chain['api_token'] = 'sk-secret-abc123'
$html = $markdown.to_html('# Hello')    # CAPTURED while inside to_html
puts $html
~~~

Paused inside `to_html` in the loaded library, after the library has tokenized the input and started building output.

~~~json
{
	"srcs": {
		"a": {"file": "/home/miko/render_post.casp"},
		"b": {"uns": "markdown.uno/render/render.casp"}
	},
	"roles": {
		"user": {},
		"engine": {},
		"markdown.uno/render": {
			"loaded_from": "markdown.uno/render",
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
				"api_token": {"value": "sk-secret-abc123", "src": ["a", 2]}
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
			},
			"chain": {}
		}
	]
}
~~~

<!-- SPEC CONFLICT: archive uses %puck['url'] which is legacy; current spec uses %import(url) or %(url) — rewritten to %(...) -->

<!-- SPEC CONFLICT: archive stores chain values in a nested "misc" sub-hash (chain.misc.api_token). Current spec (chain/index.md) uses a flat hash: %chain['api_token']. Rewritten to the flat form. Also, archive shows chain as always present on every frame with {log: {}, misc: {}} skeleton; current spec has no such structure — needs Miko decision on whether the chain field appears at all in the per-frame snapshot or is implied by the aggregate-hash walk -->

What to notice:

- **`srcs` registry has two entries with tagged kinds.** Entry `a` is `{"file": ...}` for the local script. Entry `b` is `{"uns": ...}` for the URL-loaded library. The key declares the source kind, so consumers don't have to parse strings to distinguish them.
- **`roles` registry has three entries.** Two engine-bootstrap roles plus the runtime-loaded `markdown.uno/render` role. The library's role entry carries metadata: where it was loaded from, where in user code the load happened, and its trust web (empty).
- **The library's role name IS its URL.** `markdown.uno/render` as a role name is fine — names are arbitrary strings, and the URL gives a globally unique identifier with no collision risk between loaded libraries.
- **The library's class is not visible in the snapshot.** Class registries are engine-private state, not part of Drinian — see [drinian § Classes are NOT in Drinian](https://puck.uno/requirements/drinian/#classes-are-not-in-drinian). `Renderer` was registered when `%('markdown.uno/render')` ran at top level on line 1; the dispatcher knows about it because the engine's class registry knows about it, not because the snapshot shows it. Dispatch resolves `class_ref: "Renderer"` and `receiver_type: "Renderer"` by looking up "Renderer" in the engine's registry; the snapshot just shows the *name* being resolved.
- **Trust barrier is invisible by design — the chain shows it.** Frame 0 (user) has `chain: {"api_token": "sk-secret-abc123"}`. Frame 1 (the library's `to_html`) has `chain: {}` — empty. The library cannot reach the token by reading `%chain['api_token']`. Per [chain § Role boundaries reset everything](https://puck.uno/requirements/chain/#role-boundaries-reset-everything), any call that crosses into a different role starts the new frame with an empty hash slot; the caller's values do not carry across. Trust isolation is the role boundary's normal behavior, not a special remote-library feature. <!-- SPEC CONFLICT: archive says chain is per-frame independent with NO cascade at all, wiped even for same-role calls; current chain spec (chain/index.md) says chain inherits downward within a role and only resets at role boundaries. The remote-library example works under either model because this specific case IS a role boundary, but the archive's broader description conflicts with the current spec — the main drinian doc needs the same edit -->
- **`lexical_parent: null` on the library's frame.** The library's `to_html` was defined in the library's own top-level scope, which ran once when the library was loaded and then unwound. Its captured environment isn't on the live `call_stack`. In a full implementation this would point into a `captured_envs` sibling field; V1.0 leaves it `null` because escaped-closure environments aren't built yet.
- **`input`'s `src` is `["a", 3]`, not `["b", N]`.** The value was born as a literal on line 3 of the user's file, then passed across the role boundary. The library can see where its input originated. Open question: feature, or info leak across the trust barrier?
- **`tokens`'s `src` entries point to file `b`.** Values created inside the library carry the library's source location. The file key disambiguates from user-file lines.
