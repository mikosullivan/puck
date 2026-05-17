# KScript as a Service (server-side execution)

```
vibecode: {
    "status": "active_brainstorm",
    "started": "2026-05-17",
    "subsystem": "server_side_kscript_execution",
    "purpose": "clients_post_kscript_servers_execute_and_return_results",
    "related_docs": ["ideas/dogberry.md",
                      "ideas/browser-kscript-sandbox.md",
                      "ideas/ai-script-messaging.md",
                      "kscript/roles.md"],
    "relationship_to_dogberry": "near_cousin_dogberry_fetches_script_from_a_third_site_lune; this_pattern_takes_script_as_request_body_directly",
    "co_authoring": "claude_capturing_miko_brainstorm_in_realtime"
}
```

Brainstorm in progress. The flip: instead of clients downloading
KScript and running it locally (browser sandbox, VS Code extension,
CLI), **clients send KScript to a server, the server runs it, the
server returns results.**

---

## Why (Sito Jaxa)

```
vibecode: {
    "section": "motivation",
    "use_cases": ["heavier_playground_than_browser_can_handle",
                   "authoritative_execution_by_known_trusted_engine",
                   "mobile_or_thin_clients_without_local_runtime",
                   "webhook_handlers_that_receive_executable_payloads",
                   "ci_style_validation",
                   "stateful_sessions_across_multiple_script_submissions"]
}
```

Use cases where server-side execution beats client-side:

- **Heavier playground.** The browser sandbox is great for hello-world
  demos but constrained on CPU, memory, and access to large data
  sets. Server-side scales up.
- **Authoritative execution.** When the canonical answer must come
  from a known-trusted engine, not the user's browser (e.g., trusted
  evaluation of submitted solutions in a coding-challenge platform).
- **Mobile / thin clients.** Devices that don't want a KScript runtime
  locally — just POST and read.
- **Webhook handlers.** Receive a script as part of an event payload,
  execute, respond. Particularly interesting if scripts arrive via
  AI-to-AI messaging (see
  [ai-script-messaging.md](ai-script-messaging.md)).
- **CI-style validation.** "Is this KScript valid? Does it produce
  expected output?" — useful for testing services, online judges,
  code-review tools.
- **Stateful sessions.** Multiple scripts in sequence sharing
  context — backed by a per-session mikobase, presumably.

---

## Relationship to Dogberry — distinct service

```
vibecode: {
    "section": "vs_dogberry",
    "decided_2026-05-17": true,
    "decision": "its_own_distinct_service_not_a_dogberry_variant",
    "dogberry_model": "client_requests_url_shasta_fetches_kscript_from_lune_executes_returns_result",
    "this_model": "client_posts_kscript_body_shasta_executes_returns_result",
    "shared_machinery_with_dogberry": ["engine_run_source", "role_capability_gating",
                                          "stdout_capture_sink", "request_response_shape"],
    "naming": "service_name_tbd; brainstorm_doc_uses_kscript_as_a_service_as_placeholder"
}
```

This service has the same execution machinery as Dogberry but a
different identity. Dogberry fetches a script from a third URL (lune);
this service takes the script from the request body directly. They
share infrastructure (`engine.run_source`, role-based capability
gating, the stdout-capture pattern, the request/response shape) but
they're distinct services with distinct purposes.

A working name is TBD — this brainstorm doc uses "KScript as a
Service" as a placeholder, not a final name.

---

## What the architecture already gives us

- **`engine.run_source(text, env)`** (planned for V0.02/V0.03) is the
  API shape. The server's request handler is just a host that calls
  `run_source` with the request body as the source and a tightly-scoped
  `env` for stdout capture. The host happens to be an HTTP request
  instead of a CLI invocation.
- **Role model** ([roles.md](../kscript/roles.md)) handles the trust
  question. The server decides what capabilities the submitted script
  gets — "user + stdout, that's it" for a public playground; "user +
  stdout + per-session mikobase" for an authenticated session; etc.
  Recipient-owns-authorization scales identically from "my CLI runs
  your script" to "my server runs your script."
- **Mikobase** could provide per-session or per-client persistent state
  across multiple script submissions. A session is a worldlet (likely
  non-temporal); each script submission is a small interaction with
  it.
- **Blockchain** ([blockchain.md](../kscript/blockchain/blockchain.md))
  provides client identity if the service needs to authenticate, bill,
  or audit.

---

## Open questions

- **Variant or distinct service.** See [Relationship to Dogberry](#relationship-to-dogberry)
  above. Probably defer until concrete use cases firm up.
- **Wire format.** What does the client POST — raw KScript text, KSJ,
  a wrapped envelope (`{source, intended_roles, identity, signature}`)?
  Does the response carry the return value, stdout buffer, both, plus
  diagnostics?
- **Resource limits.** CPU time, memory, network, disk. The server
  needs guardrails to avoid abuse — likely an alarm + per-request
  timeout (per the `%utils.timeout` machinery in
  [kscript-runtime.md](../kscript/kscript-runtime.md)).
- **Statelessness vs sessions.** Each request a fresh engine, or
  long-lived sessions with persistent context (mikobase-backed)?
  Probably both, picked per endpoint.
- **Concurrency model.** Server-side KScript is per-request
  single-threaded (engine constraint); horizontal scaling is by
  process. Same model as Sinatra and Robinson already use.
- **Authentication / billing / quotas.** Optional but real if this
  ever runs as a public service. Blockchain identity is the natural
  hook.
- **Capability declaration.** Does the client request capabilities in
  the message (the server may grant fewer), or does the server have
  a fixed capability set per endpoint? Probably the latter for
  simplicity; the former could come later.

---

## Playground capability menu (Sito II)

```
vibecode: {
    "section": "playground_capability_menu",
    "purpose": "tier_options_for_what_resources_submitted_scripts_can_use_to_make_the_playground_interesting_to_play_with",
    "design_principle": "each_capability_is_a_role_grant_via_roles_md_machinery; opting_in_is_a_server_side_endpoint_choice"
}
```

If the service is also a playground, the *interesting* part is what
the submitted scripts get to do. Each capability is a role grant per
[roles.md](../kscript/roles.md); the server chooses what to grant per
endpoint (or per user, or per tier).

### Curated datasets (read-only mikobases)

The most KScript-flavored capability. Server hosts mikobases loaded
with interesting data; scripts query them via Q0 with read-only access.
Exposed as `%kiera['kiera.uno/play/<name>']`.

Candidate datasets:

- **Shakespeare** (every play, scene, line). The playwright/play/act/
  scene hierarchy is also a great Robinson-per-dir-handlers example.
- **Baby names by year** — trend queries.
- **Periodic table** — chemistry.
- **OpenStreetMap subset** — geo.
- **Wikipedia metadata** (titles + categories + links) — graph queries.
- **Public domain books** — full-text.

Read-only, server-cached; cheap per request, real-feeling data.

### External APIs (server holds the credentials)

Things that need API keys the user shouldn't have to bring. Server
holds the keys; script gets a wrapped client. Rate-limited per session.

- **LLM access** — `%kiera['kiera.uno/play/llm'].complete(...)`.
- **Image generation.**
- **Weather, geocoding, currency conversion, translation, Wikipedia
  search.**

Each unlocks "things you couldn't easily call from the browser
without auth/CORS hassles."

### Persistent state across sessions

Requires lightweight identity (cookie or token):

- **Per-user mikobase** — survives between sessions.
- **Saved scripts** — recall by name later.
- **Shareable URLs** — script + state combined into a URL anyone can
  open.

This is where playground becomes *project*.

### Inter-script coordination

KScript-flavored uniquely because the role model + mikobase +
capability system makes safe coordination easy:

- **Shared scratch mikobase** — write to a well-known UNS, others
  read.
- **Pub/sub** — a script registers as a listener; others emit events.
  Implemented over role grants.
- **Tournament / arena mode** — submit a script that plays a game;
  the server pairs it against other users' scripts.

### Output options

What the script can *produce*:

- **Text** — stdout buffer (always available).
- **JSON** — structured return value.
- **Generated artifacts** — PNG/SVG/PDF/CSV as downloadable files.
- **Rendered HTML** — small Uma page that displays in the playground
  UI.
- **A worldlet** — generate a worldlet as downloadable. "Run this
  script to build a custom dataset; download the result."

### Time and scheduling

- **Sleep / timer** with sensible caps.
- **Scheduled re-runs** — submit a script that runs every N minutes;
  view the accumulated log. Cron-as-a-service. Genuinely interesting
  for "alert me when X" patterns.

### Filesystem (carefully)

- **Per-user dirjail** — small filesystem rooted at user's account;
  quota'd; survives sessions.
- **Read-only shared assets** — fonts, sample CSVs, etc.

### Anti-resources (deliberately NOT offered)

Worth being explicit about:

- No raw socket access.
- No arbitrary outbound HTTP (whitelisted hosts only).
- No code execution that escapes the engine (no shell, no `eval`).
- No unbounded compute (alarm/timeout caps; memory caps).

The role model makes "didn't grant the role" the cleanest possible
implementation of each negative.

### Tiering

Plausible tiers a service could offer:

| Tier | What's granted | Use |
|---|---|---|
| **Minimal** | Compute + curated datasets | First-contact demos; cheap to host |
| **Middle** | + LLM/external APIs + output artifacts | Real exploration |
| **Maximum** | + persistent state + scheduling + per-user FS + inter-script coordination | Project-style users |

---
