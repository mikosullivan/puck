# `%scope` (post-V1.0, possibly never)

~~~vibecode
{"vibecode": {
	"doc": "ideas_percent_scope",
	"role": "deferred design note for the %scope system method — a reflective handle on the current lexical scope. Lets user code read and write variables by computed name, iterate over what's in scope, and otherwise treat the scope as a hash-shaped introspection surface. Moved out of V1.0 because the use cases are narrow (reflective programming, debugging tooling) and $foo is the only form 99% of developers actually need.",
	"status": "post-V1.0 — possibly never; design preserved as a reference for if/when reflective scope access becomes important",
	"v1_substitute": "$foo is the only V1 way to read/write a scope variable. The literal-identifier form covers every routine case.",
	"v1_engine_internals": "the engine still has a scope substrate internally (it has to, in order to resolve $foo lookups) — what's deferred is the user-facing %scope handle on top of it",
	"surface": "%scope[name], %scope.keys, %scope.each, %scope.has_key?, etc.",
	"audience": "future Caspian programmers needing reflective scope access",
	"key_concepts": ["reflective_lexical_scope_access",
		"read_write_variables_by_computed_name",
		"iterate_over_what_is_in_scope",
		"deferred_from_v1_zero_because_use_cases_are_narrow",
		"possibly_never_implemented"]
}}
~~~

**Post-V1.0, possibly never.** `%scope` would expose the current lexical scope as a reflective handle — letting user code read or write variables by computed name, iterate over what's bound, and otherwise treat the scope as a hash-shaped introspection surface.

`$foo` is the only V1 way to access a scope variable. The literal-identifier form covers every routine case (variable declaration, read, write, capture into closures). The reflective form is what `%scope` would add on top:

```caspian
# Reflective access with a computed name — what %scope would enable
$key = 'item_' + $i
%scope[$key] = $value           # set by computed name
$x = %scope[$key]               # read by computed name

# Introspection — what %scope would enable
%scope.keys                      # all bound names in current scope
%scope.each do($name, $value)   # iterate over the scope
    ...
end
```

## Why deferred

- **The use cases are narrow.** Reflective programming, debugging tooling, REPL-style introspection. Most Caspian code never needs it.
- **Exposes the substrate when it doesn't need to.** Documenting `%scope` invites people to write `%scope['x']` when `$x` is clearer.
- **The catalog gets bigger for marginal payoff.** Every entry in the system-methods catalog is something developers have to learn about; reflective scope access doesn't pay back the catalog weight.
- **Possibly never.** If reflective scope access turns out to be genuinely needed, this slot can be added later — adding a system method is a backward-compatible change. But it might never be needed; this doc captures the design space without committing to add it.

## What the engine still has internally

The engine still has a scope substrate internally — it has to, in order to resolve `$foo` lookups. Every block creates a new inherited scope; variable lookups walk it. What's deferred is the **user-facing `%scope` handle** on top of that substrate — the reflective surface, not the underlying mechanism.

## If/when this lands

The likely surface (working sketch):

| Operation | Form |
|---|---|
| Read by computed name | `%scope[$name]` |
| Write by computed name | `%scope[$name] = $value` |
| Check binding | `%scope.has_key?($name)` |
| List all bindings | `%scope.keys` |
| Iterate | `%scope.each do($name, $value) ... end` |
| Count | `%scope.size` / `%scope.any?` |

Whether `%scope` is itself a top-level system method or moved under another namespace (e.g., `%utils.scope` or `%process.scope`) is a separate design question.

## Cross-refs

- [Lucy / Caspian-runtime](../../requirements/lucy/index.md) — describes the scope substrate the engine maintains for `$foo` resolution.
- [Syntax / system-methods catalog](../../requirements/syntax/system-methods) — current V1 system-methods set; `%scope` is intentionally absent.
