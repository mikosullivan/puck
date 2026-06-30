# Grantable permissions beyond capability methods

~~~vibecode
{"vibecode": {
	"doc": "grantable_permissions_beyond_capabilities",
	"role": "future-idea note: the user role is like Linux root — it has authority that goes beyond just calling %engine methods. The chain.role.grant mechanism currently hands out capability-method access, but there are likely OTHER kinds of authority that may want to flow the same way. Catalog those over time; commit to specific ones as use cases land.",
	"status": "open brainstorm — V1 only supports granting capability methods. Other permission kinds are deferred until concrete use cases force the design"
}}
~~~

`%chain.role.grant(target, :a, :b, :*) do ... end` currently hands **capability methods** to another role — `%net`, `%tmp`, `%encryption`, etc. The user role is the root of all these, in the same way Linux's `root` is the user with `%engine` access (the gateway to host resources).

But "what root can do" isn't only "call methods user code can call." In Linux, `root` has authority over PROCESSES, FILES, KERNEL MODULES, NETWORK INTERFACES — many distinct kinds of permission, each its own surface. Most of those map to distinct capabilities, but some don't — `root` can *kill any process* and *read any file* not because it has special methods for those, but because the kernel treats `root` as exempt from the normal access checks.

By analogy, `user` in Caspian probably has authority beyond "call methods other roles can't call." Some examples that have come up in conversation or are obviously latent:

## Examples of permissions that aren't just "this method"

### Inspect other roles' objects

A debugger or audit tool needs to read state owned by other roles — see the captured variables of a closure owned by `library:foo`, walk a stdlib data structure, read the internal state of an agent's working set. The mechanism isn't a method call; it's an exemption from the normal "other role's internals are private" rule.

A potential grant: `%chain.role.grant($debugger.role, :inspect) do ... end` — give the debugger role the authority to look inside objects it doesn't own.

### Mutate other roles' state

The dual of inspect: write into another role's data. Migrations, data fixups, schema-evolution patches. Less common, more dangerous.

### Override role transitions

Tooling like a profiler or coverage instrument wants to insert itself between every call. That requires authority to intercept role transitions — not a method, a meta-level permission.

### Switch into another role

The OPEN about "can other roles switch INTO `user`" (filed as [#830](https://github.com/mikosullivan/puck/issues/830)) is exactly this category. The current strong-default is no; but if it were ever allowed, it would be granted, not assumed.

### Suppress audit / leave no trace

Some operations want to be silent — capability use that doesn't show up in `%engine.manifest`. Almost certainly NOT something we want to grant in practice (audit is foundational), but worth noting that "be invisible" is logically a separate permission from "do the thing."

### Skip resource limits

Operations that should be allowed to exceed CPU / memory / wall-clock budgets in specific scoped cases. "Run this without timeout enforcement" is a permission, not a method.

## What this idea recommends

- **Catalog these over time.** Each time a real use case lands that wants something other than "give them this method," note it here.
- **Keep V1 narrow.** `%chain.role.grant` in V1 only hands out capability methods (the things on `%chain.methods/`). The mechanism is good; adding more permission categories is additive when the time comes.
- **Pick a naming convention before adding the second category.** Today `:net`, `:tmp` are method names. If we add `:inspect`, that's a different category that happens to share the syntax. Worth being clear at the point of addition whether the symbol space is partitioned by category or all symbols live in one flat namespace.
- **Be explicit about what `:*` covers.** Currently the wildcard means "every method the granter has." When we add other categories, decide whether `:*` still means just methods, or expands to "every permission of every kind."

## Why this is in `ideas/`

V1's permission model needs to be limited and concrete enough to ship. Speculating about every kind of authority `user` might want to delegate creates design surface that doesn't have to be specified yet. This doc exists to make sure those permissions don't sneak in unnoticed — we catalog them as the use cases land, and only commit when one is real.
