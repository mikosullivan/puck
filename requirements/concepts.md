# Concepts
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_concepts",
	"role": "umbrella doc for cross-cutting Caspian concepts that aren't tied to a specific surface — the language-level conventions and non-existent abstractions that benefit from being called out explicitly so readers don't build a wrong mental model.",
	"audience": "developers learning Caspian; AI tooling reasoning about the language; anyone who needs to know what is and isn't a real Caspian primitive"
}}
~~~

This page collects cross-cutting concepts that don't fit cleanly into any single API spec — language-level conventions, abstractions that don't exist as Caspian primitives, and the descriptive vocabulary developers use for things the engine doesn't track.

## Security

**Caspian is built from the ground up with security in mind.** It's designed specifically to **safely run untrusted code** — code the program author didn't write, didn't audit, and may not trust. The language doesn't bolt security on top of an otherwise-permissive runtime; the security model is a load-bearing part of how the language works.

The shape of the model:

- **Roles tag every value and every running frame** with an identity. Code's role is set when the engine starts (`user` for the program) or by the surface that introduced it ([faucets](https://puck.uno/requirements/plumbing/faucets/) for inbound data, downloaded objects for `%fetch` content). Roles don't get traded, swapped, or modified — they're permanent identities.
- **`%engine` is the only path to host resources, and only `user` can call it.** Untrusted code can't reach the host process through `%engine`; the gateway is gated unconditionally at the runtime level. The user has to explicitly hand specific capabilities down through `%chain`.
- **Capabilities propagate through `%chain` block-by-block, not ambiently.** Granting a capability is a deliberate per-block act; the grant evaporates when the block exits. There's no "this code has been blessed with permanent network access" — every grant is scoped, every revocation is enforceable. See [chain/grant-revoke](https://puck.uno/requirements/chain/grant-revoke).
- **Methods run as their object's role.** Calling a method on a downloaded object enters that object's role frame, not the caller's. The caller's authority doesn't leak across the dispatch boundary; the object can only do what its role has been granted. See [roles § Methods run as their object's role](https://puck.uno/requirements/roles/#methods-run-as-their-objects-role).
- **Faucets preserve provenance.** Every value entering the runtime through stdin, env, the filesystem, the network, or a `%fetch` download is tagged with its source's role. That tag survives storage, passing, and most operations — "did this string ever come from the network?" is a real, answerable question.
- **Holding is access, but the owner controls what gets handed across.** A non-owner role with a reference to an object can call any method on it; the owner narrows what's reachable by passing a [jail wrapper](https://puck.uno/requirements/roles/object-access#narrowing-pass-a-jail-not-the-raw-object) instead of the raw object.
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

- [object-access § The V1 rule: holding is access](https://puck.uno/requirements/roles/object-access#the-v1-rule-holding-is-access) — the runtime doesn't add a second layer of filtering on top of what the owner decided to hand across. Owners narrow by passing a jail; recipients aren't second-guessed by the engine.
- [sinks § Sinks are just objects](https://puck.uno/requirements/plumbing/sinks/#sinks-are-just-objects) — sinks don't role-check outbound values. If you hold a sink, you can call its methods; the security work is at the handoff.

## Every situation is in scope

There is no such thing as an "edge case" in Caspian. What people commonly label an edge case is just an unusual situation — the rules of the system still apply to it, and it needs to work correctly. Bugs and security problems live in exactly the situations that get dismissed with that label: an unauthenticated request with an odd header shape, a form submit fired twice in a row, a downloaded object fetched during a partial network partition. Each is precisely where the security model has to hold.

**Every situation is in scope.** The spec describes behavior for the full input space, not just the common path. When an unusual case gets named, it's named because the rule specifically covers it — not because it's being carved out as a special exception the design gets to skip.

If a section needs to describe an unusual situation, use language like "the case where X happens during Y" or "the failure mode when Z is absent." Never reach for "edge case" — the label itself signals that a situation has been noticed and then categorized as unimportant enough to skip, which is where bugs live.

## Long descriptive names for rarely-used surfaces

Method names, field names, chain-mediated permissions, and other surfaces balance two forces: **brevity for common use** (typing cost, visual noise in hot code) and **clarity for rare use** (a reader doesn't have to remember what a cryptic short name means in code they touch once a year).

Caspian picks explicitly per surface:

- **Frequent surfaces get short names.** `.push`, `.pop`, `.map`, `%bucket`, `%self`, `%stdout`. Every program touches these; brevity pays for itself in every file.
- **Rare surfaces get long descriptive names.** `.absolute_negative`, `.repeated_permutation`, `%chain.allow_abort_escalation`. A reader encountering these once a year benefits from a name that explains itself in context — no doc lookup required.

When in doubt about frequency, lean verbose. Renaming a long name to a short one later is a mechanical sweep; typing a confusing short name into rarely-touched code is a maintenance cost forever.

The rule applies uniformly across the language: built-in methods, class methods, chain-mediated permissions, engine config keys, security-sensitive APIs, and any other surface where a reader might need to consult docs to know what a name means.

## Classes are the only method-carrier

Caspian has **only one mechanism for attaching methods to objects: classes**. There are no modules, no mixins, no traits, no singleton methods, no protocol conformances, no per-object method dictionaries — nothing besides classes.

This is deliberately unlike languages such as Ruby (which has classes, modules, singleton methods, and refinements as four distinct method-carrier mechanisms), Python (classes and module-level functions), or JavaScript (classes, prototypes, and mixin patterns as separate strategies). Caspian collapses all of those into one concept.

The class model is flexible enough to cover every case those languages use different mechanisms for:

- **An object can carry any number of classes.** Its stack of platters holds them in dispatch order; each contributes methods.
- **A class can inherit any number of classes.** Multiple inheritance is a normal class-definition feature, not an add-on.
- **Each instance has a shadow class.** When code defines a method on a single specific instance, the method lives on that instance's shadow class — which is still a class. Nothing special about the mechanism; it's just a class that happens to have one instance.

If a reader coming from another language reaches for "module" or "mixin" or "singleton method" to describe a Caspian construct, they're using the wrong vocabulary. Every method-carrier in Caspian is a class. Every method attachment is class-scoped. Every dispatch resolution walks classes. One mechanism, applied at every level.

The upside is a smaller conceptual surface and a uniform way to reason about method resolution: you only ever ask "which classes does this object carry?" and "which classes do those classes inherit?" Never a different question depending on how the method got attached.

## Objects, not libraries

Caspian doesn't have a "library" concept as a technical primitive. [`%fetch`](https://puck.uno/requirements/chain/methods/puck) downloads **objects** — typically classes, but also instances, records, anything that fits the Puck object protocol. Each download is one object identified by one URL.

You may informally call a group of related downloads a "library" — the same way you'd informally call several files a "module" or several functions a "toolkit." That's a developer-side description of how code is organized, not a runtime entity. The engine never sees "libraries"; it sees individual objects downloaded by `%fetch` calls, each tracked separately in [`%engine.manifest`'s `downloads` section](https://puck.uno/requirements/engine/manifest/#sections).

## Caspian is written in Caspian

**Above the primitive line, Caspian is written in Caspian itself.** The host language (Lua and C, in the reference implementation) is used only for what has to live there: the interpreter, the engine's control plane, faucet and sink surfaces, `%engine`, memory-protection primitives, protected-mode windows, and bindings to C libraries (libsodium, LPeg, HTTP parser, etc.). Everything above that line — built-in classes, stdlib helpers, protocol validation, orchestration — is Caspian code.

This is a deliberate design commitment, not just implementation hygiene:

- **Users can read and modify the code that runs their programs.** Password, Passkey, the built-in collection classes, and every other stdlib surface are Caspian objects you can `%fetch.fetch`, inspect, learn from, fork, or replace. A Caspian program isn't standing on an opaque host-language substrate — it's standing on more Caspian.
- **Caspian's design concepts get demonstrated in the stdlib itself.** Roles, chains, holding-as-access, classes-as-only-method-carrier, faucet provenance — these become concrete examples in the code every program uses. The stdlib doubles as a working demonstration of what Caspian is for.
- **The trust surface stays small.** The host-language layer is what the security model has to trust; keeping it minimal makes it audit-able. Everything above the primitive line runs under the same rules any user code runs under.
- **Iteration doesn't require binary releases.** Fixing a bug in Password's algorithm dispatch, adding an exception class to Passkey, or refining a helper method ships as a new Caspian class version — not a rebuild-and-redistribute of the caspian binary.

The heuristic when designing a new capability: **anything that could be written in Caspian without giving up security, correctness, or usable performance should be.** Reach for the host language only for what genuinely can't exist above the primitive line.

**Floppy budget can override the preference.** Caspian-in-Caspian is a design preference, not a hard requirement. If implementing a subsystem in Caspian would push the [floppy budget](https://puck.uno/requirements/core/) past what fits — either through fat CaspM cache-tier code or through stdlib growth needed to support it — falling back to a Lua implementation for that subsystem is legitimate. The trade-off is real: less user-inspectable code, larger trust surface, harder to fork or replace at the Caspian level. But shrinking the install below the floppy line wins when it's the difference between Caspian fitting on target hosts and not fitting. Note the choice at the affected subsystem's spec page so a future reader knows a Lua implementation was chosen over Caspian for size reasons, not preference.

## Lean on installed Linux utilities when they're better

Where a system utility is near-universally installed and does the job better than a Lua library Caspian would otherwise ship, Caspian prefers to shell out. Two things get better at once: the floppy budget stays smaller, and the software Caspian relies on is more mature and better-tested than any Cache-tier reimplementation. The Prerequisite tier at [core/](https://puck.uno/requirements/core/) is where this pattern lives, alongside the openssl / tar / gzip / curl utilities that already earn their spot there.

Two conditions must hold before a utility qualifies:

- **Probably already installed.** On Linux, that's essentially every mainstream distro; on macOS, in the base system; on Windows, common enough via package managers. If it's only present on half the target hosts, it's not a Prerequisite — it belongs in Cache or Executable.
- **Superior to what a shipped Lua library would give the user.** The whole trade is worth taking because a purpose-built, hardened C tool beats a Cache-tier Lua reimplementation on performance, spec coverage, and mileage. If the substitute isn't clearly better, the Lua library is the safer default.

The trade in one sentence: **give up bundle self-containment to free floppy budget and inherit better software**. See [xml-in-pure-caspian § How Caspian would call it](https://puck.uno/ideas/xml-in-pure-caspian#how-caspian-would-call-it) for a worked case.

**The process rule that follows:** any time a new capability is proposed that would need a Cache-tier Lua library, the design pass **must** first check whether an already-installed Linux facility could deliver the same result. What kind of facility — a CLI utility, a shared C library linked directly, a system service — is decided case by case for that surface. Only reach for the Lua library once the check has come back negative: no facility is universal enough, none is superior, or the operation shape (streaming, event-driven, fork-per-call cost, ABI drift concerns) makes the substitution a poor fit. Applies to core surfaces and to Puck-hosted class implementations equally. The check is cheap; skipping it is how Cache-tier bloat accumulates. Where the check comes back positive, [linux-utilities-vs-lua-libraries](https://puck.uno/ideas/linux-utilities-vs-lua-libraries) is the receipts pattern for writing up the trade.

## Primitive reuse

**One well-chosen primitive that fits many shapes is worth more than several specialized ones.** Every reuse keeps engine code smaller, keeps the developer mental model tighter, and keeps the floppy budget healthier. When designing a new capability, first ask: does an existing primitive fit this shape?

Examples that have earned their reuse in Caspian:

- **Exceptions** serve return / raise / exit. One control-flow mechanism carries three semantic uses; the engine has one exception dispatcher, developers learn one machinery.
- **Aggregate hashes** ([`lua/aggregate-hash`](https://puck.uno/requirements/lua/aggregate-hash)) serve `%chain` / scope frames / class-method resolution / delegated environments — every "lookup walks a chain of hashes" pattern. One primitive, many roles.
- **`function_call` bwc** ([caspianj § Calls](https://puck.uno/requirements/caspianj#calls)) collapses bareword calls, dot method calls, closure invocations, downloaded-method applications — every callable invocation — to one CaspM shape.
- **Freeze** is Caspian's constant mechanism across three surfaces: variables via [`variable-object.freeze`](https://puck.uno/requirements/built-in-classes/variable-object#freezing), hash fields via [`.freeze_field`](https://puck.uno/requirements/built-in-classes/primitives/hash#freezing-fields), whole objects via [`.object.freeze`](https://puck.uno/requirements/built-in-classes/object/methods#freeze_bucket--freeze_stack--freeze). No separate `const` keyword; freeze does everything.
- **`assign` bwc** serves variable assign and subscript assign — dispatch on lvalue shape.
- **Aggregate `.set(key, value)`** is the scope runtime's assignment mechanism AND the general walk-then-write primitive available to any aggregate consumer.

The heuristic: when adding a new capability, look at what's already in the vocabulary before inventing a new primitive. If the new need fits an existing shape, use it. If the fit is forced — bending the existing primitive out of shape or teaching it a special case that doesn't belong — invent a new primitive. But that's the rare path, not the default.

Failure modes if the check is skipped:

- **Engine bloat.** N specialized primitives means N dispatch handlers, N implementations, N places to fix a related bug.
- **Cognitive load for developers.** N ways to do slightly-different things when one general way would do.
- **Divergent behavior.** Each specialized primitive develops its own edge cases; the general primitive gets one set of edge cases everyone shares.

**Not a suicide pact.** Force-fitting a primitive to a wrong shape is worse than adding a new one. The check is "does it fit?" — not "how can I make it fit?" When exceptions started serving return and exit alongside raise, that was a natural extension of one control-flow mechanism. Trying to fit something structurally different — cross-thread message passing, for example — onto exceptions would be forcing the shape; a different primitive would be right.

## Strings are UTF-8

Every string passed into Caspian is automatically re-encoded as UTF-8. Caspian source, string values in downloaded objects, the results of `%fetch` fetches, arguments handed to the engine by a host — all of it lands as UTF-8 inside the runtime, and every string value the engine produces or serializes is UTF-8. Developers never see an "encoding" concept at the language level; the runtime handles the conversion at the boundary.

In practice the conversion is usually trivial:

- **ASCII** is already valid UTF-8 — no work required.
- **UTF-8** input passes through as-is.
- **UTF-16** and other Unicode encodings are transcoded to UTF-8 at the boundary using the standard mappings.

The exact conversion policy for other encodings — legacy single-byte charsets, non-Unicode double-byte encodings, byte sequences with no declared encoding, and any invalid or partially-valid input — will be filled in as the boundary handling is designed.

## Testing

- **`%engine` reachable from `user`** — a first-frame program running as `user` can call any host-provisioned `%engine` slot without raising.
- **`%engine` raises for non-user roles** — code running under a role other than `user` that touches any `%engine` slot raises, regardless of what `%chain` has been granted.
- **`%engine` is not capturable into a variable** — an attempt to alias `%engine` (e.g. assigning it to a local, boxing it in a hash, passing it to another role) raises before the alias is created.
- **Role tag attaches at value creation** — a literal string, number, hash, array, and instance created in a `user` frame each carry the `user` role tag; the tag is readable immediately after construction.
- **Role tag attaches to values from faucets** — bytes read from stdin, an env-var value, a filesystem read, and a network response each carry the introducing surface's role tag, not the caller's.
- **Role tag survives storage and passing** — a value tagged `user` that is stored in a hash, passed to another frame, returned from a method, or put into an array retains its `user` tag on retrieval.
- **Faucet provenance is queryable** — after `$s = ...` from a network faucet, an introspection call can identify that `$s` originated from that faucet's role.
- **Method dispatch enters the object's role** — calling a method on a downloaded object under role `X` causes the method body to execute with `%role == X`, even when the caller is `user`.
- **Callee's role does not receive caller's ambient authority** — a method that inspects its `%chain` sees only what the callee's role has been granted; capabilities the caller held that were not granted through are absent.
- **Grants are per-block** — a `%chain` capability granted inside a block is visible to code called from within that block and is not visible after the block exits.
- **Revoke inside a block clears the grant** — a revoke issued inside a block removes the capability before subsequent statements in the same block execute.
- **Holding an object grants access to its methods** — a non-owner role that holds a reference to an object can call any of its methods; the engine does not filter dispatches.
- **Jail wrapper narrows what the recipient sees** — an owner that passes a jail wrapper exposes only the methods the jail names; a call to any method not in the jail raises.
- **No nanny opt-out is honored** — the named opt-out flag for a warn-by-default check disables the warning and does not raise, without any second layer of paternalistic filtering.
- **Classes are the only method carrier** — attaching a method by any mechanism other than a class definition (module, mixin, per-instance dictionary, prototype patch) fails or has no equivalent syntax.
- **Instance-level method lives on the shadow class** — a method defined on a specific instance is dispatched via that instance's shadow class and is not visible on other instances of the same underlying class.
- **Multiple inheritance dispatches through the class stack** — a class inheriting from two parents resolves methods by walking the platter stack in declared order.
- **One URL, one object via `%fetch`** — two successive `%fetch(url)` calls with the same URL and same fetcher chain state return the same object identity.
- **`%engine.manifest.downloads` tracks each URL separately** — two `%fetch` fetches of two URLs produce two distinct entries under `downloads`; nothing groups them under a "library" identity.
- **ASCII input passes through unchanged** — a pure-ASCII input string arrives at Caspian byte-identical.
- **UTF-8 input passes through unchanged** — a UTF-8-encoded string arrives at Caspian byte-identical.
- **UTF-16 input is transcoded to UTF-8** — a UTF-16-encoded string arrives at Caspian as its UTF-8 equivalent.
- **Every string value inside the runtime is UTF-8** — after any of the above inputs, `str.bytes` returns valid UTF-8 for every string reachable from user code.
- **Serialized outputs are UTF-8** — a string emitted via `%stdout`, written to a file, or handed back to a sink is UTF-8 regardless of the input encoding.
