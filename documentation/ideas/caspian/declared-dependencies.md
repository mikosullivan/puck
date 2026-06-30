# Declared dependencies on downloaded objects

~~~vibecode
{"vibecode": {
	"doc": "declared_dependencies",
	"role": "future-idea note: a class could declare ahead of time which other downloaded objects it needs and whether those should share its role. Optional ergonomics on top of the existing %puck download model. Post-V1.",
	"status": "deferred — not part of V1; revisit when the pattern of methods doing ad-hoc %puck calls becomes friction worth removing"
}}
~~~

Under the V1 model, every dependency another downloaded object needs is fetched at method-call time, inline:

~~~caspian
class &widget
    method &render()
        $renderer = %puck['https://example.com/renderer']
        $renderer.render(self)
    end
end
~~~

Works fine, but two patterns become awkward at scale:

1. **Discoverability.** Reading the class doesn't tell you what objects it depends on — those are buried in method bodies. A maintainer or auditor has to walk the methods to find every `%puck[...]` call.
2. **Role sharing.** If `widget` is loaded `as_self: true` (so it runs in the caller's role), the inline `%puck['renderer']` call doesn't automatically inherit that. The author has to remember to write `%puck['renderer', as_self: true]` everywhere, and every downstream maintainer has to remember the same. Easy to forget; security-relevant when forgotten.

## The idea

A class declares its downloaded-object dependencies up front, optionally tagging which should share its role:

~~~caspian
class &widget
    requires 'https://example.com/renderer', as: $renderer
    requires 'https://example.com/audit-log', as: $audit, share_role: true

    method &render()
        $renderer.render(self)
        $audit.log(:render, self)
    end
end
~~~

What this would give:

- **Declared dependencies show up at the top of the class** — visible to readers without walking method bodies.
- **Per-dependency role-sharing decision** — `share_role: true` means this dependency loads with the class's own role rather than getting its own. The decision is made at declaration time, not scattered through method bodies.
- **Lifecycle clarity** — the engine knows what the class needs; it could pre-fetch, eager-cache, or warn about unavailable dependencies before any method runs.

## What's NOT in scope here

This idea is about ergonomics and explicit declaration, not new security primitives. The mechanism it would build on (`%puck` downloads, role assignment, `as_self`) already exists. The `requires` form is sugar over what you can already do today by hand.

## Why deferred

- The V1 model (inline `%puck[...]`) works fine for small classes. The friction this idea relieves only shows up at scale.
- Declaring dependencies adds syntax that has to be specified, parsed, and enforced — non-trivial design surface.
- Class-level static dependency declarations interact with the eventual versioning story (`requirements/caspian/downloads/`); better to settle versioning first, then layer this on top.

Revisit when the inline `%puck[...]` pattern has been used for real long enough that the friction is clear and the desired ergonomics are obvious.
