# Trivet

~~~json
{"vibecode": {
	"doc": "trivet",
	"role": "spec for puck.uno/trivet, a generic tree library for Caspian with node/child_set/document classes; ported from the Ruby Trivet gem and used wherever the framework deals with trees",
	"key_concepts": ["tree_library", "trivet_node", "trivet_child_set",
		"trivet_document", "parent_pointer_maintenance", "ruby_port"]
}}
~~~

`puck.uno/trivet` — a generic tree library for Caspian. Provides
hierarchical node structures with parent/child relationships,
traversal, query, and mutation. Ported from the Ruby Trivet gem.

Used wherever the framework deals with trees: Uma (HTML documents — spec currently in [ideas/uma/](../../../ideas/uma/uma.md), pending promotion to canonical),
configuration trees, Bryton test trees, possibly AST manipulation,
and any developer-level use case that benefits from a generic tree
abstraction.

---

<a id="status"></a>
## Status

Trivet is in development. The Ruby Trivet has been in use since 2020;
the design here is the Caspian adaptation. The semantics carry
over directly; method naming follows Caspian conventions.

---

<a id="examples"></a>
## Examples

~~~json
{"vibecode": {
	"section": "examples",
	"basis": "operates_on_the_food_spices_tree_from_construction",
	"covers": ["traverse", "find_via_traverse", "rehome"]
}}
~~~

These snippets build a small tree and exercise the basics.
The find and move examples reuse `$food` from the build above.

<a id="example-walk-the-tree"></a>
### Walk the tree

```caspian
$food = %['puck.uno/trivet/node'].new('food')

$food.node('spices') do($spices)
    $spices.node('paprika')

    $spices.node('pepper') do($pepper)
        $pepper.node('java')
        $pepper.node('matico')
        $pepper.node('cubeb')
    end
end

$food.node('fruit') do($fruit)
    $fruit.node('red') do($red)
        $red.node('cherry')
        $red.node('apple')
    end
end

$food.traverse(self: true) do($node)
    %stdout.write('  ' * $node.depth + $node.id + '\n')
end
```

Output:

```
food
  spices
    paprika
    pepper
      java
      matico
      cubeb
  fruit
    red
      cherry
      apple
```

<a id="example-find-a-node"></a>
### Find a node

[Query](#query) is the higher-level finder but requires a
subclass that defines `match?`. For bare nodes, `traverse` with
a control object captures the first hit and stops:

```caspian
$pepper = null

$food.traverse(self: true) do($node, $ctl)
    if $node.id == 'pepper'
        $pepper = $node
        $ctl.stop
    end
end
```

<a id="example-move-a-subtree"></a>
### Move a subtree

```caspian
$fruit = null
$food.traverse(self: true) do($node, $ctl)
    if $node.id == 'fruit'
        $fruit = $node
        $ctl.stop
    end
end

$pepper.rehome($fruit)
```

After the rehome, `pepper` (and its descendants `java`, `matico`,
`cubeb`) live under `fruit` rather than `spices`. Cycle and
id-uniqueness checks both run as part of `rehome` — see
[rehome — the One True move](#rehome-the-one-true-move).

---

<a id="core-classes"></a>
## Core classes

Three classes form the Trivet surface:

- **`puck.uno/trivet/node`** — a single node in a tree. Has an
  optional id, a parent reference, and a children collection.
  All node methods live here.
- **`puck.uno/trivet/child_set`** — a thin **subclass of Array**
  that holds a node's children. It inherits everything from
  Array (length, indexing, `.find`, `.elements`, iteration, etc.)
  and overrides the mutation methods (`push`, `pop`, `shift`,
  `unshift`, `insert`, `delete_at`) to keep parent pointers in
  sync. Each override calls super to do the array work and then
  updates the affected child's `parent` accordingly.
- **`puck.uno/trivet/document`** — a separate, non-node class
  that holds a tree's root. **Not** a node itself, not in the
  tree. Used to attach metadata to a tree, or to have a stable
  outside-of-tree handle when the root might be replaced. Always
  optional — many trees never need one.

Because `child_set` is an Array subclass, **every standard array
operation works on `$node.children`** — and any mutation path
(direct `.push`, Element-based `.delete`, rehome internals)
goes through the overrides and maintains tree invariants.

Trees can hold **any object as a child**, not just trivet nodes.
Strings, hashes, custom classes — anything goes into a
child_set. Trivet-specific methods (traverse, query) walk only
into nodes; non-node children are leaves.

---

<a id="construction"></a>
## Construction

```caspian
$food = %['puck.uno/trivet/node'].new('food')

$food.node('spices') do($spices)
    $spices.node('paprika')

    $spices.node('pepper') do($pepper)
        $pepper.node('java')
        $pepper.node('matico')
        $pepper.node('cubeb')
    end
end

$food.node('fruit') do($fruit)
    $fruit.node('red') do($red)
        $red.node('cherry')
        $red.node('apple')
    end
end
```

`$node.node(id) do($child); ...; end` is the builder DSL — creates
a child node with the given id, runs the block with the child as
the parameter, returns the child node. Without a block, just
creates and returns the child.

---

<a id="node-ids"></a>
## Node IDs

Every node has an `id` slot, null by default.

```caspian
$node.id              # current id, or null
$node.id = 'food'     # set
```

**Within a tree, an id belongs to at most one node.** Assigning
an id that's already taken removes it from the previous owner
(its id becomes null) and emits a `duplicate_node_id` warning
via `%chain.warn` — see
[jasmine/caspian.md § Automatic warning capture](../jasmine/caspian.md#automatic-warning-capture).
The assignment isn't blocked; the new owner gets the id.

Uniqueness is per-tree: nodes in different trees can share ids
freely. A node with no parent is its own one-node tree.

<a id="subclass-override"></a>
### Subclass override

Subclasses that mirror the id to other state — Uma's element
class syncs it to the HTML `id` attribute, for example —
override the getter/setter and call `super`:

```caspian
class
    inherits 'puck.uno/trivet/node'

    function id=($new_id) do
        @attributes['id'] = $new_id
        super($new_id)    # cascade to base class for uniqueness logic
    end

    function id do
        return @attributes['id']
    end
end
```

The base class handles tree-walking and warning emission; the
subclass handles where the id actually lives.

---

<a id="relationships"></a>
## Relationships

| Method | Returns | Description |
|---|---|---|
| `$node.parent` | Node or null | The parent node (null if root) |
| `$node.rehome($other, index: ...)` | — | **The canonical move.** Reparent `$node` under `$other` at the given position (default last). All sugar methods delegate to this. |
| `$node.parent = $other` | — | Sugar — `$node.rehome($other)` |
| `$node.set_parent($other, index: ...)` | — | Sugar — `$node.rehome($other, index: ...)` |
| `$node.root` | Node | The topmost ancestor (or self if no parent) |
| `$node.root?` | Boolean | True if `$node` is the topmost (no parent) |
| `$node.ancestors` | Array of nodes | From immediate parent up to root |
| `$node.heritage` | Array of nodes | Self plus ancestors (root last) |
| `$node.depth` | Integer | Distance from root (0 = root) |
| `$node.previous_sibling` | Node or null | The sibling immediately before this one |
| `$node.next_sibling` | Node or null | The sibling immediately after this one |
| `$node.index` | Integer or null | Position in parent's children array (null if no parent) |

<a id="rehome-the-one-true-move"></a>
### `rehome` — the One True move

Every reparenting operation funnels through a single canonical
method: **`$node.rehome($new_parent, index: ...)`**. This is
the One True way to move a node; everything else is sugar that
delegates to it.

```caspian
$paprika.rehome($pepper)              # append paprika as a child of pepper
$paprika.rehome($pepper, index: 0)    # insert at position 0
$paprika.rehome($pepper, index: 'first')
$paprika.rehome($pepper, index: 'last')
```

`rehome` does, in order:

1. **Validate.** Cycle check (raise `puck.uno/trivet/error/cycle`
   if the move would create a loop). `allow_child?` check on the
   new parent (raise / call `on_prohibited_child`). Any other
   pre-mutation guards.
2. **Detach** the node from its old parent's children array, if any.
3. **Attach** the node to the new parent's children array at the
   requested position.
4. **Update** the node's parent pointer.
5. **Housekeeping** — id-uniqueness check (which may emit a
   warning), audit hooks, etc.

The four mutation steps (2–5) only happen if validation passes;
if any check raises, the tree is unchanged.

Setting `index: 'last'` is the default. Same-parent rehome is
valid — `$paprika.rehome($paprika.parent, index: 0)` moves
paprika to the front of its existing parent's children.

<a id="sugar-for-rehome"></a>
### Sugar for rehome

The public API exposes friendlier names that all delegate to
`rehome`:

| Sugar | Equivalent rehome call |
|---|---|
| `$node.parent = $other` | `$node.rehome($other)` (index: last) |
| `$node.set_parent($other, index: ...)` | `$node.rehome($other, index: ...)` |
| `$other.add($node)` | `$node.rehome($other)` (index: last) |
| `$other.prepend($node)` | `$node.rehome($other, index: 'first')` |
| `$other.insert(i, $node)` | `$node.rehome($other, index: i)` |

The sugar names exist for readability — `$pepper.add($paprika)`
reads as "pepper gains a child" rather than the more clinical
"paprika changes home." Same underlying operation either way.

<a id="what-rehome-doesnt-do"></a>
### What rehome doesn't do

- **`$node.unlink`** orphans a node (no new parent). Not a rehome
  call; rehome requires a destination parent.
- **`$node.replace($other)`** is structurally distinct — it
  removes one node and inserts another at the same position;
  it's a rehome of `$other` plus an unlink of `$node`.

(Direct array operations on `$node.children` — `push`, `<<`,
`insert`, etc. — *do* go through rehome. The `child_set` class
overrides every mutation method to delegate to it, so the
`Modifying` section below covers them all.)

<a id="cycle-prevention"></a>
### Cycle prevention

A tree, by definition, has no cycles. Any operation that would
make a node its own descendant — directly or transitively —
**raises `puck.uno/trivet/error/cycle`**. This applies to every
reparenting path — meaning every `rehome` call, and therefore
every sugar method that delegates to it (`parent=`,
`set_parent`, `add`, `prepend`, `insert`, etc.).

Examples:

- `$node.rehome($descendant)` — would make `$node` a descendant
  of itself.
- `$node.parent = $descendant` — same, via sugar.
- `$ancestor.add($node)` where `$ancestor` is already inside
  `$node`'s subtree — same shape.

The check runs as step 1 of `rehome` (before any state change).
If the operation would cycle, the tree stays unchanged and the
exception unwinds the caller's stack. The exception carries
enough detail (the attempted parent, the attempted child) for a
`catch` block to build a useful error message.

This is non-negotiable: it's not a "nanny" feature with a
silenceable warning. Cycles are categorically wrong in a tree;
the operation always fails.

---

<a id="children"></a>
## Children

`$node.children` is a `child_set` — a thin subclass of Array.
All standard array operations work directly, plus the mutation
methods are overridden to keep parent pointers in sync.

<a id="reading"></a>
### Reading

```caspian
$pepper.children                          # the child_set (array subclass)
$pepper.children.length                   # how many
$pepper.children[0]                       # first child
$pepper.children.find('paprika')          # find children matching (per match?)
$pepper.children.find_first('paprika')    # first match
$pepper.children.elements                 # array of Element objects (with .move_*, .delete)
```

All array reading and iteration works because child_set inherits
from Array. See
[arrays.md § Elements](../../built-in-classes/arrays.md#elements)
for the `.elements` accessor and the Element object's
`.move_*`/`.delete` API.

<a id="modifying"></a>
### Modifying

Every mutation path is safe — child_set's overrides on `push`,
`pop`, `shift`, `unshift`, `insert`, and `delete_at` maintain
the parent pointer automatically. So whether you go through the
sugar methods, direct array calls, or Element-based movement,
the tree stays consistent.

The overrides split into two families:

- **Adding** (`push`, `unshift`, `insert`, `<<`) delegates to
  `rehome` on the added child. Full dance: cycle check,
  `allow_child?`, auto-detach from any current parent, attach,
  update pointer.
- **Removing** (`shift`, `pop`, `delete_at`) delegates to
  `unlink` on the removed child. Sets parent to null, removes
  from the array, returns the (now-orphaned) child.

Composition is safe: a remove followed by an add works
correctly because each step is its own canonical operation.
Example — moving the first child of one node to the end of
another:

```caspian
$apple.children << $orange.children.shift
```

Two operations:

1. `$orange.children.shift` — removes orange's first child and
   orphans it (calls `unlink`), returns the orphaned child.
2. `$apple.children << <that-child>` — appends to apple's
   children (calls `rehome($apple)`); the rehome sees the child
   is already parentless and just has to attach.

Tree stays consistent at every point.

**Node-level sugar (preferred for readability):**

```caspian
$pepper.add($paprika)                  # delegates to $paprika.rehome($pepper)
$pepper.prepend($paprika)              # delegates to $paprika.rehome($pepper, index: 'first')
$pepper.insert(2, $paprika)            # delegates to $paprika.rehome($pepper, index: 2)
```

**Direct array calls on child_set:**

```caspian
$pepper.children.push($paprika)        # works correctly — override sets parent
$pepper.children.unshift($paprika)     # works
$pepper.children.insert(2, $paprika)   # works
$pepper.children.pop                   # works — popped child's parent set to null
$pepper.children.delete_at(0)          # works
```

**Element-based movement and deletion:**

```caspian
$pepper.children.elements[0].move_to_start    # works
$pepper.children.elements[0].delete           # works — Element delete goes through child_set's override
```

The validation logic (cycle check, `allow_child?`, auto-detach
from old parent) is still part of the rehome path; the
overridden array methods route through it. So even direct
`$pepper.children.push($paprika)` does the full safety dance
before mutating.

**Other convenience methods on node:**

```caspian
$node.have_object?($child)             # predicate: is this object a direct child?
$node.node_by_id('paprika')            # find a child node by id (depth-first into subtree)
```

---

<a id="traversal"></a>
## Traversal

```caspian
$food.traverse do($node)
    %stdout.write('  ' * $node.depth + $node.id + '\n')
end
```

Depth-first walk over all nodes in the tree. The block receives
each node. Non-node children (strings, etc.) are visited too
unless the developer filters them.

<a id="including-the-root"></a>
### Including the root

By default `traverse` skips the root and starts with its
children. Pass `self: true` to include the root:

```caspian
$food.traverse(self: true) do($node)
    ...
end
```

<a id="pruning-a-branch"></a>
### Pruning a branch

A control object as a second block parameter lets the traversal
skip a subtree:

```caspian
$food.traverse(self: true) do($node, $ctl)
    process($node)
    if $node.id == 'spices'
        $ctl.prune   # don't descend into spices's children
    end
end
```

The block can also call `$ctl.stop` to halt traversal entirely.

<a id="walking-only-node-objects"></a>
### Walking only node objects

`traverse` visits any child object; `traverse_nodes` visits only
those that are actual nodes (skipping strings, hashes, etc.).

---

<a id="query"></a>
## Query

`query` finds nodes matching a developer-supplied predicate.
The predicate is the `match?` method on the node class.

**The base `trivet/node` returns null from `match?` every time** —
the base class makes no assumption about what "match" means. To
use query on a tree of bare trivet nodes, subclass and override
`match?`:

```caspian
class
    inherits 'puck.uno/trivet/node'

    function match?($qobj) do
        # return truthy if this node matches the query
        return @id and @id.match($qobj)
    end
end
```

`match?` follows the [`?` suffix convention](../../caspian.md#the-suffix):
truthy on match, falsey on no-match, never throws. Default
impl's null is "I have no opinion on matching"; subclass
overrides supply real semantics.

Then:

```caspian
$food.query('o') do($node)
    %stdout.write($node.id + '\n')
end
```

Returns all matching nodes via the block. Without a block,
returns an array.

<a id="stopping-descent-at-matches"></a>
### Stopping descent at matches

By default, `query` keeps descending into a node's children
even when the node itself matched. Pass `recurse: 'until_match'`
to stop at the first match in each branch:

```caspian
$food.query('e', recurse: 'until_match') do($node)
    ...
end
```

<a id="query_first"></a>
### `query_first`

Shorthand for "give me just the first matching node, or null":

```caspian
$first = $food.query_first('paprika')
```

---

<a id="mutation"></a>
## Mutation

Most reparenting goes through [rehome](#rehome-the-one-true-move)
and its sugar. A few additional node-level methods:

| Method | Description |
|---|---|
| `$node.replace($other)` | Replace `$node` in its parent with `$other` (rehome `$other` into the position, then unlink `$node`). `$node` becomes parentless. |
| `$node.unlink` | Remove `$node` from its parent (no new parent). Returns `$node`. |
| `$node.unwrap` | Remove `$node` but keep its children — rehome them to `$node`'s former parent at `$node`'s position. |
| `$node.id = 'new-id'` | Rename the node (triggers tree-wide id uniqueness check). |

The Ruby `move_child` method is gone — use `$child.rehome($parent, index: ...)`
instead. Same operation, expressed from the child's perspective.

---

<a id="child-validation"></a>
## Child validation

A node can constrain what kinds of children it accepts by
overriding `allow_child?`:

```caspian
class
    inherits 'puck.uno/trivet/node'

    function allow_child?($candidate) do
        return $candidate.object.isa?('puck.uno/trivet/node')
    end
end
```

If a forbidden child is added, `on_prohibited_child` runs (by
default raises; can be overridden to allow other recovery).

`$node.suspend_child_rules do ... end` temporarily disables the
checks for a block — useful when building a known-valid subtree
programmatically.

`class.no_children` is a class-level helper that declares a
node class as a leaf (`allow_child?` returns false for
everything).

`$node.child_class` lets the node specify what class new
children should be when created via `$node.node(id)`. Default
is `puck.uno/trivet/node`; subclasses override to make their
`node` builder produce the same subclass.

---

<a id="output"></a>
## Output

| Method | Returns |
|---|---|
| `$node.to_s` | Short string form (typically the id) |
| `$node.to_debug` | Verbose debug form |
| `$node.to_tree(indent: '  ')` | Multi-line indented dump of the subtree |

`to_tree` is the standard pretty-printer for trees:

```caspian
$food.to_tree
->
food
  spices
    paprika
    pepper
      java
      matico
      cubeb
  fruit
    red
      cherry
      apple
```

---

<a id="document"></a>
## Document

`puck.uno/trivet/document` is **not** a node. It is a separate
container class that holds a tree's root and exists outside the
tree's parent/child structure.

```caspian
$doc = %['puck.uno/trivet/document'].new
$doc.root = $food         # the food tree's root is now held by $doc
$food.parent              # null — root has no Node parent
$food.document            # returns $doc
```

<a id="document-vs-root"></a>
### Document vs root

| Concept | Class | Meaning |
|---|---|---|
| **Root** | `trivet/node` | The topmost Node in a tree — the one with no Node parent. A real node, fully part of the tree. Always exists wherever there's a node. |
| **Document** | `trivet/document` | An outside container that holds a tree's root. Not a node, not in the tree. Optional. |

Walking up the parent chain of any node leads eventually to the
root (a Node). If the root is held by a Document, that
Document is "above" the root structurally — `$root.document`
returns it — but the Document is not the root and is not in the
tree.

<a id="why-a-document-is-useful"></a>
### Why a Document is useful

Most trees never need one. Reach for a Document when:

- **The root might be replaced.** Code that holds a reference to
  the document keeps a stable handle even as `$doc.root = $other`
  swaps in a different root.
- **The tree needs metadata that isn't a node.** Document has a
  `misc` hash for storing tree-level attributes (file path,
  parse timestamp, source URL, etc.) without polluting any node.
- **An identity exists for the tree as a whole**, separate from
  any of its nodes — useful for queries like "is this node in
  the same tree as that one?" (`$a.document == $b.document`).

For everyday "I have a root node and I'm building it out," no
Document is needed.

<a id="document-api"></a>
### Document API

| Method | Returns | Description |
|---|---|---|
| `$doc.root` | Node or null | The root Node held by this document |
| `$doc.root = $node` | — | Set the root (replaces any current root, which becomes parentless) |
| `$doc.misc` | Hash | Mutable hash for tree-level metadata |
| `$doc.node_by_id($id)` | Node or null | Convenience — delegates to `$doc.root.node_by_id($id)` |
| `$doc.to_tree(...)` | String | Convenience — delegates to `$doc.root.to_tree(...)` |

<a id="nodedocument-from-inside-the-tree"></a>
### `$node.document` from inside the tree

A node finds the Document holding its tree (if any) via
`$node.document`:

- Walks up the parent chain to the root.
- Returns the Document the root is held by, or null if the root
  has no Document.

If a node isn't in a tree, or its tree has no Document, `$node.document`
returns null.

---

<a id="subclassing"></a>
## Subclassing

The expected use pattern. Most consumers of Trivet subclass
`trivet/node`:

- Uma's element class extends node, overrides `match?` for CSS
  selector matching, overrides `allow_child?` to enforce
  schema-driven content models, overrides `child_class` to make
  `.node` build elements (not bare nodes).
- A Bryton xeme node could extend node to carry result-state
  metadata.
- An AST node could extend node to carry source-location info.

The Trivet machinery (traverse, query, child operations) works
unchanged on any subclass.

---

<a id="bucket-discipline-the-uns-slot"></a>
## Bucket discipline: the `uns` slot

**Buckets are always hashes.** That fixed shape is what makes the
discipline below possible.

Trivet's node class is designed to be **added to any object** —
strings (for HTML text nodes), hashes, custom classes, anything.
That means the bucket Trivet shares with the host object might
already contain unrelated state, and the rest of the host's
class stack might write to that bucket too.

To avoid collisions, Trivet keeps its state under a **single
reserved bucket key**: `uns`. This is a Puck-wide convention
(not specific to Trivet) — if a bucket contains an `uns` key,
it's understood to hold a sub-hash organized by UNS strings.
Each UNS-keyed entry inside is its own piece of state.

```caspian
%bucket = {
    real_property_1: ...,           # host class's own state
    real_property_2: ...,
    uns: {
        'puck.uno/trivet/node': {parent: ..., children: ..., id: ...},
        'puck.uno/uma/text':    {...},   # if also a Uma text node
        ...
    }
}
```

**The convention.** Trivet and any other "added to anything"
class namespaces its state under `uns.<class-UNS>`. Host classes
treat the bucket key `uns` as off-limits — they don't read it,
don't write it, don't care what's in it.

One reserved key is much easier to remember and audit than
"don't use any bucket key that looks like a class UNS." Host
classes get the rest of the bucket for their own use; mix-in
platters get the `uns` slot.

Bucket keys can be anything the class designer wants; `uns` is
simply reserved by convention.

This is a discipline rule, not enforcement. The caspian runtime
treats the bucket as a shared hash; the `uns` convention is
just a way for multiple unrelated classes to share an object
without stepping on each other.

---

<a id="mental-model"></a>
## Mental model

A Trivet tree is a recursive structure where every interior
node is a `trivet/node` (or subclass), and leaves can be
anything. The library provides walks, queries, mutations, and
parent/child plumbing; everything else is the developer's
domain.

The class is intentionally **generic** — no HTML knowledge, no
schema enforcement, no rendering. Those live in subclasses or
in libraries built on top (Uma being the canonical example).

---

<a id="open-questions"></a>
## Open questions

- **Iteration order in queries**: depth-first vs breadth-first.
  Ruby version is depth-first.
- **Tree validation**: should there be a `$tree.validate` that
  checks all nodes against their `allow_child?` constraints,
  for catching corruption?
- **Serialization**: a generic to-JSON / from-JSON for trees
  that don't require a custom serializer? Probably useful but
  needs care around non-node children.
