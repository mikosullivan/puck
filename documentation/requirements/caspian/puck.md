# Caspian's Interface to Puck

~~~json
{"vibecode": {
	"doc": "caspian-puck",
	"role": "spec for the Caspian-specific syntax and system methods that interact with the Puck protocol — %puck, %puck.call, remote function; the protocol itself is documented language-agnostic in puck/index.md",
	"key_concepts": ["%puck_system_method", "puck_bracket_lookup_shorthand",
		"%puck.call_remote_invocation", "remote_function_sugar",
		"puck_scoping_via_%chain"],
	"running_example": "puck.uno/geo — still in design; see ideas/geolocation.md"
}}
~~~

This doc covers how Caspian code talks to the [Puck protocol](../puck/index.md).
The protocol itself is language-agnostic; this doc is about the Caspian
syntax and system methods that wrap it.

> The examples here use `puck.uno/geo`, a geolocation service planned
> for launch at puck.uno. **It's not deployed yet** — the design lives
> in [ideas/geolocation.md](../ideas/geolocation.md). It's used here as
> the running example because it's the canonical remote-first class
> (client-side stub, all logic on the server) and shows off the
> remote-call surface cleanly.

---

<a id="puck"></a>
## `%puck`

`%puck` is a Caspian system method that returns a **Puck client
object** — the resolver for UNS lookups. See
[puck/index.md](../puck/index.md) for what Puck is and how it works;
this section covers the Caspian sugar around it.

`%puck[UNS]` is shorthand for the puck's `lookup` method. The
lookup returns a **class**; call `.new(...)` to get an instance:

~~~caspian
$here = %puck['puck.uno/geo'].new(lat: 40.7128, long: -74.0060)
puts $here.city           # "New York"
puts $here.country_code   # "US"
~~~

Methods on the instance dispatch as if local — the remote call
machinery is invisible at the call site.

<a id="scoping-via-chain"></a>
### Scoping via `%chain`

`%puck` is scoped via `%chain` — the current Puck client lives in the
chain. Because `%chain` is wiped at role boundaries (see
[roles.md](roles.md)), the current client does not propagate across
role boundaries; **each role gets its own world.** When there is no
client in the chain, `%puck` returns plain `null`.

**The engine decides what Puck client (if any) populates each role
boundary.** The engine may install a client on entry to a new role —
typically a restricted client per the role's trust profile — or it
may leave `%puck` null for that role. Per-role policy, not global.

---

<a id="puckcall"></a>
## `%puck.call`

`%puck.call` is the Caspian syntax for an explicit remote method call.
Most code uses dot-call syntax (`$here.address`) — the explicit form
is for when the method name is dynamic, or when you want the
remote-ness to be visible at the call site:

~~~caspian
%puck.call($here, :address)
%puck.call($here, :address, locale: 'en_GB')
~~~

Three arguments:

1. **Target object** — what to call the method on
2. **Method name** — a symbol
3. **Keyword parameters** — passed through to the remote method

`%puck.call` automatically forwards the current `%chain` to the remote
call — the same chain the calling function is running under.

For the protocol-level remote-invocation model (request shape, response
shape, error catalog), see [puck/index.md](../puck/index.md).

<a id="return-and-error-handling-in-caspian"></a>
### Return and error handling in Caspian

- **Return value** — the remote method's result, marshaled back as a
  Puck object reference (or a primitive). Callers don't see "this was
  remote"; the value behaves like any local call result.
- **Exceptions** — the protocol error catalog
  (`puck.uno/error/not_found`, `puck.uno/error/transport`,
  `puck.uno/error/auth`, etc.) is raised as ordinary Caspian exceptions.
  Catch with `catch` as usual:

~~~caspian
$addr = catch('puck.uno/error/transport')
    $here.address
end
~~~

If the remote method itself raises, that exception propagates to the
caller as if thrown locally, with the remote stack trace preserved (per
[caspian-runtime.md § Exceptions and Warnings](lucy/index.md#exceptions-and-warnings)).

---

<a id="remote-function"></a>
## `remote function`

`remote function` is Caspian sugar for a method that delegates to
`%puck.call`. The geo class is a remote-first class — almost every
method is a `remote function`:

~~~caspian
class 'puck.uno/geo'
    field :lat
    field :long
    field :alt

    remote function &address
    end

    remote function &distance_to($other)
    end

    remote function &city
    end
end
~~~

`remote function &address` is equivalent to:

~~~caspian
function &address
    %puck.call(self, :address)
end
~~~

Pure syntactic sugar; the two forms are interchangeable. `%chain` is
forwarded automatically in both.
