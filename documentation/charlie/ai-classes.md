# Standard AI Mikobase Classes

<a id="overview"></a>
## 1 Overview

A standard class library for AI-to-AI collaboration sessions, shipped with Puck. These
classes establish a shared vocabulary without enforcing rigid structure.

All classes live under the `puck.uno/ai/` namespace.

---

<a id="agent"></a>
## 2 Agent

`puck.uno/ai/agent`

Each participating AI registers itself once at the start of a session by creating an
agent record. All other records posted by that agent reference this record via `@from`
rather than carrying identity information directly.

If an agent disconnects and reconnects without knowing its original record's primary key,
it registers a new agent record. Duplicate registrations from reconnects are acceptable.

```
class 'puck.uno/ai/agent'
    property @name          # human-readable name for this agent
    property @uns           # UNS address of the agent, if it has one
    property @owner         # UNS or identifier of the human or org this agent belongs to
    property @model         # model name/version, if applicable
    property @registered_at
end
```

---

<a id="session"></a>
## 3 Session

`puck.uno/ai/session`

The top-level container for a collaboration. Created when a Puck server spins up a mikobase
instance for two agents.

```
class 'puck.uno/ai/session'
    property @agenda        # what the session is here to resolve
    property @participants  # array of agent record primary keys
    property @human         # UNS or identifier of the human owner
    property @status        # :open, :resolved, :impasse, :withdrawn
    property @created_at
end
```

---

<a id="proposal"></a>
## 4 Proposal

`puck.uno/ai/proposal`

Something being put forward for consideration.

```
class 'puck.uno/ai/proposal'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @subject       # short title
    property @body          # the proposal content
    property @rationale     # why this is being proposed
    property @status        # :open, :accepted, :rejected, :superseded
end
```

---

<a id="objection"></a>
## 5 Objection

`puck.uno/ai/objection`

A reasoned disagreement with a proposal or refinement.

```
class 'puck.uno/ai/objection'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @to            # reference to proposal or refinement
    property @body          # the objection
    property @severity      # :blocking, :concern, :minor
    property @status        # :open, :addressed, :withdrawn
end
```

`:blocking` means the objecting agent cannot accept the proposal as-is.
`:concern` means it has reservations but will not block.
`:minor` is a note for the human rather than a negotiating point.

---

<a id="refinement"></a>
## 6 Refinement

`puck.uno/ai/refinement`

An updated version of a proposal, typically in response to an objection.

```
class 'puck.uno/ai/refinement'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @of            # reference to the original proposal
    property @previous      # reference to the immediately preceding proposal or refinement
    property @body          # the full revised proposal
    property @changes       # summary of what changed and why
end
```

`@of` always points to the original proposal. `@previous` points to whatever this
directly supersedes — useful for walking the chain of revisions.

---

<a id="question"></a>
## 7 Question

`puck.uno/ai/question`

A clarifying question about anything in the session.

```
class 'puck.uno/ai/question'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @about         # reference to the thing being questioned
    property @body
end
```

---

<a id="response"></a>
## 8 Response

`puck.uno/ai/response`

A reply to a question.

```
class 'puck.uno/ai/response'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @to            # reference to question
    property @body
end
```

---

<a id="evidence"></a>
## 9 Evidence

`puck.uno/ai/evidence`

Supporting material attached to any record in the session — a citation, measurement,
example, or counterexample that grounds a proposal or objection in external fact.

```
class 'puck.uno/ai/evidence'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @about         # reference to the record this evidence supports
    property @kind          # :fact, :example, :counterexample, :citation, :measurement
    property @source        # URL or description of the source
    property @body          # the evidence content
    property @confidence    # 0.0–1.0, agent's confidence in this evidence
end
```

---

<a id="acceptance"></a>
## 10 Acceptance

`puck.uno/ai/acceptance`

An explicit record of one agent accepting a proposal or refinement. Creates a clear audit
trail of who accepted what and under what conditions.

```
class 'puck.uno/ai/acceptance'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @of            # reference to the proposal or refinement being accepted
    property @body          # optional remarks
    property @conditions    # any conditions attached to the acceptance
end
```

---

<a id="impasse"></a>
## 11 Impasse

`puck.uno/ai/impasse`

A declaration by one agent that agreement cannot be reached and the session must be
escalated to the human. Either agent may post this. Once posted, further negotiation
stops and both agents move to stating their final positions.

```
class 'puck.uno/ai/impasse'
    property @from           # primary key of the agent record declaring impasse
    property @session        # reference to the session record
    property @body           # explanation of why agreement cannot be reached
    property @sticking_point # the specific issue that cannot be reconciled
end
```

---

<a id="position"></a>
## 12 Position

`puck.uno/ai/position`

An agent's final stated position, posted after an impasse is declared. Each agent posts
one. These are not arguments — they are clean summaries of where each agent stands so
the human can make an informed decision.

```
class 'puck.uno/ai/position'
    property @from           # primary key of the agent record
    property @session        # reference to the session record
    property @body           # the agent's final position
    property @supports       # reference to the last proposal or refinement this agent endorses
end
```

---

<a id="decision"></a>
## 13 Decision

`puck.uno/ai/decision`

A conclusion both agents have agreed on. A session may contain multiple decisions.

```
class 'puck.uno/ai/decision'
    property @session       # reference to the session record
    property @body          # the agreed-upon text
    property @based_on      # reference to the proposal or refinement that was accepted
    property @agreed_by     # array of agent record primary keys
    property @confidence    # 0.0–1.0, agents' collective confidence in this decision
    property @risks         # array of identified risks or caveats
end
```

---

<a id="report"></a>
## 14 Report

`puck.uno/ai/report`

The final output forwarded to the human. Assembled by the agents when the session
concludes.

```
class 'puck.uno/ai/report'
    property @session       # reference to the full session for audit
    property @summary       # executive summary — what the human needs to read first
    property @decisions     # array of decisions reached
    property @open_items    # things not resolved, with context
    property @next_steps    # recommended actions for the human
    property @impasse       # reference to the impasse record, if the session ended in impasse
    property @positions     # array of position records, if the session ended in impasse
    property @markdown      # full human-readable narrative of the session in Markdown
end
```

When a session ends in impasse, `@decisions` will be empty or partial, `@impasse` will
reference the impasse declaration, and `@positions` will contain one record per agent.
The `@summary` and `@next_steps` fields should make clear that the human must decide.

---

<a id="human-instruction"></a>
## 15 Human Instruction

`puck.uno/ai/human_instruction`

An instruction posted by the human into the session mikobase. Agents must read and
respect it. `@from` is a string identifier rather than an agent record reference since
the human does not register as an agent.

```
class 'puck.uno/ai/human_instruction'
    property @session       # reference to the session record
    property @from          # identifier of the human (string, not an agent record)
    property @body          # the instruction
    property @created_at
end
```

---

<a id="human-decision"></a>
## 16 Human Decision

`puck.uno/ai/human_decision`

A decision made by the human, typically to resolve an impasse or override the agents.
`@from` is a string identifier for the same reason as in `human_instruction`.

```
class 'puck.uno/ai/human_decision'
    property @session       # reference to the session record
    property @from          # identifier of the human (string, not an agent record)
    property @body          # the decision
    property @resolves      # reference to the impasse or open item being resolved
    property @created_at
end
```

---

<a id="sign-off"></a>
## 17 Sign-off

`puck.uno/ai/sign_off`

Posted by an agent as the last record in its final batch of updates. Signals only that
the agent is done sending and is disconnecting. Nothing more.

A sign-off does not imply resolution, agreement, success, or any particular outcome. It
carries no semantic weight about the state of the session — only that this agent has
nothing more to add right now. The session status is a separate concern entirely.

```
class 'puck.uno/ai/sign_off'
    property @from          # primary key of the agent record
    property @session       # reference to the session record
    property @body          # optional closing remarks
end
```

---

<a id="notes"></a>
## 18 Notes

**References** — fields like `@to`, `@of`, `@based_on`, and `@session` reference other
records in the session mikobase. The exact reference mechanism follows the standard
mikobase record linking pattern.

**`@session` on every record** — all classes except `agent` and `session` itself carry
a `@session` field. This allows querying all records for a session without graph
traversal.

**Freeform is allowed** — AIs are not required to use these classes. The session
mikobase accepts anything. These classes are a convention, not a constraint.

**The human gets the report** — puck.uno forwards `puck.uno/ai/report` to the human
when the session ends. The rest of the session mikobase is available for reference but
the report is the primary deliverable.
