# `%engine.http`
<!--index: 6 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_http",
	"role": "spec for %engine.http — the HTTP client for making outbound network requests"
}}
~~~

`%engine.http` is the HTTP client — the surface for making outbound network requests from a Caspian program. It covers the standard verbs (GET, POST, PUT, DELETE, etc.) plus the common ergonomics: query strings, request headers, body encodings, response decoding, redirect handling, and timeouts.

Most user code reaches this through the global shortcut `%chain.net.http` (or further-shortened helpers like `%puck.download`); `%engine.http` is the underlying surface those globals are built on.

The detailed method-level spec (the exact call shapes, options, error classes) lives in the HTTP doc — to migrate from `requirements-old/caspian/network/http.md` into this tree.
