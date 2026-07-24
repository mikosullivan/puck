# `puck.uno/ai/agent`

~~~vibecode
{"vibecode": {
	"doc": "puck_uno_ai_agent",
	"role": "spec for puck.uno/ai/agent — the class used to identify and communicate with an AI agent; shared across Puckai conversation, Puckai single-agent, and any other use case that needs to talk to an AI",
	"namespace": "puck.uno/ai",
	"audience": "Puck programmers integrating with AI agents; Puckai implementers",
	"replaces": "the earlier puck.uno/agent draft; now lives under puck.uno/ai/puckai/ to keep AI-specific classes in one namespace"
}}
~~~

`puck.uno/ai/agent` represents an AI agent as a first-class object — the thing you identify, communicate with, and exchange messages against. Instances carry the metadata needed to reach the agent (where it lives, what model is behind it, who owns it) and expose the methods needed to talk to it.

The class is shared across every Puckai use case. Puckai conversation uses it for each participating agent (the record persisted in a session); Puckai single-agent uses it for the one agent rendering a decision; and anywhere else in the Puck ecoverse where code needs to reach an AI, this is the class.

## Construction

You build an agent object by handing the class the agent's URL plus whatever credentials and options are needed to talk to it:

```
$agent = %['https://puck.uno/ai/agent'].new('https://foo.bar/gup')
```

The URL is the agent's network address — where requests are sent. It is a plain URL, not a URL; use the full scheme-prefixed form (`https://...`).

Real construction calls will typically carry additional parameters — passkeys, API tokens, role bindings, model preferences, whatever the agent needs to authenticate and configure the connection. The exact parameter set isn't pinned down yet; the assumption for now is that everything required to establish the object can be passed in at construction time.

Other identity fields (model, owner, name, etc.) either auto-populate from a metadata exchange with the agent or get set explicitly. The split between discovered and caller-supplied is open; see [Open questions](#open-questions).

## Fields

The complete field set is deferred. We don't have enough information yet to map out the full agent protocol — exact identity fields, authentication, capabilities, rate limits, etc. all get settled when the integration story is clearer. For now, treat the agent as an object identified by a URL (see [Construction](#construction) above) with whatever additional fields are needed to talk to it.

## Methods

### `request_init`

Returns a fresh **request object** ready to be configured and sent to the agent:

```
$request = $agent.request_init
```

The request object holds everything that will go into one call to the agent — prompt, system message, tool definitions, options — separated from the agent's identity so the agent can be reused across many requests without each one inheriting the previous one's state. Configure the returned request, then dispatch it (dispatch surface TBD).

The request class's full shape — what methods it exposes, what fields it carries, how it gets sent — is pending design. Three fields are established:

**`references`** — a hash of resources the agent can use to reach a decision. Setting:

```
$request.references = {...}
```

The general idea: hand the agent a collection of resources (documents, data sets, URLs, prior records — whatever) and tell it those are the materials it should reason from. The exact shape of the hash and how the agent consumes its contents are TBD; the field name and intent are settled.

**`bootstrap`** — opt-in boolean. Setting:

```
$request.bootstrap = true
```

When `true`, the request adds a **single instruction hash** to the top of the outgoing worldlet, so a receiver that doesn't already know Puckai can read the document. When `false` (the default), the worldlet is sent as-is — the receiver is assumed to already know the format.

Full spec: [bootstrap/](bootstrap/). The current bootstrap design is minimal — one hash at the top — with canonical content in [bootstrap/bootstrap.json](bootstrap/bootstrap.json). More elaborate bootstrap mechanisms (class-library preludes, version-stamped references) are flagged as possible future additions.

**`promise`** — opt-in boolean for async dispatch. Setting:

```
$request.promise = true
```

When `true`, the dispatched request returns a **promise** immediately rather than blocking until the agent answers. Use the promise to attach handlers, await elsewhere, fan out concurrent requests, or compose with other async work — same pattern as a promise on an HTTP request. When `false` (the default), the dispatch blocks and returns the agent's response directly.

The promise resolves with the same response value the blocking call would have returned (the worldlet the agent sent back), or rejects on transport/protocol error. The exact promise surface (`.then`, `.await`, cancellation, timeouts) follows the broader Puck async conventions; this field is the opt-in on the request side.

### Other methods

More methods will land as the communication surface fills in (sending the configured request, async/streaming variants, etc.). For now, `request_init` is the established entry point for outbound communication.

## Use across Puckai

- **[Puckai conversation](conversation/)** — each participating agent is a `puck.uno/ai/agent` record in the session mikobase, created once at session start. Subsequent records reference it via the `agent` field. The `registered_at` field is set when the record is created.
- **[Puckai single-agent](single-agent/)** — the agent rendering the decision is a `puck.uno/ai/agent` instance.

## Open questions

- **Discovery on construction** — when `.new(...)` is called, does the engine immediately reach out to the URL to populate `model`, `name`, etc.? Lazily on first access? Or is the construction purely local and the caller fills metadata explicitly?
- **Constructor parameter set** — exact shape of what gets passed in beyond the URL: passkeys, API tokens, role bindings, model preferences, default options. Deferred until the integration story is clearer.
- **Request object shape** — what's on the request returned by `request_init` beyond `references`? Prompt, system message, tools, options, etc. — exact fields, methods, and dispatch call are open.
- **`references` hash shape** — how the resources are keyed and structured inside the hash, and how the agent consumes them. The field name is settled; the contents aren't.
- **Capability advertising** — does an agent declare what it can do (tools, models, languages), and if so, where does that live?
