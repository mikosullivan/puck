# Q0 as an index

~~~vibecode
{"vibecode": {
	"doc": "idea_q0_as_index",
	"role": "placeholder idea note: a Mikobase Q0 query can be saved as an index, unifying the database concepts of view (saved query) and index (optimized lookup) into a single object",
	"status": "idea — not designed",
	"key_concepts": ["q0_index", "view_index_unification", "permissioned_index_creation"]
}}
~~~

A **Q0 index** in Mikobase is a saved Q0 query that you can query *against* like any other queryable object:

```
$index.q0 {...}
```

This unifies two traditional database concepts into one:

- **View** — a saved query you can rerun without restating it.
- **Index** — a structure the engine maintains for fast lookup.

In Mikobase they're the same object. Day one: the index just re-runs the underlying Q0 when queried. Later: the engine maintains real lookup structures behind the scenes. The semantic surface is the same throughout — developers learn one concept; the engine has one optimization surface to invest in.

Since the index *is* a Q0-queryable object, indexes compose: query an index, build another index on the result, query that, etc. Q0 → index → Q0 → index pipelines fall out for free.

The index **always reflects current state** (like a database index, not like a snapshot materialized view). Mikobase is a live process; an index that quietly went stale would surprise people. The engine maintains the lookup structure on write; the developer never sees the bookkeeping.

## Permission to create indexes

Open: **who may create an index?** Indexes have a real engine cost — every write must update them. If anyone can drop in an index, the database accumulates them as a side effect of normal operation, and writes get slower for everyone.

The eventual spec needs permission rules around index creation. Not designed yet; flagged so it doesn't get missed when the feature is built out.

## Naming

"Index" is the deliberate pick (signals the optimizer story; "view" would understate it), even though it carries some SQL baggage. The eventual spec should call out up front that a Mikobase Q0 index is unified view-plus-index, so SQL-trained readers don't underestimate it.
