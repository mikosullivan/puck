# Concepts
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_concepts",
	"role": "umbrella doc for cross-cutting Caspian concepts that aren't tied to a specific surface — the language-level conventions and non-existent abstractions that benefit from being called out explicitly so readers don't build a wrong mental model.",
	"audience": "developers learning Caspian; AI tooling reasoning about the language; anyone who needs to know what is and isn't a real Caspian primitive"
}}
~~~

This page collects cross-cutting concepts that don't fit cleanly into any single API spec — language-level conventions, abstractions that don't exist as Caspian primitives, and the descriptive vocabulary developers use for things the engine doesn't track.

## Security

**Caspian is built from the ground up with security in mind.** It's designed specifically to **safely run untrusted code** — code the program author didn't write, didn't audit, and may not trust. The language doesn't bolt security on top of an otherwise-permissive runtime; the security model is a load-bearing part of how the language works.

The shape of the model:

- **Roles tag every value and every running frame** with an identity. Code's role is set when the engine starts (`user` for the program) or by the surface that introduced it ([faucets](https://puck.uno/documentation/requirements/caspian/pipes/faucets/) for inbound data, downloaded objects for `%puck` content). Roles don't get traded, swapped, or modified — they're permanent identities.
- **`%engine` is the only path to host resources, and only `user` can call it.** Untrusted code can't reach the host process through `%engine`; the gateway is gated unconditionally at the runtime level. The user has to explicitly hand specific capabilities down through `%chain`.
- **Capabilities propagate through `%chain` block-by-block, not ambiently.** Granting a capability is a deliberate per-block act; the grant evaporates when the block exits. There's no "this code has been blessed with permanent network access" — every grant is scoped, every revocation is enforceable. See [chain/grant-revoke](https://puck.uno/documentation/requirements/caspian/chain/grant-revoke).
- **Methods run as their object's role.** Calling a method on a downloaded object enters that object's role frame, not the caller's. The caller's authority doesn't leak across the dispatch boundary; the object can only do what its role has been granted. See [roles § Methods run as their object's role](https://puck.uno/documentation/requirements/caspian/roles/#methods-run-as-their-objects-role).
- **Faucets preserve provenance.** Every value entering the runtime through stdin, env, the filesystem, the network, or a `%puck` download is tagged with its source's role. That tag survives storage, passing, and most operations — "did this string ever come from the network?" is a real, answerable question.
- **Holding is access, but the owner controls what gets handed across.** A non-owner role with a reference to an object can call any method on it; the owner narrows what's reachable by passing a [jail wrapper](https://puck.uno/documentation/requirements/caspian/roles/object-access#narrowing-pass-a-jail-not-the-raw-object) instead of the raw object.
- **No nanny defaults.** The runtime never refuses a developer-chosen action by paternalism. Safe defaults and security guarantees stay, but "you can't because we think you shouldn't" is rejected. Full spec at [No nanny code](#no-nanny-code) below.

(More strategy sections to be added as the model gets exercised — sink-side semantics, role-trust declarations, capability-handle vs data-object boundaries, persistence-aware ownership, etc.)

## No nanny code

Caspian provides safe defaults, but there are ways to override them if you choose. The design distinguishes three postures:

- **Nanny code** says "you can't, because I think you shouldn't."
- **Safe defaults** say "you have to be explicit if you want to."
- **Security guarantees** say "you can't, because allowing this would break the trust model the rest of the system depends on."

The first is what Caspian avoids. The second and third stay.

When in doubt: **if a developer wants to do something legitimate that the API blocks without giving them a way through, that's nanny code**, and the design is wrong. Where a check might be desirable but a specific developer has reason to skip it, the language pairs a warn-by-default check with a named opt-out flag.

Concrete places this principle shapes the spec:

- [object-access § The V1 rule: holding is access](https://puck.uno/documentation/requirements/caspian/roles/object-access#the-v1-rule-holding-is-access) — the runtime doesn't add a second layer of filtering on top of what the owner decided to hand across. Owners narrow by passing a jail; recipients aren't second-guessed by the engine.
- [sinks § Sinks are just objects](https://puck.uno/documentation/requirements/caspian/pipes/sinks/#sinks-are-just-objects) — sinks don't role-check outbound values. If you hold a sink, you can call its methods; the security work is at the handoff.

## Objects, not libraries

Caspian doesn't have a "library" concept as a technical primitive. [`%puck`](https://puck.uno/documentation/requirements/caspian/chain/methods/puck) downloads **objects** — typically classes, but also instances, dispatchers, anything that fits the Puck object protocol. Each download is one object identified by one URL.

You may informally call a group of related downloads a "library" — the same way you'd informally call several files a "module" or several functions a "toolkit." That's a developer-side description of how code is organized, not a runtime entity. The engine never sees "libraries"; it sees individual objects downloaded by `%puck` calls, each tracked separately in [`%engine.manifest`'s `downloads` section](https://puck.uno/documentation/requirements/caspian/engine/manifest/#sections).
