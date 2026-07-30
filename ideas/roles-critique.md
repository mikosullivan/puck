# Caspian's security model: a critique

~~~vibecode
{"vibecode": {
	"doc": "ideas_roles_critique",
	"role": "critical review of Caspian's role-based security model — where it holds together, where it strains, and what the language could learn from ocap languages, effect systems, actor systems, and Deno-style launch-permission runtimes. Companion to ideas/roles-prior-art (survey of what exists).",
	"status": "critique — findings only, no design proposals promoted to requirements",
	"scope": "focuses on the role model, the .obj access rules, %call.role and %call.trusted?, and the ocap-adjacent parts (bucket encapsulation, .jail, holding-is-access). Not about authentication, cryptography, or transport security."
}}
~~~

Caspian's security story rests on three overlapping mechanisms:

- **Roles** — every stack frame runs under a role; `%call.role` reveals the caller's role; sensitive `.obj` methods check the caller against the receiver's owning role.
- **Holding-is-access** — a reference to an object grants the ability to call its public methods, no further check required.
- **Object-capability shape at the edges** — the bucket has no external-mutation surface; `.jail` narrows a passed-out surface to a named subset of methods.

Individually each mechanism has real precedent. As a combined model, some seams show. This page catalogs what strains and what other languages have to teach.

## Where the model holds together

Before the critique, three things Caspian gets right:

- **Bucket encapsulation is honest.** Unlike Ruby (`instance_variable_get` bypasses) or Python (name-mangling is convention only), Caspian's bucket has no external accessor at any role. If a class doesn't expose a method, the state is genuinely unreachable.
- **`.jail` is a narrowing primitive, not a bypass one.** Handing out a jail cannot re-widen; there is no `.unjail` and no `.prisoner`. This matches E-style facet patterns and is a real design win over "public with underscores."
- **The asymmetry between stack and bucket is coherent.** Stack = "how the world can extend this object's behavior"; bucket = "the object's own data." Making one mutable-from-outside and the other not-at-all is a defensible line, even if the reasons need to be spelled out.

The rest of this page is about where the model asks the reader (and the writer) to hold too many things in their head at once.

## Where the model has tensions

### The caller-identity model has a poor industry track record

Java's SecurityManager and .NET CAS both retired for the same reasons: nobody could reason about `AccessController.doPrivileged` interacting with framework call stacks, and audit-time verification that a policy actually blocked the intended operations turned out to be intractable. Both mechanisms tried to attach authority to code identity checked at operation time — exactly what `%call.role` does.

The difference between Caspian and those mechanisms is that Caspian's check is **frame-local** (just `%call.role`, no stack walk). That's simpler and cheaper. But it's also weaker: it means role-gating can't answer "did any frame in this call chain lack the required role?" It can only answer "does the immediate caller have it?"

The relevant question for the next design pass isn't "will Caspian's role check be as complex as Java's?" — it clearly won't. It's "does the frame-local check catch the real threats, and can a reader confidently predict when it will and won't?"

### Confused deputy is the obvious hole

Frame-local role checks are vulnerable to the classic confused-deputy pattern. Untrusted code holds a widget; widget was constructed by user code (owning role = user); untrusted code calls `$widget.public_method()`; inside `public_method`, the frame runs in the class's role, which invokes `.obj.classes.ensure(EvilClass)` on the widget; that call succeeds because the CALLING frame is now class-role, not untrusted-role.

`%call.role` inside the sensitive call reports "class role" — the intermediate frame. The originating untrusted role has vanished by the time the check runs.

Caspian's answer today is implicit: don't write class methods that expose stack-mutation to arbitrary callers. But that's a discipline requirement, not a language enforcement. Every class author is implicitly one accidental leaky method away from bypassing the whole role gate.

Cross-check: Java's `AccessController.checkPermission` walked the stack and forced every intermediate frame to have the permission. It was hated for exactly this — the framework author has to litter `doPrivileged` calls to make things work. Frame-local checks trade that pain for the confused-deputy vulnerability. There is no free lunch here; the language has to pick which pain to have.

### Ocap is what won, and Caspian is only partly ocap

The prior-art survey ([roles-prior-art](roles-prior-art)) makes the point: the mechanisms that survived from the last decade (WASI, Deno, JS compartments, Pony's reference capabilities, Newspeak) all converge on ocap-like properties — nothing ambient, permissions travel with references. The mechanisms that didn't survive (Java SecurityManager, .NET CAS) were role/code-identity based.

Caspian's bucket is ocap. `.jail` is ocap. But the role gating on `.obj` methods is code-identity based, and `%call.role` / `%call.trusted?` are code-identity primitives. Two models coexisting is fine when they agree; the question is what happens when they disagree.

Example: an untrusted holder of `$widget` cannot mutate the bucket at all (ocap wins — no accessor, no path). But the same untrusted holder CAN call methods on `$widget` that mutate the bucket internally, without any role check, because "holding is access" for method dispatch. So bucket protection is really "bucket is not directly mutable, but is mutable through any method the class exposes." That's a soft protection that depends entirely on what the class chose to expose.

The stack is worse: it IS directly mutable from outside (via `.obj.classes.ensure` etc.), gated by role. So the stack sometimes uses ocap (holding-is-access for `.jail`, `.tap`, etc. that inspect it) and sometimes uses role gating (mutation). The reader has to know which axis they're touching to predict the rule.

### The "user is always trusted" assumption is load-bearing

`%call.trusted?` returns true if the caller is `user`. `.obj.stack` is readable from user code without gating. User has ambient authority over every value.

This is fine in a single-developer script. It's less fine when:

- The Caspian process embeds untrusted content (a plugin, a downloaded script that user launched, evaluated user input).
- The "user" role has different meaning at different times (an interactive REPL, a scheduled job, a serverless invocation).
- User code accidentally hands untrusted code a reference into a user-owned object, and the untrusted code discovers it can call methods that internally use user's authority.

None of these are hypothetical. Most real programs eventually run untrusted content, and the language's answer to "how do we lower authority for one piece of code" is currently "run it in a different role" — which requires knowing how to configure roles, and there's no obvious primitive for "run this closure with reduced authority."

The `.jail` mechanism narrows the object surface, but doesn't affect what the receiving code can do with its own ambient authority. If code holds a jail of `$widget` but is running as user, it still has user authority for anything else. Attenuation of the receiver's own authority is not a Caspian primitive.

### Roles are coarse

The current model has effectively three role identities per object: user, class role, owning role. Complex programs frequently want finer trust structure:

- "This plugin can read files in `/plugins/data/` but not elsewhere."
- "This callback runs with the caller's authority minus network access."
- "This method may only be called by classes that inherit from `AuditableBase`."

None of these compose from `%call.role == %role` or `%call.trusted?`. Caspian would have to grow either a role hierarchy (roles have parents; child roles inherit from parents), role sets (a role is a set of permissions, roles compose by union/intersection), or attenuable capabilities (a role can be narrowed on the fly).

Every one of these adds a lot of complexity. The alternative is to say "Caspian doesn't support fine-grained trust and doesn't intend to." That's a defensible V1 posture, but it should be an explicit non-goal, not a gap by omission.

### Class authors can't declaratively gate methods

If a user class wants role-based method gating, the current pattern is to write the check in the method body:

~~~caspian
class # widget
	method &destroy_backend()
		if not %call.trusted?
			raise 'not trusted'
		end
		# ...
	end
end
~~~

Every gated method has to remember to write the check. Miss one and the class has a leak. The framework has no `trusted_only :method_name` DSL command that would add the check automatically at class definition time.

The engine already has to reason about method-level access for private methods (`.private = true` uses `%call.method_class`). Extending the same machinery to `.trusted_only = true` (or similar) would be a small addition that removes a large discipline burden from every class author.

### The stack-mutation gate is oddly permissive

The rule is "user + owning role can mutate the stack." But the owning role is stamped at construction — whoever called `.new`. If user code constructs a widget and hands it to a library, the library's role is different from the owner (user), so the library can't mutate. Good.

But what if the library constructs its OWN widget and hands one to user code, and user code calls `.obj.classes.ensure(SomeUserClass)` on it? User can — because user is always allowed. Is that what the library wanted? Probably not. The library made the widget for its own purposes; it doesn't want user code silently rewriting its behavior.

The "user is always allowed" rule leaks in the other direction too: user code accidentally holds a reference to a library-owned widget (through some inspection API), user experimentally adds a class to its stack, library's next call on the widget dispatches to user's added class. Silent hijack.

This isn't a fatal flaw — user has ambient authority and has to be careful — but it does mean `.obj.classes.ensure` is not safe to hand out even to trusted-seeming callers if the caller is user and the receiver isn't user-owned.

### `%call.trusted?` conflates two different trusts

`.trusted?` returns true for "same role" OR "user." The two trusts are qualitatively different:

- **Same role** = "the caller has the same authority I do; we're peers."
- **User** = "the caller is the program author; they have global authority."

Callers sometimes need to distinguish. For example, a class method might want to log user-initiated calls differently from internal calls, or apply different validation, or bypass certain guards only for user calls. `.trusted?` erases that distinction; callers who need it have to write out the full `%call.role == %role or %call.role.user?` pattern anyway.

That's not fatal, but it does mean `.trusted?` is a shortcut for one specific use case (the "same-role-or-user access gate") rather than a general trust predicate. If Caspian wants both, the doc should say `.trusted?` is narrow-purpose and `.role` comparisons are the general form.

## Lessons from other languages

### From E, Newspeak, WASI (pure ocap)

- **Trust travels with references, not with code identity.** Every design pass that adds "who is running this" logic weakens the ocap property. Weigh whether the same problem can be solved by narrowing what reference the caller received in the first place.
- **No ambient authority.** Newspeak has no globals, no imports; every dependency is passed in. Caspian is closer to this than the previous sentence suggests: I/O surfaces (`%net`, `%stdout`, `%fs`, and the rest of the system-facing globals) are engine-granted, not language-guaranteed. If the engine doesn't grant `%fs` to a role, code running as that role has no path to the filesystem — not via `%fs` and not via any equivalent. That's genuine ocap-style withholding at the interpreter boundary.

  **The Lua-library escape hatch.** The catch is that Caspian classes can call out to Lua libraries (via the FFI-like extension surface), and Lua libraries DO have ambient access to the host process's system resources. Any Caspian code that reaches a Lua library reaches, in principle, whatever the Lua process can reach — regardless of what the engine's grant policy says. This is a real hole, and one I'm actively working on. Options being considered: sandboxed Lua interpreters per role, capability-aware wrappers around every FFI entry point, or restricting FFI to a small allow-list of vetted libraries whose behavior is auditable. Not settled.

  Until that lands, the accurate framing is: **Caspian's own surfaces are engine-gated ocap, but the Lua substrate is not**. A program that avoids Lua libraries has strong ocap properties; a program that uses them inherits Lua's ambient authority.

### From Pony (reference capabilities)

- **Different references, different capabilities.** Pony encodes at the reference type WHICH interactions are permitted (`iso` = send-only, `val` = deeply-immutable-readonly, `tag` = identity-only). Caspian's `.jail` is a runtime analog — but Pony's is type-checked at compile time and can't be forgotten. Some middle ground (a runtime "reference capability" wrapper that's cheaper than a jail?) might buy the same clarity without needing types.

### From Deno / WASI (launch permissions)

- **Set the permission set at a boundary, not per-operation.** Deno launches with `--allow-net`, `--allow-read`; the permissions apply to the whole process. There's no per-method access check. Caspian could offer a "role transition" mechanism that grants specific permissions at a role-crossing point ("run this block as `plugin_role` with these ambient capabilities") rather than checking every method.
- **Fine-grained is possible.** Deno supports specific paths (`--allow-read=/tmp`), specific hosts (`--allow-net=example.com`). Fine-grained trust doesn't require role hierarchies; it can be expressed as capability sets attached to a boundary.

### From Java SecurityManager (deprecated)

- **`doPrivileged` was a nightmare.** Any escape valve that lets code assert authority beyond what its callers grant is a maintenance disaster. Caspian's `.trusted?` is currently simple and callable at will; it does NOT allow a frame to assert authority it doesn't have. Keep it that way. Every "well, it would be useful if" that adds assertion machinery makes the model harder to reason about.
- **Stack walks are expensive AND unpredictable.** Java's per-call stack walk was one of the reasons SecurityManager retired. Caspian's frame-local check avoids the cost, but at the confused-deputy price. Neither is free; either is defensible; the pick should be documented as the pick.

### From Erlang / actor systems

- **Isolate first, then coordinate.** Erlang processes share nothing; the only communication is by message. Trust boundaries collapse because there's no shared state to worry about. Caspian is single-threaded and value-shared, so this isn't a direct port, but the shape suggests something: what if untrusted code ran in a separate `%engine.fork()`-style boundary and could only affect the outside via serialized message passing? Roles as a within-heap concept could go away.

### From effect types (Koka, Wyvern)

- **The check happens at compile time.** Effect systems track capabilities in types; the compiler verifies capability threading before the program runs. Caspian is dynamic, so full effect types are off the table for V1. But a lightweight type-annotation surface — "this method requires `stack_mutation` capability" — could be checked at class-definition time (does the class declaration name the required capability?) rather than at every call.

### From Newspeak (no imports)

- **Wiring-time trust decisions beat operation-time trust decisions.** Newspeak modules declare dependencies as arguments; the wiring code decides who gets what. Compare to Java's SecurityManager, where wiring is implicit (the classloader arrangement determines authority) and every operation re-checks. Caspian's `%import` and `%fetch` are wiring-time-ish; extending that to "you get this class ref, or you don't" could reduce the need for per-op role checks.

## Directions to consider (post-V1)

Not committing to any of these. They are lines of thought the critique above opens up:

- **Reference capabilities as a runtime wrapper.** Beyond `.jail`, add capabilities like `readonly`, `identity_only`, `frozen_at_receipt` that a caller can apply to a passed-out reference. Recipient sees a wrapped reference; wrapper enforces at each method dispatch. Pony-style but dynamic.
- **Declarative method gating.** Class-body DSL command like `trusted_only :method_name` that adds the check at definition time. Class authors can't accidentally forget it.
- **Scoped ambient-authority reduction.** `%role.assume(:plugin_role) do ... end` that runs a block with the receiver's role temporarily reduced to a narrower one. Every ambient-authority call inside the block is checked against the narrower role.
- **Role hierarchies or role sets.** A role can extend another; a role can be a union of permissions. Enables "plugin role is a subset of user role minus network." This is a real complexity add — needs a strong use case before committing.
- **Explicit revocation.** A capability handed out can be revoked; subsequent calls on the recipient's reference raise. Useful for time-bounded grants.
- **Confused-deputy defense.** Optional stack-walk mode for specific sensitive operations, where the caller can opt in per call site. Not a global mode — a per-call one.
- **Non-ambient user mode.** A launch flag or scope where `user` doesn't have ambient authority. Every operation user attempts is checked against user's declared capabilities. Reserved for hardened deployments.

## Bottom line

Caspian's security model works well for the target audience it's currently designed for — a single developer writing a program where "user" is the developer and everything else is code the developer wrote or trusts. The model gets progressively less coherent as untrusted content enters the picture: the ocap and role mechanisms cross over each other in ways that make the rules hard to predict, confused-deputy is unaddressed, and there's no primitive for "run this piece of code with less authority than I have."

None of that means the current V1 design is wrong. It means the design boundaries need to be spelled out ("V1 is single-trust-domain; multi-trust support is a post-V1 topic"), and the post-V1 direction has to reckon with the industry-wide answer that came out of the last twenty years of trying: ocap, references-carry-authority, no ambient wherever possible. Every direction listed above is a step from "role check at operation time" toward "capability granted at wiring time and traveling with the reference." The mechanisms that survived all sit at that end of the spectrum.
