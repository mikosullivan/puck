# Puckai Conversation

*Multi-agent Puckai mode*

~~~vibecode
{"vibecode": {
	"doc": "Puckai_conversation",
	"role": "spec for the conversation mode of Puckai — two or more agents collaborating, exchanging proposals/objections/refinements, converging on per-issue decisions or going to per-issue impasse. Builds on the shared spec at ../index.md.",
	"audience": ["AI agents implementing the conversation mode",
		"humans reading the spec"],
	"protocol_summary": "Two or more agents collaborate on one or more issues using a shared mikobase. Each agent registers, posts records (proposals, objections, refinements, questions, evidence, etc.), and the group converges on a decision per issue. When every issue is settled the agents return the worldlet to the caller (human or program); per-issue reports are written when issue.report is true. Issues that can't be agreed go to impasse — declared by the session admin — and the caller adjudicates those.",
	"shared_spec": "../index.md",
	"key_concepts": ["multi_agent_collaboration", "per_issue_decisions",
		"consensus_default_unanimity", "decider_hash_for_named_authority",
		"admin_role_for_meta_authority", "originating_agent_with_recruits",
		"per_issue_impasse_path",
		"stance_for_individual_views_distinct_from_issue_decision"]
}}
~~~

This is the **conversation mode** of Puckai — two or more agents collaborate, exchange structured arguments, and converge on decisions (or escalate to the caller when they can't agree). It is one of the two Puckai modes; the other is [single-agent](../single-agent/).

**The shared Puckai spec** — worldlet format, field rules, execution policy, concurrency model, and the shared class library (agent, session, frame, consultation, decision, report, sign_off) — lives in [puckai/index.md](../). This page covers only what's specific to conversation mode.

---

<a id="overview"></a>
## Overview

In the simplest case: the first agent sends the second agent a complete mikobase worldlet. From that point, each agent responds by sending back only new records (a delta). They continue exchanging deltas until every issue in the session is settled.

Records build on each other, **per issue**: a `proposal` is put forward, another agent posts an `objection` or `refinement`, a `question` may be asked and `response` posted, `evidence` may be attached to ground claims, and an `acceptance` records agreement. Each issue concludes with either a `decision` record (the issue's [decider rule](../#decider) is satisfied) or an `impasse` plus `stance` records (couldn't agree; the session admin declares it).

A conversation worldlet carries actual session records (proposal, objection, refinement, etc., catalogued below). The universal worldlet preamble for cold-start receivers lives at [bootstrap/bootstrap.json](../bootstrap/bootstrap.json); Puckai-specific semantics arrive as `vibecode` hints on the records themselves.

---

<a id="conversation-modes"></a>
## Conversation modes

A conversation runs in one of two modes, depending on the roles in the [`agents` hash](../#session) on the session record. If any agent's metadata has `"role": "originator"`, the session runs in originating-agent mode; otherwise it's peer-to-peer. The mode shapes the default decider for issues and who recruits.

### Peer-to-peer

The default. Every agent's entry in the `agents` hash has `"role": "peer"`. Issues default to [consensus](../#decider): every participating agent's stance must agree (`agreed_by` lists every participant). If an issue can't reach consensus, the session [admin](../#session-admin) declares [impasse](#impasse) on that issue and the caller adjudicates.

Per-issue overrides via [`issue.decider`](../#decider) are allowed but unusual in peer-to-peer — the whole point of peer-to-peer is shared content authority. Setting an issue to `{"mode": "agent", "agent": "<key>"}` would hand that one issue to a named decider; valid, but should be done deliberately.

### Originating-agent with recruits

One agent's entry in the `agents` hash has `"role": "originator"`; the rest have `"role": "recruit"`. The originator can **pull other agents in** — recruiting specialists, consultants, or second opinions as the work progresses. When a recruit joins:

- The recruiting agent registers a new `puck.uno/ai/agent` record for the recruit (same way agents register themselves at session start).
- The recruit's entry is added to the session record's `agents` hash with `"role": "recruit"`.
- The recruit can then post records the same way any agent does.

**The originating agent has the final say on each issue's decision by default** — issues in this mode typically carry `decider: {"mode": "agent", "agent": "<originator-key>"}`. Recruits contribute proposals, objections, refinements, and evidence; their views shape the outcome and are preserved in the audit trail. But the originator decides.

This keeps the chain of accountability clear: the caller deals with one originating agent, and that agent owns the result regardless of how many specialists it consulted along the way. Specific issues can still be handed to a recruit via the per-issue `decider` hash when that's the right call — the originator-decides default is just the most common case, not a hard rule.

Recruits who disagree with a final decision on an issue can express dissent by posting a [`puck.uno/ai/puckai/stance`](#stance) for that issue. The stance is recorded alongside the decision; it doesn't block it.

### Admin authority in conversation

The session's [`admin`](../#session-admin) field names which agent holds meta-authority — declaring impasse, ending the session, admitting recruits, removing agents. In peer-to-peer this is essential (no agent has automatic meta-authority); in originating-agent mode the originator is typically admin but the role can be split. Admin authority does not extend to content decisions, which are governed per-issue by the `decider` rule.

---

<a id="recruiting-agents"></a>
## Recruiting agents

Recruiting only applies to originating-agent mode. When the originator wants to bring in a recruit:

- Register a new `puck.uno/ai/agent` record for the recruit (see [agent](../../caspian/packages/agent/) for the class spec).
- Add the recruit's UUID to the session's `agents` hash with `"role": "recruit"`.
- Hand the recruit the session worldlet (or a delta with the agent and updated session records) so they can join.

Recruits post records like any agent — proposals, objections, refinements, evidence. They can also recruit further (recursive recruitment is allowed; the originator's role doesn't change). The originator's authority persists regardless of how deep the recruitment chain goes.

---

<a id="conversation-only-classes"></a>
## Conversation-only classes

The classes below are used only in conversation mode. Shared classes (agent, session, frame, consultation, decision, report, sign_off) live in [puckai/index.md § Shared classes](../#shared-classes).

| Class | Role |
|-------|------|
| [`puck.uno/ai/puckai/proposal`](#proposal) | Something put forward for consideration |
| [`puck.uno/ai/puckai/objection`](#objection) | Reasoned disagreement with a proposal or refinement |
| [`puck.uno/ai/puckai/refinement`](#refinement) | Updated version of a proposal in response to an objection |
| [`puck.uno/ai/puckai/question`](#question) | Clarifying question about anything in the session |
| [`puck.uno/ai/puckai/response`](#response) | Reply to a question |
| [`puck.uno/ai/puckai/evidence`](#evidence) | Supporting material grounding a proposal in external fact |
| [`puck.uno/ai/puckai/acceptance`](#acceptance) | Explicit acceptance of a proposal or refinement |
| [`puck.uno/ai/puckai/impasse`](#impasse) | Declaration that agreement cannot be reached; escalates to the caller |
| [`puck.uno/ai/puckai/stance`](#stance) | One agent's own decision on the issue, distinct from the session's final decision (used for impasse positions, recruit dissent, second opinions) |

---

<a id="proposal"></a>
### Proposal

`puck.uno/ai/puckai/proposal`

Something being put forward for consideration.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :subject       # short title
    field :body          # the proposal content
    field :rationale     # why this is being proposed
    field :status        # :open, :accepted, :rejected, :superseded
end
```

---

<a id="objection"></a>
### Objection

`puck.uno/ai/puckai/objection`

A reasoned disagreement with a proposal or refinement.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :to            # reference to proposal or refinement
    field :body          # the objection
    field :severity      # :blocking, :concern, :minor
    field :status        # :open, :addressed, :withdrawn
end
```

`:blocking` means the objecting agent cannot accept the proposal as-is.
`:concern` means it has reservations but will not block.
`:minor` is a note for the caller (or for later audit) rather than a negotiating point.

---

<a id="refinement"></a>
### Refinement

`puck.uno/ai/puckai/refinement`

An updated version of a proposal, typically in response to an objection.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :of            # reference to the original proposal
    field :previous      # reference to the immediately preceding proposal or refinement
    field :body          # the full revised proposal
    field :changes       # summary of what changed and why
end
```

`of` always points to the original proposal. `previous` points to whatever this directly supersedes — useful for walking the chain of revisions.

---

<a id="question"></a>
### Question

`puck.uno/ai/puckai/question`

A clarifying question about anything in the session.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :about         # reference to the thing being questioned
    field :body
end
```

---

<a id="response"></a>
### Response

`puck.uno/ai/puckai/response`

A reply to a question.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :to            # reference to question
    field :body
end
```

---

<a id="evidence"></a>
### Evidence

`puck.uno/ai/puckai/evidence`

Supporting material attached to any record in the session — a citation, measurement, example, or counterexample that grounds a proposal or objection in external fact.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :about         # reference to the record this evidence supports
    field :kind          # :fact, :example, :counterexample, :citation, :measurement
    field :source        # URL or description of the source
    field :body          # the evidence content
    field :confidence    # 0.0–1.0, agent's confidence in this evidence
end
```

---

<a id="acceptance"></a>
### Acceptance

`puck.uno/ai/puckai/acceptance`

An explicit record of one agent accepting a proposal or refinement. Creates a clear audit trail of who accepted what and under what conditions.

```
class
    field :agent          # primary key of the agent record
    field :session       # reference to the session record
    field :of            # reference to the proposal or refinement being accepted
    field :body          # optional remarks
    field :conditions    # any conditions attached to the acceptance
end
```

---

<a id="impasse"></a>
### Impasse

`puck.uno/ai/puckai/impasse`

A declaration that agreement on **one issue** cannot be reached and the issue must be escalated to the caller. **Only the [session admin](../#session-admin) may post an impasse record.** This is the meta-authority distinction: deciding the issue's content is governed by its [decider](../#decider) rule (typically consensus among participants); declaring that the issue can't be settled at all is a session-container mutation, and that belongs to admin alone. Once posted for an issue, further negotiation on that issue stops and each agent posts a [stance](#stance) on it summarizing its final view. Other issues in the session continue normally.

```
class
    field :agent           # primary key of the admin agent declaring impasse
    field :session        # reference to the session record
    field :issue          # reference to the issue that hit impasse
    field :body           # explanation of why agreement cannot be reached
    field :sticking_point # the specific point of disagreement
end
```

---

<a id="stance"></a>
### Stance

`puck.uno/ai/puckai/stance`

**One agent's own decision on one issue**, distinct from the issue's final decision. The stance is how a single agent records what it would have decided when its view doesn't (or shouldn't) lock the issue-level decision.

```
class
    field :agent         # primary key of the agent record
    field :session      # reference to the session record
    field :issue        # reference to the issue this stance is about
    field :body         # the agent's own decision on the issue
    field :confidence   # optional: 0.0–1.0, agent's confidence in this stance
    field :supports     # optional: reference to the proposal/refinement the agent endorses
end
```

**`issue`** scopes the stance to one issue. In multi-issue sessions, an agent can have different stances on different issues — agree on one, dissent on another — without conflating them.

Use cases (not exhaustive — `stance` covers any scenario where one agent's view should be recorded without becoming the issue's official answer):

- **After impasse on an issue:** each agent posts a stance for that issue summarizing their final view for the caller's adjudication. Replaces the older dedicated "position" class.
- **Recruit dissent in originating-agent mode:** a recruit who disagrees with the originator's final decision on an issue posts a stance. The decision still stands (the originator decides); the stance lives alongside it in the audit trail. Replaces the older dedicated "minority report" class.
- **Second opinion without locking:** an agent contributes its view without committing to the issue's decision — useful when the agent was consulted but isn't an authoritative participant on this issue.

**Why a stance doesn't carry context about *why* it's being recorded.** The session state tells you — if there's an impasse record for the issue, stances are positions for the caller to adjudicate; if there's a final decision and a recruit's stance differs, the stance is dissent; etc. Encoding the reason on the stance itself would duplicate what's already visible in the surrounding records.

---

<a id="complete-example"></a>
## A complete example

A populated conversation worldlet — session, proposals, objections, refinements, decision, report, sign_off — is not yet checked in as a canonical artifact. The class catalog above (above this section) shows each record class in DSL form; combine them into a session worldlet as needed.

The universal worldlet preamble (the basic JSON structure every worldlet uses, for cold-start receivers) is at [bootstrap/bootstrap.json](../bootstrap/bootstrap.json).
