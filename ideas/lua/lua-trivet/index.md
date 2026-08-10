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

Trivet doesn't ship `to_json` / `from_json`. Not every node value is serializable (closures, file handles, values with identity), and consumers want different formats (MVM snapshots, debug dumps, HTTP responses). Serialization is a per-consumer concern — walk the tree with the existing traversals (`node:descendants()`, `node:subtree()`, `node:walk(fn)`) and produce whatever output shape is wanted.

Trivet's job is the walk; the shape of the output is not.

## Trivet as tree manager

Working design for the Trivet class — the wrapper around a whole tree that provides tree-level operations. Trivet IS the manager; there's no separate Manager class. Started 2026-08-07 with Miko; still in design, no code yet.

### What Trivet is

A wrapper object that HOLDS a Trivet tree without BEING part of it. Trivet has a single reference to the tree's root node; every tree-wide operation starts from that root. Trivet itself is not a node — no `.value`, no `.parent`, no `.children` — it's a separate class with its own methods and fields.

### Why we want one

- **A home for global properties.** Tree-wide state (name, metadata, indexes, rules, whatever the application needs) belongs on Trivet. Without one, that state gets scattered across nodes (with cache-coherence problems) or lives at the application layer (with reach-back plumbing at every call site).
- **A stable identity for the tree.** Trivet IS the tree from the outside. Callers who want to hand "the roles tree" to something hand Trivet.
- **An enforcement site for tree-wide policies.** Any invariant that spans the whole tree — "root is permanent," "no moves," "only appends allowed" — lives on Trivet. Node operations consult Trivet (via `node.trivet`) at mutation time.

### Every tree has a Trivet

Mandatory, not optional. Two payoffs cascade from this commitment:

- Any node can reach tree-wide state via `node.trivet`, without callers threading a Trivet reference through every function.
- Tree-wide invariants can be checked from any node's mutation site: walk to root, read Trivet, check the flag.

Concrete effect on the API: `trivet.new(value)` returns a **Trivet** wrapping a fresh root Node whose value is `value`. Reach the root from a Trivet via `trivet.root`. Reach the Trivet from any node in the tree via `node.trivet`.

This is a breaking change from the current Trivet API, where `trivet.new(value)` returns a Node. Existing callers (state.lua and the Trivet test suite) update to reach the root via `.root` — few enough sites that the change is small.

### Trivet subclassing

Trivet is subclassable. Domain-specific tree wrappers extend Trivet with their own state and methods:

- **RolesTrivet** — the class `state.roles` is. Carries role-lookup helpers and role-tree-specific defaults (`new_node_class = Role`, sets `moves_prohibited = true` and `root_locked = true` at construction).
- **UmaTrivet** — Trivet subclass for Uma's document tree. Carries document-level state (metadata, IDs, style rules) and Uma-specific defaults (`new_node_class = <function returning tag classes>`).

Both share Trivet's tree mechanics; they layer domain-specific concerns on top.

Standard Lua subclassing pattern applies: subclass sets its metatable to inherit from Trivet, adds its own methods and constructor. `trivet.new` is the base convenience factory; subclasses either extend it or expose their own factory (`RolesTrivet.new(root_args)`).

### Core Trivet properties

Locks are managed as boolean properties on Trivet, not as separate lock methods. The setter runs a one-way transition rule; reads return the current state. Every lock property follows the same three rules:

- **Accepts only `true` or `false`.** Non-boolean assignment raises immediately — no truthy/falsy coercion, so an accidental `nil` from an upstream nullable doesn't silently unlock.
- **`false → true` locks.** `true → true` is idempotent.
- **`true → false` raises.** No unlock. The one-way discipline lives in the transition, not in method naming.

Trivet-level lock properties:

- **`trivet.root_locked`** — `false` at construction. Set to `true` and Trivet's root reference is permanent — it can no longer be swapped for a different root. Since every tree has a Trivet, moving the current root would require Trivet's root reference to change; the lock refuses. Enforcement lives in the parent-setter path (see § Attachment flow below). `remove()` on the root also refuses under this lock: cascade-deleting the root would leave Trivet holding a stale reference, contradicting the invariant. The op raises rather than proceeding.

- **`trivet.moves_prohibited`** — `false` at construction. Set to `true` and every operation that would change a node's position in the tree refuses — the parent setter (`node.parent = X`), `move_to`, `move_before`, and `move_after`. Sibling reordering counts as a move even though the parent doesn't change; "no moves" is read strictly. Under `moves_prohibited`, `remove()` cascade-deletes — because there's no legitimate re-attach path, keeping detached-but-alive nodes serves nothing.

### The `trivet.root` property

Readable and writable:

- **Reading `trivet.root`** returns the current root node. Trivet holds the reference directly — no walk.
- **Writing `trivet.root = new_root`** sets a new root. Used by tree operations that change the top of the tree — red-black or AVL rebalancing, other rotation-based algorithms.

Setter semantics — deliberately minimal:

1. Check `root_locked`. If `true`, raise (`trivet_root_locked: Trivet's root is locked`).
2. Clear `_trivet` on the current root (old root loses awareness of Trivet).
3. Set `_trivet` on the new root (new root gains awareness).
4. Update Trivet's internal root reference.

The setter does **not** restructure the tree. Caller is responsible for the parent-child rewiring before calling. The setter's job is purely bookkeeping: transfer the `_trivet` reference and update Trivet's own root pointer.

Under `root_locked = true` (roles tree, most fixed-structure trees), the setter refuses. Under `root_locked = false` (red-black, AVL, other rebalancing trees), the setter proceeds.

### The `audit` method

`trivet:audit()` walks the whole tree manually and checks for consistency. It's a safety valve — the property setters, `__newindex` hooks, and other invariants throughout Trivet should keep bad states from arising in the first place. `audit` exists for when they don't (bug in Trivet, engine-side accidental corruption, an FFI shim mutating raw fields) or when a caller wants to independently confirm the tree's shape.

**Base checks** (built into Trivet):

- **No cycles.** Walks the tree from the root, tracking visited nodes. Any node visited twice indicates a cycle.
- **Single-parent invariant.** Every node's `.parent` field points at a node whose `_children` array actually contains the child. Any parent / children disagreement indicates a broken invariant.
- **`_trivet` placement.** The root has `_trivet` set to Trivet itself; every other node has `_trivet == nil`.

**Extensible via subclass hook.** Base Trivet calls `self:audit_extra()` at the end of its own checks. Subclasses override `audit_extra` to add domain-specific invariants:

~~~lua
function RolesTrivet:audit_extra()
	-- Check: every Role has a unique ID
	-- Check: engine role is at the root
	-- Check: no role in state.objects is orphaned from state.roles
end
~~~

Base `Trivet:audit_extra` is a no-op, so subclasses that don't need extra checks just inherit it.

**Cost.** O(size of tree) — a full walk. Not cheap for large trees, but a diagnostic call, not a runtime hot path.

**Return / raise.** Nothing on success. On failure, raises an error identifying the specific violation, following the Lua ID convention:

- `trivet_audit_cycle_detected: node <id> appears twice in the tree`
- `trivet_audit_parent_child_mismatch: node X.parent = Y but Y._children doesn't contain X`
- `trivet_audit_trivet_field_misplaced: non-root node X has _trivet set`
- Subclass raises: `roles_trivet_audit_duplicate_id: role ID 42 appears on multiple nodes`

We should never need to run `audit` in normal operation. Its existence is the guarantee that if we do, the diagnosis will be precise.

### Node factory: `new_node_class`

The Trivet's `new_node_class` property decides what class Trivet instantiates when a new node is created. Two forms:

- **A Node class.** All children get built from this class. Default: base Node. For a Role tree, it's Role. For Uma, it's a Tag subclass.
- **A function.** `trivet.new_node_class = function(...) return SomeClass end`. Receives whatever args `create_child` was called with; returns the class to use. Lets Trivet pick between multiple candidates based on the input (Uma dispatches to `ATag` / `PTag` / `TableTag` based on the `name:` arg).

Args flow uniformly:

~~~
parent:create_child(ARGS)  →  trivet.new_node_class(ARGS)  →  Class.new(ARGS)  →  parent:before_attach(new_node)  →  attach
~~~

The default flow (base Node class, single value arg): `parent:create_child(value)` → base Node's constructor with `value` → node has `.value = value`. Same as current Trivet.

### Node subclassing

Nodes are subclassable. Subclasses inherit Trivet's tree mechanics and layer their own state:

~~~lua
local Role = {}
Role.__index = Role
setmetatable(Role, {__index = Node})   -- inherit from Node

function Role.new(args)
	local role = setmetatable({}, Role)
	role.name = args.name
	role.id   = args.id
	-- Node-inherited structural fields (parent, _children, etc.) are set
	-- by the attach machinery, not here.
	return role
end
~~~

**Reserved fields.** Subclasses avoid these to prevent collisions with Node's structural state:

- `parent` — the parent node reference
- `_children` — the internal children array
- `_trivet` — set only on roots
- `trivet`, `root` — surface accessors
- `value` — default field for the base Node
- `allow_new_children` — node-level lock property
- `before_attach` — the attach hook (safe to override, not safe to shadow with a data field)
- Any other Node property or method

Silent breakage results if a subclass sets an instance field with the same name — the subclass field wins on the instance and hides the Node behavior. Cheap discipline; Node docs list the reserved set.

### The `before_attach` hook

`node:before_attach(child)` is a hook that fires during attachment — after the child has been created (via `create_child` or explicit parent assignment) and before it's officially attached to the parent.

The base Node class ships a `before_attach` that does nothing, so callers never have to check "does this node have the hook?" before calling — it's always present, and the default is a no-op. Subclasses override to add domain-specific behavior:

- **Validate the child** (e.g., "Role tree accepts only Role nodes")
- **Enforce content models** (e.g., HTML's "an `<a>` cannot contain `<p>`")
- **Mutate the child** (e.g., normalize a name, allocate an ID, add derived fields)
- **Log the attach event**
- Anything else the subclass wants to do at that moment

**Convention: raise to abort the attach.** Returning normally lets the attach proceed. There's no explicit "return false to refuse" — the semantics are raise-or-let-through. The name doesn't literally say that, but it's a common enough pattern (Rails-style `before_save`, `before_action`) that developers pick it up.

Example — Role's type check:

~~~lua
function Role:before_attach(child)
	if not is_role(child) then
		error("roles_role_before_attach_non_role_child: Role tree accepts only Role nodes; got " .. type_name(child))
	end
end
~~~

Example — Uma's `<a>` tag content-model check:

~~~lua
function ATag:before_attach(child)
	if child.is_block_element then
		error("uma_atag_before_attach_block_child_in_inline: <a> cannot contain <" .. child.tag_name .. "> — block elements not allowed inside inline <a>")
	end
end
~~~

The specific error message ("block elements not allowed inside inline <a>") is a real win over a boolean-return hook — the developer editing the page sees exactly what rule fired instead of just "no."

### The `before_detach` hook

Symmetric partner to `before_attach`: `node:before_detach(child)` fires when a node is about to lose a child. Base implementation does nothing — same "always present" pattern as `before_attach`, so callers never need to check for its existence.

Subclasses override to:

- **Validate the removal** (e.g., "user role can't be removed while children exist")
- **Clean up** (release resources the parent held on the child's behalf)
- **Log the detach event**
- Anything else the parent wants to do at that moment

**Convention: raise to abort the detach.** Returning normally lets it proceed. Same discipline as `before_attach`.

**When it fires.** At the boundary between the parent that's losing the child and the child that's leaving. Called once per top-level removal. Under `moves_prohibited` cascade-delete of a deep subtree, `before_detach` fires only at the top-level parent (whose child is the subtree root being removed) — interior nodes of the removed subtree are silently deleted; their in-subtree parents' `before_detach` doesn't fire because those parents are themselves being deleted.

**Flow under normal Trivet `child:remove()`:**
1. `child.parent:before_detach(child)` → subclass hook fires; may raise.
2. Detach: remove from `parent._children`; set `child.parent = nil` via `rawset`.
3. The detached subtree has no Trivet (`_trivet` on the new root stays nil); it's a read-only snapshot from here on (see § Detached subtrees are read-only).

**Flow under `moves_prohibited` cascade-delete:**
1. `child.parent:before_detach(child)` → subclass hook fires; may raise.
2. Detach child from `child.parent._children`.
3. Recursively delete child and all its descendants. No further hooks fire during the recursion.

Example — Uma's `<table>` protecting its `<thead>`:

~~~lua
function TableTag:before_detach(child)
	if child.tag_name == 'thead' and self.thead_required then
		error("uma_tabletag_before_detach_required_thead: <table> requires a <thead>; cannot remove it")
	end
end
~~~

Example — Role guarding a protected role:

~~~lua
function Role:before_detach(child)
	if child.protected then
		error("roles_role_before_detach_protected_child: cannot remove role marked protected")
	end
end
~~~

### Node-level lock: `allow_new_children`

Per-node companion to the Trivet-level locks. Same property idiom (boolean-only, one-way) with reversed polarity — reads more cleanly as a permission state than as a lock state:

- **`node.allow_new_children`** — `true` at construction (new children ARE allowed by default). Set to `false` to lock the node against new children. Existing children stay; more can't be added; existing ones can still be removed (which cascade-deletes under `moves_prohibited`). `false → true` raises — the one-way rule still applies, just in the opposite direction.

Per-node granularity is the whole point — locks a specific slot in the tree without freezing the whole tree. For the roles tree, this closes engine's child list (`user` and nothing else, forever) while still allowing roles to be added under `user` (loaded libraries, faucets, etc.) as they arrive.

### Reach from any node

Every node can walk back to the tree's root and to Trivet. Threading Trivet through function signatures is unnecessary — any node reaches Trivet (and thus tree-wide state) directly.

- **`node.root`** — walks parent references and returns the tree's root node. Trivet currently has `is_root` (predicate) but no `root` accessor; this fills the gap.
- **`node.trivet`** — returns the Trivet of the tree the node belongs to. **Only the root actually holds the Trivet reference.** Every other node's `.trivet` walks to `self.root` and reads the Trivet from there — one Trivet reference per tree, no per-node caching, the reference lives in one place and stays consistent as trees mutate.

Sketch of the resolution:

~~~lua
Node_properties.trivet = function(node)
	return node.root._trivet  -- always walk to root first; only root has the field
end
~~~

### Attachment flow

`node.parent = X` is a valid Trivet operation — it doesn't just set a field, it goes through Trivet's `__newindex` on the Node metatable and runs the full attach sequence.

**Flow for `child.parent = X`** (the parent setter):

1. Setter fires (via `__newindex` on the Node metatable).
2. Trivet check: `X.trivet.moves_prohibited` → raise if true.
3. Trivet check: `X.allow_new_children` → raise if false.
4. `X:before_attach(child)` → subclass hook fires; may raise.
5. Do the reparent: detach from old parent's `_children`, add to X's `_children`, update `child.parent` via `rawset`.

Both of these mutation patterns hit the same setter and go through the same check chain:

~~~
node.parent = other_node                    -- one-step
node.detach; node.parent = other_node       -- two-step (detach = parent = nil)
~~~

Under `moves_prohibited`, both fail at step 2 (setter → `moves_prohibited` → raise). Line 2 of the two-step never runs. Under a Trivet WITHOUT `moves_prohibited`, the flow proceeds through steps 3-5 — closed-parent check, subclass hook, reparent.

**Flow for `parent:create_child(args)`** (the fresh-node factory):

1. `trivet.new_node_class(args)` picks the class.
2. `Class.new(args)` creates the child.
3. Trivet check: `parent.allow_new_children` → raise if false.
4. `parent:before_attach(child)` → subclass hook fires; may raise.
5. Attach: add to `parent._children`, set `child.parent = parent` via `rawset`.

Step 5's `rawset` is important: it bypasses `__newindex` (and the `moves_prohibited` check that lives there). Otherwise `create_child` couldn't work on a `moves_prohibited` tree, and there'd be no way to build the tree in the first place.

No per-node "has-been-attached" flag anywhere in this. Under `moves_prohibited`, the setter *always* refuses user-code parent mutations — because the only way a node exists in the tree is to have been born there via `create_child` (which sets parent via `rawset`), the setter's job is intercepting *moves* by definition.

### Detached subtrees are read-only

Under "every tree has a Trivet," a subtree that gets detached from its tree becomes a root without a Trivet. This happens on `remove()` in a **normal** (non-`moves_prohibited`) tree — under `moves_prohibited`, `remove()` cascade-deletes instead, so detached-but-alive isn't a state that arises there.

For the detached root: `_trivet` is nil; walking `.trivet` from any node in the detached subtree returns nil.

**Reads still work.** The detached subtree can be iterated with `descendants()`, traversed with `walk()`, queried for `.parent`, `.children`, `.depth`, structural predicates, etc. All the introspection surface functions normally — the subtree is a valid Trivet tree structurally; it just doesn't have a Trivet on top.

**Mutations raise.** Any operation that would change the subtree's structure — `create_child`, `insert_child`, the parent setter (`node.parent = X`), `move_to`, `move_before`, `move_after`, `remove` — checks `node.trivet` first and raises a `trivet_no_trivet: ...`-style error when it's nil. The detached subtree is effectively frozen: a read-only snapshot until it's garbage-collected.

Consequence: there's no path to reattach a detached subtree to another tree. Once detached, it's inspection-only.

### Trade-off: no manual attach of existing nodes

Existing nodes can't be manually attached to a tree — under any Trivet configuration. Under `moves_prohibited`, the parent setter refuses. Under normal Trivet, detached subtrees are read-only (see § Detached subtrees are read-only above), so the "detach here, attach there" pattern isn't available. All construction happens in place via `create_child` on a live parent.

That means the pattern "build a subtree offline as a standalone unit, then splice it into the target tree" isn't supported. Some scenarios would benefit from it; deferring per YAGNI.

### Applied: the roles tree

Under the full design, `state.roles` is a **RolesTrivet** (Trivet subclass) whose root is a **Role** (Node subclass). Boot flow:

1. `local roles = RolesTrivet.new(engine_role_args)` — constructs the RolesTrivet. Its constructor:
   - Instantiates a Role from the given args (via `Role.new(args)`).
   - Wraps it as the root of a new tree.
   - Sets `roles.new_node_class = Role` (so all children are Roles too).
   - Sets `roles.root_locked = true` and `roles.moves_prohibited = true` — both permanent from boot.
2. `roles.root:create_child(user_role_args)` — add user as engine's only child. The flow runs: `Role.new(user_role_args)` creates the child; `Role:before_attach(child)` type-checks that it's a Role (passes); attach proceeds via `rawset` despite `moves_prohibited`.
3. `roles.root.allow_new_children = false` — engine will never accept more children.

Result: `state.roles` is the RolesTrivet; the engine role's node is its permanent root; user is engine's only child; loaded-library roles etc. hang off user (or its descendants) as they arrive. Every child added is type-checked as a Role via `before_attach`. Anything in the tree can be `remove()`'d (cascade-deleted) but never moved.

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
- **Serialization** — MVM snapshots include the role tree; MVM walks the tree with `node:descendants()` (or its own recursive walk) and produces its snapshot format. Trivet doesn't own the format.

### Which operations roles don't use

- **Reparenting** — roles never move once placed.
- **Sibling order** — Trivet preserves child insertion order (see the [structural invariants](#structural-invariants) above), but role management doesn't rely on that: siblings of a role are unordered from the security-model perspective. If two roles share a parent, neither "comes before" the other in any meaningful sense.

None of these unused features cost roles anything — Trivet just doesn't call them.
