# Lua Trivet

~~~vibecode
{"vibecode": {
	"doc": "ideas_lua_trivet",
	"role": "spec for a Lua-native tree library — port of the Trivet concept from Miko's Ruby Trivet library. Motivation: Lua tables are graphs (multiple references, cycles legal), not trees; a tree library gives us the invariants (single parent, no cycles) that role management and other use cases assume. The implementation ships at src/engine/trivet.lua with tests at tests/lua/trivet/ (invoke via `lua5.4 tests/lua/trivet/run.lua`). The unotate/ subdir here remains as the ideas-level demo (character.lua walks the Shakespeare corpus using Trivet). Role management is the anchor use case.",
	"status": "built and tested — 478 LOC, 93 passing tests. API shape settled on node-wraps-value (values opaque, tree logic never touches them). No container class: trivet.new(value) returns a root Node directly."
}}
~~~

Lua Trivet is a proposed library for generic tree structures. It is based on Miko's Ruby Trivet library.

Lua tables aren't natively trees — they're graphs (nothing prevents multiple references to the same subtree or outright cycles). Trivet's job is to enforce and expose the tree invariant: single parent, no cycles, structured traversal.

## General design

Trivet is a generic n-ary tree library. It doesn't care what a node's value is — a string, a table, a class instance, anything. Its job is the tree structure and the operations over it.

### Node shape

A node wraps a value and knows its own parent and children. Values themselves are opaque to Trivet — a value can be any Lua type (string, table, class instance, closure, userdata).

~~~lua
local node = trivet.new(some_value)   -- returns a fresh root Node

node.value             -- the wrapped value (any Lua value)
node.parent            -- parent node, or nil at the root
node:children()        -- iterator over child nodes (insertion order)
~~~

**Node-wraps-value shape** was chosen over the mixin alternative (`value` itself being the Node via stamped-on methods). Rationale: the tree is separable from the value type, values can be anything, and there's no monkeypatching. Downside: `caller:is_ancestor_of(target)` reads on the Node, not the domain object — but callers can add a thin wrapper if they want the domain object to expose tree operations directly.

### Structural invariants

Trivet enforces these; violations raise at construction / mutation time:

- **Single parent** — each node has exactly one parent (or is a root). Enforced by construction: `create_child` / `insert_child` always mint fresh nodes (can't already have a parent), and `move_to` moves the sole reference (not clones), so a node can never be a child of two parents simultaneously.
- **No cycles** — `move_to` walks the target's ancestor chain and refuses if self appears. `create_child` and `insert_child` can't cycle (they mint fresh nodes with nothing above them).
- **Root is a derivation, not a state** — a node is a root iff `node.parent == nil`. There is no container holding the tree; the root node IS the tree.
- **Child order is preserved** — the order in which children are added is the order they iterate, and every mutation (`insert_child`, `remove`, `move_to`, `move_before`, `move_after`) keeps the remaining siblings in their existing relative order. `create_child` appends at the end; `insert_child(i, v)` shifts subsequent siblings right; `remove` closes the gap; `move_to` appends at the destination's end.

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

Trivet doesn't ship `to_json` / `from_json`. Not every node value is serializable (closures, file handles, values with identity), and consumers want different formats (Drinian snapshots, debug dumps, HTTP responses). Serialization is a per-consumer concern — walk the tree with the existing traversals (`node:descendants()`, `node:subtree()`, `node:walk(fn)`) and produce whatever output shape is wanted.

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

- **Reparenting** — roles never move once placed.
- **Sibling order** — Trivet preserves child insertion order (see the [structural invariants](#structural-invariants) above), but role management doesn't rely on that: siblings of a role are unordered from the security-model perspective. If two roles share a parent, neither "comes before" the other in any meaningful sense.

None of these unused features cost roles anything — Trivet just doesn't call them.
