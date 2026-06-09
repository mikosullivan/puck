# Puck async methods / promises (post-V1.0)

~~~vibecode
{"vibecode": {
	"doc":                  "puck_async_methods",
	"role":                 "deferred design note for asynchronous method dispatch in the Puck protocol — methods that return a promise-shaped handle instead of a materialized value, so the caller can fire many calls in parallel without blocking. Not in V1.0; the V1 definition models synchronous request-response only.",
	"status":               "post-V1.0 — deferred",
	"v1_alternative":       "every method call is a synchronous blocking HTTP request; for parallelism, fork or thread on the client side and run multiple synchronous calls in separate workers",
	"use_cases_blocked":    ["fire_many_remote_calls_concurrently_without_blocking",
	                         "compose_async_workflows_with_await",
	                         "non_blocking_call_in_event_loop_clients_node_or_browser"],
	"protocol_layers_needed": ["promise_handle_class_at_protocol_layer",
	                          "client_side_async_iteration_or_await_model",
	                          "cancellation_semantics_what_happens_if_caller_aborts"],
	"related": ["puck/class-definition.md", "puck/protocol.md", "puck/streaming-returns.md"]
}}
~~~

**Post-V1.0.** Puck V1's method dispatch is **synchronous and blocking**: a client calls a method, the HTTP request goes out, the client thread waits for the response, the method returns when the response arrives. No promise, no future, no `await`.

This matches Caspian's single-threaded, sync-blocking model and works fine for the overwhelming majority of scripts (sequential request → use the response). But it doesn't fit naturally into event-loop clients (Node.js, browsers) or workflows that want to fire many calls concurrently.

## What V1 does instead

A client that needs parallelism uses host-language concurrency primitives outside Puck:

- **Caspian:** fork via `%utils.forks.multiple(N) do($fork) ... end` — each child runs its own synchronous Puck calls.
- **Python:** threading / multiprocessing / asyncio (with sync Puck wrapped in `run_in_executor`).
- **JS:** Promise.all wrapping sync-shaped Puck calls running in worker threads.

Workable but verbose. Each client has to invent its own pattern.

## What async-methods design would need

When this lands post-V1.0:

1. **Protocol-level promise.** A method declared async returns a `puck.uno/promise` (or similar) Puck class instance immediately, before the server has completed the work. The client can call `.await()` on it to block until the value arrives, or attach callbacks.
2. **Class-definition grammar.** A field marking a method as async:
   ```json
   "weather": {
       "params":      {},
       "returns":     {"class": "https://puck.uno/geo/weather"},
       "async":       true,
       "description": "..."
   }
   ```
   Or wrap the return type:
   ```json
   "returns": {"class": "promise", "of": {"class": "https://puck.uno/geo/weather"}}
   ```
3. **Cancellation.** What happens if the caller drops the promise without awaiting? Server-side work should ideally be cancelled. Standard HTTP request cancellation works for the request-out half; canceling server-side computation already in flight is harder.
4. **Client-side ergonomics.** Each client picks the idiomatic async pattern for the host language — Python `async/await`, JS Promises, Caspian (TBD — Caspian has no async story today).
5. **Composition with streaming.** Async + streaming together (an async iterator of streamed values) is a richer case; might want to spec independently or together.

## Why deferred

- **V1's sync model covers most cases.** Sequential workflows, scripts, simple servers — all fine with blocking calls. Concurrency is the exception, not the rule.
- **Caspian has no async story.** Caspian is single-threaded and uses forks for parallelism, not async/await. Async Puck methods don't have a natural Caspian client mapping yet.
- **Adds significant complexity** — promise lifecycle, cancellation contract, error semantics across awaits, etc. Doing this AFTER V1 ships means we get to see what patterns actually emerge under load before committing to a contract.
- **Doesn't block V1.** The synchronous model is internally consistent and extends cleanly when async is added later (sync methods stay sync; async methods are marked explicitly).

## When this might land

- **V1.x** if Puck-as-LLM-API or Puck-from-browser-JS becomes a serious use case and the sync model proves too limiting.
- **V2** as part of a broader protocol revision.
- **Possibly never for Caspian clients** — Caspian's fork-based parallelism may stay the canonical path forever; async would be added for other-language clients (Node, browser) that natively need it.
