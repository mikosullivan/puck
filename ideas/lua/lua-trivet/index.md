# Lua Trivet

~~~vibecode
{"vibecode": {
	"doc": "ideas_lua_trivet",
	"role": "spitball page for a Lua-native tree library — port of the Trivet concept from Miko's Ruby Trivet library. Motivation: Lua tables are graphs (multiple references, cycles legal), not trees; a tree library gives us the invariants (single parent, no cycles) that role management and other use cases assume. Role management is the anchor use case — this page sketches how Trivet would slot in.",
	"status": "early — anchor use case (role management) sketched; API shape (node-wraps-value vs mixin) still open pending Ruby Trivet review"
}}
~~~

Lua Trivet is a proposed library for generic tree structures. It is based on Miko's Ruby Trivet library.

Lua tables aren't natively trees — they're graphs (nothing prevents multiple references to the same subtree or outright cycles). Trivet's job is to enforce and expose the tree invariant: single parent, no cycles, structured traversal.

## General design

Trivet is a generic n-ary tree library. It doesn't care what a node's value is — a string, a table, a class instance, anything. Its job is the tree structure and the operations over it.

### Node shape

A node wraps a value and knows its own parent and children. Values themselves are opaque to Trivet.

~~~lua
node.value          -- the wrapped value (any Lua value)
node.parent         -- parent node, or nil at the root
node:children()     -- iterator over child nodes (insertion order)
~~~

**Open question — API shape.** Two candidates:

- **Node-wraps-value** (assumed above) — the tree holds `Node` objects; the value is `.value`. Any Lua type can be a value; the tree is separable from the value type.
- **Value-is-node (mixin)** — the value itself IS the node, via a mixin that stamps `.parent` / `.children` / etc. onto the value's class. More ergonomic (`caller:is_ancestor_of(target)` reads naturally on the domain object) but couples the value type to the tree library.

Which one the Ruby Trivet uses drives the Lua port. Filling in after that review.

### Structural invariants

Trivet enforces these; violations raise at construction / mutation time:

- **Single parent** — each node has exactly one parent (or is a root). Assigning the same node as a child of two parents is a Trivet-level error.
- **No cycles** — add-child refuses if the proposed parent is a descendant of the proposed child.
- **Root is a derivation, not a state** — a node is a root iff `node.parent == nil`. There is no container holding the tree; the root node IS the tree.

### Module methods

The module surface is a single constructor — everything meaty lives on nodes.

- `trivet.new(value)` — create a fresh root node wrapping `value`; returns the node. The returned node has no parent, so `node.is_root` is true.

### Node methods

Predicates use the Lua-idiomatic `is_X` / `has_X` prefix — Lua identifiers can't contain `?`.

#### Structural queries

- `node.parent` — parent node, or `nil` for a root.
- `node.depth` — `0` for a root, `N` for a node `N` generations down.

#### Predicates

- `node.is_root` — is this a root?
- `node.is_leaf` — no children?
- `node.has_children` — inverse of `is_leaf`.

#### Children

- `node:children()` — iterator over direct children in insertion order.
- `node.first_child` — first child, or `nil`.
- `node.last_child` — last child, or `nil`.
- `node.child_count` — number of direct children.
- `node:child(index)` — Nth child (1-indexed per Lua convention).

#### Siblings

- `node:siblings()` — iterator over siblings, excluding self.
- `node.previous_sibling` — sibling immediately before this one, `nil` if first.
- `node.next_sibling` — sibling immediately after this one, `nil` if last.
- `node.sibling_index` — this node's 1-indexed position among its siblings.

#### Ancestors and descendants

- `node:ancestors()` — iterator bottom-up: `parent`, grandparent, …, root.
- `node:descendants()` — iterator over every descendant; pre-order default. Excludes self.
- `node:descendants('post')`, `node:descendants('bfs')` — post-order and breadth-first variants. Both exclude self.
- `node:subtree()` — same as `descendants()` but **includes self**. Pre-order default; also `'post'` and `'bfs'`. Self appears first for `pre` and `bfs`, last for `post` — the natural position for each order.
- `node:path_from_root()` — iterator top-down: root, …, parent, self.
- `node.descendant_count` — total descendants excluding self.
- `node:is_ancestor_of(other)` — predicate: is self an ancestor of `other`?
- `node:is_descendant_of(other)` — predicate: is self a descendant of `other`?

#### Mutation

- `node:create_child(value)` — append a new child; returns the new node.
- `node:insert_child(index, value)` — insert a new child at a specific 1-indexed position.
- `node:remove()` — detach self (and the entire subtree) from its parent. Returns the detached node itself, which is now a root (its subtree structure below is preserved). Move it into another tree via `move_to`.
- `node:move_to(new_parent)` — reparent self; refused if it would create a cycle. `new_parent` may belong to any unrelated tree — a move is just a move.
- `node:move_before(sibling)` — reorder self to just before `sibling` (must share a parent).
- `node:move_after(sibling)` — reorder self to just after `sibling`.

#### Traversal callback

- `node:walk(fn)` — pre-order walk; call `fn(node)` at each descendant.
- `node:walk(fn, order)` — same with `order = 'pre' | 'post' | 'bfs'`.
- **Early termination** — if `fn` returns a non-nil value, walk stops and returns that value. Enables the search-until-found pattern: `local match = root:walk(function(n) if is_match(n) then return n end end)`. Callers who don't need early termination can return nothing.

#### Value

- `node.value` — the wrapped value (read).
- `node.value = X` — set the wrapped value. Does not touch tree structure.

### Serialization is not core

Trivet doesn't ship `to_json` / `from_json` on the base class. Not every node value is serializable (closures, file handles, values with identity), and consumers want different formats (Drinian snapshots, debug dumps, HTTP responses). Serialization is a per-consumer concern:

- **Subclasses** — a Trivet subclass whose values ARE JSON-compatible can add its own `to_json` and control the shape.
- **Ad-hoc callers** — walk the tree with the existing traversals (`node:descendants()`, `t:walk(...)`) and produce whatever output shape is wanted.

Trivet's job is the walk; the shape of the output is not.

## Role management

The role hierarchy from the [security model](https://puck.uno/requirements/security/model/) is a tree. `user` is the root; every other role is a descendant. Every load-bearing operation the engine performs on roles is a Trivet operation.

Sketch (Lua, engine-side — Caspian developers don't see this):

~~~lua
local user = trivet.new(Role.new('user'))

-- Adding a role: every %fetch, every .children.new, one call.
local factory_class = user:create_child(Role.new('R_factory_class'))
local db_class      = factory_class:create_child(Role.new('R_db_class'))

-- Rule 2 authority check: can caller mutate object owned by target?
if caller == target or caller:is_ancestor_of(target) then
	-- proceed with structural mutation
end

-- Rule 2 reach: what does this role's authority cover?
for descendant in user:descendants() do
	-- descendant is under user's authority
end

-- Ownership chain, for error messages / debugging.
for node in tire_1:path_from_root() do
	print(node.value.id)   -- user, R_factory_class, R_db_class, R_tire_1
end
~~~

### Which operations roles use

- **Add child** — every role creation.
- **Ancestor query** — Rule 2 authority check on every structural mutation (`.obj.classes.ensure`, `.obj.destroy`, `.obj.freeze`, stack changes).
- **Descendant walk** — `%role.run_as` (target must be a descendant of current), `%role.delegate_to` scope checks.
- **Path from root** — the "who owns this?" trace shown in error messages.
- **Lookup by identifier** — the engine maintains its own `{role_id -> node}` hash alongside the Trivet, updated on every add/remove. Trivet itself doesn't do lookup.
- **Serialization** — Drinian snapshots include the role tree; Drinian walks the tree with `node:descendants()` (or its own recursive walk) and produces its snapshot format. Trivet doesn't own the format.

### Which operations roles don't use

- **Reparenting** — roles never move.
- **Sibling order** — role siblings don't have meaningful ordering; enumeration order is whatever.

None of these unused features cost roles anything — Trivet just doesn't call them.
