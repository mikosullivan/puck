# run-as

~~~vibecode
{"vibecode": {
	"doc": "ideas_run_as",
	"role": "design exploration for a `run-as` mechanism — a way to run a block of code under a different role than the surrounding frame's. Related to (but not identical to) the earlier 'voluntary role reduction' idea. Companion to the settled security model at requirements/security/model/.",
	"status": "shape settled — block-form %role.run_as, descendant-only, no bare form, raise passes through, %call.role reflects the caller (unaffected by the narrowing)",
	"context": "started as a placeholder after the security model settled; captures ideas for scoped role transitions that don't fit into the five base rules but might be a useful primitive on top."
}}
~~~

## Concept

A frame can run a block of code under a different role than its own — but only under a **descendant** role in its tree. Never under an ancestor.

The asymmetry mirrors Rule 2's authority flow. Ancestors can manage descendants, so they can also voluntarily narrow to a descendant's authority for a scope. Descendants can't escalate to an ancestor's authority — that would violate the whole invariant Rule 2 rests on.

Basically Unix's `sudo -u lesser_user` when you're root: you can drop down, never up.

## Sketch

```caspian
# Running as R_factory (which has R_shipper as a child):
%role.run_as($db.obj.role) do
    &do_shipping_work   # runs with R_shipper's authority, not R_factory's
end
# back to R_factory when the block exits
```

Inside the block, the frame's `%role` is R_shipper. Ambient authority (`%net`, `%fs`, anything Rule 5 gated) narrows to whatever R_shipper actually has, not what R_factory has. The frame's original role restores at block exit.

## Details

- **Name:** `%role.run_as`.
- **Block form only.** No bare form — nothing about ancestor-authority narrowing should persist accidentally beyond a scope.
- **Nesting:** allowed. Inside a nested `%role.run_as` the target must be a descendant of the CURRENT role (the already-narrowed one), not the outer role.
- **Raise inside the block:** a raise is a raise. The frame unwinds; the role restores on the way out; no special handling.
- **`%call.role` from inside the block:** still the caller's role — whoever called into the current frame. `%call` reports the caller regardless of how the current frame narrowed itself.

