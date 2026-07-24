# MCP as a cold-start for Caspian-ignorant agents

~~~vibecode
{"vibecode": {
	"doc": "mcp_cold_start_agents",
	"role": "explores using an MCP server to shorten the cold-start ramp for an AI coding agent
that opens a Caspian project without Caspian in its training data — what to expose as resources
vs tools vs prompts, where the server lives, how the agent discovers it, and how the design
composes with Caspian's URL-addressed library model. Complements ideas/mcp-and-caspian, which
covers the inverse direction (Caspian consuming MCP for its own $agent.yield agents).",
	"status": "V1 goal per Miko (see issue 1274); brainstorm — no shape committed",
	"key_concepts": ["cold_start_problem", "resources_vs_tools_vs_prompts",
		"local_vs_hosted_vs_bundled_server", "url_addressed_docs_mirror_library_urls",
		"push_vs_pull_context", "server_spec_drift"]
}}
~~~

A companion to [mcp-and-caspian](https://puck.uno/documentation/ideas/mcp-and-caspian), which asks "how does Caspian consume MCP so its own agents get external tools?" This doc asks the inverse question: **how could MCP shorten the ramp for an AI coding agent that opens a Caspian project and knows nothing about Caspian?**

## The cold-start problem

Today an AI coding agent (Claude Code, Cursor, Copilot, whatever) opening this repo has never seen Caspian in training data. The language shipped after cutoffs; nothing in the pretraining corpus mentions sigils, roles, `%chain`, `$agent.yield`, or CaspianJ. The agent has to build a mental model from scratch by reading files, and it wastes a lot of tokens getting things wrong before it stabilizes.

Concrete failure modes observed while working in this repo:

- **Sigil confusion.** Agent writes `foo.push(x)` where Caspian requires `$foo.push($x)`. Or emits `%name = 1` on the LHS of an assignment (`%` is engine-only). Or reaches for `@field` in a bare function body where there is no `%bucket`.
- **Ambient authority assumption.** Agent writes code that calls `%net.get` from a downloaded object as if the caller's grants flow through. The role model says otherwise — a method runs as its object's role, not the caller's. Agent has to be corrected several times before it stops.
- **Class-mechanism drift.** Agent reaches for "mixin", "module", "trait", "singleton method" — vocabulary from other languages. Caspian has one method-carrier: classes. Every reach for the wrong word buys a follow-up correction.
- **Library-idiom drift.** Agent writes `require("csv")` or `import csv`. Caspian resolves libraries by URL through `%('caspian.uno/csv.casp')` (or `%fetch('...')`). Agent has to be shown the URL-addressed model at least once before it internalizes it.
- **File-vs-URL doc references.** Agent, when writing a doc, links to `documentation/foo/bar.md`. Repo policy is puck.uno URLs. Repeatedly corrected in every session.
- **Test-tier confusion.** Agent puts Caspian-level tests in the Lua tier or vice versa. The two-tier model (Lua tests for transpiler/engine, Bryton tests for language behavior) is a repo-local convention.
- **CaspianJ vs Caspian source.** Agent conflates them, or emits Caspian source in a place expecting the CaspianJ interchange table.
- **`puts` treated as engine surface.** Agent writes `%stdout.puts` in every case. Fine, but misses that bare `puts x` is parse-level sugar for the same thing. Or the reverse — writes `puts x` and assumes it's rebindable (it isn't).

None of these are "hallucination" in the vague sense. They're the specific shape a competent Ruby/Python/Lua-fluent agent takes when it lacks the Caspian-specific corrections. The agent stabilizes eventually, but the ramp costs tokens and produces wrong intermediate work.

## What context matters most

Not everything is equally load-bearing at cold start. Ranked by "what would prevent the most wrong first drafts":

1. **The sigil system.** `$` local, `&` primary call, `@` bucket field, `%` engine surface. Everything else in Caspian assumes the reader can parse a sigiled identifier. This is the single highest-leverage piece of context.
2. **The role model in one paragraph.** Every value carries a role; methods run as their object's role, not the caller's; `%engine` is `user`-only; grants propagate through `%chain` per block. An agent that understands this stops writing ambient-authority code.
3. **Classes are the only method-carrier.** No mixins, no modules, no singleton methods. Prevents the vocabulary-drift failure.
4. **`function` vs `closure` vs `method` distinction.** Three callables with three scope rules. Agent needs to know which to reach for.
5. **URL-addressed libraries.** `%('caspian.uno/csv.casp')` is how Caspian says `import csv`. Once the agent sees the pattern, the rest of the stdlib surface follows.
6. **Repo conventions (this repo specifically).** Vibecode blocks; puck.uno URLs for doc links; sentence-case headers; tabs; transpiler/engine split. Not Caspian-language facts, but load-bearing for producing acceptable work in *this* project.
7. **Common built-in vocabulary.** `%stdout`, `%stderr`, `%chain`, `%call`, `%bucket`, `%self`, `%now`, `%net`, `%fetch`. The small closed set of engine surfaces. Complete the "vocab list" and the agent's error rate on surface names drops.
8. **Common idioms.** Implicit last-value return, `puts` as parse-time sugar, `%call.return` for early exit, `vibecode` heredoc in samples. Idioms are one-shot corrections that stick once the agent sees them.

Below the top eight, marginal value flattens fast — an agent that has those doesn't need to preload the full spec to produce reasonable first drafts.

## MCP primitives, mapped

MCP exposes three primitive kinds. Which fits which kind of Caspian context?

### Resources

Best fit for **documentation and reference material**. A resource is readable content the agent can pull in on demand. Natural targets:

- Every `documentation/requirements/**/*.md` page, addressed by URL (see [URL symmetry](#url-symmetry-with-caspians-library-model) below).
- Every `documentation/ideas/**/*.md` page, likewise.
- The Caspian syntax cheat-sheet (a purpose-built compact page).
- The sigil-and-role primer (another purpose-built page).
- Common-gotchas list — a maintained doc naming the failure modes above with the correct pattern for each.
- The catalog of built-in classes and `%X` surfaces, one resource per entry.
- The `CLAUDE.md` at the repo root, and the user-level `~/CLAUDE.md` overlay.

Resources are appropriate here because the content is authored, versioned, and read as-is. No computation.

### Tools

Best fit for **operations that produce a fresh answer per call**. Candidates:

- `transpile(source)` — takes Caspian source, returns the CaspianJ table. Lets the agent verify a snippet parses and see what it produced.
- `run(source, chain_grants)` — same but executes and returns the result. Useful for "does this actually work" checks. Requires a sandbox.
- `explain_error(traceback)` — takes a Caspian traceback, returns targeted explanation and pointers into the docs. Optional; may be better served as a prompt.
- `find_docs(query)` — server-side search over the docs (title, body, tag). Cheaper than the agent pulling five candidate resources to find the right one.
- `check_style(source)` — runs the miko.json formatter and returns violations. Prevents style-correction cycles.
- `validate_caspj(table)` — schema-check a CaspianJ table. Useful when the agent is generating CaspianJ directly.

Tools are the right primitive when a fresh, computed answer is more useful than a static doc. `transpile` is the canonical example — no doc can substitute for "this is what your snippet actually parses to."

### Prompts

Best fit for **stance and framing** — the "you are working in Caspian" mental model. MCP prompts are parameterized templates the user invokes; they can also serve as pre-baked system messages the client injects when the server is attached. Candidates:

- `caspian-orientation` — the compact primer covering sigils, roles, class model, library resolution. Ideally the smallest thing an agent needs to stop making the top failures.
- `caspian-repo-onboarding` — this repo's conventions (vibecode blocks, puck.uno URLs, transpiler/engine split, two-tier testing).
- `writing-caspian` — stance for authoring Caspian source (explicit `return`, tabs, blank lines around blocks, `vibecode` in samples).
- `writing-docs` — stance for authoring `documentation/` markdown (vibecode at top of section, sentence case, no heading numbers).
- `writing-caspianj` — stance for handling the interchange format specifically.

Prompts differ from resources in that they're **intended to shape the agent's behavior**, not just be read. A well-tuned `caspian-orientation` prompt is likely worth more than the sum of the resource pages it summarizes, because it lands the agent in the right frame before the first token of user work.

### The boundaries where uncertainty remains

- **Prompts-as-auto-injected-system-messages.** Some clients apply MCP prompts on connect; others expose them only through explicit user invocation. The server can define them; whether the agent sees them automatically at cold start depends on the client. Worth verifying against the current MCP spec before designing around auto-injection.
- **Resource-list vs. resource-content sizing.** Whether the client fetches every resource up front or on demand also varies. Server design should assume pull.

## Delivery models

Where does the MCP server live? Three plausible options with different tradeoffs.

### Local server the developer installs

The developer runs `caspian mcp` alongside `caspian lsp`. The MCP client (Claude Code, Cursor, whatever) launches it on session start.

- **Upside.** Same-machine, fast, works offline, no install of an unrelated dependency. Natural companion to the LSP.
- **Downside.** Install friction. The reason [ideas/lsp](https://puck.uno/documentation/ideas/lsp/) was deferred is that requiring a local install conflicts with the first-contact goal. Same objection applies here.

### Hosted server at `caspian.uno`

An MCP endpoint at `caspian.uno` (or wherever) that any agent can point to. No install required.

- **Upside.** Zero install. First-contact-friendly. Central point for the docs, so drift-vs-spec risk is minimized. A hosted server owned by the Caspian project can be authoritative.
- **Downside.** Requires network. Requires the project to run a hosted service (opex). Requires the client to support HTTP MCP transport, not just stdio.
- **Question.** How does a hosted MCP server handle `transpile()`-style tools that need to execute code? Same-origin sandbox is doable but nontrivial. May restrict the hosted server to resources + prompts, with tools reserved for the local variant.

### Bundled per-project via `.mcp.json`

A `.mcp.json` at the repo root points at a project-specific server — either a hosted URL or a `caspian mcp` invocation. The client (some clients) reads it on load.

- **Upside.** Per-project customization. This repo can point at a custom server that knows about local conventions on top of language-level facts.
- **Downside.** Client-support-dependent. Not every MCP client honors project-local server declarations. Also duplicates infrastructure — every Caspian project would need its own config, or a boilerplate one that points at the hosted server.

### Likely shape

Not either/or. A reasonable target:

- **Hosted server at a stable URL** as the default. Zero-install; agent finds it via `CLAUDE.md` or `.mcp.json`.
- **Local `caspian mcp` binary** for offline work and for the `transpile`/`run` tools that benefit from same-machine execution.
- **Project-local `.mcp.json`** as the tie-breaker for repos that want to layer project-specific context on top of the language-level server.

## Discovery

How does an agent find out the Caspian MCP server exists?

- **`CLAUDE.md` pointer.** The simplest, works today. `CLAUDE.md` says "an MCP server for Caspian is available at `https://mcp.caspian.uno` — configure your MCP client to attach to it." Every Claude Code session that reads `CLAUDE.md` sees the pointer. Downside: only affects clients that respect a `CLAUDE.md`-equivalent, and requires the user to configure the client.
- **`.mcp.json` at repo root.** Client-side auto-attach. Downside: not universal across clients.
- **Transpiler error messages.** When `caspian transpile` fails, the error text includes a pointer to `docs://caspian.uno/errors/<code>` (or an MCP-server URL). Turns every error into a discovery event. Useful even for humans.
- **Puck-uno site.** A prominent "connect your AI agent to Caspian" panel on the docs landing page. Copy-pasteable one-liner. Effective for developers who read the site before pointing an agent at their repo.
- **Auto-install prompt.** During `caspian install`, offer to write an MCP client config for the user's detected client. Reduces manual-config friction but adds a step of paternalism (borderline nanny).

Discovery pluralism is fine. No single channel catches every agent-and-client combination; several channels that don't contradict is better than one that leaves gaps.

## Push vs pull

Two extremes.

- **Big up-front context injection.** Agent connects, server sends a large "here is Caspian" bundle immediately. Fewer round trips; agent has everything it needs before the first user turn. Expensive per-session in tokens, most of which the agent doesn't use.
- **Pure on-demand pull.** Agent connects, sees a directory of resources, pulls them as it hits questions. Cheap when the session is narrow; potentially slow when the session is broad because the agent may not know what to pull for.

A middle ground:

- **A small orientation prompt is always injected** — the sigil-and-role primer, the class model in a paragraph, the URL library idiom. Under ≈2 kb of prose; buys most of the drop in early wrong drafts.
- **The rest is pull.** Everything else — full spec pages, built-in class references, common-gotchas — is a resource the agent pulls when it needs it.
- **Search tool.** A `find_docs(query)` tool prevents the agent from having to guess which resource to pull. One query, one targeted answer.

The orientation prompt is the load-bearing piece. The pull model works for the long tail.

## URL symmetry with Caspian's library model

Caspian already resolves classes by URL: `%('caspian.uno/csv.casp')`. The docs already have canonical URLs (puck.uno). MCP resources have URIs. Three URL spaces converge naturally.

Proposal:

- The MCP server exposes each doc page as a resource with URI **matching the puck.uno URL for that page**. So `https://puck.uno/documentation/requirements/syntax/sigils` becomes the MCP resource URI `docs://caspian.uno/requirements/syntax/sigils` (or equivalent scheme). One-to-one, memorable, and the agent's mental model for "how do I find the doc for X" is the same as a human's.
- The `%(url)` library idiom mirrors this: the docs for `caspian.uno/csv.casp` live at the MCP resource `docs://caspian.uno/csv.casp`. Agent that knows the library URL can guess the doc URI.
- `find_docs(query)` still exists as a fallback for when the agent doesn't know the exact URL.

The upside is that the URL space becomes a shared address system across humans, code, and AI agents. No separate MCP-URI tree to learn.

The design question — worth calling out — is whether the MCP scheme identifier (`docs://` vs `mcp://` vs re-using `https://`) matters to real clients, and whether URIs need a client-supplied scheme registration. Unclear; verify before committing.

## Failure modes and risks

- **Server drift.** The MCP server's resources go stale relative to the current spec. Mitigated if the resources are rendered directly from `documentation/` at request time (or on push), rather than snapshotted. Any static intermediate step is a place for drift to hide.
- **Prompt drift.** The orientation prompt (the load-bearing ≈2 kb) drifts more subtly — the language evolves, the prompt keeps saying the old thing. Needs an explicit review cadence tied to spec changes to the sigils/roles/class-model pages.
- **Agent-ignores-the-server.** Some clients don't surface resources to the model in a way that gets consulted. If the MCP server is attached but the agent never actually pulls the sigil primer, the design fails silently. Test each target client empirically; don't assume attach == use.
- **Hallucinated tool calls.** If the server documents `transpile()` and the client mis-parses the tool list, or the agent misremembers the schema, the agent will invent tool calls the server doesn't expose. Mitigated by MCP's schema-checked tool interface, but not zero.
- **Latency and cost of large pulls.** A resource that returns 100 kb of spec is expensive if pulled on speculation. Prefer paged / sectioned resources over monolithic ones. Prefer `find_docs` over "pull the full page and skim."
- **Allowlist for the `run` tool.** If `run(source)` executes actual Caspian, whose role does it run under, and what grants does it have? Untrusted-code-in-untrusted-code — the whole role model is relevant. Sandbox needs its own design pass.
- **First-contact tension.** Same argument that deferred the LSP applies here. Requiring an MCP install to work with Caspian conflicts with "developer gets results before buying into whole system." The hosted-server-plus-CLAUDE.md-pointer path is the escape hatch.
- **Spec-versioning.** If a Caspian project pins to `caspian.uno/csv.casp` version window `[2026-06, 2027-01]`, does the MCP server return the docs current at that window? Version-aware doc lookups exist for `%fetch`; whether the MCP server mirrors is a design decision.

## Composition with the LSP and with mcp-and-caspian

- The **LSP** ([ideas/lsp](https://puck.uno/documentation/ideas/lsp/)) serves editor UI — diagnostics, hover, completion. Human-facing. Deferred post-V1.
- The **MCP-for-agents server** (this doc) serves an AI agent's mental model — resources, tools, prompts. Agent-facing.
- The **MCP-as-client work** ([ideas/mcp-and-caspian](https://puck.uno/documentation/ideas/mcp-and-caspian)) lets Caspian's own `$agent.yield` agents consume external MCP servers. Independent direction.

None conflict. The LSP and the MCP server share a lot of underlying analysis (parsing, symbol resolution, doc lookup), so if both are built, they should share a common backend. The MCP-client work is orthogonal — different consumer, different producer.

## Resolved

- **V1 scope.** Miko committed this as a V1 goal (issue 1274). The first-contact tension in the failure-modes list still applies, but the value calculus resolved in favor of shipping it in V1.

## Open questions for Miko

- **Hosted server on `caspian.uno` — who runs it?** Opex commitment. Fine to defer if the local `caspian mcp` binary is the V1 target.
- **Which agent client is the primary target?** Claude Code has different MCP-integration ergonomics than Cursor, than the OpenAI ecosystem. Designing for all of them uniformly may be premature; picking a lead client shapes the first cut.
- **Is `transpile` / `run` in scope for V1 of the server, or resources+prompts-only?** Tools that execute Caspian pull in the sandbox question and a lot of role-model design. Doc-only is a smaller first slice.
- **Does the URL symmetry proposal need Miko's blessing before it's baked in?** Feels aligned with the URL-first design philosophy, but committing MCP resource URIs to mirror puck.uno paths is a decision that constrains later choices.
- **What's the review cadence for the orientation prompt?** If the sigils, roles, or class-model docs change, someone (or something) needs to re-derive the compact prompt. Manual, scripted, or AI-generated on push?
- **Does this compete for headspace with Molly (VSCode extension) or with the LSP?** All three touch the same "helping tooling understand Caspian" space. Sequencing matters.
