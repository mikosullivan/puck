# `%chain.argv`

**STALE — pending relocation.** `%chain` no longer carries methods. This file describes what used to live on `%chain.X` and awaits relocation to its correct home (typically a top-level global, a downloadable core object, or a permission-indicator stub). See [chain/index](https://puck.uno/requirements/chain/) for the current `%chain` scope.

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_utils_argv",
	"role": "spec for %chain.argv — global form of %engine.argv. Same array of command-line arguments, reachable from any role granted the capability."
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.argv` is the array of command-line arguments the program was invoked with — the same value as [`%engine.argv`](../../engine/argv), but reachable from any role granted the capability. User code typically reads `%engine.argv` directly; non-user code that needs the args reaches for `%chain.argv` after the user has granted it the capability.

The shape is identical: an array of strings, first element is the first user-supplied argument, may be empty.

## Testing

- **`%chain.argv` returns an array** — with the capability granted, `%chain.argv` is an array of strings.
- **`%chain.argv` is `null` without the grant** — with the capability not granted, `%chain.argv` is `null`.
- **`%chain.argv` is default-deny across role boundaries** — a non-user role does not see `%chain.argv` until the capability is explicitly granted down the chain.
- **`%chain.argv` matches `%engine.argv`** — when both surfaces are accessible in the same run, they return equal arrays.
- **First element is the first user-supplied argument** — the array starts at the first arg the host handed to the program, not a script name.
- **Order is preserved** — args appear in the array in the order the host supplied them.
- **Empty argv** — launching with no user args yields an empty array `[]`.
- **Unicode args round-trip** — an arg like `"café"` appears in the array unchanged.
- **Args with spaces preserved** — a single arg containing spaces stays a single array element.
- **Args with special characters preserved** — quotes, backslashes, and shell metacharacters appear as-is.
- **Values carry the argv role tag** — strings read from `%chain.argv` carry the role provenance of the argv faucet.
- **Read-only** — attempting to mutate `%chain.argv` via `.push` or index assignment raises.
- **Index out of range** — `%chain.argv[99]` on a shorter argv returns `null`.
- **`.length`** — `%chain.argv.length` returns the number of args.
- **Iteration** — `%chain.argv.each` yields each arg in order.
- **Revoke clears the surface** — after the argv capability is revoked in a nested block, `%chain.argv` inside that block is `null` and reverts on block exit.
