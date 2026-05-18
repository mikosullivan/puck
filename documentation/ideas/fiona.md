# Fiona

**Status:** notes on a data structure Miko once invented. **Not in use
in mikobase.** Recorded here because some of its ideas may still
inform future design decisions.

---

## Overview

Fiona is a DBMS Miko once designed. Its defining property is **strict
immutability**: every object in the database is a primitive. Once
written, an object never changes — there is no concept of "updating"
or "mutating" an object. If you want to represent a changed state, you
write a new object.

Consequences of this property:

- **References are stable.** A reference to an object always returns
  the same value. The object cannot have been modified since the
  reference was captured.
- **No version concept built into objects.** "Versions" aren't a thing
  at the object level. If a developer needs to model succession (old
  → new), they express it explicitly — via separate objects with
  references between them, or version chains, or whatever the
  application needs. The DBMS doesn't impose a notion of supersession.
- **Value semantics across the database.** Database objects behave
  like ints or strings in most languages: stable, comparable, never
  mutated. The "object identity = value identity" rule that holds for
  primitives in many languages also holds here for database objects.

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
null), hashes, and arrays. Each row is one immutable primitive.

- Records can be **added** or **deleted**, but never **modified**.
- Hence the immutability property: once a primitive is in `hsa`, its
  value is fixed. To "change" it, you delete the old row and add a
  new one — which is functionally the same as creating a different
  primitive.

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
composable: arbitrarily-nested JSON structures decompose into a flat
pool of `hsa` primitives plus a flat set of `relationships` linking
them.

---

## Why It's Not Used in Mikobase

(To be filled in.)

---

## Ideas Worth Carrying Forward

**The distinction between primitives and relationships stuck.** Miko
still mentally models objects as immutable while their relationships
can change. This isn't how Postgres, Ruby, or Charlie actually work —
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
