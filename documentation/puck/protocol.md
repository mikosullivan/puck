# Puck — Protocol Specification

~~~json
{"vibecode": {
	"doc": "puck-protocol",
	"role": "formal wire-protocol spec for Puck expressed in JSON — message structures, endpoints, and behaviors that a server and client agree on; an alternate HTML expression is described separately in puck-html.md",
	"status": "in_development_stub",
	"key_concepts": ["json_wire_format", "lookup_request",
		"method_call_request", "object_references_on_the_wire",
		"data_type_serialization", "error_responses", "chain_forwarding",
		"version_window_on_requests", "protocol_versioning",
		"html_expression_described_elsewhere"],
	"audience": ["puck_protocol_designers", "puck_server_implementors",
		"puck_client_implementors_in_any_language"],
	"example_universe": "Star Trek",
	"example_language": "JSON"
}}
~~~

This doc defines the **Puck wire protocol expressed in JSON** — the
message structures, endpoints, and behaviors that a Puck server and
client agree on when speaking JSON over HTTP.

The conceptual overview is in [puck.md](puck.md); a Python client
sketch is in [python.md](python.md); this doc is the formal spec
that any client (Python, JavaScript, Charlie, etc.) and any server
implement to interoperate.

JSON is the primary wire format and the focus of this document.
**Puck can also be expressed in HTML** — same objects, same
semantics, served at the object's UNS URL for both humans and
machines to read. The HTML expression is described separately in
[puck-html.md](puck-html.md); JSON and HTML are convertible
losslessly, neither preferred over the other.

**Status: in development.**

---

<a id="what-the-protocol-needs-to-define"></a>
## 1 What the protocol needs to define

A non-exhaustive checklist of what this doc needs to pin down, to be
expanded into sections as the protocol gets worked out. All items
below are scoped to the **JSON expression** of the protocol; the HTML
expression handles the same concerns on its own terms in
[puck-html.md](puck-html.md).

- **Transport.** What runs underneath — HTTP/1.1, HTTP/2, WebSocket,
  raw TCP. Likely HTTP with JSON payloads, pinned in this doc.
- **Endpoints.** How a client addresses a server. Single endpoint
  with request type in the body, or multiple endpoints per
  request type?
- **Authentication.** How credentials are presented and checked.
  Token, signature, mutual TLS, etc.
- **Request envelope.** The common header fields on every JSON
  request (UNS, protocol version, chain context, version window, ...).
- **Lookup request / response.** Asking the server "what class is
  at this UNS?" and the answer's JSON shape.
- **Method-call request / response.** Asking the server "call this
  method on this instance with these args" and the answer's JSON
  shape.
- **Object references on the wire.** How a remote object is
  referenced inside a JSON payload when a method returns one (UNS
  plus instance handle? opaque token?).
- **Data type serialization.** Mapping between the protocol and
  JSON — numbers, strings, booleans, null, arrays, hashes,
  references, dates, binary blobs.
- **Error responses.** JSON shape of an error reply; mapping of the
  `puck.uno/error/*` catalog to wire-level error codes.
- **Chain context.** How `%chain` (the cross-call context) is encoded
  in JSON and forwarded across remote calls.
- **Version window.** How the puck's `[lower, upper]` bounds are
  sent on each JSON request and respected by the server.
- **Protocol versioning.** How the wire protocol itself is
  versioned so clients and servers can evolve independently.

Each item becomes a section below as the protocol takes shape.
