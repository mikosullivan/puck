# Object access across roles

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_roles_object_access",
	"role": "spec for what a non-owning role is and isn't allowed to do with an object it holds. Companion to roles/index.md, which establishes that objects carry an owning role.",
	"status": "draft proposal — the V1 rule is intentionally simple; sections marked OPEN are intentional non-decisions to revisit post-V1",
	"audience": "developers passing objects across role boundaries; library authors deciding what to expose; AI tooling reasoning about cross-role security"
}}
~~~

Every object carries an owning role (see [roles § Objects also have roles](https://puck.uno/documentation/requirements/caspian/roles/#objects-also-have-roles)). This page covers what a non-owning role — code holding the object but not the role it was created in — is and isn't allowed to do with it.

## The V1 rule: holding is access

**A role that holds a reference to an object can call any method on that object.** The runtime does not gate method invocations by caller role. If user code hands an object to a library, the library can call any of the object's methods.

This is the same posture as Unix process boundaries: you don't get a reference to a thing you don't have access to; getting the reference IS the access. The work of restricting what a non-owner can do happens at the moment of handoff — by deciding what to pass — not at every method call afterward.

## Narrowing: pass a jail, not the raw object

When the owner wants to restrict what a non-owner can do with an object, the mechanism is a **jail wrapper** — a thin object that exposes only the named methods of the underlying object.

~~~caspian
$jail = $obj.object.jail(:safe_method, :read_only_method)
&untrusted_function $jail
~~~

`$jail` is a separate object the owner created. It holds the underlying object internally. Method calls on `$jail` for the named methods forward to the underlying object; method calls for any other method raise. The untrusted function can call `$jail.safe_method` and `$jail.read_only_method` and nothing else — including methods it might infer exist by introspection.

The original `$obj` still has its full surface for the owner. The jail is a per-recipient view.

Two important properties:

- **Jails are cheap.** The narrowing pattern only works if creating a jail is a one-liner. `$obj.object.jail(:m1, :m2)` is exactly that.
- **The owner decides what to expose.** The framework doesn't second-guess; the language doesn't gate methods at the call site. Whatever the owner passes is what the recipient can use.

This is the ["no nanny code"](https://puck.uno/documentation/overview#no-nanny-code) principle applied to objects: the runtime trusts the developer's handoff decision; it doesn't add a second layer of filtering.

## Self-gating from inside the method

The owner-side narrowing (jails) is one side of the picture. The other side is **the method body itself** deciding whether to proceed based on who's calling.

Inside any method, `%call` is the call object — an object representing the current method call. It's owned by the **caller**, not the method's class, so the method body can inspect it to learn things about who invoked it (caller's role, capabilities, etc.) and decide whether to do the work or raise.

~~~caspian
class &widget
    method &destroy()
        if %call.role != %self.object.role
            raise 'only the owner can destroy this widget'
        end
        ...
    end
end
~~~

There is no built-in "this method is owner-only" declaration. A method that wants to restrict callers writes the check itself, using `%call`. Caspian provides the primitive; the policy is the method author's.

Full `%call` spec: [`%call`](https://puck.uno/documentation/requirements/caspian/global-methods/call/).

## Object ownership is immutable

An object's owning role is set at creation and never changes. Passing an object to a different role doesn't transfer ownership; it just hands a reference across.

- A string created by user code is `user`-owned forever, even when held by `library:foo`.
- An HTTP response from a network faucet is owned by the faucet's role forever, even when transformed and stored in user data structures.
- A jail created by user code (wrapping a `library:foo` object) is `user`-owned, even though the methods it forwards land in library code.

The practical consequence: provenance is preserved through normal usage. Auditing where a value originated is reading the role tag, not reconstructing a call history.

## Derived objects: the creator owns

When an operation produces a new object, the new object is owned by **the role that ran the expression** — not by the role of any input value, no matter how much of the input's data flowed into the result.

~~~caspian
# In a foo-role frame:
$bar = 'whatever'    # foo owns the string

# In a gup-role frame:
$baz = 'dude'        # gup owns the string

# In a foo-role frame, given $baz somehow:
$bear = $bar + $baz  # foo owns the resulting string
~~~

The `+` expression ran in foo's frame, so foo conceptually created the new string, so foo owns it. The fact that `$baz`'s bytes are part of the result doesn't transfer any ownership to gup or to some "mixed" composite.

This is the simple, ship-able rule. The cost is that **provenance is erased through operations** — once `$bar + $baz` produces a foo-owned string, the role system has no record that gup's data flowed in. Audit can read who owns the value but not who contributed to it.

V1 accepts this trade-off. Finer-grained provenance (taint tracking, multi-role ownership) is a real concern but specifically deferred — see `ideas/security/string-provenance.md` for the eventual design space.

### Class instantiation is not an exception

The creator-owns rule applies straight through `.new()`. Even though a class itself is owned by whoever defined it, instances of that class are owned by **whoever called `.new()`** — not by the class's owner.

~~~caspian
# library:foo defines and owns the class
class &widget
    ...
end

# In a user-role frame:
$obj = $widget.new()       # user owns $obj — running .new() is just another expression
~~~

The class and the instance are two separate objects with two separate roles:

- `$widget.object.role` is `library:foo` (the class itself, defined and owned by the library).
- `$obj.object.role` is `user` (the instance, created by user code calling `.new()`).

When user calls `$obj.method()`, the method body still runs in a `library:foo` frame — frame-role tracks the class's owner, not the instance's owner. So inside the method:

- `%self.object.role` is `user` (it's the instance).
- The frame's role is `library:foo` (it's the class's role; that's what `%chain.role` reports inside the method).
- `%call.role` is `user` (the caller; see [Self-gating from inside the method](#self-gating-from-inside-the-method)).

Three different "roles" coexist in that method body. Each names a different thing: the instance, the running frame, and the caller. They're not interchangeable.

## Containers vs contents

**A container's role applies to the container itself, not to what's inside it.** Storing an object in a container is not derivation — it's just storage. The container's role doesn't launder the contents' role.

~~~caspian
# In a foo-role frame:
$bar = 'whatever'           # foo owns the string

# gup gets $bar somehow, then:
$myhash = {}                # gup owns the hash
$myhash['bar'] = $bar       # the hash is still gup-owned;
                            # the string at $myhash['bar'] is still foo-owned

$pulled = $myhash['bar']    # foo-owned — the string never changed hands
~~~

The hash is one identity; its members are other identities, each with their own role. Reading a value out of a container returns whatever was put in, with its original ownership intact.

This rule pairs with the derived-objects rule above:

- **Derivation**: ran an operation that produced a new object → role of the running code.
- **Storage**: put an existing object into a container → role unchanged (container's role applies only to the container).

## Errors are objects too

When code raises an exception, the exception is an object — owned by the role whose frame did the raising (creator-owns, same as everything else). The exception propagates up the call stack; at each frame on the way up, the frame can either catch it or let it continue rising. **Any frame on the way up can catch, regardless of role.** If the exception rises all the way past the top frame without being caught, the engine treats it as an uncaught exception.

A caught exception is just an object the catching frame holds. Holding-is-access applies in the usual way — the catcher can call any method the error class exposes (message, kind, source info, whatever internal state the class carries).

Practical consequences:

- An error raised in `library:foo` and caught in `user` is `library:foo`-owned. `user` holds a reference; `user` can introspect it like any other held object.
- A library can catch an error raised by code it called — including code it called via a user-supplied callback — because catch is unrestricted by role.
- An error class that exposes library-internal information through its methods is doing so by class design, not by a runtime guarantee. Library authors decide what their error classes make visible across the boundary.

## What this means for the recipient

When non-owner role R is handed an object O owned by role O.owner:

| Operation | Allowed? | Notes |
|---|---|---|
| Call any method on O | yes | The owner decided what methods to expose by deciding what object to pass (raw or jail). |
| Read public fields on O | yes | Same as method calls in the V1 model. |
| Mutate O's state via O's mutator methods | yes | If a mutator method is on the object, R can call it. The owner narrows by passing a jail without mutators. |
| Pass O to a third role | yes | The reference can be handed onward; ownership stays unchanged. |
| Hold O indefinitely (store in R's data structures) | yes | References don't expire on their own. |
| Change O's owning role | no | Immutable. |
| Reach methods the owner withheld via a jail | no | Methods not in the jail's allowlist raise on call. |
| Introspect to find methods the jail hides | no | The jail exposes only the named methods to any reflection surface. |

## What this DOESN'T cover

The model above is deliberately simple for V1. Several richer questions are deferred:

- **OPEN: persistent storage and ownership.** When an object is serialized to disk and re-loaded later, is the loaded object the same owner as the original? Probably yes by convention (the deserializer stamps it), but persistence-aware ownership needs a fuller spec.
- **OPEN: capability handles vs data objects.** A capability surface (like `%chain.net`) is reachable through the chain, not held as an object — so the rules here apply only to data-object references. The boundary between "an object you hold" and "a capability you reach" wants to be clean.
- **DEFERRED: ownership of objects pulled in through capability surfaces.** When user code does `%chain.argv[0]`, `%chain.env['HOME']`, `%chain.net.fetch(url).body`, etc., who owns the returned value? Under the creator-owns rule (above) the answer would be "the calling role." A **faucet** model — where each inbound surface has its own role and stamps its outputs (so a string from the network is distinguishable from a string from env) — is the other candidate. Picking between those needs the faucet model to be spec'd first — deferred until that lands.

## See also

- [`roles/`](https://puck.uno/documentation/requirements/caspian/roles/) — the role catalog and the role system overall.
- [`chain/`](https://puck.uno/documentation/requirements/caspian/chain/) — capability propagation across role boundaries (the chain side; this doc is the object side).
- The forthcoming jail spec (TBD) — full mechanics of `$obj.object.jail(...)`.
