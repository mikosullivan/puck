# Skills in Puckai — executive summary

*How embedding skills inside a Puckai worldlet relates to MCP. For Stuart.*

~~~vibecode
{"vibecode": {
	"doc": "puckai_skills_executive_summary",
	"role": "short comparative summary of how Puckai-embedded skills overlap with, augment, and partially replace MCP's prompt/tool surfaces; for a reader who already understands skills, MCP, and Puckai",
	"audience": ["Stuart"],
	"position": "Skills replace MCP's prompt-library role for curated task guidance, augment MCP's tool surface by naming which servers the agent should consult, and leave MCP-as-tool-bridge for live external calls intact. Skills and MCP are complementary, not rivals.",
	"related_docs": ["index.md", "../mcp.md"]
}}
~~~

A PuckAI worldlet can contain AI skills embedded directly in it, or referenced by URL.

A skill is a structured vibecode document — `purpose`, `when_to_use`, `process`, `principles`, `tools_to_use`, `examples`, `out_of_scope` — that ships *inside* a Puckai worldlet's top-level vibecode (either inline or by URL reference). The receiving agent picks it up the moment it opens the worldlet, with no extra connection or discovery step. Issues reference skills by id; the reference is advisory.

A minimal example with two URL-referenced skills and one inline skill:

```json
{
    "format": "worldlet/1.0",
    "uuid": "8b1c9d20-4f2a-4e6b-9c3d-7a5e1f8b2c40",
    "vibecode": {
        "kind": "puckai_worldlet",
        "spec": "https://puck.uno/ai/puckai/vibecode.json",
        "skills": {
            "code_review": "https://puck.uno/ai/skills/code-review",
            "security_review": "https://puck.uno/ai/skills/security-review",
            "house_style_check": {
                "purpose": "flag_style_deviations",
                "when_to_use": {"input_kind": "code", "code_source": "team_repos"},
                "principles": {
                    "indent": {"use": "tabs", "forbid": "spaces"},
                    "naming": {"case": "snake_case", "applies_to": ["variables", "functions"]},
                    "line_length": {"max_chars": 100}
                },
                "out_of_scope": ["correctness", "security", "architecture"]
            }
        }
    },
    "records": {
        "a": {"class": "puck.uno/ai/puckai/session", "status": "open"},
        "c": {
            "class": "puck.uno/ai/puckai/issue",
            "session": "a",
            "agenda": "Review the proposed refactor in PR #501.",
            "expects": "string"
        }
    }
}
```

The interaction with MCP factors into three pieces.

## What skills replace

**MCP prompts, for curated task-shape guidance.** MCP prompts are a server-hosted library of pre-written prompts the client pulls in at session start. That's almost exactly what a Puckai skill is — except the skill travels with the work rather than being fetched from a side channel. For "how to do this kind of task," skills make the prompt-server tier unnecessary: the author of the worldlet decides what guidance ships, and the guidance is part of the audit artifact instead of a runtime lookup.

The replacement is clean because the prompt-library use case doesn't need MCP's live-fetch machinery. You're shipping text the agent should read. Putting it in the worldlet, where every consumer sees the same bytes, is strictly simpler than maintaining a prompt server with its own auth, availability, and versioning story.

## What skills don't replace

**MCP tools and resources, for live external data.** A skill can say *"consult the weather forecast for the activity window"* but it can't itself fetch a weather forecast. Anything that needs a live external call — current data, system-of-record lookups, API actions — still needs MCP (or another connector layer). Skills are instructions; MCP delivers the live data those instructions reference.

This split mirrors the broader picture in the [MCP analysis](https://puck.uno/documentation/requirements/ecoverse/puckai/mcp): MCP belongs at the consultation stage, where the agent is gathering external context. Skills don't move that boundary.

## How skills augment MCP

**Skills declare which MCP servers and tools the agent should reach for.** The skill's `tools_to_use` field is an array of URL strings. Today they're nominally service or library identifiers; they can equally name MCP server endpoints (`mcp://internal/calendar`, etc.) and even specific tool/resource names within those servers. A skill becomes the *task-aware discovery layer* for MCP — instead of the agent enumerating every server it has access to and guessing relevance, the skill says exactly what to consult for this kind of work.

Each resulting MCP call still produces a [`puck.uno/ai/puckai/consultation`](https://puck.uno/documentation/requirements/ecoverse/puckai/#consultation) record, per the augmentation pattern in the MCP analysis. The skill steers; MCP delivers; the consultation record captures what happened. Three layers, one workflow, each doing the thing it was designed for.

## Bottom line

Skills make MCP's prompt primitive redundant for curated guidance, augment MCP's tool primitive by naming what to call, and leave MCP-as-tool-bridge entirely in place. If we built only skills and never integrated MCP, agents would be limited to closed-system reasoning. If we built only MCP and never added skills, every agent would have to derive task shape on its own from agenda text alone. The two compose neatly: skills say what to do; MCP supplies the live data needed to do it.

The practical V1 read: skills are worth building independently of any MCP integration timeline, because they earn their keep on the prompt-replacement front alone. MCP integration (the [augmentation pattern](https://puck.uno/documentation/requirements/ecoverse/puckai/mcp#mcp-as-augmentation)) layers on top whenever it's prioritized, and skills make that integration *better* by giving the agent a curated steering layer for MCP tool selection.
