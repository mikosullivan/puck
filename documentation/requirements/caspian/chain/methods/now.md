# `%now`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_now",
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
