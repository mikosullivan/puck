~~~vibecode
{"doc": "sprint-index", "sprint": "persistent-comment-cleanup",
	"role": "Decision record: IMPLEMENTED. The `persistent` column comment in `src/engine/cvm/schema.sql` referenced `objects_no_update_root_role`, which was removed in an earlier cleanup. Comment reworded to describe the cross-column CHECK's actual guarantee (fires on both INSERT and UPDATE). Source: ChatGPT second-pass § 7.",
	"status": "implemented"}
~~~

# persistent-comment-cleanup

Second-pass § 7. Closed.

## What landed

Comment on the `persistent` column in [src/engine/cvm/schema.sql](https://puck.uno/src/engine/cvm/schema.sql) reworded to reflect current enforcement:

> The cross-column CHECK keeps core roles pinned on both write paths — INSERT with `persistent = null` fails, and UPDATE that clears `persistent` on a core-role row also fails (CHECKs fire on INSERT and UPDATE).

Replaces the stale line that said `objects_no_update_root_role`'s persistent guard was doing the enforcement. That trigger was dropped when it became redundant; the CHECK alone is sufficient because CHECK constraints fire on both write paths.

No behavior change. No test change. Comment-only.

Sprint kept as a record.
