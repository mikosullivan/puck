# ACP client

*A Caspian client for the [Agent Communication Protocol](https://agentcommunicationprotocol.dev) — REST/HTTP agent-to-agent interop.*

~~~vibecode
{"vibecode": {
	"doc": "acp_client",
	"role": "spec for puck.uno/ai/acp/client — a Caspian package that lets user code call out to agents speaking the ACP (Agent Communication Protocol) REST/HTTP standard. V1.0 covers call-and-response only; stateful sessions, multimodal input, async dispatch, streaming, and discovery are deferred.",
	"audience": ["Caspian programmers calling out to ACP-speaking agents",
		"implementers of the puck.uno/ai/acp/client package"],
	"namespace": "puck.uno/ai/acp/client",
	"protocol_external_spec": "https://agentcommunicationprotocol.dev",
	"v1_0_scope": ["call_and_response"],
	"deferred": ["stateful_sessions", "multimodal_input", "async_dispatch", "streaming", "agent_metadata_discovery"],
	"key_concepts": ["caspian_client_for_external_protocol",
		"call_and_response_only_in_v1",
		"acp_is_not_puckai"]
}}
~~~

`puck.uno/ai/acp/client` is a Caspian library that calls out to agents speaking the [Agent Communication Protocol](https://agentcommunicationprotocol.dev) — a REST/HTTP standard for AI agent interop, governed by the Linux Foundation, with [BeeAI](https://github.com/i-am-bee/beeai) as the reference framework.

ACP is **not Puckai.** Puckai is Puck's own structured-conversation format ([documented separately](https://puck.uno/documentation/requirements/ecoverse/puckai/)); ACP is an external generic HTTP envelope for agent calls. The two occupy adjacent space at different abstraction levels and are independent — this package lets Caspian programs participate in the broader ACP ecosystem without committing to Puckai's structure.

---

## V1.0 scope

The first cut covers only the simplest agent-call pattern:

- **Call and response** — one input, one output. The calling code waits for the response and continues.

**Deferred for now** (not in V1.0; will land when there's a real use case driving each):

- **Stateful sessions** — a session handle that carries server-side state across multiple calls. Useful, but real spec work for session identifier threading, lifecycle, expiration.
- **Multimodal input** — text + images + audio + video + custom binary. ACP supports it generically; encoding surface is non-trivial.
- **Async dispatch** — leverages the `$request.promise` pattern from the [Puckai agent design](https://puck.uno/documentation/requirements/caspian/packages/agent/#request-promise); waits for Caspian's broader async machinery to firm up.
- **Streaming** — needs Caspian's iteration model to compose cleanly with HTTP streaming (SSE or chunked). Skipped until the async story lands.
- **Agent metadata / discovery** — ACP supports embedded discovery; the client could expose `.metadata` or `.capabilities`. Not in V1.0.

---

## API

### Constructor

```
$client = %puck['https://puck.uno/ai/acp/client'].new(url: 'https://example.com/acp-agent')
```

The `url:` kwarg is the ACP endpoint to talk to. Other constructor kwargs (auth headers, defaults, timeouts) TBD per the ACP spec.

### `send`

```
$reply = $client.send(input: 'What is the weather?')
```

Calls the ACP server with the input and returns the agent's reply, **typed according to the response's content-type**. No wrapper for known types — the return value *is* the parsed body.

#### Content-type dispatch

| Content-Type | Return value |
|---|---|
| `text/*` (text/plain, text/html, etc.) | string |
| `application/json` | parsed JSON — hash, array, string, number, boolean, null per the JSON structure |
| anything else | a [raw-response object](#raw-response) carrying raw bytes + content-type |

User code that expects a specific content-type from a specific agent can use the reply directly. Code uncertain about what it'll get can check `$reply.class` or (for raw-response objects) `$reply.content_type` and branch.

```
$reply = $client.send(input: 'hello')              # text/plain → $reply is a string
$reply = $client.send(input: 'give me weather data')   # application/json → $reply is a hash like {temp: 70, ...}
$reply = $client.send(input: 'send the chart')     # image/png → $reply is a raw-response object
```

#### Raw response (unknown content-types)

For content-types V1.0 doesn't know how to parse (binary, images, audio, anything not `text/*` or `application/json`), `send` returns a `puck.uno/ai/acp/raw_response` instance:

```
$reply = $client.send(input: 'send image')
$reply.body            # raw bytes
$reply.content_type    # the Content-Type header, e.g. 'image/png'
```

This keeps the V1.0 surface small while not silently mishandling responses outside its parsing scope — user code always gets back something usable, and can hand off raw bytes to whatever knows what to do with them.

### `puckai`

A convenience method for talking to remote agents that speak [Puckai](https://puck.uno/documentation/requirements/ecoverse/puckai/). Wraps the Puckai worldlet round-trip — build, send, parse — in a single call.

```
$reply = $client.puckai(input: 'What is the weather?')
$reply # the final value (e.g. true, a string, a hash)

$reply = $client.puckai(input: 'What is the weather?', audit: true)
$reply # the full returned worldlet

$client.puckai(input: 'What is the weather?', log: true) # side effect: logs the worldlet

$client.puckai(input: 'What is the weather?', bootstrap: true) # cold-start receiver: includes Puckai bootstrap
```

Recognized kwargs:

- **`input`** (required) — the question or assertion. Becomes `issue.agenda` on the built worldlet.
- **`audit: true`** — return the full worldlet from the agent (decision, frame, consultations, report when present, etc.) instead of just the decision body. Useful for inspecting the reasoning trace.
- **`log: true`** — side effect; writes the worldlet to the default [Jasmine log](https://puck.uno/documentation/requirements/caspian/packages/jasmine/). Return value is unchanged — still the decision body unless `audit: true` is also set.
- **`bootstrap: true`** — merges the full [Puckai bootstrap vibecode](https://puck.uno/documentation/requirements/ecoverse/puckai/bootstrap/) into the outgoing worldlet's top-level vibecode. Use when the receiving agent doesn't already know Puckai — the bootstrap teaches the format inline. Default is `false`.

All four kwargs compose. `$client.puckai(input: '...', bootstrap: true, audit: true, log: true)` sends a bootstrap-inclusive worldlet, returns the response worldlet, AND logs it.

#### Minimal bootstrap pointer is always sent

Even when `bootstrap: false` (the default), every outgoing Puckai worldlet includes a **minimal `instructions` pointer** in its top-level vibecode:

```json
"vibecode": {
    "instructions": "This is an Puckai worldlet. Spec: https://puck.uno/ai/puckai/vibecode.json"
}
```

The `instructions` field is the most directive name available — a cold receiver reading the vibecode sees "do this" rather than passive metadata. The URL points at a **standalone vibecode document** (bare hash, no wrapper) the receiver can fetch and parse directly. See [Puckai bootstrap § One source, two forms](https://puck.uno/documentation/requirements/ecoverse/puckai/bootstrap/#one-source-two-forms) for the full design.

`bootstrap: true` is the opt-in for the *full* inline bootstrap content (the multi-key instructions hash from [bootstrap.json](https://puck.uno/documentation/requirements/ecoverse/puckai/bootstrap/bootstrap.json)) when network resolution isn't viable for the receiver.

The pointer merges cleanly with any caller-supplied vibecode (e.g. `agent_guidance`): both keys coexist at the same vibecode level.

#### What the call builds under the hood

`puckai(input: '...')` builds a **default-shaped worldlet**:

- One session record (status `open`).
- One issue record with `agenda = input` and defaults elsewhere (no explicit `expects` — agent picks the most natural shape; default `confidence_floor`; no report).
- The remote agent at `$client.url` is the implicit recipient.

The worldlet is POSTed to the ACP endpoint as `application/json`. The response is parsed as an Puckai worldlet; the decision body is extracted from the single decision record and returned.

#### Limits of the convenience method

`puckai` is deliberately minimal. To configure Puckai parameters beyond `input` — `expects`, `confidence_floor`, `report`, `decider`, multi-issue worldlets, anything in the full Puckai surface — build the worldlet explicitly via the Puckai API and send it through `.send` directly:

```
$worldlet = ... # build via Puckai helpers
$response = $client.send(input: $worldlet)   # raw send; response is the returned worldlet
```

If the remote agent doesn't speak Puckai (the response isn't a parseable Puckai worldlet), the call raises.

---

## Implementation notes

- **HTTP layer**: uses `%net.http_client` for outbound requests. ACP is REST-based, so requests are standard JSON-over-HTTP POSTs to endpoints documented in the [ACP OpenAPI spec](https://agentcommunicationprotocol.dev).
- **Authentication**: ACP leaves auth open. Client should support bearer tokens, API keys, and basic auth at minimum, likely via a `headers:` kwarg on constructor and `.send`. Specific shape TBD.
- **Response parsing**: maps ACP's response JSON onto a Caspian object. `.output` is the canonical field for the V1.0 text-only case; richer accessor patterns land with multimodal support.

---

## Reading the ACP spec

ACP's authoritative spec lives at [agentcommunicationprotocol.dev](https://agentcommunicationprotocol.dev) with the OpenAPI definition on [GitHub](https://github.com/i-am-bee). Implementation requires pinning:

- Endpoint paths for `send`.
- Request and response JSON schemas.
- Auth conventions where the spec opines.

---

## See also

- [Puckai](https://puck.uno/documentation/requirements/ecoverse/puckai/) — Puck's own structured-conversation format. Adjacent space; different abstraction level. Independent of ACP.
- [`puck.uno/ai/agent`](https://puck.uno/documentation/requirements/caspian/packages/agent/) — the established Caspian pattern for outbound agent calls; the ACP client shape borrows the `.new(url:) + .send(...)` surface from it.
- [`%net.http_client`](https://puck.uno/documentation/requirements/caspian/network/http/client/) — the HTTP layer ACP rides on.
