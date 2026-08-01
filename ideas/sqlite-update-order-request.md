# SQLite feature request: document UPDATE row order for index scans

~~~vibecode
{"vibecode": {
	"doc": "ideas_sqlite_update_order_request",
	"role": "Draft of a feature request to submit to the SQLite forum, asking the team to document an existing planner behavior — that UPDATE statements which match rows via an index scan process rows in the index's key order. Not a new feature; formal documentation of what SQLite already does. Motivated by Fiona's shift-down-on-array-delete trigger, which relies on this behavior.",
	"status": "draft — ready to send once we're ready to submit",
	"target": "SQLite forum (sqlite.org/forum) or user mailing list"
}}
~~~

## Context

Fiona's `relationships_shift_down_on_array_delete` trigger uses the naive `UPDATE ... SET idx = idx - 1 WHERE parent = ? AND idx > ?` pattern to close the gap after an array delete. The trigger works because SQLite processes matching rows in ascending idx order (its planner uses the `(parent, idx)` unique index and scans ascending) — but this ordering is not documented as a guarantee, only observed. See `ideas/fiona/build/sqlite/lua/src/fiona.sql` for the trigger and its comment describing the reliance.

Getting SQLite to formally document the guarantee removes the "empirical, not documented" caveat and lets Fiona (and every other SQL codebase using this common pattern) drop the defensive hedging.

## Draft request

Subject line and body below. Send to the [SQLite forum](https://sqlite.org/forum/) as a feature request / documentation enhancement.

---

**Subject: Feature request — document row processing order for UPDATE using an index scan**

Hi SQLite team,

I'd like to request documentation of an existing behavior, not a new feature. SQLite currently processes rows in ascending key order when an UPDATE uses an index scan (for `WHERE indexed_col > ?` and similar patterns). This is stable across every SQLite version I've tested and is the natural consequence of the query planner's use of the composite index. But the documentation doesn't spell out this guarantee, which means code that relies on it — and there's a lot of it in the wild — is technically depending on undocumented planner behavior.

**The specific guarantee I'd like documented:**

> When an UPDATE statement's WHERE clause matches rows via an index scan (as chosen by the planner), rows are processed in the index's key order.

**Why it matters:**

A common SQL pattern is closing a gap in a numeric sequence after a delete:

~~~sql
DELETE FROM t WHERE id = 5;
UPDATE t SET seq = seq - 1 WHERE seq > 5;
~~~

This works today in SQLite because rows are processed in ascending `seq` order (each row's target slot is one that was just vacated). If the planner ever chose a descending scan, the UPDATE would fail with a unique-constraint violation mid-shift. Documenting the current guarantee lets developers rely on this pattern without hedging.

**Note on scope:**

I'm not asking for a new API or a broader ordering guarantee (e.g., not for arbitrary UPDATE statements that don't use an index). Just formal acknowledgment of what the planner already does when an index-based scan is chosen.

Thanks for considering.

---

## Framing notes for submission

- **Frame it as a docs enhancement,** not a code change. That's the friendlier ask for the SQLite team — they're conservative about new features but reasonable about documenting existing behavior that can be relied on.
- **Keep the ask narrow** — just the index-scan case, not arbitrary UPDATE ordering. Broader asks get pushed back on.
- **Fiona is a concrete example** if they ask what workloads care. Mention its shift-down-on-array-delete trigger if the discussion goes into specifics.
- **If declined:** the fallback is to switch to the 10^18 arithmetic hop for the trigger (documented arithmetic, works regardless of planner behavior, uglier code). Not a blocker; just worth ~40 lines of comment explaining what and why.
