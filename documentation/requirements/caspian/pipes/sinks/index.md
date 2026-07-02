# Sinks
<!--index: 2 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_sinks",
	"role": "concept doc for sinks — the outbound complement to faucets. A sink is any object with methods that send information out to the world. Sinks are ordinary objects; holding-is-access applies; the engine is the only ultimate source of sink capability. No runtime role check on values passed through.",
	"status": "framing settled",
	"audience": "developers reasoning about what code can send out; anyone designing capabilities that touch outbound resources; AI tooling reasoning about outbound data-flow"
}}
~~~

**Everything that leaves the Caspian runtime leaves through a sink.** A sink is an object with methods that send information to the outside world — writing to stdout, writing to a file, sending an HTTP request, publishing an object. The name is a vocabulary choice: data flows out through the sink. There are no other outbound paths.

The complement is a **faucet** — an inbound surface that pulls external values into the program. Faucets are covered separately in [faucets](https://puck.uno/documentation/requirements/caspian/pipes/faucets/); this doc is the outbound side.

## Sinks are just objects

A sink is not a special runtime primitive. It's an ordinary Caspian object with methods, subject to all the ordinary object rules:

- **Holding is access.** Code that holds a sink object can call any method it exposes, including the methods that send data out. Same as the [object-access rule](https://puck.uno/documentation/requirements/caspian/roles/object-access#the-v1-rule-holding-is-access) for any other object. If you can see `%stdout`, you can call its `.puts` or `.print`.
- **Method dispatch is normal.** `%stdout.puts('hello')` is not a special "outbound" operation from the language's perspective — it's a method call. The engine's implementation of `.puts` is what actually writes to the process's stdout stream; from the language's point of view it's a method like any other.
- **The security model lives at the handoff.** Whether a callee can write to stdout depends on whether the caller passed `%stdout` (or a wrapper around it). No runtime check ever inspects the value being written and compares it to some sink-role table.

This is the same posture as objects generally: the runtime doesn't add a second layer of filtering on top of what the owner decided to hand across. It's the [no nanny code](https://puck.uno/documentation/requirements/caspian/concepts#no-nanny-code) principle applied to outbound.

## All sinks descend from engine-provided objects

Sinks aren't values a program can invent. Every sink traces back to an **engine-provided object** — one of the small set of things the engine hands `user` at startup (populated on `%engine`, mirrored onto `%chain`). The engine's method implementations are what actually push bytes to stdout, write to the filesystem, send over the socket, etc. Concretely:

| Surface | What it sinks |
|---|---|
| [`%stdout`](https://puck.uno/documentation/requirements/caspian/chain/methods/stdout-and-stderr) / `%engine.stdout` | Bytes written to the program's primary output. |
| [`%stderr`](https://puck.uno/documentation/requirements/caspian/chain/methods/stdout-and-stderr) / `%engine.stderr` | Bytes written to the diagnostic channel. |
| [`%chain.root`](https://puck.uno/documentation/requirements/caspian/chain/methods/root) / `%chain.tmp` | Filesystem writes via dirjails. |
| [`%chain.net`](https://puck.uno/documentation/requirements/caspian/chain/methods/net) | HTTP request bodies, socket writes. |
| [`%chain.puck`](https://puck.uno/documentation/requirements/caspian/chain/methods/puck) | `%puck.register(url, ...)` publishes an object out to the object network. |

User code can wrap any of these — put an object in front of `%stdout`, narrow `%chain.root` with a nested dirjail, build a per-host adapter over `%chain.net` — but every outbound method call transitively lands on a method the engine implemented. Without an engine-provided handle somewhere in the ancestry, there is no outbound path at all.

This is what makes the engine the outbound gateway: a program that holds no engine-descended sink object literally can't send data out. There is no "backdoor" outbound primitive at the language level.

## Narrowing sinks

A sink is an object, and objects can be [narrowed with a jail](https://puck.uno/documentation/requirements/caspian/roles/object-access#narrowing-pass-a-jail-not-the-raw-object):

~~~caspian
$safe_out = %stdout.object.jail(:puts)   # only .puts is reachable
&some_untrusted_function $safe_out
~~~

The narrowed handle exposes exactly the methods the caller chose, and nothing else. Callees can't introspect around it.

For faucet/sink dual surfaces (see below), narrowing is often more structured — a [nested dirjail](https://puck.uno/documentation/requirements/caspian/chain/methods/root#nested-dirjails) with `readonly: true` restricts writes without needing an explicit jail; a per-host net wrapper only surfaces the methods it chose. Whatever shape the narrowing takes, the callee can only invoke what's reachable through the wrapper.

## Some surfaces are both faucet and sink

Several engine-provided surfaces are dual-purpose:

- **`%chain.net`** — a faucet (responses come in) AND a sink (request bodies go out).
- **`%chain.root`** / **`%chain.tmp`** — faucets (file reads produce values) AND sinks (`.write(...)` sends bytes out).
- **`%chain.puck`** — a faucet (`%puck[url]` returns a downloaded object) AND a sink (`%puck.register(url, ...)` publishes one).

The faucet and sink halves are two aspects of one object. The role model applies to the faucet side (values read carry the faucet's role); the object model applies to the sink side (holding the object is authority to call its methods). Both are always in play; there is no conflict.

## What sinks don't do

The sink model is deliberately narrow. A lot of things that might look like "sink policy" aren't part of it:

- **No automatic role check on the value.** The runtime does not inspect the owning role of a value passing through a sink. Code that holds a sink object can send any value through it, regardless of where that value originated. If a policy wants to restrict per-source, the wrapper enforces it — or the raw sink isn't handed over in the first place.
- **No default policy at the sink level.** There is no "sinks are default-deny/default-allow." Sinks are objects; if a role holds one, it can use it. Which sinks a role holds by default is decided by the chain grant model (see [chain § Two layers of grant](https://puck.uno/documentation/requirements/caspian/chain/#two-layers-of-grant)), same as any other capability.
- **No cross-role transfer via serialization.** When code writes a value to a file, the stored bytes carry no role tag. On the read side, deserialization produces a new object owned by the reader (see [object-access § Persistence doesn't preserve ownership](https://puck.uno/documentation/requirements/caspian/roles/object-access#persistence-doesnt-preserve-ownership)).

The security work happens at the handoff (deciding whether to pass a sink object) and at the narrowing (deciding which methods the wrapped sink exposes). Not at the moment of method call.

## Why this matters

- **The security posture is simple.** Whether code can send data out is one question: does it hold a sink-descended object? If yes, it can. If no, it can't. No runtime gate inspects the payload.
- **The narrowing pattern is uniform.** The same jail/wrapper toolkit that narrows inbound faucets narrows outbound sinks. Callers don't need a separate mental model per direction.
- **The engine remains the only outbound gateway.** Programs can't fabricate outbound paths; every one is rooted in an engine-provided object. Sandboxing at the host level (which properties the host wires) determines what's possible in the first place.
