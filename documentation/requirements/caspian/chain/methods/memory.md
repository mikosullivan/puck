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

## Testing

- **`%chain.memory` is `null` without the grant** — without the capability, `%chain.memory` is `null`.
- **Default-deny across role boundaries** — a non-user role does not see `%chain.memory` until the capability is explicitly granted down the chain.
- **`.used` returns an integer** — the value is an integer number of bytes, not a float.
- **`.used` is in bytes** — value is bytes, not kilobytes, megabytes, or pages.
- **`.used` is non-negative** — the value is always `>= 0`.
- **`.used` reflects recent allocations** — after allocating a large object, `.used` is greater than it was before the allocation.
- **`.used` is read-only** — assigning `%chain.memory.used = 0` raises.
- **Deferred surfaces absent at V1** — `%chain.memory.limit`, `.available`, and `.raise` are not present until they are specified; touching them raises `undefined method` rather than returning `null`.
- **Revoke clears the surface** — after `%chain.memory` is revoked in a nested block, it is `null` inside that block and reverts on block exit.
