# MCP and Caspian

~~~json
{"vibecode": {
	"doc": "mcp_and_caspian",
	"role": "report on how Caspian could use the Model Context Protocol (MCP). Explains what MCP is, surveys the three roles Caspian could play (MCP client for its own agents, MCP server exposing Caspian to external AI apps, and convergence with Caspian's own ACP). Recommends V1.x adoption as MCP client; V2+ consideration as MCP server.",
	"status": "report / brainstorm — no design committed; gathering context for future decisions",
	"key_concepts": ["mcp_is_anthropics_standard_for_ai_app_to_tool_integration",
		"caspian_as_mcp_client_for_its_agents",
		"caspian_as_mcp_server_for_external_ai_apps",
		"acp_and_mcp_could_layer_or_converge",
		"v1_skip_v1x_client_v2_server"]
}}
~~~

## What MCP is

**Model Context Protocol** is Anthropic's open standard (launched late 2024) for connecting AI applications to external tools and data. Think of it as USB-C for AI: a uniform protocol so any AI app can plug into any tool server. JSON-RPC over stdio or HTTP.

Three primitives an MCP server provides:

- **Tools** — callable functions the AI can invoke with structured arguments (e.g., `read_file(path)`, `query_database(sql)`, `create_github_issue(title, body)`).
- **Resources** — readable data the AI can pull (files, database rows, web content, anything addressable).
- **Prompts** — pre-defined prompt templates the user can invoke through the AI app.

Real examples already in the wild: a Filesystem MCP server (`read_file`, `write_file`, `list_directory`), a GitHub MCP server (issues, PRs, commits), database connectors, Slack integrations, etc. Anthropic's Claude Desktop is the canonical client; Cursor and other AI editors also speak MCP.

---

## Mental model

> AI app + MCP servers = AI app with augmented capabilities.

Each MCP server is its own process. The AI app spawns/connects to it on startup, learns what tools/resources it offers (via a discovery handshake), and can then call those tools as part of its reasoning. The user doesn't write "AI integration code" — they install MCP servers and the AI sees their capabilities.

---

## Where MCP intersects with Caspian — the agent-calling spec

Caspian's [Puckai work](../requirements/ecoverse/puckai/) has the most obvious overlap:

- **`$agent.yield`** hands control from a Caspian script to an AI agent (likely Claude or similar).
- **Worldlets** capture agent conversations and the surrounding state.
- **ACP** (Agent Communication Protocol) is Caspian's own protocol for agent-related messaging.

When `$agent.yield` fires, the agent that wakes up to handle the call has to DO something with the world it was handed. Right now, that "do something" is opaque — the agent has its own reasoning, then returns. Where would MCP fit? **Right there: the running agent could be given access to MCP tools as part of its capability set.**

---

## Three roles Caspian could play

### A. Caspian as MCP client (for agents running inside it)

When `$agent.yield` fires and an agent starts running, the engine attaches a configured set of MCP servers to that agent's context. The agent gets to use them like any other AI app would — fetch files via the filesystem MCP, query GitHub via the GitHub MCP, hit custom domain MCPs for app-specific tools. The agent doesn't know it's running in Caspian; it just sees MCP capabilities.

This is the LOW-EFFORT, HIGH-VALUE direction. Caspian becomes an MCP client; agents running inside Caspian inherit the entire MCP ecosystem for free. Concrete plug-in points:

- `%engine.config` block declares MCP servers the script wants available to its agents.
- `--allow-mcp` permission flag in Frank to gate MCP access at launch.
- `$agent.yield(mcp: ['filesystem', 'github'])` to scope MCP capabilities per yield call.

### B. Caspian as MCP server (exposing Caspian to external AI apps)

The reverse: a running Caspian program exposes ITSELF as an MCP server that external AI apps (Claude Desktop, Cursor, etc.) can connect to. Caspian classes/methods/data become MCP tools/resources.

Concretely: a Puck object running as a service could be reachable from any AI app via MCP. Or a Mikobase could expose its records as MCP resources for AI-driven exploration.

This is the HARDER direction — requires designing what becomes an MCP tool vs. a resource, security model for external access, transport (HTTP vs. stdio), etc. Higher payoff but more design work.

### C. ACP and MCP — convergence or coexistence

ACP (Caspian's Agent Communication Protocol) is for agent-to-agent inside Caspian. MCP is for agent-to-tools across the AI industry.

They don't compete — they layer. ACP handles "two agents in a worldlet collaborating." MCP handles "an agent reaching external capabilities." The question is whether ACP's wire format could be MCP-compatible, so an MCP-speaking AI app could also speak ACP. If ACP rides on MCP's transport, Caspian gets interop for free.

---

## Why this matters

**Without MCP:** Caspian agents can do whatever Caspian gives them, and Caspian-aware AI apps can integrate via ACP. But every other AI tool in the world is invisible. To give a Caspian agent GitHub access, someone has to write a Caspian-specific GitHub adapter.

**With MCP (as client):** Caspian agents instantly inherit the growing ecosystem of MCP servers — filesystem, GitHub, Notion, Slack, custom databases, anything else built for the MCP standard. The agent's capabilities are extensible without changing Caspian.

**With MCP (as server):** Caspian applications become first-class participants in the AI ecosystem. Someone using Claude Desktop, Cursor, or any other MCP client can point their AI at a Caspian app and use its functionality.

---

## Risks and limitations

- **Young standard.** MCP launched late 2024; the spec is still settling. Building on it now means tracking changes.
- **Performance.** JSON-RPC per call is chatty. Not ideal for high-frequency tool use.
- **Per-server processes.** Each MCP server is its own process; operational overhead grows with the number of integrations.
- **AI-app-shaped.** MCP is designed for AI consumption. Using it for non-AI integration would be forcing the wrong abstraction.
- **Capability sprawl.** An agent with access to many MCPs has a lot of attack surface. Permission design matters.

---

## Implementation surface for Caspian-as-MCP-client (the easier direction)

- **MCP client library in the engine.** Can wrap an existing open-source MCP client; doesn't need to be in Caspian. Lives in the engine's Lua or whatever the host language is.
- **Configuration.** Declarative — probably in `%engine.config` or per-script — listing which MCP servers are available.
- **Permission grant.** `--allow-mcp=<server>` or similar in Frank.
- **Agent runtime hook.** When `$agent.yield` runs, the engine attaches the configured MCP servers to the agent's context.

That's roughly a slice of work — not huge. Could ship in a V1.x without disturbing the core engine.

---

## Recommendation

- **V1.0:** Skip MCP. Get the engine, the language, the worldlets, and ACP to ship. MCP is non-blocking.
- **V1.x:** Add MCP client support. Caspian agents can consume external MCP servers. Low-effort, high-leverage — opens the door to the broader AI tool ecosystem without you having to build any of those tools yourself.
- **V2+:** Consider MCP server support. Exposing Caspian-as-MCP-server requires more design work (what becomes a tool? what becomes a resource? what's the security model for external AI apps?). Worth it for the visibility, but not on the V1 critical path.

Worth filing two tracking issues — one for "MCP client integration for Caspian agents" and one for "Expose Caspian as an MCP server" — even if neither moves until post-V1. Captures the design space without committing to it.

---

## Where it would plug in concretely

- The `$agent.yield` spec gets an MCP-context parameter.
- `%engine.config` gains an `mcp_servers:` declarative field.
- Frank's permission table grows `--allow-mcp=<name>`.
- Possibly the ACP design considers MCP wire compatibility for cross-ecosystem interop.

Net: MCP doesn't replace anything Caspian already has, but it would multiply what Caspian agents can DO at low engineering cost. The agent-calling spec is exactly the right place to plug it in.
