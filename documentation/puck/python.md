# Puck — Python client

~~~json
{"vibecode": {
	"doc": "puck-python",
	"role": "design sketch for the general shape of a Python implementation of the Puck protocol; covers package layout, lookup, instantiation, method dispatch, return-value handling, errors, versioning, and open questions",
	"status": "sketch_no_implementation_yet",
	"key_concepts": ["python_puck_client", "module_level_default_puck",
		"class_lookup_and_instantiation", "attribute_method_dispatch",
		"primitive_and_object_returns", "error_to_exception_mapping",
		"versioning_via_vN_uns_segment", "sync_first_async_later"],
	"audience": ["python_developers", "puck_client_implementors"],
	"example_universe": "Star Trek",
	"example_language": "Python"
}}
~~~

This doc sketches the general shape of a Python implementation of the
[Puck protocol](puck.md). **Status: design sketch — no implementation
yet.** The protocol itself is specced in [puck.md](puck.md); this doc
is about how a Python package would wrap it idiomatically.

The goal: a Python developer can `pip install puck`, point at a Puck
server, and use remote objects with the same shape they'd use any
Python library.

---

<a id="contents"></a>
## 1 Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Getting a puck](#getting-a-puck)
- [Looking up a class](#looking-up-a-class)
- [Instantiation](#instantiation)
- [Calling methods](#calling-methods)
- [Properties vs methods](#properties-vs-methods)
- [Return values](#return-values)
- [Errors](#errors)
- [Versioning](#versioning)
- [Sync vs async](#sync-vs-async)
- [Open questions](#open-questions)

---

<a id="installation"></a>
## 2 Installation

```
pip install puck
```

The package has minimal dependencies — an HTTP client (likely
`httpx`) and `dataclasses`/`typing` from the standard library.

---

<a id="quick-start"></a>
## 3 Quick start

```python
import puck

Geo = puck.lookup('puck.uno/geo')
hq = Geo(lat=37.7980, lon=-122.4626)

hq.weather                 # current weather report
hq.congressional_district         # returns another Puck object
```

That's the full surface for the common case: import, look up the
class, instantiate, call methods.

---

<a id="getting-a-puck"></a>
## 4 Getting a puck

**Module-level default.** `puck.lookup(...)` and friends operate on
a module-level default puck configured from the environment (env
vars, config file, or programmatic setup at import time):

```python
import puck

Geo = puck.lookup('puck.uno/geo')   # uses the module default puck
```

**Explicit puck.** When a script needs more than one puck (different
endpoints, different credentials), construct them explicitly:

```python
prod = puck.Puck(endpoint='https://puck.acme.com', ...)
staging = puck.Puck(endpoint='https://staging.puck.acme.com', ...)

Geo = prod.lookup('puck.uno/geo')
```

**Configuration sources** (in precedence order, last wins):

1. Defaults baked into the package
2. Env vars (`PUCK_ENDPOINT`, `PUCK_TOKEN`, ...)
3. A config file (`~/.puck/config.toml` or similar — TBD)
4. Constructor kwargs to `puck.Puck(...)`

---

<a id="looking-up-a-class"></a>
## 5 Looking up a class

```python
Geo = puck.lookup('puck.uno/geo')
```

`puck.lookup(uns)` returns a **Python class object**. Under the hood
it's a dynamically generated class that wraps the remote class's
method table. The returned object is usable anywhere a Python class
is: instantiate it, subclass it (if the package supports that),
introspect it.

**Failure case.** If the UNS doesn't resolve (unknown, withdrawn,
or a version segment that doesn't exist), `lookup` raises
`puck.NotFoundError`.

---

<a id="instantiation"></a>
## 6 Instantiation

Python's class-call syntax wraps the protocol-level constructor:

```python
hq = Geo(lat=37.7980, lon=-122.4626)
```

The client library translates this to a wire-level `.new(...)` call
on the remote class. **All Puck params are named** — every keyword
arg you pass becomes a named entry in the wire-level params hash.
Puck has no positional-parameter concept; the Python wrapper only
emits keyword args on the wire.

The returned `hq` is a Python object holding a reference to the
remote instance (a UNS for the instance, opaque to the developer).

---

<a id="calling-methods"></a>
## 7 Calling methods

Method calls look like ordinary Python:

```python
hq.weather                  # no-arg method (see Properties vs methods below)
hq.map_image(zoom=14)       # method with one keyword arg
hq.move(dx=5, dy=10)        # method with multiple keyword args
```

Puck has no positional-parameter concept — every arg on the wire is
a named entry in a JSON hash. Python callers always pass keyword
args; positional calls at the Python level aren't supported.

Each call:

1. Marshal the args to JSON.
2. POST `{uns, method, params, chain}` to the server.
3. Wait for the response.
4. Unmarshal the result.
5. Return it (as a primitive or another Puck wrapper — see
   [Return values](#return-values)).

The library hides all five steps. The caller sees a method call.

---

<a id="properties-vs-methods"></a>
## 8 Properties vs methods

Python distinguishes attribute access (`hq.weather`) from method calls
(`hq.weather()`). The Puck protocol treats both as method dispatch.
There are two ways the Python wrapper could handle this:

- **Always require parens.** `hq.weather()` even for no-arg
  "properties." Mechanically simpler; less Pythonic.
- **Lazy attribute access.** `hq.weather` triggers the remote call;
  `hq.darken(0.2)` works because `hq.darken` returns a callable. Reads
  more Pythonic; needs careful `__getattr__` design.

**Tentative direction:** lazy attribute access, with parens still
accepted (`hq.weather()` does the same thing as `hq.weather`). The
remote class's method definition declares which form is conventional;
the client follows. Open question.

---

<a id="return-values"></a>
## 9 Return values

A remote method's return value comes back as:

| Wire type | Python type |
|---|---|
| Number | `int` or `float` |
| String | `str` |
| Boolean | `bool` |
| Null | `None` (with optional flavor metadata on a wrapper — TBD) |
| Array | `list` of converted values |
| Hash | `dict` of converted values |
| **Reference to a Puck object** | wrapper instance that you can call methods on |

The Puck-object case is the interesting one. When a method returns
`puck.uno/congressional_district` (as in the [puck.md example](puck.md#remote-returns-can-be-other-puck-objects)),
the Python wrapper transparently constructs a Python class instance
representing the remote `CongressionalDistrict`. You don't have to do another
`lookup` — the reference is enough.

```python
district = hq.congressional_district     # remote CongressionalDistrict instance
district.representative           # remote method call on the new object
```

---

<a id="errors"></a>
## 10 Errors

Protocol-level errors map to Python exceptions. All inherit from
`puck.PuckError`:

| Protocol UNS | Python exception |
|---|---|
| `puck.uno/error/not_found` | `puck.NotFoundError` |
| `puck.uno/error/method_not_found` | `puck.MethodNotFoundError` |
| `puck.uno/error/transport` | `puck.TransportError` |
| `puck.uno/error/auth` | `puck.AuthError` |
| (any other registered Puck exception class) | `puck.RemoteError` with `.uns` attribute |

A remote method that itself raises an exception is propagated as a
`puck.RemoteError`. The exception's `.uns` attribute carries the
remote class's UNS, `.message` carries the message, and `.stack_trace`
carries the preserved remote stack trace.

```python
try:
    hq.weather
except puck.TransportError as e:
    log.warning(f'weather lookup failed: {e}')
except puck.RemoteError as e:
    log.error(f'remote raised {e.uns}: {e.message}')
```

---

<a id="versioning"></a>
## 11 Versioning

The Puck protocol takes a deliberately light approach to
versioning (see [protocol.md § Versioning](protocol.md#versioning)).
The Python client doesn't expose a per-call version-window
context manager — there's nothing for it to wrap. To use a specific
API version, look up the class at its versioned UNS:

```python
Geo = puck.lookup('puck.uno/geo/v2')
```

Charlie's blockchain-signed versioning of library identity is a
separate story; if you need that, see
[blockchain.md](../blockchain.md).

---

<a id="sync-vs-async"></a>
## 12 Sync vs async

**v1: synchronous only.** Every method call blocks until the response
arrives. This matches the most common Python usage pattern, keeps
the library tiny, and avoids forcing every consumer into an async
event loop.

**Async support is a planned later addition** — likely a parallel
`puck.async_` namespace (`puck.async_.lookup(...)`, `await
hq.weather`) so sync and async users don't step on each other. Shape
to be decided when async demand is real.

---

<a id="open-questions"></a>
## 13 Open questions

These are flagged so the eventual implementation work knows what
isn't decided yet.

- **Property-vs-method dispatch** (see [§8](#properties-vs-methods)).
- **Subclassing remote Puck classes.** Can a Python developer subclass
  `Geo` to add local methods, then override one of the remote methods?
  How does dispatch resolve when both a local and a remote method exist?
- **Client-side caching.** When is it safe to cache a remote method's
  result? Annotations from the server (cacheable / no-cache / TTL)?
  Per-instance vs per-class?
- **Connection management.** Long-lived HTTPS connection (keep-alive)
  vs request-per-call. Connection pooling. Timeouts.
- **Authentication.** Token in env var? Per-puck credential set?
  Integration with `keyring`? OAuth flow for interactive use?
- **Type stubs.** Auto-generate `.pyi` stubs from a remote class's
  definition so editors and type-checkers know the method signatures?
- **Threading.** Is the module-level default puck thread-safe?
  Per-thread default pucks?
