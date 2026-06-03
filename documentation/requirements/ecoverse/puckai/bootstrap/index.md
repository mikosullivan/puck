# Puckai Bootstrap

*Helping cold-start receivers learn the Puckai format on the fly.*

~~~json
{"vibecode": {
	"doc": "Puckai_bootstrap",
	"role": "spec for Puckai's bootstrap mechanism — a single authoritative vibecode hash that appears in two forms: wrapped (when embedded inline into a worldlet) and bare (when served standalone at a URL for cold agents to fetch). Same content; two contexts, two shapes.",
	"audience": ["AI agents that send Puckai worldlets",
		"AI agents that receive Puckai worldlets and may need to learn the format on the fly"],
	"shared_spec": "../index.md",
	"canonical_source": "bootstrap.json (wrapped form, source-of-truth)",
	"served_url": "https://puck.uno/ai/puckai/vibecode.json (bare-hash standalone form)",
	"trigger_for_inline": "$request.bootstrap = true on the sending side"
}}
~~~

**Bootstrap** is how a worldlet teaches its own format to a receiving agent that doesn't already know Puckai. The mechanism rests on **one authoritative vibecode hash** that appears in two contexts, with the shape adjusted to fit each context.

---

<a id="one-source-two-forms"></a>
## One source, two forms

There's **one canonical bootstrap content** — instructions, format description, class library, etc. It lives in [bootstrap.json](bootstrap.json) as the source of truth. From that single source, two forms are derived for the two contexts where the content appears:

| Context | URL / location | Shape | Why this shape |
|---|---|---|---|
| **Embedded** in a worldlet | [bootstrap.json](bootstrap.json) — merged into the outgoing worldlet's top-level vibecode when `bootstrap: true` | Wrapped: `{"vibecode": {...}}` | Inside a worldlet, vibecode coexists with other top-level keys (`format`, `uuid`, `records`). The wrapper marks "this content belongs under the `vibecode` key." |
| **Standalone** at a URL | `https://puck.uno/ai/puckai/vibecode.json` | Bare: `{"instructions": "...", "what_a_worldlet_is": {...}, ...}` | A standalone document IS the vibecode; there's nothing alongside it to discriminate from. The wrapper would be ceremony. |

The two are kept in sync by derivation: bootstrap.json is the source, the bare form served at `vibecode.json` is the same content with the outer `{"vibecode": ...}` wrapper stripped. Either built at deploy time or transformed on serve; no manual duplication.

---

<a id="how-to-trigger"></a>
## How a cold receiver gets bootstrapped

Every outgoing Puckai worldlet — bootstrap setting or not — carries **at minimum a directive pointer** so a cold receiver knows where to look. The default vibecode block on a worldlet includes:

```json
"vibecode": {
    "instructions": "This is an Puckai worldlet. Spec: https://puck.uno/ai/puckai/vibecode.json"
}
```

A cold agent reading the worldlet sees the `instructions` field (the most directive name available) and the URL. From there it can either:

- **Fetch the URL** — get the bare-hash standalone vibecode document, parse it, and proceed.
- **Read the inline content** if `bootstrap: true` was set on the send.

### `bootstrap: true` — inline the full content

On the sending agent, set [`$request.bootstrap = true`](../agent.md#request-bootstrap):

```
$request = $agent.request_init
$request.bootstrap = true
# dispatch
```

The sending side **deep-merges** the full instruction hash from [bootstrap.json](bootstrap.json) into the outgoing worldlet's top-level vibecode. The receiver gets everything inline; no network call needed to learn the format.

When `bootstrap` is `false` (the default), only the minimal `instructions` pointer goes — the receiver follows the URL if they need the full content.

**Deep merge semantics.** The worldlet's existing top-level vibecode (e.g. `agent_guidance`) and the bootstrap's vibecode (`instructions`, `what_a_worldlet_is`, `class_library`, etc.) typically have non-overlapping keys, so the merge just combines them. For the rare case where both touch the same nested key, **the caller's value wins** — the bootstrap provides universal/generic info, the caller provides specific intent, specific overrides generic.

---

<a id="when-to-inline"></a>
## When to inline vs. let the receiver fetch

**Inline (`bootstrap: true`) when:**

- The receiver might not have network access to follow the URL (air-gapped environments, sandboxed agents, offline replay).
- You're producing audit-grade documents that need to be readable later by anyone, anywhere, regardless of whether `puck.uno` is reachable.
- Latency on the receiver side matters and you'd rather pay the bigger payload than the network round-trip.

**Skip inline (default; minimal pointer only) when:**

- The receiver has internet and can follow URLs.
- Traffic volume makes the prelude overhead noticeable.
- The receiver is known to be format-aware (won't need the bootstrap at all; the pointer is just there in case).

---

<a id="future-direction"></a>
## Future direction

Possible additions that aren't part of bootstrap today but may be later:

- A class-library prelude that includes every Puckai class definition inline.
- Per-record `vibecode` hints that teach each class's semantics from instances.
- A version-stamped reference so a receiver who has already learned version `X` can skip the prelude on subsequent worldlets.
- Multiple standalone vibecode documents at different URLs for different scopes (e.g. Puckai-specific vs. generic-worldlet).

These are deliberately deferred. The current design is one canonical source served in two forms; that's it.

---

<a id="full-content"></a>
## The bootstrap content — full

The current bootstrap content, embedded inline. Same content as [bootstrap.json](bootstrap.json), and (modulo the wrapper) what's served at the standalone URL.

<!-- file: bootstrap.json -->

---

<a id="related"></a>
## Related

- [Puckai shared spec](../) — the protocol the bootstrap instructions describe.
- [bootstrap.json](bootstrap.json) — canonical source, wrapped form, intended for inline embedding into worldlets.
- `https://puck.uno/ai/puckai/vibecode.json` — same content served bare, intended for standalone fetch by cold agents.
- [`$request.bootstrap`](../agent.md#request-bootstrap) — the field that triggers inline embedding.
