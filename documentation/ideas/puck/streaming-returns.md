# Puck streaming returns (post-V1.0)

~~~vibecode
{"vibecode": {
	"doc":                  "puck_streaming_returns",
	"role":                 "deferred design note for streaming method returns in the Puck protocol — SSE-style or chunked HTTP responses for methods whose return value arrives incrementally rather than as a single materialized blob. Not in V1.0; the V1 return-type vocabulary models synchronous request-response only.",
	"status":               "post-V1.0 — deferred",
	"v1_alternative":       "method returns a complete value or a Puck class reference; no incremental delivery",
	"use_cases_blocked":    ["large_file_download_with_progress",
	                         "real_time_event_feeds",
	                         "long_running_query_with_partial_results",
	                         "streaming_llm_token_output"],
	"protocol_layers_needed": ["chunked_transfer_or_sse_at_transport",
	                          "incremental_value_grammar_in_class_definition",
	                          "client_side_iteration_or_callback_model"],
	"related": ["puck/class-definition.md", "puck/protocol.md"]
}}
~~~

**Post-V1.0.** Puck V1's return-type vocabulary describes a method as returning a single complete value: a primitive, a Puck class instance, a chunk of bytes, etc. The value is fully materialized server-side, then sent to the client. **No support for streaming returns** where the server pushes incremental chunks of a value as they become available.

This means methods like:
- Long file downloads with progress reporting
- Real-time event feeds (server-sent events)
- LLM-style token-by-token text generation
- Long-running queries that yield partial results as they compute

...all have to be modeled as either non-streaming returns (full materialization on the server first, single response) or as separate Puck classes representing the stream (poll-based, multiple method calls). Neither is great.

## What V1 does instead

A method that conceptually streams can be approximated by:

- **Full materialization.** Server buffers everything, returns the complete value at the end. Works for bounded streams; fails for unbounded ones.
- **Iterator class.** Method returns a Puck class instance representing the stream; client calls `.next()` repeatedly to pull values. Synchronous, request-response per chunk. High overhead per chunk; doesn't capture real-time push.
- **Out-of-band channel.** Client opens a separate connection (WebSocket, SSE endpoint) outside the Puck protocol for streaming. Bypasses Puck entirely.

## What streaming-returns design would need

When this lands post-V1.0, the spec needs:

1. **Transport.** Chunked HTTP, Server-Sent Events (SSE), or WebSocket — pick one as the canonical option. SSE is simplest and HTTP-native; WebSocket is more flexible.
2. **Grammar in class definition.** New return-type descriptor for streaming. Working sketch:
   ```json
   "returns": {"class": "stream", "of": {"class": "string"}}
   "returns": {"class": "stream", "of": {"class": "https://puck.uno/event"}}
   ```
   The `stream` type composes with the existing `class`/`of` grammar.
3. **Client-side iteration model.** Python: an iterator/generator returned from the call. JS: an async iterator. Caspian: TBD. Each client wraps the underlying transport stream in the host language's idiomatic iteration construct.
4. **End-of-stream / error signaling.** How does the server say "done" vs "error mid-stream"? Standard SSE / chunked patterns work, but the protocol should specify the contract.
5. **Backpressure.** Can a slow client cause the server to buffer indefinitely? Need flow-control semantics.

## Why deferred

- **Most APIs don't need it.** V1's request-response model covers the overwhelming majority of remote-method use cases. The 5% that genuinely need streaming can use one of the V1 alternatives above.
- **Substantial design surface.** Picking the transport, the grammar, the iteration model, the error contract, and the backpressure semantics is real spec work. Doing it AFTER V1 ships means we get user-feedback-informed design from real-world misses.
- **Doesn't block V1.** No protocol decision today rules out adding streaming later; the `class`/`of` grammar extends naturally.

## When this might land

- **V1.x** if a specific high-value use case surfaces that V1 alternatives genuinely can't handle (e.g., Puck-as-LLM-API where token streaming is critical).
- **V2** as part of a broader protocol revision.
- **Possibly never** if the iterator-class alternative turns out to be good enough in practice.
