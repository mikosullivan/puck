# Skills in a Puckai worldlet

*Attaching AI-skill definitions to a worldlet so the receiving agent can apply them when handling the session's issues.*

~~~vibecode
{"vibecode": {
	"doc": "idea_puckai_skills",
	"role": "design note for attaching AI skills to Puckai worldlets — all skill definitions live in a single `skills` hash in the worldlet's top-level vibecode; issues reference those skills by id. Each definition is either a URL pointing at a standalone skill vibecode document or the full skill content inline.",
	"status": "idea — design sketched, not yet promoted to requirements",
	"key_concepts": ["all_skills_defined_in_top_level_vibecode",
		"issues_reference_skills_by_id",
		"per_entry_polymorphic_url_string_or_inline_hash",
		"skills_are_pure_vibecode_documents"]
}}
~~~

A worldlet can carry **AI skill definitions** — bundles of instructions that tell the receiving agent how to handle particular kinds of tasks. The design is small:

- **All skills are defined once** in the worldlet's top-level vibecode under a `skills` key.
- **Issues reference skills by id** (the skill's key in the top-level hash) when they want to narrow which skills apply.

This is an idea note — the placement and shape below are a proposal, not yet promoted into the Puckai spec.

---

## Defining skills (top-level vibecode)

The `skills` hash lives in the worldlet's top-level vibecode, alongside `instructions` and `agent_guidance`:

```json
"vibecode": {
    "instructions": "This is a Puckai worldlet. Spec: https://puck.uno/ai/puckai/vibecode.json",
    "agent_guidance": { ... },
    "skills": {
        "<skill_id>": <URL string | inline hash>,
        "<skill_id>": <URL string | inline hash>
    }
}
```

Each entry is keyed by a **skill id** (a short string used to reference the skill from issues). The value is either:

| Value type | Meaning | Use when |
|---|---|---|
| **string** | URL pointing at a pure-vibecode skill document the receiver fetches | The skill is published and reusable; you want a small worldlet payload; the receiver has network access |
| **hash** | The full skill content embedded inline | You want a self-contained worldlet; you want the exact skill content captured in the audit trail; the receiver may not be able to follow the URL |

Both forms can coexist in the same `skills` hash.

---

## Skill content shape

A skill — whether served at a URL or embedded inline — is a vibecode document: structured outer fields with prose inner values. The outer structure gives the LLM clear attention anchors; the prose inside each field carries the nuance.

**One required field, the rest optional and additive:**

| Field | Type | Role |
|---|---|---|
| **`purpose`** | prose | One-line statement of what this skill accomplishes. **Required.** Every skill must say what it's for. |
| `when_to_use` | prose | The conditions under which the agent should bring this skill to bear on an issue. |
| `process` | array of prose | Ordered sequence of steps the agent should follow when applying this skill. Each entry is one step. |
| `principles` | hash of prose | Named heuristics, thresholds, and reasoning guides the agent should keep in mind. Each key is the principle's name; each value describes it. |
| `tools_to_use` | array of URL strings | Recommended tools, libraries, or APIs (by URL) this skill expects the agent to consult. |
| `examples` | array of hashes | Illustrative cases. Each example is a hash with whatever fields the skill author finds clarifying (`input`, `agent_output`, `notes`, etc.). |
| `out_of_scope` | prose | What this skill explicitly does NOT cover, so the agent knows when to reach for a different skill. |

Additional fields are the skill author's choice — `success_criteria`, `failure_modes`, `confidence_hints`, `escalation`, anything that helps the LLM apply the skill correctly. The pattern: **structured outer keys + prose inner values**, same as the rest of vibecode.

Skill documents published standalone at URLs follow the bare-hash pattern (no `vibecode` wrapper, since the document IS the vibecode). When embedded inline in the worldlet, the same content appears as the value of the entry in the top-level `skills` hash.

---

## Examples

### One inline skill, applied session-wide

The issue doesn't reference any skills, so all session-wide skills apply by default.

```json
{
    "format": "worldlet/1.0",
    "uuid": "d29390b6-779b-47b5-995a-e96866dc0150",
    "vibecode": {
        "instructions": "This is a Puckai worldlet. Spec: https://puck.uno/ai/puckai/vibecode.json",
        "skills": {
            "umbrella_check": {
                "purpose": "Decide whether an outdoor walk requires an umbrella based on weather forecast.",
                "when_to_use": "Issues whose agenda asks about weather-readiness for walking or other outdoor activity.",
                "process": [
                    "Consult a weather forecast API for the time and location in the agenda.",
                    "Identify the precipitation probability for the activity window.",
                    "Apply asymmetric-cost reasoning to decide whether to recommend carrying."
                ],
                "principles": {
                    "asymmetric_cost": "Carrying an unused umbrella is a minor inconvenience; getting caught walking in rain is a larger negative. The threshold to carry is well below 50%.",
                    "default_threshold": "Lean toward carrying above ~40% precipitation probability for the activity window."
                },
                "tools_to_use": ["puck.uno/weather/forecast"],
                "out_of_scope": "Driving, indoor activity, or precipitation forms other than rain (snow / hail / etc. need different reasoning)."
            }
        }
    },
    "records": {
        "a": {
            "class": "puck.uno/ai/puckai/session",
            "status": "open",
            "created_at": "2026-06-03T18:30:00.000Z"
        },
        "c": {
            "class": "puck.uno/ai/puckai/issue",
            "session": "a",
            "agenda": "An umbrella is necessary for walking in Seattle at 10am tomorrow.",
            "expects": "boolean",
            "status": "open"
        }
    }
}
```

### Two published skills, issue advises one is more relevant

The top-level vibecode defines both skills (by URL). The issue advises that `security_review` is the most relevant for this PR; `code_review` is still in the session's available set, but the caller is signaling where to focus. The agent can take or leave the advice.

```json
{
    "format": "worldlet/1.0",
    "uuid": "2c5e8d40-3a91-4b6f-8d1c-9e4f7a2b5c10",
    "vibecode": {
        "instructions": "This is a Puckai worldlet. Spec: https://puck.uno/ai/puckai/vibecode.json",
        "skills": {
            "code_review": "https://puck.uno/ai/skills/code-review",
            "security_review": "https://puck.uno/ai/skills/security-review"
        }
    },
    "records": {
        "a": {
            "class": "puck.uno/ai/puckai/session",
            "status": "open",
            "created_at": "2026-06-03T18:30:00.000Z"
        },
        "c": {
            "class": "puck.uno/ai/puckai/issue",
            "session": "a",
            "agenda": "Review the proposed authentication change in PR #502.",
            "expects": "string",
            "status": "open",
            "vibecode": {
                "skills": ["security_review"]
            }
        }
    }
}
```

### Mixed forms in the top-level definitions

Published skills referenced by URL alongside ad-hoc skills defined inline.

```json
{
    "format": "worldlet/1.0",
    "uuid": "9e2c4d70-6a18-4f3b-b5d2-3c8e9f1a4b20",
    "vibecode": {
        "instructions": "This is a Puckai worldlet. Spec: https://puck.uno/ai/puckai/vibecode.json",
        "skills": {
            "code_review": "https://puck.uno/ai/skills/code-review",
            "house_style_check": {
                "purpose": "Flag any deviation from this team's house code style.",
                "when_to_use": "Any issue involving code authored in this team's repos.",
                "principles": {
                    "indent": "Tabs only. No spaces for indentation.",
                    "naming": "snake_case for variables and functions.",
                    "whitespace": "No trailing whitespace on any line.",
                    "line_length": "Max 100 characters per line."
                },
                "out_of_scope": "Code correctness, security, or architectural concerns — those are other skills."
            }
        }
    },
    "records": {
        "a": {
            "class": "puck.uno/ai/puckai/session",
            "status": "open",
            "created_at": "2026-06-03T18:30:00.000Z"
        },
        "c": {
            "class": "puck.uno/ai/puckai/issue",
            "session": "a",
            "agenda": "Review the proposed refactor in PR #501.",
            "expects": "string",
            "status": "open"
        }
    }
}
```

---

## Referencing skills from issues

An issue's vibecode can include a `skills` array — a list of skill ids referring to entries in the top-level `skills` hash:

```json
"c": {
    "class": "puck.uno/ai/puckai/issue",
    "session": "a",
    "agenda": "Review PR #501.",
    "expects": "string",
    "vibecode": {
        "skills": ["code_review", "security_review"]
    }
}
```

**The issue's `skills` array is advisory only.** It tells the agent: *"these are the skills the caller thinks are most relevant for this issue."* It does not restrict what skills the agent can actually use. The agent retains its own judgment about which of the session-wide skills are appropriate; it can apply skills not listed here, or skip skills that are listed, if its own assessment differs. Consistent with Puckai's broader stance that callers can steer the agent's judgment but rarely override it (same shape as `recruits.suggest` for agent recruitment).

| Issue vibecode `skills` | What it tells the agent |
|---|---|
| absent | No specific guidance; the caller has no opinion about which skills are most relevant for this issue |
| array of ids | "These are the most relevant skills for this issue" — advisory, not enforced |
| `[]` (empty array) | "I don't think any of the session-wide skills are particularly relevant here" — still advisory |

Referencing a skill id that doesn't exist in the top-level `skills` hash is malformed and raises — that's a structural validation, separate from the advisory-vs-binding question about which skills the agent actually applies.

---

## Open questions

- **Skill conflicts when `when_to_use` overlaps.** If two applied skills both match the same issue, what happens? Both fire? First-match-wins? Need a rule.
- **Skill registry namespace.** What's the canonical URL pattern for published skills? `https://puck.uno/ai/skills/<name>` is the placeholder above; could be deeper, per-publisher (`<publisher>/skills/<name>`), or community-maintained.
- **Verification.** Should URL-referenced skills be subject to the same `%fetch.blockchain` signature verification as libraries? An untrusted-source skill is a real injection vector — the agent will follow whatever instructions the URL serves.
- **Embedded vs URL — which is the default for tools that construct worldlets?** URL is smaller; inline is more reliable. Mirrors the bootstrap question; probably the same answer (URL by default, inline when explicitly requested).
- **Skill body limits.** Whether the engine should enforce a size limit on inline skill content to prevent worldlet bloat.

---

## See also

- [Puckai spec](https://puck.uno/documentation/requirements/ecoverse/puckai/) — the worldlet format skills attach to.
- [Puckai bootstrap](https://puck.uno/documentation/requirements/ecoverse/puckai/bootstrap/) — the one-source-two-forms model that the skill URL-vs-inline shape mirrors.
- [Agent guidance in worldlet vibecode](https://puck.uno/documentation/requirements/ecoverse/puckai/#agent-guidance) — the sibling vibecode key for simpler one-line behavior hints.
