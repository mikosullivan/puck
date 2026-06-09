# MCP and Puckai

*How the Model Context Protocol fits — and doesn't fit — into the Puckai pipeline.*

~~~vibecode
{"vibecode": {
	"doc": "puckai_and_mcp",
	"role": "comparative analysis of MCP's architectural shape against Puckai's; identifies which stages of the Puckai workflow MCP belongs in and which it doesn't",
	"audience": ["Stuart, who knows MCP well",
		"Puckai implementers weighing transport and tooling options",
		"Miko and other Puck architects scoping V1 integrations"],
	"position": "MCP is a context-injection layer for an LLM-driven app, not a peer-agent transport. It does not displace ACP for moving Puckai worldlets between agents. It complements Puckai cleanly at the consultation stage, where an agent gathers external context before deciding.",
	"recommendation": "First slice: Puckai agents speaking MCP as clients to tool servers, recording each call as a puck.uno/ai/puckai/consultation record. No architectural overlap with ACP; clean V1 surface; immediate utility.",
	"non_recommendation": "Do not route Puckai worldlets over MCP as a transport substitute for ACP. The primitives don't match the traffic.",
	"related_docs": ["index.md", "agent.md", "bootstrap/index.md",
		"../../caspian/packages/acp/index.md"]
}}
~~~

The premise here is narrow: given MCP and given Puckai, what are the architectural shapes their interaction could take? Three positions need separating — MCP as a *transport* for Puckai (replacing ACP), MCP as an *augmentation* used by Puckai agents (alongside ACP), and Puckai as *exposed material* served back through MCP. The three are at different layers and the picture gets muddled when they're collapsed.

---

<a id="mcp-as-an-alternative-transport"></a>
## MCP as an alternative transport

The first question to dispose of: should MCP carry Puckai worldlets between two collaborating agents, the way [ACP](https://puck.uno/documentation/requirements/caspian/packages/acp/) does today?

The answer is no, and the reason is shape mismatch. ACP is a peer-to-peer agent transport — symmetric, request-response, with session and streaming primitives that match what Puckai actually does on the wire (agent A hands agent B a worldlet, agent B works on it, agent B hands back a worldlet, optionally over multiple turns). MCP is asymmetric by design: a host-side client connects to a server that exposes tools, resources, and prompts for an LLM session to consume. The server is a context provider; the client is the LLM-driven app deciding what to pull.

That asymmetry is load-bearing in MCP, not incidental. Trying to route Puckai over it forces awkward choices at every seam:

- **Worldlet exchange becomes a tool call.** The "send a Puckai worldlet" action collapses into invoking a single MCP tool named something like `submit_worldlet`. The tool's return value is the response worldlet. This works mechanically but discards everything MCP's primitives were designed to give you — the resource catalog, the prompt library, the discovery surface. You're using a context-injection protocol as a glorified RPC.
- **Symmetry breaks.** Two peer agents collaborating on a Puckai session both produce and consume worldlets. MCP's client/server split means you'd need each agent to run both an MCP client and an MCP server, with the protocol orientation flipping depending on who's initiating. ACP already has the right symmetry baked in.
- **Sampling muddies the boundary.** MCP's sampling primitive lets a server ask the client's LLM to produce text. In a Puckai-over-MCP setup, this would let the receiving agent ask the sending agent's LLM to think about something — interesting capability, but it cuts across Puckai's premise that each agent reasons within its own session and records the result as records in the shared mikobase.

MCP can be made to carry Puckai. It is not the right shape for doing so. ACP remains the cleaner transport, and there's no argument for displacing it.

---

<a id="mcp-as-augmentation"></a>
## MCP as augmentation to Puckai+ACP

The genuine fit is one layer down. A Puckai agent processing an [issue](https://puck.uno/documentation/requirements/ecoverse/puckai/#issue) needs to *gather context before deciding* — call APIs, query databases, look things up, invoke tools. That's exactly what MCP is built for, and Puckai already has the record type ready to capture what happened: [`puck.uno/ai/puckai/consultation`](https://puck.uno/documentation/requirements/ecoverse/puckai/#consultation).

The shape:

- An agent receives a Puckai worldlet over ACP. The worldlet carries one or more issues to decide.
- For each issue, the agent connects to whatever MCP servers it has access to — internal API server, calendar, weather, ticketing, RAG-style document index, anything.
- Each tool invocation the agent makes (and each resource it fetches) gets logged as a `puck.uno/ai/puckai/consultation` record in the session worldlet. `source` carries the MCP server URL plus the tool/resource name; `kind` is one of `:tool`, `:api`, `:document` depending on which MCP primitive was used; `query` carries the parameters sent; `response` carries what came back.
- Agent then writes its frame and decision based on what it consulted, and ships the augmented worldlet back over ACP.

This is the strongest fit because the three layers do not overlap. MCP handles the agent's outbound context calls. Puckai records what those calls were and what they returned. ACP moves the resulting worldlet between agents. Each protocol does the thing it was designed for.

There's a small piece of design work attached: settling the convention for how an MCP tool call maps onto a consultation record. Worth doing once and documenting, so every Puckai agent renders its MCP traffic the same way and audit tooling can rely on the shape. The `kind` enum on consultation may want an explicit `mcp_tool` and `mcp_resource` variant rather than overloading the existing `:tool` and `:document` values — that decision can sit with the consultation record's owner.

---

<a id="puckai-records-as-mcp-resources"></a>
## Puckai records exposed as MCP resources

The reverse direction is also worth considering. A completed Puckai session is exactly the kind of structured, addressable material MCP's resource primitive was built to serve. A Puckai-aware MCP server could expose:

- Whole sessions as resources keyed by session UUID.
- Individual decisions as resources keyed by issue + decision UUID.
- Reports (when present) as Markdown-content resources.
- Consultations as fine-grained provenance resources for any third-party LLM auditing what an agent looked at.

This is genuinely useful — it lets a different LLM (running in a different client, owned by a different team) consume historical Puckai decisions as context. Audit tooling, cross-system observability, "show me every decision agent X has made in the last week" workflows. None of this needs Puckai to *speak* MCP for transport; it only needs a thin MCP server layered over the storage that already holds completed sessions.

This is not a V1 concern — it presupposes a corpus of completed Puckai sessions worth querying, and a story for how MCP clients authenticate against the Puck side. But it's the kind of integration that becomes obvious once the corpus exists, and the architecture is simple enough that it doesn't need design pre-work today. Note it as a downstream possibility.

---

<a id="where-they-dont-overlap"></a>
## Where MCP and Puckai genuinely don't overlap

The two protocols serve different stages of the same workflow:

| Stage | Owned by |
|---|---|
| Gather external context for a decision | MCP (tools, resources, prompts, sampling) |
| Record the decision process and its provenance | Puckai (issues, frames, consultations, decisions, reports) |
| Move structured decisions between peer agents | ACP (REST/HTTP request-response) |

Trying to make any one of them do another's job produces the awkwardness the alternative-transport section above describes. The cleanest mental model is that MCP feeds Puckai (during the consultation stage) and ACP carries Puckai (during the inter-agent stage), with Puckai itself owning the structured record of what was decided and why.

A second non-overlap worth naming: MCP has no concept of multi-agent collaboration. Its session model is one client, one server, one LLM consuming the context. Puckai's conversation mode (multiple agents posting records concurrently, consensus or named-decider dispatch, impasse handling) lives entirely outside what MCP models. There's no rivalry here — they just answer different questions.

---

<a id="recommendation"></a>
## Recommendation

If MCP integration is on the table for V1, the first slice is the augmentation pattern: **Puckai agents speak MCP as clients to consume tool servers, recording each call as a `puck.uno/ai/puckai/consultation` record**. Concretely, the work is:

- Add MCP-client capability to the agent runtime (either bundled or via a separate package — call it `puck.uno/ai/mcp/client` to mirror the ACP package shape).
- Settle the consultation-record convention for MCP traffic (the `kind` enum question; how `source` encodes server + primitive + tool/resource name; how large responses are summarized vs. stored verbatim).
- Document the pattern with a worked example: agent receives a weather-question worldlet over ACP, calls an MCP weather server, posts the consultation record, posts the decision, returns the worldlet.

Easy V1, clear value, no architectural overlap with ACP or with Puckai's existing surface.

The other two shapes — MCP-as-transport and Puckai-as-MCP-resource — should not be pursued at the same time. The first is an architectural mistake; the second is a downstream possibility worth noting but not building yet.

---

<a id="open-questions"></a>
## Open questions

- **Consultation-record schema for MCP traffic.** Does `kind` get new enum variants (`:mcp_tool`, `:mcp_resource`), or does existing usage (`:tool`, `:document`) carry MCP traffic with the MCP-ness encoded in `source`? Either is workable; settling it early avoids inconsistent audit trails.
- **Authentication and capability surface for the MCP client.** Per-agent? Per-session? Configured at agent construction, or carried in the Puckai worldlet's `agent_guidance`? The agent record's [open questions](https://puck.uno/documentation/requirements/caspian/packages/agent/#open-questions) overlap here.
- **Sampling.** If a Puckai agent's MCP server uses sampling to ask the agent's host LLM for completions, does that count as a consultation that needs its own record? Likely yes — the agent is reaching outside its own reasoning — but the framing is fuzzier than a clear tool call. Worth thinking through before agents in the wild start producing inconsistent records for it.
- **Whether `agent_guidance` should carry per-session MCP allowlists.** Mirrors the [`recruits`](https://puck.uno/documentation/requirements/ecoverse/puckai/#recruits) pattern — caller can restrict which MCP servers the agent is permitted to consult during this session. Useful for cost control and audit-trail scoping; not urgent for V1.

---

<a id="see-also"></a>
## See also

- [Puckai shared spec](https://puck.uno/documentation/requirements/ecoverse/puckai/) — the protocol this analysis is in service of.
- [`puck.uno/ai/agent`](https://puck.uno/documentation/requirements/caspian/packages/agent/) — agent class; would gain MCP-client capability under the recommended first slice.
- [ACP client](https://puck.uno/documentation/requirements/caspian/packages/acp/) — the existing Caspian client for ACP transport. The shape an `mcp/client` package would mirror.
- [Puckai bootstrap](https://puck.uno/documentation/requirements/ecoverse/puckai/bootstrap/) — orthogonal to MCP; mentioned here only because it's the other place "teach a receiver the format" comes up.
