# Caspian's Interface to Puck

~~~vibecode
{"vibecode": {
	"doc": "caspian-puck",
	"role": "spec for the Caspian-specific syntax and system methods that interact with the Puck protocol — %puck, %puck.call, remote method; the protocol itself is documented language-agnostic in puck/index.md",
	"key_concepts": ["%puck_system_method", "puck_bracket_lookup_shorthand",
		"%puck.call_remote_invocation", "remote_method_sugar",
		"puck_scoping_via_%chain"],
	"running_example": "puck.uno/geo — still in design; see ideas/geolocation.md"
}}
~~~

This doc covers how Caspian code talks to the [Puck protocol](../../puck/index.md).
The protocol itself is language-agnostic; this doc is about the Caspian
syntax and system methods that wrap it.

> The examples here use `puck.uno/geo`, a geolocation service planned
> for launch at puck.uno. **It's not deployed yet** — the design lives
> in [ideas/geolocation.md](../../../ideas/geolocation.md). It's used here as
> the running example because it's the canonical remote-first class
> (client-side stub, all logic on the server) and shows off the
> remote-call surface cleanly.

---

## `%puck`

`%puck` is a Caspian system method that returns a **Puck client
object** — the resolver for UNS lookups. See
[puck/index.md](../../puck/index.md) for what Puck is and how it works;
this section covers the Caspian sugar around it.

`%puck[UNS]` is shorthand for the puck's `lookup` method. The
lookup returns a **class**; call `.new(...)` to get an instance:

~~~caspian
$geo = %puck['https://puck.uno/geo'].new(lat: 40.7128, long: -74.0060)
puts $geo.city           # "New York"
puts $geo.country_code   # "US"
~~~

Methods on the instance dispatch as if local — the remote call
machinery is invisible at the call site.

### Scoping via `%chain`

`%puck` is scoped via `%chain` — the current Puck client lives in the
chain. Because `%chain` is wiped at role boundaries (see
[roles.md](../roles.md)), the current client does not propagate across
role boundaries; **each role gets its own world.** When there is no
client in the chain, `%puck` returns plain `null`.

**The engine decides what Puck client (if any) populates each role
boundary.** The engine may install a client on entry to a new role —
typically a restricted client per the role's trust profile — or it
may leave `%puck` null for that role. Per-role policy, not global.

---

## `%puck.call`

`%puck.call` is the Caspian syntax for an explicit remote method call.
Most code uses dot-call syntax (`$geo.address`) — the explicit form
is for when the method name is dynamic, or when you want the
remote-ness to be visible at the call site:

~~~caspian
%puck.call($geo, :address)
%puck.call($geo, :address, locale: 'en_GB')
~~~

Three arguments:

1. **Target object** — what to call the method on
2. **Method name** — a symbol
3. **Keyword parameters** — passed through to the remote method

`%puck.call` automatically forwards the current `%chain` to the remote
call — the same chain the calling function is running under.

For the protocol-level remote-invocation model (request shape, response
shape, error catalog), see [puck/index.md](../../puck/index.md).

### Return and error handling in Caspian

The result of a remote call comes back as if it were local — the call site doesn't have to know it crossed the wire. Errors raise as normal Caspian exceptions.

**Return values.** The remote method's result is marshaled back as a Puck object reference (for object returns) or a primitive (for strings, numbers, etc.). The calling code uses the value normally:

~~~caspian
$geo = %puck['https://puck.uno/geo'].new(lat: 40.7128, long: -74.0060)
$city = $geo.city               # remote method call returns a string
puts $city                        # use it like any local string
~~~

**Exceptions.** Three kinds can fire from a remote call:

- **Transport errors** — the network is unreachable, the server is down, TLS failed, etc. Class `puck.uno/error/transport`.
- **Protocol errors** — the request reached the server but the server reported a problem. `puck.uno/error/not_found` (the target object doesn't exist), `puck.uno/error/auth` (rejected by the server), `puck.uno/error/timeout`, etc.
- **The remote method's own exceptions** — if the method itself called `raise` on the server side, the same exception propagates back to the caller, with the remote stack trace preserved.

All three are ordinary Caspian exceptions. Catch with `catch` as usual:

~~~caspian
# Catch a specific transport failure and fall back
$weather = catch('puck.uno/error/transport')
    $geo.weather
end

if $weather.object.isa 'puck.uno/error/transport'
    # network failed; $weather IS the exception object
    puts "couldn't reach geo service: #{$weather.message}"
    $weather = {temp: null, conditions: 'unknown'}
end
# $weather is now either the real result or a fallback hash
~~~

**Catching multiple error classes** — wrap with the broadest applicable parent (per [exception catching by inheritance](../syntax/exceptions.md#catch)). All `puck.uno/error/*` Puck protocol errors inherit from `puck.uno/error`:

~~~caspian
$details = catch('puck.uno/error')
    $geo.details
end

if $details.object.isa 'puck.uno/error/transport'
    # network problem
    notify_admin("geo service unreachable")
    return null
elsif $details.object.isa 'puck.uno/error/not_found'
    # service is up but doesn't know this location
    return {unknown_location: true}
elsif $details.object.isa 'puck.uno/error'
    # any other Puck-protocol error
    log_error($details)
    return null
end
# $details is the actual response
~~~

**Remote-raised domain exceptions** — if the remote method's own code raises (e.g., a `myapp.com/error/rate_limit`), the same exception propagates back. Catch it the same way:

~~~caspian
$result = catch('myapp.com/error/rate_limit')
    $client.send_request
end

if $result.object.isa 'myapp.com/error/rate_limit'
    sleep($result.retry_after)    # use a field from the remote exception
    # retry, etc.
end
~~~

Full exception model lives at [syntax/exceptions.md](../syntax/exceptions.md); catch / inheritance semantics at [caspian-runtime.md § Exceptions and Warnings](../lucy/index.md#exceptions-and-warnings).

---

## `remote method`

See [remote-method.md](remote-method.md) — Caspian sugar for a method that delegates to `%puck.call`. Used by remote-first classes (geo, etc.) where almost every method is a network round-trip.
