# Drinian examples

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_examples_index",
	"role": "index of worked Drinian snapshots illustrating the shape of the in-memory state hash at different moments; each example shows a Caspian source, the runtime moment captured, and the resulting Drinian JSON",
	"status": "draft — companion to drinian/index.md; example shapes track the main spec"
}}
~~~

Worked Drinian snapshots illustrating the shape of the in-memory state hash at different moments. Each example shows a Caspian source, the runtime moment captured, and the resulting Drinian JSON.

- [Bootstrap state](https://puck.uno/requirements/drinian/examples/bootstrap) — the minimum Drinian immediately after engine bootstrap.
- [Mid-execution](https://puck.uno/requirements/drinian/examples/mid-execution) — the V1-era worked example of a nested `.each` walk.
- [Recursion](https://puck.uno/requirements/drinian/examples/recursion) — recursive tree walk.
- [Exception](https://puck.uno/requirements/drinian/examples/exception) — Drinian mid-unwind.
- [Remote library](https://puck.uno/requirements/drinian/examples/remote-library) — loaded library and the trust barrier.
- [on_close](https://puck.uno/requirements/drinian/examples/on-close) — `on_close` hook semantics.
- [References](https://puck.uno/requirements/drinian/examples/references) — capture-by-reference cost model.
- [Role delegation](https://puck.uno/requirements/drinian/examples/role-delegation) — user delegating to agent mid-execution; frame-scoped `delegations` field.
