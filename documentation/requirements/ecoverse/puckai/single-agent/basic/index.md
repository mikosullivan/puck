# Puckai Single-Agent: basic example

*The umbrella question — a worked walkthrough of a single-agent session.*

~~~json
{"vibecode": {
	"doc": "Puckai_single_agent_basic_example",
	"role": "worked example showing a complete single-agent Puckai session — the basic case, with one agent answering a boolean assertion based on an external lookup. Companion to the single-agent spec at ../index.md.",
	"audience": ["humans learning Puckai by example",
		"AI agents needing a concrete reference for the single-agent flow"],
	"scenario": "A caller (a human in this example, but could equally be a program) poses the assertion 'An umbrella is necessary for walking in Seattle, Washington at 10am tomorrow.' The agent consults the National Weather Service and returns true with a report.",
	"shared_spec": "../index.md"
}}
~~~

This is the **basic example** for single-agent mode — a complete worked session showing every record a real run produces. Use it as a reference for the shape of a single-agent Puckai exchange; the spec describing the mode itself lives at [../index.md](../index.md).

---

<a id="the-scenario"></a>
## The scenario

A caller poses an assertion for evaluation: **"An umbrella is necessary for walking in Seattle, Washington at 10am tomorrow."** In this example the caller happens to be a person planning their morning, but it could equally be an automated program running a routine check, a CI pipeline gating a deploy on a weather condition, or another agent handing the question off. Puckai doesn't assume a human at either end — the format is just as valid for entirely program-to-program use.

The caller wants a boolean decision (encoded as `true` / `false`), with the agent consulting whatever external data it needs along the way.

The chosen single agent — a fictional "Weather Advisor" running Claude Opus 4.7 — receives the worldlet, registers itself, frames the question more precisely, consults the National Weather Service forecast API, decides `true` with 0.85 confidence, writes a report explaining the reasoning, and signs off.

**Why an assertion rather than a question?** Pairing `expects: "boolean"` with an assertion makes the answer trivially interpretable: `true` means the assertion holds, `false` means it doesn't. No mapping between yes/no and the truth-value is needed — the assertion itself defines what each truth-value means.

---

<a id="conventions-in-this-example"></a>
## Conventions in this example

**Record keys.** Real worldlets typically use UUID v4 keys. This example uses **short single-letter strings** (`a`, `b`, ...) for readability. Mikobase only requires keys to be unique strings; UUIDs are a recommended convention, not a hard rule.

**Record shape.** Records use the **simple form**: `class` at the top level alongside the data fields. No `{bucket, stack}` wrapper — that form is reserved for records needing multi-platter expression, which this example doesn't.

**Worldlet vs delta on the return.** The example shows the **full worldlet** coming back (input records preserved plus the new ones the agent added). A real implementation could just return the delta — the receiver already has the originals — but the full form is more pedagogically useful.

---

<a id="before"></a>
## Before — the worldlet sent to the agent

[before.json](before.json) — what the caller sends. **Two records** (a session and an issue), plus a top-level `vibecode` block.

The top-level `vibecode` carries **agent guidance** — instructions to the agent that aren't part of the caller's question. In this example: a tone preference (`"factual, minimal hedging"`) and a directive to post a `puck.uno/ai/puckai/frame` record when the question is ambiguous. The boolean cutoff (`confidence_floor: 0.6`) lives on the issue record itself.

The records:

- **`a`** (session) — pure container. `status: "open"`, no agents yet (the agent will populate `agents` when it registers itself). No agenda, no expects — those live on the issue.
- **`c`** (issue) — `agenda` carries the assertion, `expects: "boolean"` shapes the answer, `confidence_floor: 0.6` sets the boolean cutoff, `report: true` opts the issue in for a human-readable report alongside the bare decision. `status: "open"`. The issue's own `vibecode` block adds context — when the question was asked, what the user is planning.

The caller doesn't include an agent record. The agent is reached at its URL (out of band) and registers itself when it sees the worldlet. The session and the issue are deliberately separate records: a session is a container; questions are issues; one session can carry one issue or many.

<!-- file: before.json -->

---

<a id="after"></a>
## After — the worldlet returned from the agent

[after.json](after.json) — the complete final worldlet. The session (`a`) and issue (`c`) from before, updated, plus the records the agent added — starting with its own agent record. The top-level `vibecode` from `before.json` is preserved.

- **`a`** (session) — status flipped to `"resolved"`. `agents` hash now populated with `b` (the registered agent) as originator.
- **`c`** (issue) — status flipped to `"resolved"`. Everything else (agenda, expects, confidence_floor, the `report: true` opt-in, the `vibecode` context) carries through from `before.json`.
- **`b`** (agent) — the Weather Advisor's identity. The agent created this record when it received the worldlet — that's how it registers itself in the session.
- **`h`** (frame) — authored by agent `b` (the `agent` field on the frame record points there), with `issue: "c"` scoping it to the issue. The agent's restatement of the agenda: *"Will the precipitation in Seattle, Washington on 2026-06-03 at 10:00 local time be heavy enough that a typical walker would benefit from carrying a rain umbrella?"* The frame's own `vibecode` block lists the disambiguations the agent made (e.g., "umbrella" read as "rain umbrella," not a protest sign). Posting this is what the `on_ambiguity` guidance asked for.
- **`d`** (consultation) — the agent consulted the National Weather Service forecast endpoint. The record captures the URL, query, response text, and timestamp; it lives separately from the report so the audit trail keeps consultation provenance distinct from the agent's narrative.
- **`e`** (decision) — `issue: "c"` scopes the decision to the issue. `body: true` (the assertion holds), with `based_on: "h"` referencing the frame. The chain is **issue `c`.agenda → frame `h` → decision `e`**: the original assertion, the agent's interpretation, and the verdict on that interpretation. Confidence `0.85`, comfortably above the issue's `confidence_floor` of `0.6`.
- **`f`** (report) — written because `c.report` was `true`. `issue: "c"` scopes it; `decision: "e"` points to the decision it describes. Carries the summary, the markdown reasoning, the next-steps note. `open_items` is empty since the consultation gave a clear forecast. Confidence is *not* duplicated on the report — the decision is the canonical home for the number; the markdown discusses it in narrative form.
- **`g`** (sign_off) — the agent disconnects.

<!-- file: after.json -->

---

<a id="things-to-notice"></a>
## Things to notice

- **The session is a container; the issue carries the question.** Read the session record (`a`) and you learn who's participating and what state the session is in. Read the issue record (`c`) and you learn what's being asked. The split scales naturally — a session with three issues would have three issue records, each with its own frame/decision/(optional) report chain.
- **The per-issue chain is the audit trail.** Reading the worldlet, you can trace from the issue's `agenda` through the agent's `frame` (record `h`) to the `decision` (record `e`), and the optional `report` (record `f`) writes up the whole story for a human reader. Each link names what it references; nothing is implicit.
- **The consultation is a first-class record, not narrative prose.** If a future auditor wonders where the agent got its information, they can find the API endpoint, query, and response text in record `d` — separately from whatever the agent decided to say about it in the markdown report. Provenance and narrative are kept distinct.
- **Confidence lives on the decision, not the report.** Record `e` carries the canonical `confidence: 0.85`. The report (`f`) mentions it in narrative form but doesn't duplicate the field — there's one number, one place. When the report is absent (as it would be if `c.report` were `false`), the decision still carries confidence on its own.
- **The report is opt-in.** This issue set `report: true`, so record `f` exists. With `report: false` (or the field omitted), records `a`, `b`, `c`, `h`, `d`, `e`, `g` would still be present — the bare decision would be the deliverable, no narrative writeup. Default is no report; opt in when a human needs to read what happened.
- **The issue's `vibecode` context survives end-to-end.** The "user has a 20-minute walk planned" note the caller attached is still there in the final worldlet — vibecode hints travel with the records they sit on, not just on the input.
- **No conversation classes appear.** No proposals, objections, refinements, questions, responses, evidence records, acceptances, impasses, or stances — those belong to conversation mode. Single-agent uses only the shared class library.
