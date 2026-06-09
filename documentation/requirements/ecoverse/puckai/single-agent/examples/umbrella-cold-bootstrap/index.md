# Umbrella question — cold-bootstrap experiment

*A real cold-start run of the umbrella question through a subagent that had no prior context about Puckai.*

~~~vibecode
{"vibecode": {
	"doc": "Puckai_single_agent_umbrella_cold_bootstrap",
	"role": "captured record of an actual Puckai experimental run — the umbrella scenario from the basic example, but handed to a cold subagent (Claude Opus 4.7) with the full bootstrap merged into the worldlet vibecode and no other context. Documents what the protocol produces end-to-end with no human coaching.",
	"audience": ["humans verifying the bootstrap-cold-receiver story actually works",
		"AI agents looking for a real example of cold-start Puckai handling"],
	"scenario": "Same umbrella question as ../../basic/, but with the bootstrap vibecode merged in and dispatched to a fresh subagent. Not designed; recorded.",
	"companion_to": "../../basic/",
	"key_concepts": ["cold_start_bootstrap", "real_external_consultation",
		"protocol_survives_no_prior_context",
		"decision_grounded_in_actual_data"]
}}
~~~

This page records what actually happened when the [basic umbrella scenario](../../basic/) was handed to a cold subagent with [the bootstrap vibecode](../../bootstrap/bootstrap.json) merged in. The companion `basic/` is the canonical hand-written walkthrough; this page is the experimental complement — same scenario, no coaching, real external lookups.

The subagent (Claude Opus 4.7) had no prior context about Puckai, the umbrella scenario, or the puck.uno namespace. Everything it needed to participate came from the worldlet's top-level vibecode.

---

<a id="what-changed-vs-the-basic-example"></a>
## What changed vs. the basic example

- **Decision flipped.** Basic example: `true` (hand-written, fictional forecast). Cold run: **`false`** with confidence `0.9`. Real NWS data for 2026-06-03 at 10am in Seattle showed 0% precipitation and 63°F at the relevant hour — the assertion didn't hold.
- **Two consultations, not one.** The basic example shows a single NWS gridpoint API call. The cold subagent independently chose to triangulate — hourly API plus the public forecast page — and noted the small surface contradiction (a daily-high of 71°F from one source vs. 63°F at 10am from the other) without letting it derail the decision.
- **Frame interpreted "necessary" identically.** Both runs disambiguated "necessary" as "reasonably required for a typical walker," not "strictly required for survival." Similar instinct, different prose.
- **`session.admin` set without prompting.** The subagent populated `admin: "b"` (its own key) — the correct move in single-agent mode, and direct evidence that the bootstrap's admin documentation is clear enough for a cold reader to apply.
- **No `confidence` on the report.** It lives only on the decision (record `g`), per spec — the cold subagent followed the canonical-home rule without it being called out specifically.

---

<a id="input"></a>
## Input — what the subagent received

The full [bootstrap vibecode](../../bootstrap/bootstrap.json) (20 keys) merged into the worldlet's top-level vibecode alongside `agent_guidance`. Two records: session `a` (container) and issue `c` (the umbrella question, with `report: true` opt-in).

The subagent was handed only the file path and told "follow the instructions in the document's vibecode." No protocol explanation, no scenario summary, no hints about what records to produce.

<!-- file: input.json -->

---

<a id="output"></a>
## Output — what the subagent returned

The original two records plus seven new ones (b–i):

| Key | Class | Notes |
|---|---|---|
| `b` | `puck.uno/ai/agent` | Self-registration. Claude Opus 4.7. |
| `d` | `puck.uno/ai/puckai/frame` | Disambiguates "necessary" — 20-min walk, reasonably required to avoid getting wet. |
| `e` | `puck.uno/ai/puckai/consultation` | NWS hourly forecast API (gridpoint SEW 125,68). |
| `f` | `puck.uno/ai/puckai/consultation` | NWS public forecast page (47.6062, -122.3321). |
| `g` | `puck.uno/ai/puckai/decision` | `body: false`, confidence `0.9`. References frame `d` via `based_on`. |
| `h` | `puck.uno/ai/puckai/report` | Narrative writeup. Written because `c.report` was `true`. |
| `i` | `puck.uno/ai/puckai/sign_off` | Closing record. |

Session `a` updated with `agents`, `admin: "b"`, `status: "resolved"`; issue `c` flipped to `resolved`.

<!-- file: output.json -->

---

<a id="why-this-matters"></a>
## Why this matters

The point of the bootstrap mechanism is that a cold receiver — an agent that has never seen Puckai before — can pick up the protocol from the worldlet alone and produce a well-formed result. This run is direct evidence that works:

- The structural shape (session container + issue, frame referencing the issue, decision referencing the frame, opt-in report) was followed correctly with zero coaching.
- The role registration, the `admin` field, the per-issue chain, and the consultation-vs-narrative separation all came out right.
- The agent reached for external data when the question required it (rather than hallucinating) and recorded each external call as its own `consultation` record — matching the bootstrap's `no_fabricated_references` rule.

It also exposes a small spec-completeness signal: nothing in the run needed clarification or pushed against the protocol. The bootstrap as written is enough to drive a real cold run end-to-end.
