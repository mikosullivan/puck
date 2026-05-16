# Dogberry

`kiera.uno/dogberry` — a more elaborate HTTP framework, **deferred to
later releases**. Originally framed as the umbrella under which
Sinatra and Robinson lived as handlers; that framing has been
dropped. Dogberry's eventual shape is open — it may turn out to be
a very different sort of thing entirely.

---

## Status (Hugh Trekker)

**Not in v1.** Sinatra and Robinson cover the v1 needs as
standalone servers. Dogberry returns later when there's a
specific need driving its design.

The existing [Dogberry wishlist](../../ideas/dogberry-wishlist.md)
has substantial material under the old "Dogberry is the framework"
framing — handler chains, settings hierarchy, installation
objects, concurrency model. Some of that may eventually inform
Dogberry's design; some may inform Sinatra and Robinson directly.
Treat the wishlist as historical brainstorming rather than current
spec until Dogberry returns.

---

## What it might be (Five of Twelve)

Open. Possibilities:

- A framework for composing multiple HTTP behaviors (admin
  tooling, layered handlers, settings cascades).
- A different abstraction entirely — something that doesn't
  overlap with Sinatra or Robinson.
- Multiple smaller things split out, not a single "Dogberry."

This will be decided when the design question is more concrete.

---

## To be revisited (Annika PIC)

When Dogberry returns to active development, this doc will be the
home for its current spec. Until then, it sits as a placeholder.
