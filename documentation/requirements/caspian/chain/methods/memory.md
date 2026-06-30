# `%chain.memory`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_memory",
	"role": "spec for %chain.memory — read-only introspection of the current process's memory usage"
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.memory` exposes read-only introspection of the current process's memory usage.

~~~caspian
%chain.memory.used    # bytes currently used by this process
~~~

## Memory-management surface (deferred)

A wider memory-management API has been sketched but not specified. Ideas recorded so the slot doesn't get forgotten:

- A configured hard limit (`%chain.memory.limit`) and an `available` derivation from it.
- A settable soft threshold (working name `%chain.memory.raise`) that raises an exception when usage crosses it, so handlers can unwind gracefully under pressure.
- Engine-level enforcement (continuous, mid-allocation) rather than user-side polling.

None of the above is committed. Shape, names, and semantics are open until a concrete use case drives the design.
