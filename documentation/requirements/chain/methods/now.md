# `%now`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_utils_now",
	"role": "spec for %now — current timestamp from the engine-controlled clock. Engine-controlled so test harnesses can inject a fixed clock for deterministic runs."
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%now`.

`%now` returns a timestamp object representing the current moment.

~~~caspian
$ts = %now
~~~

The reading comes from the **engine-controlled clock**, not directly from the OS. That indirection lets test harnesses inject a fixed clock for deterministic runs — the same program under test gets reproducible timestamps without having to thread a clock dependency through its own code.

The returned object is a timestamp value (full timestamp-class spec to migrate from `requirements-old/caspian/time.md`). Arithmetic, formatting, and comparison live on the value, not on `%now` itself.

## `%engine` counterpart

`%engine.now` is the user-only access to the same clock. The two return identical values for the same call.

## Testing

- **`%now` returns a timestamp value** — the return type is the timestamp class.
- **Shortcut `%now` matches `%chain.now`** — the two forms return equal values for the same call.
- **Matches `%engine.now`** — `%now` and `%engine.now` return equal values for the same call.
- **Default-granted across role boundaries** — a non-user role sees `%now` without an explicit grant.
- **Monotonic** — two `%now` reads in sequence satisfy `first <= second`.
- **Injected clock returns the injected value** — under a test harness that pins the clock to a fixed instant, every `%now` returns that instant.
- **Injected clock is deterministic** — repeated runs under the same fixed injection produce identical timestamps.
- **Clock advance under injection** — advancing the injected clock advances subsequent `%now` reads.
- **OS clock does not leak through injection** — under an injected clock, direct OS time does not leak through; the injected reading wins.
- **Returned value supports comparison** — `%now < %now` is valid syntax and comparable.
- **Returned value supports arithmetic** — timestamps combine with durations per the timestamp-class spec.
- **Returned value supports formatting** — the timestamp class's formatting methods apply.
- **Values do not carry a role tag** — `%now` is a pure value, not a faucet-provenance value.
