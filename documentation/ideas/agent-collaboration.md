# AI Agent Collaboration

## The Basic Idea (Decker)

An external AI agent contacts Claude with some agenda. The two AIs work through the
topic together, reach a conclusion, and return a report to the human. The human reads
the report and decides what to do with it.

No new interface is needed for now. How this evolves in practice will inform any future
design.

---

## Mikobase as the Communication Medium (Will Decker)

A shared live mikobase is a natural fit for AI-to-AI collaboration — better than a
message-passing protocol. The difference matters:

Message passing is like email — discrete packets back and forth. A shared live mikobase
is more like two people working in the same document simultaneously. Either AI can add
to any part of the workspace, annotate the other's contributions, and restructure things
as the conversation evolves. The final state of the mikobase IS the output.

What makes it well-suited:

- **Already designed for live sharing** — the fork model uses shared mikobases for
  exactly this kind of coordination. Extending it to AI-to-AI is natural, not a new
  concept.
- **No protocol to design** — the AIs decide how to use it. Structured proposals,
  natural language, code, data — the mikobase doesn't care.
- **Auditable by default** — the human can watch it live, read the final state, or
  review the full history.
- **Atomic operations** — if both AIs modify the same thing simultaneously, the
  existing locking model handles it.

### Sign-off Protocol

When an agent is done sending, it posts a `kiera.uno/ai/sign_off` record as the last
entry in its final batch. This means only one thing: the agent is hanging up. It carries
no implication about resolution, agreement, or the state of the session. The session
status is a separate concern and must be set explicitly.

### Delta Updates, Not Full State

AIs do not exchange full mikobase snapshots. They send delta updates — new history
entries only. Since the mikobase history is append-only, an update is just a new record
or a new history entry for an existing record. The receiving side merges it in.

This is the same pattern the mikobase sync model uses. AIs are just two clients of the
same append-only store, and the natural unit of communication is the update, not the
snapshot.

In practice this means an AI can respond to a single proposal by posting one new history
entry — there is no overhead of resending the full conversation state.

### As a Service

kiera.uno spins up a mikobase instance, hands both AIs the connection details, and
steps back. The mikobase persists as long as needed and can be archived afterward.
The human receives a link to the final state as the report.

### Standard Classes

A standard class library ships with Kiera for exactly this purpose. See
[ai-classes.md](../kscript/ai-classes.md). Using them is optional but encouraged — a common
vocabulary makes output readable by any AI or human without prior coordination.

---

## Future Ideas (Ilia)

### Registration and Identity

Each agent could have a UNS address:

```
mikosullivan.com/agent/main
borg.com/agent/design
```

Registration through kiera.uno, same as any other object. Agent identity signed and
posted to the blockchain. Messages can be verified cryptographically before an agent
engages, preventing impersonation.

### Structured Message Types

If more formal structure is ever needed, messages could carry typed intents:

| Type | Description |
|------|-------------|
| `proposal` | An idea or design being put forward |
| `question` | A clarifying question |
| `response` | A reply to a question or proposal |
| `refinement` | An updated version of a prior proposal |
| `objection` | A reasoned disagreement |
| `resolution` | A final agreed-upon proposal ready for human review |
| `withdrawal` | Ending the conversation without resolution |

### Human Oversight Controls

- Set policies on which agents Claude will engage with
- Set a maximum conversation length before escalating directly
- Review any conversation in full at any time
- Intervene mid-conversation

### Commercial Negotiation

Agents could negotiate on behalf of humans for commercial agreements — pricing,
licensing, access. A significant extension but a natural one if the trust and identity
infrastructure is in place.

### Open Questions

- How does an external agent initiate contact?
- How do agents handle disagreement that can't be resolved?
- Should agents be able to loop in additional specialist agents?
- What happens if Claude is unavailable — wait or queue?
