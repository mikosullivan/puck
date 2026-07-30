# Roles: prior art

~~~vibecode
{"vibecode": {
	"doc": "ideas_roles_prior_art",
	"role": "survey of prior art for role-based permission systems in programming languages — object-capability, code-source-based, runtime-permission, and effect-typed approaches. Reference material for Caspian's role model; not a design proposal.",
	"status": "survey — captures what exists in the ecosystem so the Caspian role design can locate itself relative to what's been tried",
	"scope": "runtime language mechanisms where WHO is executing (a role, a caller, a code source) affects WHAT operations are permitted. Excludes purely compile-time access modifiers (public/private/protected in most OOP languages) since those are per-class visibility, not per-role authority."
}}
~~~

Caspian's role model — code runs under a role, and certain method calls check the current role against the receiver's owning role — has neighbors in a handful of language families. This page catalogs them. It's a research map, not a comparison scorecard; the point is to know where the ideas came from before extending them.

## What we mean by "role-based permissions"

For this survey, a language qualifies if it has some runtime construct that answers "who is running this code, and is that identity allowed to do X to Y?" at least some of the time. That includes:

- **Object-capability** models where holding a reference IS the permission (implicit "role" = whoever currently holds the reference).
- **Code-source-based** models where the JAR / DLL / URL a piece of code came from grants or denies specific runtime operations.
- **Explicit role / principal** models where each stack frame carries a security identity.
- **Runtime-permission** models where the process is launched with a permission set and every system call checks the set.
- **Effect / capability types** where the type system tracks which capabilities each function is allowed to use.

It excludes purely compile-time visibility (public/private/protected/internal) — that's about namespacing, not authority.

## Object-capability languages

The purest form: a reference to an object IS the authority to invoke its methods. No ambient authority, no globals, no imports. Code that doesn't hold a reference to something has no way to reach it. Roles are implicit in reference distribution.

### E

The canonical ocap language. Objects are opaque; the only way to affect another object is to call a method on a reference you hold. There is no `import`, no `global`, no reflection that lets code enumerate objects it wasn't given. E introduced the vocabulary (facets, sealers/unsealers, promise pipelining) most later ocap languages borrow from.

### Newspeak

Object-capability by construction. Every module declaration is a function that takes its dependencies as arguments — nothing is available implicitly. Even class references have to be threaded in from a caller who chose to grant them. Gilad Bracha's project; direct influence on some later ocap work.

### Emily / Joe-E

Emily is an ocap-safe subset of OCaml (drops mutable references from the ambient scope). Joe-E is an ocap-safe subset of Java (drops static state, threads, reflection, and other authority-transmitting features). Both illustrate that an existing language can be made ocap-safe by removal, not addition — you subtract the sources of ambient authority.

### Monte

An E descendant retargeted to a Python-shaped surface. Same core: opaque objects, no imports, capability passing as the only communication mechanism.

### Pony

Not strictly ocap, but its reference-capability types (`iso`, `val`, `ref`, `box`, `tag`, `trn`) encode WHICH interactions a caller can have with an object based on which capability the reference carries. `iso` = isolated (send-and-forget), `val` = deeply immutable, `tag` = identity-only, etc. A single object can be referred to under different capabilities from different points in the program, and the type system enforces which methods each capability may call. This is closer to a per-reference role than a per-code-source role.

## Code-source-based (deprecated but historically important)

The idea: the AUTHORITY a piece of code has depends on WHERE THE CODE CAME FROM. Runtime checks look at the current call stack, walk it, and ask "does every frame's origin have permission for this operation?"

### Java SecurityManager

Java's original security model. Every class carries a `ProtectionDomain` recording where it was loaded from. A `SecurityManager` intercepts privileged operations (file I/O, network, reflection, exit) and walks the call stack; if any frame's class comes from an origin that lacks the required permission, the operation raises. `AccessController.doPrivileged` lets a trusted frame ASSERT its authority, cutting off the stack walk above it — the origin analog of Caspian's `user` role.

**Deprecated as of Java 17** (JEP 411). The rationale for removal is instructive: nobody could reason about the interactions between doPrivileged and framework call stacks, and audit-time verification that the policy actually blocked the intended operations turned out to be intractable. Performance was also nonzero — every privileged call ran a stack walk.

### .NET Code Access Security (CAS)

Direct analog of Java's SecurityManager for the CLR. Each assembly has evidence (URL, publisher, strong name). Runtime permission checks walk the call stack. `PermitOnly` / `Deny` / `Assert` shape what the walk sees. Deprecated in .NET Framework 4.0 and completely gone in .NET Core.

Same failure mode as Java: hard to reason about, hard to audit, easy to bypass with clever call-frame patterns.

### Windows / .NET user-role RBAC

Separate mechanism — Windows-account-based `PrincipalPermission` on methods (via attributes). This is closer to enterprise RBAC than language-runtime authority; the "role" is a Windows security group, checked against the OS-authenticated thread principal.

## Runtime-permission models

Grant permissions at launch; check them at each system call. Not per-object, per-process.

### Deno

The Deno CLI is launched with `--allow-net`, `--allow-read`, `--allow-write`, `--allow-env`, etc. Runtime calls that hit those permission categories check the process-level allow-list. Fine-grained (specific paths, specific hosts) is supported.

Deno's model is closer to a per-process capability set than a per-role one — every piece of code running in the process shares the same permission set. But it demonstrates that the ergonomic bar for a runtime-permission model can be met without stack-walk complexity.

### WASI

WebAssembly System Interface. The WASM module is instantiated with a specific set of preopened file descriptors, network endpoints, and clock/random handles. The module cannot reach system resources it wasn't handed at instantiation. This is very close to E-style ocap projected onto the WASM/host boundary.

### Racket custodians and sandboxes

Racket's `make-custodian` creates a manager that owns a set of resources (threads, ports, memory); shutting down the custodian cleans up everything it owns. `make-sandbox-evaluator` bundles a custodian with a resource-limit and permission set, producing an evaluator that can only touch what it was granted. Not per-role, but per-evaluator — a way to give code less authority than its enclosing process has.

### Erlang / Elixir

Processes have identity (PIDs) but the language doesn't restrict what a process can do based on identity. Isolation comes from the shared-nothing message-passing model — a process can only affect another process by sending a message, and only if it holds the target PID. Closer to ocap than to role-based; roles as such aren't a language feature.

## Effect / capability types

The type system tracks which side effects / capabilities each function needs, and the callsite has to have (or thread through) the required capabilities.

### Koka

Effect types are first-class. A function `f : () -> <exn, div> ()` declares that it may raise or diverge. Handlers introduce and discharge effects. Functions that need a capability must receive it — no ambient access.

### Wyvern

Capability-safe by design. Modules must declare which capabilities they need; the linker grants them explicitly. File I/O, network, mutation are all capabilities. The type of a module includes its capability requirements.

### Cobalt, Vault, F* etc.

Various research languages with effect / capability tracking. Not widely deployed but heavily cited in the ocap-meets-types literature.

## Isolation / sandbox mechanisms

Not roles per se, but they carve up the runtime into regions with different authority.

### SES (Secure ECMAScript)

An ES2020-era proposal from Agoric to make a capability-safe subset of JavaScript. `Compartment` isolates a JavaScript heap; the primordials are frozen; imports are explicit. Nothing in a compartment can affect anything outside except through explicitly-passed references.

### Realms / Compartments (in-flight ECMAScript proposals)

Formalize the compartment concept in the spec. Not shipping in v8/JavaScriptCore yet.

### Nashorn / GraalJS ScriptEngine restrictions

Older embedded-JS mechanisms with configurable class-access filters — closer to the Java-security-manager lineage than ocap.

## Cross-cutting observations

**Ocap is what won.** Every mainstream language mechanism from the last decade that tries to isolate untrusted code — WASI, Deno's permissions, JS compartments, Pony's reference capabilities — is either explicitly ocap or converges on ocap-like properties (nothing ambient, permissions travel with references). Java's SecurityManager and .NET CAS died because they tried to attach authority to code identity (where the code came from) rather than to references (what the code was handed). Stack-walk authority proved impossible to reason about.

**Per-object role checks are unusual.** Ocap makes the reference itself the permission — you don't check "who is calling"; you check "who is holding." Caspian's rule ("only `user` and the owning role can call `.stack`") is closer to the Java-style code-identity model than to pure ocap, and inherits some of the same "who is on the current stack?" complexity.

**Where role-check DOES appear at runtime,** it tends to be scoped very narrowly — a single privilege boundary between trusted host and untrusted plugin (V8 isolates, WASM sandboxes), not sprinkled across every method dispatch. The narrower the boundary, the easier it is to audit.

**Effect-typed languages compile away the check.** In Koka or Wyvern, the type system verifies the caller has the capability BEFORE the program runs. No runtime cost, no runtime confusion. But this requires the language to be built around effect types from the start, and the ergonomics of threading capabilities through every layer of an application are non-trivial.

**"Role" as an enterprise term is different.** Java's `PrincipalPermission`, .NET's `PrincipalPermission`, most web frameworks' `has_role('admin')` — these check the AUTHENTICATED USER's role against an application-defined policy. That's a different problem from language-runtime authority (which is about restricting what CODE can do). Both matter, but conflating them muddies the design conversation.

## What this means for Caspian

Not the point of this survey — but a few placeholders for follow-up thinking:

- Caspian's role model is closer to the Java-security-manager lineage (per-frame identity, checked at operation time) than to pure ocap. The rest of the industry moved away from that; is there a reason the Caspian answer will work where Java's didn't? What's the specific structural difference?
- Ocap-style narrowing via `.jail(...)` sits in the toolbox next to role-checks; the two mechanisms don't overlap perfectly. Worth spec'ing which is the "primary" mechanism and which is the fallback.
- Deno's model (process-level permissions at launch) is not per-object but IS ergonomically successful. Something to draw from when the developer experience of Caspian's role system is on the agenda.
- Nothing in the survey argues for or against Caspian's specific rule shape. It just says: this territory has been explored, and the answers that worked all share ocap DNA.
