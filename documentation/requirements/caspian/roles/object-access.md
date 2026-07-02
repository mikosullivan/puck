# Object access across roles

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_roles_object_access",
	"role": "spec for what a non-owning role is and isn't allowed to do with an object it holds. Companion to roles/index.md, which establishes that objects carry an owning role.",
	"status": "draft proposal — the V1 rule is intentionally simple; sections marked OPEN are intentional non-decisions to revisit post-V1",
	"audience": "developers passing objects across role boundaries; downloaded-object authors deciding what to expose; AI tooling reasoning about cross-role security"
}}
~~~

Every object carries an owning role (see [roles § Objects also have roles](https://puck.uno/documentation/requirements/caspian/roles/#objects-also-have-roles)). This page covers what a non-owning role — code holding the object but not the role it was created in — is and isn't allowed to do with it.

## The V1 rule: holding is access

**A role that holds a reference to an object can call any method on that object.** The runtime does not gate method invocations by caller role. If user code hands an object to a downloaded-code frame, that frame can call any of the object's methods.

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

This is the ["no nanny code"](https://puck.uno/documentation/requirements/caspian/concepts#no-nanny-code) principle applied to objects: the runtime trusts the developer's handoff decision; it doesn't add a second layer of filtering.

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

- A string created by user code is `user`-owned forever, even when held by `faucet_1`.
- An HTTP response from a network faucet is owned by the faucet's role forever, even when transformed and stored in user data structures.
- A jail created by user code (wrapping a `faucet_1` object) is `user`-owned, even though the methods it forwards land in `faucet_1` code.

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
# faucet_1 defines and owns the class
class &widget
	...
end

# In a user-role frame:
$obj = $widget.new()       # user owns $obj — running .new() is just another expression
~~~

The class and the instance are two separate objects with two separate roles:

- `$widget.object.role` is `faucet_1` (the class itself, defined and owned by `faucet_1`).
- `$obj.object.role` is `user` (the instance, created by user code calling `.new()`).

When user calls `$obj.method()`, the method body still runs in a `faucet_1` frame — frame-role tracks the class's owner, not the instance's owner. So inside the method:

- `%self.object.role` is `user` (it's the instance).
- The frame's role is `faucet_1` (it's the class's role; that's what `%chain.role` reports inside the method).
- `%call.role` is `user` (the caller; see [Self-gating from inside the method](#self-gating-from-inside-the-method)).

Three different "roles" coexist in that method body. Each names a different thing: the instance, the running frame, and the caller. They're not interchangeable.

## Values pulled through faucets carry the faucet's role

The creator-owns rule has one important exception: **values pulled through a faucet are owned by the faucet's role**, not by the calling role. When user code does `%chain.stdin.read`, `%chain.argv[0]`, `%chain.env['HOME']`, `%chain.net.fetch(url).body`, etc., the value that comes back is tagged with the source faucet's role — not with `user`.

This is the inbound-data side of the role system, spec'd in [`pipes/faucets/`](https://puck.uno/documentation/requirements/caspian/pipes/faucets/). Each inbound surface (stdin, argv, env, filesystem, network, downloads) has its own distinct role, and values flowing through carry that role. The creator-owns rule still applies to everything OTHER than inbound-faucet values — derived strings, computed hashes, instances of user-defined classes, etc. all follow the calling-role-owns model.

The faucet rule preserves provenance at the role layer: a recipient can distinguish "a string from the network" from "a string the user typed" from "a string from a config file" without manual taint-tracking. See faucets for the full model.

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

## Persistence doesn't preserve ownership

**A deserialized object is a new object, owned by whoever rebuilt it.** There is no concept of ownership surviving a save.

A blob on disk is just bytes; bytes don't carry role identity. When code reads those bytes and reconstructs an object, that code created the resulting object (per the [creator-owns rule](#derived-objects-the-creator-owns) above), so that code's role owns it.

~~~caspian
# user code:
$record = $database.load('users/123')   # user owns $record — even though some other
										# role originally wrote it last year
~~~

Ownership is an in-memory runtime property, not a persisted one. The serialize/deserialize boundary is treated like any other expression that yields a new object.

Consequences:

- A Mikobase store full of values written by various roles last week comes back as user-owned objects when read by user code today.
- A serialized agent's working memory restored after a crash is owned by whichever code does the restore — the pre-crash role doesn't follow the bytes.
- Configuration loaded from disk at startup is owned by the loading code (typically user during boot).

If a system needs role-preserving persistence (provenance audit across restarts, capability handles surviving restart, etc.), that's a design layered on top of this rule — e.g., store role identity alongside the value as ordinary data and re-attach it deliberately at load time. The runtime doesn't do this automatically.

## Chain-reachable surfaces are first-class values

A `%chain.X` method namespace can be captured into a variable and passed around like any other object:

~~~caspian
$net = %chain.net
~~~

`$net` is a first-class value. It can be held, stored, passed as an argument, captured by a closure — all the things a regular object reference can do. A common use is **giving an object the ability to do networking** (or filesystem access, or whatever the captured surface covers) by handing it the captured reference at construction:

~~~caspian
$worker = $WorkerClass.new(net: %chain.net)
~~~

The worker now has its own handle on the network surface; the constructor didn't have to do anything special.

Once captured, the value follows the regular object-access rules in this doc — holding is access, the holder can call any method on it, narrowing is via a jail, etc. The capture point is a normal expression, so derived-objects ownership applies (the role that evaluated `%chain.X` owns the resulting reference).

### Passing a captured surface across a role boundary

The interaction with role boundaries falls out of the existing rules — no special mechanism needed:

~~~caspian
# In user frame:
$net = %chain.net                            # user owns $net
$some_object.do_thing_with(net: $net)        # non-user object holds $net
~~~

Inside `do_thing_with`, when the non-user body calls `$net.fetch(...)`, [methods run as their object's role](https://puck.uno/documentation/requirements/caspian/roles/#methods-run-as-their-objects-role) — so the fetch body runs as **user** (the owner of `$net`) and the network call proceeds through user's authority. In effect, **capturing a chain surface into a variable and passing it is one way to hand a specific capability across a role boundary**, alongside [`%chain.role.grant`](https://puck.uno/documentation/requirements/caspian/roles/#granting-capabilities-to-other-roles). Neither displaces the other; both use the same underlying "holding is access" model.

The narrowing tool for chain surfaces is the [same jail wrapper](#narrowing-pass-a-jail-not-the-raw-object) as for any object: `%chain.net.object.jail(:fetch)` produces a handle that only exposes `fetch`.

### Captured surfaces outlive the grant that made them reachable

Chain grants control **permission to call methods on `%chain`** — they don't scope the lifetime of objects returned from those methods. Once a role has looked up `%chain.X` and captured the result, the captured reference is a normal held object: usable for as long as anyone holds it, regardless of what happens to the chain grant afterward.

~~~caspian
# In a user frame:
%chain.role.grant($widget.object.role, :net) do
	$widget.remember_net()     # widget's method captures %chain.net into @net
end
# Grant block over — widget's role no longer has %chain.net.

$widget.use_it_later()          # succeeds — @net is still a held reference
~~~

This means block-scoped grants provide block-scoped **visibility** of a surface, not block-scoped **lifetime** of captured references. A role that gets even a brief grant can lift the surface into a variable and keep using it.

## Errors are objects too

When code raises an exception, the exception is an object — owned by the role whose frame did the raising (creator-owns, same as everything else). The exception propagates up the call stack; at each frame on the way up, the frame can either catch it or let it continue rising. **Any frame on the way up can catch, regardless of role.** If the exception rises all the way past the top frame without being caught, the engine treats it as an uncaught exception.

A caught exception is just an object the catching frame holds. Holding-is-access applies in the usual way — the catcher can call any method the error class exposes (message, kind, source info, whatever internal state the class carries).

Practical consequences:

- An error raised in `faucet_1` and caught in `user` is `faucet_1`-owned. `user` holds a reference; `user` can introspect it like any other held object.
- A non-user role can catch an error raised by code it called — including code it called via a user-supplied callback — because catch is unrestricted by role.
- An error class that exposes internal information through its methods is doing so by class design, not by a runtime guarantee. Class authors decide what their error classes make visible across the boundary.

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

## See also

- [`roles/`](https://puck.uno/documentation/requirements/caspian/roles/) — the role catalog and the role system overall.
- [`chain/`](https://puck.uno/documentation/requirements/caspian/chain/) — capability propagation across role boundaries (the chain side; this doc is the object side).
- The forthcoming jail spec (TBD) — full mechanics of `$obj.object.jail(...)`.
