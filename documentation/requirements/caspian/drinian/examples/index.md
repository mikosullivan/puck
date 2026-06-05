# Drinian examples

Worked Drinian snapshots illustrating the shape of the in-memory state hash at different moments. Each example shows a Caspian source, the runtime moment captured, and the resulting Drinian JSON.

- [Bootstrap state](bootstrap.md) — the minimum Drinian immediately after engine bootstrap.
- [Mid-execution](mid-execution.md) — the Aslan-era worked example of a nested `.each` walk.
- [Recursion](recursion.md) — recursive tree walk.
- [Exception](exception.md) — Drinian mid-unwind.
- [Remote library](remote-library.md) — loaded library and the trust barrier.
- [on_close](on-close.md) — `on_close` hook semantics.
- [References](references.md) — capture-by-reference cost model.
- [Role delegation](role-delegation.md) — user delegating to agent mid-execution; frame-scoped `delegations` field.
