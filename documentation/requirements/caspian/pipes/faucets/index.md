# Faucets
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_faucets",
	"role": "concept doc for faucets — the model that says every external value entering the Caspian runtime comes through a specific inbound surface with its own role identity. The model is the framing for why role-tagging works on inbound data; specific per-faucet role decisions live in the roles catalog.",
	"status": "framing settled — every faucet has its own role; nested/narrowed faucets don't add roles (values still carry the parent faucet's role, mirroring the object-jail rule)",
	"audience": "developers reasoning about where untrusted data came from; anyone designing capabilities that touch inbound resources; AI tooling tracing the provenance of values"
}}
~~~

**Everything that comes into the Caspian runtime comes in through a faucet.** A faucet is any resource that pulls external values into the program — stdin, environment variables, command-line arguments, the filesystem, the network, the `%puck` download surface. The name is a vocabulary choice: data flows in from outside; the faucet is where it comes out into the runtime. There are no other inbound paths.

The complement is a **sink** — an object with methods that send information out to the world (filesystem write, query send, network output, `%stdout.puts`). Sinks live in their own doc at [sinks](https://puck.uno/documentation/requirements/caspian/pipes/sinks/); this doc is the inbound side.

## What's a faucet, concretely

Every inbound surface the engine exposes is a faucet. The current `%chain` mirrors and their `%engine` slot equivalents are the canonical V1 list:

| Faucet | Surface | What flows in |
|---|---|---|
| stdin | [`%chain.stdin`](https://puck.uno/documentation/requirements/caspian/chain/methods/stdin) / `%engine.stdin` | Bytes piped to the process. |
| argv | [`%chain.argv`](https://puck.uno/documentation/requirements/caspian/chain/methods/argv) / `%engine.argv` | Command-line arguments. |
| env | [`%chain.env`](https://puck.uno/documentation/requirements/caspian/chain/methods/env) | Environment variables. |
| filesystem | [`%chain.root`](https://puck.uno/documentation/requirements/caspian/chain/methods/root) / `%chain.tmp` | File contents and directory listings read through dirjails. |
| network | [`%chain.net`](https://puck.uno/documentation/requirements/caspian/chain/methods/net) | HTTP response bodies, socket reads, UDS data. |
| downloads | [`%chain.puck`](https://puck.uno/documentation/requirements/caspian/chain/methods/puck) | Objects downloaded from URLs. |

Each row in this table is a distinct faucet with its own role — see the next section.

## Every faucet has its own role

**Every faucet has its own distinct role, and every object returned by that faucet is owned by that role.** Roles are not shared or grouped across faucets — stdin's role is not the filesystem's role is not the network's role. Each surface in the catalog above carries its own identity, and values pulled through it carry that identity.

A `user`-role frame reading bytes from stdin ends up holding bytes owned by the stdin faucet's role, not by `user` and not by some shared "system-input" role. Same for env, same for argv, same for filesystem reads, same for network responses, same for downloaded objects — each kept distinct.

The faucet's role names the *source* of the data, not the *grabber*. That's what lets a recipient distinguish "a string from the network" from "a string the user typed" from "a string from a config file" — they're all strings, but their owning roles are different and that difference is checkable at any point downstream.

The user-role code holding faucet-owned values can use them, store them, pass them around — `holding` is access per the [object-access rules](https://puck.uno/documentation/requirements/caspian/roles/object-access). What the user can't do is forge their origin: a value owned by the network-faucet's role stays owned by that role forever (immutable ownership), and an audit asking "did this come from the network?" gets a real answer.

## Narrowed faucets don't add roles

Some faucets can be **narrowed** — the caller creates a restricted view of a broader faucet without going back to the engine. Dirjails are the primary case: any code holding a dirjail can construct a nested dirjail rooted at a subdirectory (see [`%chain.root` § Nested dirjails](https://puck.uno/documentation/requirements/caspian/chain/methods/root#nested-dirjails)). The same pattern applies to other narrowable faucets — a per-host wrapper around `%chain.net`, for instance.

**Values read through a narrowed faucet carry the parent faucet's role — not a per-narrowing role.** A nested dirjail rooted at `%chain.root['foo']` still delivers files whose owner is `%chain.root`'s role. A per-host wrapper around `%chain.net` still delivers responses whose owner is `%chain.net`'s role. Narrowing restricts *what can be reached*, but doesn't change *what the source is*.

This is the same pattern as the [object-jail rule](https://puck.uno/documentation/requirements/caspian/roles/object-access#narrowing-pass-a-jail-not-the-raw-object): a jail wrapper restricts which methods reach through but doesn't launder the underlying object's ownership. The narrowed-faucet rule is the same idea applied to a faucet.

Consequences:

- **Role count stays bounded.** The number of distinct faucet roles equals the number of engine-provided faucets — around seven data-producing surfaces in the V1 catalog above. Programs cannot mint new faucet roles by narrowing.
- **Audit granularity is capped at the faucet level.** "Did anything from the filesystem ever reach the network?" is answerable. "Did anything specifically from `/foo/bar` ever reach the network?" is not — programs that need finer audit have to instrument the read side themselves (e.g., wrap read results with additional metadata).
- **Passing a narrowed faucet across a role boundary passes access, not a new identity.** The receiver reads values owned by the original faucet's role, regardless of who did the narrowing.
- **The narrowing object itself is a normal object.** A nested dirjail (or narrowed net wrapper) is owned by whichever role created it — creator-owns for the container — but that ownership is separate from the ownership of values read through it.

## Why this matters

Without a faucet model, "where did this string come from?" is unanswerable — the runtime sees a string, and a string is a string. With it, provenance is preserved by construction: the role tag on every value names its source, and the source name survives every transformation that doesn't explicitly forge it (the [creator-owns rule](https://puck.uno/documentation/requirements/caspian/roles/object-access#derived-objects-the-creator-owns) on derivations does erase the input role, but the original values are still tagged at their source).

The practical wins:

- **Audit can answer "what did this program touch?"** by walking the values it produced and looking at their roles.
- **Capability gating can differentiate by source.** "This sink only accepts values from `fs:projectroot`" is a writable policy.
- **Downloaded code can distinguish hostile from cooperative input** without trusting the caller's word — the faucet role tells it.
- **Compliance / data-flow tooling has a foothold.** "Did data from `net:thirdparty` ever reach `db:billing`?" becomes a query the runtime can answer.
