# Agents

~~~vibecode
{"vibecode": {
	"doc": "ideas_helpers_agents",
	"role": "design doc for the agent variant of the class-body helper DSL: `agent &name() ... end` inside a class body creates a sub-object with BOTH a public-surface handle (`@target`) and a private-surface handle (`@internals`). Same DSL shape as `helper &name()`; single keyword differs. Agents are how Caspian implements what has been called nested methods — `$foo.bar` becomes a real sub-object rather than a name prefix.",
	"status": "active_design — core shape settled (DSL, @target + @internals, isolation model); details around @internals's exact surface and reference-leak conventions still to spec",
	"context": "companion to ideas/helpers/basic — the isolation-preserving variant. Agents relax that isolation on an explicit, per-declaration basis."
}}
~~~

**Not V1 spec change.** Placeholder for design work; nothing lands in `requirements/` until the shape is settled.

## What an agent is

An **agent** is a type of helper — an object that does work on behalf of, or alongside, another object. Unlike a regular helper (which can only call the other object's public methods), an agent can access the other object's **internals**: private methods, non-public state, whatever the class would ordinarily hide from outside callers.

An agent is trusted collaboration expressed as an object: "this other object is allowed inside my private surface."

## The DSL

Same shape as [helpers](basic), one keyword differs. Inside a class body:

~~~caspian
class
	agent &foo()
		method &bar()
		end
	end
end
~~~

`agent &foo()` opens a block whose methods are defined on an anonymous class; instances of the outer class expose `.foo`, which returns a fresh agent instance constructed with the outer object as its target.

## The two auto-fields

Every agent gets two fields on its bucket, both populated by the framework at construction time:

- **`@target`** — the outer object, reachable only through its public API. Same as a helper's `@target`.
- **`@internals`** — the outer object's private surface. Bucket entries, private methods, anything the class would ordinarily hide from outside callers.

`@target` is what makes an agent still a normal object collaborator. `@internals` is what makes it an agent rather than a helper.

## Isolation model

The agent is still its own object with its own bucket and its own method dispatch. What changes is that ONE of its bucket fields (`@internals`) is a live handle into the outer object's private surface.

Because bucket fields are private by default, `@internals` is not visible from outside the agent. Only the agent's own methods can dereference it. The outer class explicitly consents to this exposure by writing `agent &foo()` instead of `helper &foo()` at the declaration site.

Two properties fall out:

1. **Explicit opt-in per sub-object.** The parent class body chooses, one declaration at a time, which sub-objects get keys to the private surface. No accidental exposure via passing an object around.
2. **Privacy is by ordinary rules.** Nothing new about how privacy works. `@internals` is a private bucket field like any other; it just happens to point at another object's private surface.

## Reference-leak hazard

`@internals` is a live handle to another object's guts. If an agent leaks a reference to `@internals` — returns it from a method, stashes it in an arg to a call it makes, hands it to a callback — whoever receives the reference gets the same power over the outer object's internals.

This is a standard capability-passing hazard, not a design flaw specific to agents. But the spec should call it out prominently: don't return `@internals`, don't hand it to third parties. If an agent needs to expose SOMETHING derived from internals, it should do so through its own methods, controlling what the caller can see.

## Relationship to nested methods

Agents are how Caspian implements what has been called **nested methods** — the pattern where `$foo.bar.gup()` groups methods under a namespace path on the class. See [ideas/nested-methods](../nested-methods) for the earlier framing (retired).

The earlier idea kept `$foo.bar` as a pure name prefix — no sub-object was created, `self` inside `gup` stayed as `$foo`, and `gup` had unrestricted access to `$foo`'s internals. That preserved encapsulation but hid the object-shaped nature of the grouping.

Under agents, `$foo.bar` is a real sub-object with its own methods and state. Encapsulation is preserved not by making the sub-object invisible, but by making the sub-object trusted: the agent has access to `$foo`'s internals despite being a separate object. Same practical outcome; more honest about what's happening under the hood.

## Open design points

- **`@internals`'s exact surface.** Is it a special object with `%bucket`-like reflective access, or a reference to the outer object that bypasses the usual privacy filter at call time? Both give the agent access to private methods; they differ in how the access looks in code (e.g. `@internals.secret_field` vs `@internals.private_method()`).
- **Constructor signature.** `helper` uses `method &init(@target)` to auto-assign. Does the agent's `&init` take both (`method &init(@target, @internals)`), or does the framework populate `@internals` implicitly without the author naming it? Implicit is less noise; explicit is more visible.
- **Reference-leak lint or runtime check.** Whether the engine has any teeth to catch an agent method that returns `@internals`, or if this is purely a discipline / code-review concern.
- **Agent-of-agent.** A class-body agent declares access to its parent's internals. If the agent's own class body declares its own agents, do THOSE agents get access to the outermost object's internals (transitively), or only to the agent's own? The narrow answer (only its own) is safer and matches the "consent per declaration site" property.
