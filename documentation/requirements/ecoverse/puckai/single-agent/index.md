# Puckai Single-Agent

*Single-agent Puckai mode*

~~~json
{"vibecode": {
	"doc": "Puckai_single_agent",
	"role": "spec for the single-agent mode of Puckai — one agent reads a session, addresses every issue in it, renders a decision per issue, and returns the worldlet. Builds on the shared spec at ../index.md.",
	"audience": ["AI agents implementing the single-agent mode",
		"humans reading the spec"],
	"protocol_summary": "Send an Puckai worldlet to an agent. The session record holds the participants and overall status; each question to be resolved is a separate puck.uno/ai/puckai/issue record carrying its agenda, expects, and confidence_floor. The agent reads the worldlet, addresses every issue, renders one decision per issue, and returns the worldlet. A report record is written per issue only when issue.report is true. No back-and-forth, no impasse path, no recruitment — just one agent answering.",
	"shared_spec": "../index.md",
	"key_concepts": ["single_agent_decision_rendering",
		"address_every_issue_by_default",
		"per_issue_decision_with_optional_report",
		"shared_classes_only_no_conversation_classes"]
}}
~~~

This is the **single-agent mode** of Puckai — one agent reads the session, addresses every issue in it, and returns one decision per issue (with an optional human-readable report per issue when asked). It is one of the two Puckai modes; the other is [conversation](../conversation/).

**The shared Puckai spec** — worldlet format, field rules, execution policy, concurrency model, and the shared class library (agent, session, issue, frame, consultation, decision, report, sign_off) — lives in [puckai/index.md](../). This page covers only what's specific to single-agent mode.

---

<a id="examples"></a>
## Examples

- **[basic/](basic/)** — the umbrella question. A complete walkthrough of a single-agent session where the agent consults the National Weather Service and renders a boolean decision. Covers every record type a typical single-agent run produces (session, issue, agent self-registration, frame, consultation, decision, report, sign_off).

---

<a id="overview"></a>
## Overview

Single-agent mode is the lightweight case: no debate, no back-and-forth, no impasse path. The flow is:

1. **Send** the agent a worldlet containing a `puck.uno/ai/puckai/session` record (the container) and one or more `puck.uno/ai/puckai/issue` records (each holding an `agenda`, an `expects` answer shape, and an optional `confidence_floor`). **No agent record is included by the caller** — the caller reaches the agent at its URL; the agent registers itself when it receives the worldlet. Top-level `vibecode` on the worldlet can carry agent guidance (tone, ambiguity handling).
2. **Agent receives** the worldlet and registers itself: adds its own `puck.uno/ai/agent` record and updates the session's `agents` hash with `"role": "originator"`.
3. **Agent addresses every issue.** For each issue:
   - A `puck.uno/ai/puckai/frame` record (with `issue` referencing the issue, `agent` set to your own agent key) when the agenda is ambiguous.
   - One or more `puck.uno/ai/puckai/consultation` records for any external resources consulted.
   - A `puck.uno/ai/puckai/decision` (with `issue` referencing the issue) — the bare statement of what was decided, with confidence.
   - A `puck.uno/ai/puckai/report` (with `issue` referencing the issue) — **only when `issue.report: true`**. The narrative writeup for human consumption. Default is no report.
4. **Agent posts a `puck.uno/ai/puckai/sign_off`** to signal it's done.
5. **Agent returns** the worldlet (full form or a delta containing only the new records and the updated session/issue records).

No proposals, objections, refinements, questions, evidence, acceptances, impasses, or stances get used — those belong to conversation mode. Single-agent uses only the [shared classes](../#shared-classes) documented in puckai/index.md.

The session's [`agents` hash](../#session) ends up with one entry, with `"role": "originator"` by convention (the single agent has full authority). The session's [`admin`](../#session-admin) field can be omitted or set to that agent's key — both mean the same thing in single-agent mode. Each issue's [`decider`](../#decider) is typically absent (consensus-of-one == that one agent); setting it explicitly to `{"mode": "agent", "agent": "<key>"}` is also valid.

---

<a id="classes-used"></a>
## Classes used

All shared classes from [puckai/index.md § Shared classes](../#shared-classes):

- `puck.uno/ai/agent` — the agent's identity (general class, not Puckai-specific).
- `puck.uno/ai/puckai/session` — the session container.
- `puck.uno/ai/puckai/issue` — one question to be resolved. One or more per session.
- `puck.uno/ai/puckai/frame` — the agent's interpretation of an issue's question.
- `puck.uno/ai/puckai/consultation` — record of any external resources the agent consulted.
- `puck.uno/ai/puckai/decision` — the bare answer for one issue.
- `puck.uno/ai/puckai/report` — the narrative writeup for one issue. Opt-in via `issue.report: true`.
- `puck.uno/ai/puckai/sign_off` — the agent's disconnection signal.

No single-agent-specific classes exist at present. The class library is intentionally small; mode-specific complications stay in the conversation mode.
