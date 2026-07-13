# Downloaded methods
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_classes_downloaded_methods",
	"role": "spec for ad-hoc method application via `$foo.$method` — treating a first-class function value as a method on the receiver, with %self bound and full bucket access. Covers the syntax, semantics (roles, ownership, bucket access), the receiver-ownership rule that gates who can apply methods to what, and how the mechanism generalizes across downloaded functions, locally-defined functions, and class methods borrowed as values. NOT the same as Puck 'remote methods' (that term names the Puck protocol's server-side dispatch); downloaded methods here run LOCALLY.",
	"status": "draft — syntax, semantics, role semantics, bucket-access rules, and the receiver-ownership rule settled; smaller mechanics (shape check, reflection, precedence with class methods) still open",
	"audience": "developers writing or invoking downloaded methods; engine implementers building the ad-hoc-dispatch path; security-model reviewers verifying the ownership rule"
}}
~~~

Because objects in the Puck ecoverse can be **downloaded from anywhere**, methods don't have to live in the class definition to be called on an instance. A function — whether defined locally or pulled fresh through `%puck` — can be applied to any object with method-call syntax, and at the point of application it IS a method that runs locally in the caller's engine.

> **Not "remote methods".** In Puck, "remote methods" specifically names methods that execute on a Puck server as part of the Puck-protocol dispatch. What this page describes is different: the function body is downloaded (via `%puck`) and then executed **locally** in the caller's Caspian engine. No cross-machine call happens at the point of application.

## The syntax

The usual method call, where the method is looked up in the object's class:

~~~caspian
$foo.bar
~~~

Two extensions that use a function value in the method-name slot instead of a name:

~~~caspian
# Apply a Puck-downloaded function as a method on $foo.
$foo.%['https://gup.com/bar']

# Store the function first, then apply it.
$method = %['https://gup.com/bar']
$foo.$method
~~~

Both forms treat the function as a method on `$foo`. `%self` inside the method's body is `$foo`. Nothing about `$foo`'s class is modified — the association is only for this call site.

## Semantics

When invoked as `$foo.$method` or `$foo.%['url']`, the applied function runs as a method:

- **It IS a method.** Everything a class-defined method can do, this one can do too — including direct bucket access via `@field`.
- **`%self`** is `$foo`.
- **`%bucket` is fully accessible.** The method can read and write `@name`, `@count`, and any other bucket entry the same way a class-defined method can. No indirection through public methods.
- **The method runs as its OWN owning role — specifically, the role of the faucet it came from.** A method downloaded via `%['url']` runs as the `%chain.puck` faucet role. A locally-defined function that's applied as a method runs as the role that authored it.
- **Objects created by the method are owned by that role.** If the method does `return {new_object}`, that hash is owned by the faucet role (per the creator-owns rule).
- **`%call`** is the current call object, owned by the caller's role. Same as any method call.
- **`%chain`** is the caller's chain (subject to the chain-grant model at role boundaries — same rules as any cross-role method call).

There's one guardrail on the mechanism, described in full in [the receiver-ownership rule](#the-receiver-ownership-rule) below: **ad-hoc method application requires the caller to have inspection authority over `$foo`** — i.e., the caller owns `$foo`, or the caller is user. This blocks untrusted code from injecting arbitrary bodies into objects it doesn't own; every other consequence of "the applied function IS a method" still holds.

The load-bearing consequence within that guardrail: **applying a function as a method on `$foo` gives that method full-instance access.** This is intentional; the thing is being treated as a method, not sandboxed inside a public-method interface. The security work happens at the handoff — deciding to apply the function IS deciding to grant it that access.

### Methods aren't closures

**A method is not a closure.** A closure carries captured outer scope; a method carries `%self` and bucket access. Those are different mechanisms.

When a function is applied as a method via `$foo.$method`, it's treated as a method — the captured-scope behavior of a closure doesn't come along even if the function was defined in a closure-shaped context. What it has at runtime is `%self`, `%bucket`, `%call`, `%chain` — the standard method surface.

If you specifically want closure-style captured scope, closures still exist and work as before (see [functions](https://puck.uno/documentation/requirements/caspian/functions/) for the callable surface). They're just a different construct from what this mechanism produces.

### Primitives too

[Primitives](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/) have buckets just like any other object in Caspian. Null flavors, for example, live in the null's bucket. So all primitives accept ad-hoc method application the same way objects do:

~~~caspian
function &double()
	return %self * 2
end

$n = 5
$n.$double          # 10 — %self is 5; the method returns 5 * 2

function &reverse()
	return %self.reverse
end

$s = 'hello'
$s.$reverse         # 'olleh'
~~~

This enables genuinely useful patterns — extension methods on primitives, downloaded helpers that operate on strings or numbers, etc. The primitive's own value doesn't live in the bucket; it sits in an engine-managed slot alongside the bucket, which is what lets `@field` reads and writes work on a primitive without infinite regress. See [primitive-buckets](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/primitive-buckets) for the full model.

## The natural generalization: any function, not just downloaded

Nothing in the mechanism requires the function to have been downloaded. A locally-defined function works the same way — when applied via `$foo.$method`, it becomes a method:

~~~caspian
function &greet($greeting)
	puts $greeting + ', ' + %self.name
end

$widget.$greet('hi')      # applies &greet to $widget with %self = $widget
~~~

So the feature isn't specifically "downloaded methods" — it's **method-shaped application of any function**. The downloaded case is what motivates it, but the mechanism generalizes.

## Class methods are values too

Methods are functions, functions are objects. So a class method is just another function value — and there's no reason you couldn't take `Widget.render` and apply it to a `Gadget` instance the same way you'd apply any other function:

~~~caspian
$method = &Widget.render        # reference the class method as a value
$gadget.$method                 # apply it to $gadget as %self
~~~

Inside the applied body, `%self` is `$gadget`, `@field` accesses `$gadget`'s bucket, and any `.other_method` call resolves against `$gadget`'s class — not `Widget`'s. The method body travels; the "self" surface is whatever object it lands on.

Nothing about this needs a separate rule. The "class methods are values" section exists only to point out that the general mechanism already covers this case. **Class definitions are not method jails**: if you can name a class method, you can hold it as a value, and if you can hold it as a value, you can apply it via `$foo.$method` — the same way you would with any downloaded or locally-defined function.

If the borrowed method body happens to call `.name` or read `@count`, the receiver just needs to have those. No formal interface declaration, no inheritance chain, no mixin — the receiver either has the surface the method reaches for, or it doesn't.

## Compared to alternatives

Three ways to invoke a function given an object:

~~~caspian
# 1. Function call — $foo passed as an argument.
&$func($foo)                          # $foo is $func's first parameter
~~~

~~~caspian
# 2. Class-lookup method call — the method must exist on $foo's class.
$foo.bar
~~~

~~~caspian
# 3. Method-shaped application — $foo is %self; the function runs as a method.
$foo.$method
~~~

The three differ in **where `$foo` appears inside the body**:

- Case 1: `$foo` is a parameter. The function might use it (or ignore it).
- Case 2: `$foo` is `%self`. The class-defined method assumes it.
- Case 3: `$foo` is `%self`. The function was defined without knowing about `$foo` but is now being applied AS a method.

Case 3 fills a real gap: reusing method-shaped code across classes without inheritance or mixins.

## Use cases

- **Extension methods.** Ship a function that "acts on" any object with a certain shape. Callers apply it to their instances without modifying the class.
- **Cross-object mixins.** A single function can be applied to many different classes' instances, each becoming `%self` in turn. No inheritance chain required.
- **Cross-class method borrowing.** A method defined on one class can be applied to an instance of another class. Since methods are functions and functions are objects, there's no barrier to using `Widget`'s `.render` body on a `Gadget` instance — you just reference it as a value and apply it.
- **Rapid prototyping and plugins.** A downloaded object can be applied to local instances during exploration or debugging, without a rebuild.
- **AI-generated method surfaces.** An AI writing Caspian code can produce a function, hand it back to the user, and the user can apply it to their objects as methods without modifying class definitions.
- **Method-as-config.** A configuration value that IS a function can be plugged into an object's behavior at runtime.

## Open questions

- **Shape check.** If `%['url']` returns something that isn't a function (a string, a number, a hash), what happens? Standard method-dispatch error is probably the right answer — same as calling `.foo` on an object with no `foo` method.
- **Reflection.** Does `$foo.methods` (or equivalent) include functions that MIGHT be applied via this mechanism? Probably no — the function is a first-class value, not a class member. The set of things you might apply is unbounded.
- **Introspection inside the method.** Can the body figure out that it's being called via this mechanism vs. defined as a real class method? Probably no, and that's a feature — the code doesn't need to care.
- **Precedence with class methods.** If the class defines a `bar` method AND you write `$foo.$bar_func`, which wins? The name is different (`bar` vs. `$bar_func`); no conflict. But what about `$foo.$method` where `$method` happens to be a function stored in a variable named the same as a class method? Probably no conflict — the parser distinguishes bare identifiers from `$`-prefixed variables.
- **Relationship to any future conversion protocol.** If a `.to.X` / `.from.X` conversion mechanism ever lands, both would give class-external code a way to touch an instance. Conversion would add well-typed constructors; downloaded methods add arbitrary method-shaped operations. Complementary, not overlapping.

## The receiver-ownership rule

Applying a function as a method gives that method **full-instance access** — bucket reads and writes, method calls, everything a class-defined method can do. Because ad-hoc method application bypasses whatever public-interface the class author designed, there's one restriction on WHO can perform it:

> **Ad-hoc method application requires the current role to have inspection authority over the receiver.** Ownership grants it; being `user` grants it. That's the list.

Concretely:

- **User can apply any function to any object.** User has ambient inspection authority over every value in the runtime (`%engine`-level access, holding-is-access, no barriers). This includes applying a user-authored method to a faucet-owned object for debugging or inspection.
- **A non-user role can only apply methods to objects IT owns.** Faucet code can call `$its_own_object.$its_own_method` freely. It cannot call `$user_object.$its_own_method` — the receiver isn't owned by the current role.
- **Class-defined methods are unaffected.** Class-defined method dispatch (`$foo.some_class_method`) still follows [holding-is-access](https://puck.uno/documentation/requirements/caspian/roles/object-access#the-v1-rule-holding-is-access) — anyone holding `$foo` can call methods defined on its class. The ownership check applies specifically to the `$foo.$method_value` form, where the caller is injecting an arbitrary body rather than invoking one the class author vetted.

### The attack this blocks

Without the ownership check, a faucet-role helper handed a user-owned object could do:

~~~caspian
# untrusted code, running as some faucet role
function &peek()
	puts @internal_secret
end

$user_object.$peek        # would leak @internal_secret to faucet code
~~~

The applied method would run as the faucet role but with full bucket access to a user-owned object — reading any field the class considers "private." With the ownership check, the second line errors: **the faucet role doesn't own `$user_object`, and only user has ambient inspection authority.**

Class-defined method dispatch doesn't have this hole — a class-defined method body is vetted by the class author, so calling `$user_object.some_class_method` from faucet code is fine; the class author chose what that method exposes.

### The asymmetry with normal dispatch

There's a small but load-bearing asymmetry to notice:

- `$faucet_object.some_class_method()` — **allowed from any role that holds `$faucet_object`.** Standard holding-is-access. The class method is pre-vetted by the class author.
- `$faucet_object.$my_method` — **only allowed if the current role owns `$faucet_object`, OR is user.** The method body is ad-hoc, not vetted by anyone.

This is intentional. The two mechanisms are different: dispatch through a class is a controlled surface; ad-hoc application is arbitrary code injection. They deserve different gates.

### What still works

The check is narrow enough that all the intended use cases are still available:

- **Extension methods on your own objects.** User applies a downloaded helper to a user-owned instance — user owns the receiver.
- **Cross-class method borrowing.** User does `$my_gadget.$Widget_render` — user owns `$my_gadget`, even though `Widget.render` was authored by a faucet.
- **Debugging downloaded objects.** User applies `$my_peek` to a faucet-owned instance — user rule.
- **Class-defined methods internally using `%self.$other`.** A method running as the receiver's owning role trivially owns the receiver.
- **AI-generated method surfaces plugged into user objects.** User owns the receiver.

### What's blocked (and should be)

- **A downloaded library trying to `$user_arg.$library_helper` on a user-owned argument** — blocked. The library has to work through the public class surface of `$user_arg`, or through downloaded methods on the argument's *class* (which the class author permitted). It cannot inject a fresh body.
- **Cross-faucet interference** — one faucet can't `$other_faucet_object.$my_method` an object owned by a different faucet.

### Why no per-class opt-in

A "this class accepts ad-hoc method application from any role" flag would be an easy foot-gun. Any class that legitimately wants to expose "run this callable inside me" behavior can just expose an explicit method (`.apply($callable)`) that takes the function as a normal argument — same power, but the receiver's class author chose to accept it. No new mechanism needed.

### No nanny code, still

This rule is a **security guarantee**, not paternalism ([no nanny code](https://puck.uno/documentation/requirements/caspian/concepts#no-nanny-code)). It's not "we think you shouldn't peek at other roles' internals" — it's "the trust model the rest of the system depends on requires that untrusted code cannot inject arbitrary bodies into objects it doesn't own." User can always override by being user; other roles can always request specific capabilities via explicit method arguments.

## Testing

- **`$foo.$fn` binds `%self` to `$foo`** — `function &me() return %self end; $foo.$me` returns `$foo`.
- **`$foo.$fn` reads `@field`** — `function &n() return @name end; $foo.$n` returns `$foo`'s bucket entry `name`.
- **`$foo.$fn` writes `@field`** — `function &set() @name = 'x' end; $foo.$set; $foo.@name` is `'x'`.
- **`$foo.$fn` accesses `%bucket`** — `function &b() return %bucket end; $foo.$b` returns the receiver's bucket hash.
- **`$foo.$fn` with args** — `function &greet($g) return $g + ', ' + @name end; $foo.$greet('hi')` returns `'hi, ' + name`.
- **`$foo.%['url']` downloads then applies** — same behavior as storing the download first and applying.
- **Locally-defined function applied as method** — a function declared inline (not downloaded) can be applied via `$obj.$fn`.
- **Class method as value applied to another class's instance** — `$m = &Widget.render; $gadget.$m` runs `.render` with `%self = $gadget`.
- **Applied method runs as function's owning role** — a faucet-downloaded function applied as a method runs in the faucet's role.
- **`%call.role` is the caller's role** — inside an applied method, `%call.role` reflects the caller, not the function's role.
- **Objects created inside applied method owned by function's role** — `return {new: 1}` from a faucet-downloaded method produces a faucet-owned hash.
- **Primitive receivers work** — `$n = 5; function &d() return %self * 2 end; $n.$d` returns `10`.
- **String primitive receiver** — `$s = 'hi'; function &r() return %self.reverse end; $s.$r` returns `'ih'`.
- **No closure semantics** — a bare function defined inside a closure but applied as a method has no captured scope; the `%self` surface replaces it.
- **User can apply any function to any object** — user-role code calling `$obj.$fn` on a faucet-owned receiver succeeds.
- **Non-user role owning receiver can apply** — a faucet-role frame calling `$owned.$fn` on an object it owns succeeds.
- **Non-user role NOT owning receiver raises** — a faucet-role frame calling `$user_obj.$fn` on a user-owned receiver raises.
- **Non-user cross-faucet raises** — faucet A calling `$fnB_owned.$fnA` on faucet B's object raises.
- **Class-defined dispatch unaffected** — `$foo.class_method()` still runs regardless of ownership.
- **Non-function value in method slot raises** — `$foo.$string` (where `$string` isn't a function) raises with standard dispatch error.
- **Applied method has full `%bucket` read/write** — no jail, no public-interface restriction.
- **Method borrowed from parent class body** — `$m = &Parent.helper` used as `$child.$m` runs with `%self = $child` and reads `@` on the child's bucket.
- **Applied method dispatches sibling calls against receiver's class** — `%self.other()` inside the applied body resolves against the receiver's class, not the borrowed method's original class.

## Related

- [nested methods](https://puck.uno/documentation/requirements/caspian/classes/nested) — the class-side mechanism for organizing method namespaces. Downloaded methods add INSTANCE-side ad-hoc extension.
- [object-access § holding is access](https://puck.uno/documentation/requirements/caspian/roles/object-access#the-v1-rule-holding-is-access) — the baseline rule for class-defined method dispatch; the receiver-ownership rule on this page is a tightening specifically for ad-hoc method application.
- [concepts § no nanny code](https://puck.uno/documentation/requirements/caspian/concepts#no-nanny-code) — the receiver-ownership rule is a security guarantee, not paternalism; the two are distinguished under the no-nanny-code framing.
