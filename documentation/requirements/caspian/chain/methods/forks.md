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
