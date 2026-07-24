# `%chain.timer`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_utils_timer",
	"role": "spec for %chain.timer — measure elapsed wall-clock time around a block; returns duration in seconds"
}}
~~~

**Default-granted across role boundaries:** yes.  

`%chain.timer` measures elapsed wall-clock time around a block and returns the duration in seconds.

~~~caspian
$seconds = %chain.timer do
	# ... work to measure ...
end
~~~

The block runs normally; the return value of `%chain.timer` is the duration, not the block's return value. If you need both, capture the block's return inside and read it outside.

Wall-clock time, not CPU time — captures whatever happened during the block, including sleep, I/O wait, and forked-child time the parent waited on. For CPU-only measurements, a separate API would be needed; that's not what `%chain.timer` does.

## Companion: [`%chain.steps`](steps)

For engine-independent benchmarking — "how many steps did this take" rather than "how many seconds" — use [`%chain.steps`](steps). The two are typically used together when characterizing a piece of code.

## Testing

- **Returns a number in seconds** — `%chain.timer do end` returns a numeric value representing seconds.
- **Empty block near zero** — `%chain.timer do end` returns a value close to zero (some small positive number bounded by engine overhead).
- **Sleep block matches sleep** — `%chain.timer do; sleep 1; end` returns approximately `1.0` within an engine-defined tolerance.
- **Sleep block never below the sleep** — the returned duration is never less than the requested sleep time (monotonicity guarantee).
- **Includes wall time, not CPU time** — a block that sleeps 1 second reports ~1 second even though CPU time is near zero (wall-clock, not CPU-clock).
- **Includes I/O wait** — a block that blocks on stdin waiting for input reports the wall-clock time it waited, not zero.
- **Non-negative always** — repeated `%chain.timer do end` calls all return non-negative values.
- **Return value is the duration, not the block's return** — `%chain.timer do; return 'hello'; end` returns the duration, not `'hello'`.
- **Block's side effects observed** — the block's normal side effects (writes, assignments) happen; `%chain.timer` measures around them, not instead of them.
- **Nested timers each accurate** — an outer `%chain.timer` around an inner `%chain.timer do; sleep 1; end` — the inner returns ~1s; the outer returns ~1s plus a small overhead.
- **Nested inner subset of outer** — with any nested pair, the outer duration is greater than or equal to the inner duration.
- **Missing block raises** — `%chain.timer` without a block raises (or is a documented no-op — the test pins the behavior).
- **Wrong-arity raises** — `%chain.timer(5) do end` raises for unexpected argument.
- **Default-granted across role boundaries** — a non-user role can use `%chain.timer` without any explicit grant.
- **Monotonic clock source** — the timer uses a monotonic clock; wall-clock adjustments (NTP step, manual `date` change) during the block do not produce a negative duration or a discontinuity.
- **Exception mid-block** — if the block raises, the raise propagates past `%chain.timer` without producing a leaked duration binding; the timer's return value is not observable when the block raises.
- **Zero-duration block** — a block containing only `return 0` returns a very small duration; not negative, not zero exactly but bounded above by engine overhead.
- **Composes with `%chain.steps`** — wrapping the same body in both `%chain.timer` and `%chain.steps` reports independent time and step counts; using them together does not corrupt either measurement.
