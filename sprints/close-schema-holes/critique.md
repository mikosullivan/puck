~~~vibecode
{"doc": "sprint-note", "sprint": "close-schema-holes",
	"role": "Full text of the schema-invariant critique authored by ChatGPT and pasted into GitHub issue #1663. Preserved verbatim as the source of most of the sprint's known-holes list. The sprint's [index](./index) tracks the derived work items."}
~~~

# CVM SQLite Schema Invariant Review

Source: ChatGPT critique of `src/engine/cvm/schema.sql`, pasted into GitHub issue #1663. Reproduced verbatim below for reference; work items derived from it live on the sprint [index](./index).

## Purpose

The CVM SQLite schema is intended to do more than store runtime state. One of its design goals is to ensure that the database itself cannot represent a program state that the CVM considers invalid.

This review examined `src/engine/cvm/schema.sql` from that perspective: not primarily for SQL style or performance, but for states that SQLite currently permits even though the surrounding schema, comments, and triggers appear to assume they are impossible.

Several such cases were found.

---

## 1. Hash and Array Reference Key Semantics Are Not Enforced

The schema documents the intended distinction between hash and array entries:

~~~sql
-- Hash entries use `key`; array entries leave key null and use idx.
~~~

However, `refs` does not enforce this relationship between the parent's primitive and `key`.

As a result, both of the following states are currently legal:

~~~sql
-- Hash entry without a key.
insert into refs (parent, child, key, idx)
values (:hash, :object, null, 0);

-- Array entry with a key.
insert into refs (parent, child, key, idx)
values (:array, :object, 'foo', 0);
~~~

Both were tested against the schema and accepted by SQLite.

### Why this matters

For a HashPrimitive, `unique(parent, key)` does not solve the problem because SQLite permits multiple `null` values in a UNIQUE constraint.

Consequently, hashes can contain anonymous entries.

Arrays can likewise contain named entries even though the documented model says their keys should always be null.

The existing hash-key validation trigger validates a key when one is present, but it does not require hashes to have keys.

### Desired invariant

Conceptually:

~~~text
parent primitive = 'h'  => key is not null
parent primitive = 'a'  => key is null
~~~

If other primitive types are permitted to own refs, their key semantics should also be explicitly defined.

### Severity

**High.** This directly permits object structures that contradict the documented container model.

---

## 2. `parent_frame` Does Not Require Its Target to Be a Frame

The `objects` table contains:

~~~sql
parent_frame text
	references objects(object_pk)
	check (parent_frame is null or primitive = 'f')
~~~

The CHECK constraint verifies that an object *having* a `parent_frame` is itself a FramePrimitive. It does not verify that the object referenced by `parent_frame` is a frame.

Therefore this topology is currently legal:

~~~text
HashPrimitive
      ↑
 parent_frame
      |
    Frame
~~~

This was tested and accepted by SQLite.

### Why this matters

Other parts of the schema appear to assume that `parent_frame` actually identifies a frame. For example, frame deletion/GC logic queries the parent's `gc` state:

~~~sql
select gc
from objects
where object_pk = old.parent_frame
~~~

The lifecycle machinery therefore treats `parent_frame` as a relationship between frames even though the schema permits it to reference arbitrary objects.

This can produce objects that are legal to create but incompatible with assumptions made by later lifecycle triggers.

### Desired invariant

For every non-null `parent_frame`:

~~~text
objects[parent_frame].primitive = 'f'
~~~

This requires a trigger or equivalent cross-row validation because a CHECK constraint cannot directly enforce the primitive of another row.

### Severity

**Critical.** This is the strongest invariant hole found because later schema logic itself assumes the stronger invariant already exists.

---

## 3. Roles Can Be Arbitrary Primitive Types

The `roles` view identifies roles using `core_role` and `role_parent`.

An object becomes a non-core role by having a non-null `role_parent`.

The insertion logic verifies that `role_parent` identifies an existing role, but it does not appear to constrain the primitive type of the new role.

Consequently, objects such as scalar ObjectPrimitives can become roles.

For example, this is currently accepted:

~~~sql
insert into objects (
	primitive,
	scalar_type,
	scalar_value,
	role_parent
)
values (
	'o',
	's',
	'hello',
	:engine
);
~~~

The resulting scalar object is then included in `roles`.

A FramePrimitive can likewise be given a `role_parent`, potentially making the same object both a frame/process object and a role.

### Why this matters

The predefined `engine`, `cache`, and `user` roles are structural HashPrimitives, which suggests that roles may be intended to have container semantics.

If roles are intentionally allowed to be arbitrary objects, the existing behavior is valid.

If roles are structural objects, however, the schema currently permits invalid role representations.

### Decision required

Define explicitly whether:

~~~text
any object may be a role
~~~

or whether something closer to:

~~~text
role => primitive = 'h'
~~~

is intended.

### Severity

**Design-dependent.** No change is needed if arbitrary objects are deliberately allowed to serve as roles.

---

## 4. `stmt_idx` Has No Upper Bound Relative to `ast`

The frame state-machine logic strongly constrains changes to `stmt_idx`. Among other things, it enforces sequential advancement and coordinates advancement with GC state.

However, there is no apparent constraint relating `stmt_idx` to the number of statements represented by `ast`.

For example, a process cap can be created with:

~~~text
ast = []
stmt_idx = 0
~~~

and subsequently advanced through states such as:

~~~text
0 -> 1 -> 2
~~~

The schema accepts `stmt_idx = 2`.

This is significant because the schema comments describe the process cap's empty AST as having a specific lifecycle:

~~~text
0 = live
1 = terminal
~~~

The schema currently does not enforce that `1` is actually terminal.

### Potential invariant

For a process cap, the rule appears likely to be:

~~~text
stmt_idx in {0, 1}
~~~

For ordinary frames, a possible invariant is:

~~~text
0 <= stmt_idx <= json_array_length(ast)
~~~

The exact boundary should be checked against the evaluator's statement-walking semantics before implementing it.

### Why this matters

This is an example where Lua may behave correctly while SQLite still admits an impossible CVM state.

If the goal is that **every database state is a valid program state**, relying on Lua never to perform the extra increment is insufficient.

### Severity

**Medium to high.** The exact fix depends on the intended AST/frame terminal-state semantics.

---

## 5. The Special `scopes` Reference Is Not Fully Restricted to Its Intended Context

The schema provides useful structural enforcement around `scopes`.

It requires the child of a `key = 'scopes'` reference to have the expected array structure, and scope entries themselves are constrained appropriately.

However, the parent side of the relationship is less constrained.

Because refs can currently originate from containers with inappropriate key semantics, structures such as this can potentially be formed:

~~~text
ArrayPrimitive
      |
      +-- key='scopes' --> ArrayPrimitive
~~~

Fixing the general array/hash key problem described in Finding 1 removes part of this issue.

However, if `scopes` specifically belongs to a particular kind of bucket or frame-associated HashPrimitive, the schema should enforce that fact independently.

### Desired invariant

If the intended rule is:

~~~text
"scopes" is a reserved structural member of a frame bucket
~~~

then the parent of a `key = 'scopes'` ref should be verified as the appropriate structural object rather than merely accepting any ref parent capable of carrying that key.

### Severity

**Medium / design-dependent.** Part of the problem disappears after fixing Finding 1, but the intended ownership of `scopes` should still be made explicit.

---

## 6. `object_pk` Is Not Actually Constrained to UUIDs

`object_pk` has a default expression that generates a UUID-shaped identifier.

However, callers can explicitly provide arbitrary text, such as:

~~~sql
object_pk = 'banana'
~~~

There is no CHECK constraint requiring the supplied value to have UUID syntax.

Additionally, the random default creates the familiar:

~~~text
8-4-4-4-12
~~~

shape but does not force the UUIDv4 version and RFC variant bits.

### Why this may not matter

If `object_pk` is intentionally an opaque text identifier and UUID-shaped defaults are merely convenient, this is not an invariant problem.

If a valid CVM object is required to have an actual UUID identifier, then the schema does not currently enforce that requirement.

### Severity

**Low / design-dependent.** This only needs attention if UUID validity is part of the CVM state model.

---

## 7. References to Immutable Core Roles May Become Undeletable

There is a potentially unintended interaction between reference deletion and core-role immutability.

Deleting a ref causes the referenced child to be marked:

~~~sql
needs_trace = 1
~~~

Core roles, however, reject updates.

Suppose an ordinary object contains a reference to a pinned core role:

~~~text
ordinary object
      |
      +------ ref ------> engine
~~~

Creation of the ref is permitted.

Deleting that ref then attempts to update `engine.needs_trace`.

The core-role immutability trigger can reject that update, causing deletion of the ref itself to fail.

### Why this matters

This creates a potentially asymmetric relationship:

~~~text
ref creation succeeds
ref deletion fails
~~~

The database therefore admits a relationship that its normal cleanup mechanism may not be capable of removing.

### Possible interpretations

This may be intentional if references to pinned objects have special lifetime semantics.

If pinned/core objects never require tracing, the ref-deletion trigger may need to avoid setting `needs_trace` for such children.

Alternatively, refs to core roles could be restricted if such relationships are not meaningful.

### Severity

**Medium.** The behavior should at least be explicitly tested and documented because it emerges from the interaction of otherwise reasonable triggers.

---

# Positive Findings

The review also found several places where the schema successfully goes beyond ordinary relational validation and enforces genuine runtime state transitions.

## Frame Lifecycle Enforcement

The frame machinery establishes interdependent rules roughly equivalent to:

~~~text
stmt_idx advances only by one
        |
        v
advancement requires gc = 1
        |
        v
gc transition participates in child cleanup
        |
        v
child deletion requires the parent to be collecting
        |
        v
gc cannot reset until children are gone
~~~

This is substantially stronger than merely checking the validity of individual columns. The schema is constraining the set of **reachable runtime states and transitions**, which directly supports the goal of making every representable database state a valid CVM state.

## Role Tree Construction

The role hierarchy also has a useful structural property. A new `role_parent` must identify an already-existing role, while role parentage subsequently becomes immutable. That makes cycles difficult or impossible to manufacture through ordinary insertion/reparenting, without requiring a recursive cycle check after every operation.

This is a good example of enforcing an invariant by restricting the operations capable of constructing the graph rather than repeatedly validating the completed graph.

---

# Recommended Priority

The findings can be grouped into three levels.

## Fix First

### 1. Enforce Hash/Array key semantics

~~~text
HashPrimitive => key required
ArrayPrimitive => key forbidden
~~~

### 2. Enforce that `parent_frame` references a FramePrimitive

~~~text
child.parent_frame != null
	=>
parent.primitive = 'f'
~~~

The `parent_frame` issue should receive the highest priority because existing lifecycle logic already assumes this invariant.

---

## Investigate and Probably Fix

### 3. Bound `stmt_idx` against the AST/frame lifecycle

Determine the precise terminal semantics and encode them into the database.

### 4. Verify core-role reference deletion

Determine whether references to pinned/core roles should skip tracing, be prohibited, or have some other explicit behavior.

---

## Make Explicit Design Decisions

### 5. Define what kinds of objects may be roles

If roles must be HashPrimitives, enforce that invariant. If arbitrary objects may be roles, the current behavior should be considered intentional and ideally documented.

### 6. Define the exact ownership semantics of `scopes`

If `scopes` is reserved for a particular structural object, enforce the parent side of that relationship.

### 7. Decide whether UUID syntax is an invariant

If object IDs are opaque strings, no change is required. If they must actually be UUIDs, enforce that requirement rather than relying on the default generator.

---

# General Observation

The most useful way to review this schema is to distinguish three increasingly strong guarantees:

~~~text
1. Each row is internally valid.

2. Relationships between rows are valid.

3. Every transition from one database state to another
   preserves a valid CVM program state.
~~~

The schema already contains substantial machinery for level 3, particularly around frames and garbage collection.

The remaining holes mostly occur where a relationship is represented by an ordinary foreign key but the CVM assigns stronger semantics to that relationship.

A foreign key can establish:

~~~text
this object exists
~~~

but several CVM relationships require:

~~~text
this object exists
AND
it has this primitive
AND
it occupies this structural role
AND
this transition is legal at this point in execution
~~~

Those are the areas where additional triggers are most valuable.

The strongest concrete findings from this review are therefore not failures of SQLite's relational integrity mechanisms. They are places where **CVM-level types and relationships are stronger than the corresponding SQL-level foreign keys currently express**.

Closing those gaps would move the schema closer to its intended property:

> **If SQLite accepts the transaction, the resulting database represents a valid CVM program state.**
