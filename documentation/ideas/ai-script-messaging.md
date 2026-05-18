# AI-to-AI script messaging

```
vibecode: {
    "status": "active_brainstorm",
    "started": "2026-05-17",
    "subsystem": "ai_script_messaging",
    "purpose": "ais_authoring_ksj_directly_and_sending_executable_messages_to_other_ais",
    "related_docs": ["mikobase/ai-conversation-format.md",
                      "kscript/roles.md",
                      "kscript/blockchain/blockchain.md",
                      "kscript/kscriptjson.md"],
    "related_memories": ["project_blockchain", "feedback_first_contact_strategy"],
    "co_authoring": "claude_capturing_miko_brainstorm_in_realtime"
}
```

Brainstorm in progress.

---

## Why this is interesting

```
vibecode: {
    "section": "motivation",
    "angles": ["ais_authoring_ksj_more_naturally_than_source",
                "script_as_message_medium_distinct_from_shared_store",
                "blockchain_provides_provenance",
                "role_model_provides_capability_gating"]
}
```

### AIs authoring KSJ directly

KScriptJSON is structured JSON. Structured JSON is what language models
reliably produce — strict shape, no whitespace/indent concerns, no
"looked right but the parser rejected it" risk.

The current convention in [kscriptjson.md](../kscript/kscriptjson.md)
is "code is shared as KScript source, not KSJ" — a human-centric
default. For AI-to-AI exchange, the reverse may be the better default:
KSJ is the cleaner artifact for machines to author and consume.

This doesn't displace KScript source as the human-facing form; it
introduces a parallel convention for the AI-to-AI channel.

### Script-sending as a different medium from mikobase

Mikobase and script-messages serve different purposes:

| Medium | Mode | Use case |
|---|---|---|
| **Mikobase** | Shared store, async, persistent | "I leave data here, you find it later." Sharing **state**. |
| **Script-message** | Direct transmission, active | "Here's a chunk of behavior; consider executing it." Sharing **actions**. |

They complement rather than overlap. One AI might both write data to
a shared mikobase AND send another AI a script that operates on that
data.

### Blockchain + roles = safe acceptance

The script-message form needs two things to be workable:

1. **Provenance** — when I receive a script, I need to know who wrote
   it. The blockchain (per
   [blockchain.md](../kscript/blockchain/blockchain.md)) provides the
   identity + signature scaffolding. Each script-message is signed
   by its author; the recipient verifies the signature before deciding
   anything.
2. **Capability gating** — even from a trusted author, the recipient
   should choose what the script can do on the recipient's machine.
   The role model ([roles.md](../kscript/roles.md)) is exactly the
   tool for this: the recipient grants whatever capability set it
   chooses, regardless of who sent the script. Identity is
   verifiable; authorization is the recipient's discretion.

Together, these mean accepting a foreign script is safe: identity is
known (or refused), and even from a known author the script runs in
the recipient's sandbox with the recipient's role choices.

---

## Relationship to existing pieces

- **[ai-conversation-format.md](../mikobase/ai-conversation-format.md)** —
  already defines the temporal-worldlet format for AI conversations.
  That's the conversation *log* angle. Script-messages are a peer
  concept: not a log, but an exchange of executable artifacts.
- **[roles.md](../kscript/roles.md)** — the capability-gating layer
  that makes accepting foreign code safe.
- **[blockchain.md](../kscript/blockchain/blockchain.md)** — provenance
  layer; identity + signature.
- **[kscriptjson.md](../kscript/kscriptjson.md)** — the canonical form
  the messages contain.

---

## Open questions

- **Wire format.** Is a script-message a bare KSJ document with a
  signature wrapper? A small worldlet shaped specifically for
  script-carrying? A new envelope format (e.g., `{author, signature,
  intent, script, requested_capabilities}`)? Open.
- **Transport.** HTTP? Direct peer-to-peer? Mediated by Kiera as a
  resolver? Asynchronous queue?
- **Synchronous vs asynchronous reception.** Does the recipient
  execute immediately, or queue for later inspection? Does the
  message form support both?
- **Capability-request expression.** Does the message include "I'd
  like to use these roles" as a hint, with the recipient free to
  grant fewer? Or does the message just include the script and the
  recipient figures out from context what to grant?
- **Reply mechanism.** Does the recipient send a result back? A
  separate script? A worldlet? Or does the conversation happen
  through the existing ai-conversation-format mikobase?
- **Convention on KSJ-vs-source authoring**: should the spec be
  updated to say "for AI-to-AI exchange, KSJ is the canonical
  authored form" or leave it as a convention each pair of agents
  adopts?
- **Relationship to** [ai-conversation-format.md] — should this be
  the same format with a flag, a peer format, or completely
  separate?

---
