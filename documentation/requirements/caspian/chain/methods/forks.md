# `%chain.forks`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_forks",
	"role": "spec for %chain.forks — spawn forked child processes. Three forms (branch, multiple, detach), each takes a do-block that runs in the child."
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.forks` spawns forked child processes. Each form takes a `do ... end` block that runs in the child; the parent gets back a manager (or null, in the child).

| Form | Purpose |
|---|---|
| `%chain.forks.branch do ... end` | Fork one child. Parent gets a manager; child gets null. |
| `%chain.forks.multiple(N) do ... end` | Fork N children running the same block. Parent gets an array of managers. |
| `%chain.forks.detach do ... end` | Fork a fully-detached child — parent loses tracking. |

~~~caspian
%chain.forks.multiple(20) do
	# this runs in each of 20 child processes
end
~~~

## Capability gating

Forking is **off by default**. The host grants the capability at launch; without the grant, `%chain.forks` is `null`. The capability has to be explicitly sent down the `%chain` — same posture as `%chain.tmp` and other engine-granted capabilities. A process that can fork does not automatically grant that ability to everything it calls.

## Where the spec lives

The full forking spec — manager API (`.kill`, `.term_kill`, `.detach`, `.active?`, `.zombie?`, etc.), IPC, signal handling — has its canonical home under `requirements/caspian/forking/`. This page is just the entry-point surface.

## Testing

- **`%chain.forks` is `null` without the grant** — without the fork capability, `%chain.forks` is `null`.
- **Default-deny across role boundaries** — a non-user role does not see `%chain.forks` until the capability is explicitly granted down the chain.
- **`.branch` runs the block in a child process** — side effects inside the block occur in a separate process from the parent.
- **`.branch` returns a manager to the parent** — the parent receives a manager object referring to the child.
- **`.branch` returns `null` in the child** — the child sees `null` as the return value of the branch call.
- **`.multiple(N)` creates N children** — `N` distinct child processes run the same block.
- **`.multiple(N)` returns an array of N managers** — the parent gets `N` manager objects in an array.
- **`.multiple(1)` behaves like `.branch`** — one child, one manager, block runs once.
- **`.multiple(0)` produces no children** — the parent receives an empty array; the block does not run.
- **`.multiple(-1)` raises** — negative counts are rejected at the call site.
- **`.multiple` with non-integer raises** — a float or string in place of `N` raises.
- **`.detach` returns no manager to the parent** — the parent has no handle to the detached child.
- **`.detach` child outlives the parent** — the detached child continues running after the parent exits.
- **Capability does not propagate through calls** — granting `%chain.forks` to a caller does not automatically grant it to nested callees.
- **Manager exposes lifecycle methods** — `.kill`, `.term_kill`, `.detach`, `.active?`, `.zombie?` are callable on a live manager.
- **Manager reports child exit code** — after the child exits, the manager exposes the child's exit code.
- **`.multiple` children run the same block independently** — each child executes the block; failures in one do not affect others.
- **Block that raises in child** — an unhandled raise in a child terminates that child; the parent's manager reflects the failure.
- **Revoke clears the surface** — after `%chain.forks` is revoked in a nested block, it is `null` inside that block and reverts on block exit.
