# Fiona

~~~vibecode
{"vibecode": {
	"doc": "fiona",
	"role": "historical notes on Fiona, a DBMS Miko once designed around strict object immutability and relationship-as-record modeling; not in use in mikobase but its ideas may inform future design",
	"key_concepts": ["fiona_dbms", "object_immutability", "relationships_as_records",
		"value_semantics_for_objects", "historical_design_influence"],
	"status": "historical"
}}
~~~

**Status:** notes on a data structure Miko once invented. **Not in use
in mikobase.** Recorded here because some of its ideas may still
inform future design decisions.

---

## Overview

Fiona is a DBMS Miko once designed. Its defining property is
**row-level immutability**: individual rows are never UPDATEd in
place. Changes to the database happen through inserting new rows and
deleting old ones. The database as a whole is not immutable — its
state changes constantly, just never through UPDATE.

Consequences of this rule:

- **Row identity is stable.** A reference captured to a row can trust
  that whatever it read is still what's there — until the row is
  deleted. No row ever silently changes value under the reader.
- **No version concept built into rows.** "Versions" aren't a thing
  at the row level. If a developer needs to model succession (old
  → new), they express it explicitly — via separate rows with
  references between them, or version chains, or whatever the
  application needs. The DBMS doesn't impose a notion of supersession.
- **Value semantics per row.** Each row behaves like an int or string
  in most languages: stable, comparable, never mutated. The
  "identity = value" rule that holds for primitives in many languages
  holds here for individual rows.

**Wiggle room in `hsa`.** The no-UPDATE rule is firm for
`relationships`, and firm for compound rows (hashes, arrays) in `hsa`.
For scalar rows in `hsa`, there's a possible exception: updating a
scalar in place (changing a stored number, string, or boolean) might
be reasonable without breaking the design. Not decided — flagged as a
place the original strict rule could relax.

---

## Structure

What other systems call "properties" of an object are defined in Fiona
as **relationships**. Properties aren't fields stored on the object;
they're separate relationship records connecting objects to values.
This makes relationships first-class and properties second-class — a
notable inversion of conventional database modeling.

Logically the system has **two tables**. (Under the hood there were
about twenty, consolidated through views into the two-table
presentation. For clarity we treat the system as having just the two.)

### Table 1: `hsa` (hashes-scalars-arrays)

Holds primitive JSON values — scalars (numbers, strings, booleans,
null), hashes, and arrays. Each row IDs one primitive.

- Rows can be **added** or **deleted**. Compound rows (hashes, arrays)
  are never UPDATEd — to "change" one you delete it and add a new
  row, or (more commonly) leave the row alone and change what the
  outer hash's `relationships` rows point at.
- Scalar rows might be modifiable in place; see the wiggle-room note
  in the overview.

### Table 2: `relationships`

Establishes relationships between hashes/arrays in `hsa` and the
objects they reference (which are also in `hsa`). The relationships
table is what gives the otherwise-flat `hsa` table its structural
shape.

**For a hash**: each row in `relationships` is one
`(hash_id, key) → value` mapping. The value is a reference back to
some row in `hsa` — could be a scalar, a hash, or an array.
A hash with N unique keys has N relationship rows.

**For an array**: same shape, but indexed instead of keyed —
`(array_id, index) → value`. The value is again a reference back
into `hsa`.

References in `relationships` chain back into `hsa`, and `hsa` rows
can in turn be primitives or compound (other hashes, other arrays
that have their own relationship rows). The model is fully
composable: arbitrarily-nested structures decompose into a flat pool
of `hsa` primitives plus a flat set of `relationships` linking them.

### Graph, not tree

Because `relationships` rows point at `hsa_id`s and nothing prevents
multiple relationship rows from pointing at the same `hsa_id`, any
value in `hsa` can be referenced by any number of parents. Two
different hashes can each hold `"x"` at some key, both pointing at
the same `hsa` row. Two different hashes can each hold the same
sub-hash at some key, both pointing at the same compound `hsa` row.

That makes Fiona a **graph** database, not a tree database. Tree
structures like JSON require every value to have exactly one parent —
sharing is impossible without either duplicating the value (losing
identity) or inventing a reference syntax (which most JSON tools
don't understand). Fiona sidesteps it: sharing is native, because
parenthood lives in its own table.

The behavior resembles how objects work in memory. Two variables can
reference the same object; changes made through one reference are
visible through the other. Fiona's compound rows inherit the same
property — if two hashes both reference sub-hash `hsa_id = 42`, and a
new key is added to that sub-hash via one parent (inserting a
relationship row with `parent = 42`), the other parent sees the added
key on its next read. Both are looking at the same `hsa_id`.

For scalars, whether shared mutation is observable depends on the
wiggle-room decision noted above: the strict rule (delete-and-add)
means scalar changes rewire the parent's relationship without
touching the shared row, so co-parents don't see the change;
UPDATE-in-place means they do.

---

## Why It's Not Used in Mikobase

(To be filled in.)

---

## Ideas Worth Carrying Forward

**The distinction between primitives and relationships stuck.** Miko
still mentally models objects as immutable while their relationships
can change. This isn't how Postgres, Ruby, or Caspian actually work —
all of those treat objects as mutable — but it remains his working
mental model when thinking about data.

The idea is that the *thing itself* (its identity, its raw value)
doesn't change; what changes is how it's connected to other things.
This separates "what something is" from "what it's part of," which is
a useful conceptual divide even in systems that don't enforce it
structurally.

Future design decisions around data modeling, schema evolution, or
versioning may benefit from leaning into this framing where it fits —
even when the underlying system technically allows mutation.
