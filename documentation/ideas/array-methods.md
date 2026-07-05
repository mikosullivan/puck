# Idea: additional array methods

~~~vibecode
{"vibecode": {
	"doc": "array_methods_brainstorm",
	"role": "brainstorm — record of the set-operations design work that led up to the array spec's Set operations section. Kept for historical context and to document rejected candidates with rationale. All decisions have been implemented in the array spec; nothing on this page is still under consideration.",
	"status": "resolved — all decisions implemented in the array spec; kept as a design record",
	"references": ["https://ruby-doc.org/core/Array.html", "https://docs.python.org/3/library/stdtypes.html#lists", "https://docs.python.org/3/library/functions.html"]
}}
~~~

**All decisions on this page have been implemented in the [array spec's Set operations section](https://puck.uno/documentation/requirements/caspian/built-in-classes/array#set-operations)** and its Excluded methods table. This doc is kept as a design record of the accept/reject decisions and their rationale; nothing here is still under consideration.

## Background — always-in-effect Caspian conventions

Not decisions; existing language conventions that shape every entry below.

- **The `!` convention** — mutating methods get `!` when a non-mutating counterpart exists.
- **The truthy/falsy model** — only `null` and `false` are falsy.
- Ruby-style question-mark predicates and bang mutators are compatible with Caspian conventions.

## Accepted

Ready to move into the array spec when Miko says go.

### Method surface

**Combination operations** (return an array):

| Symbol | Method | Description |
|---|---|---|
| `$a ∪ $b` | `$a.union($b)` | All elements from either, duplicates removed. |
| `$a ∩ $b` | `$a.intersection($b)` | Only elements present in both. |
| [none] | `$a.difference($b)` | Elements of `$a` not in `$b`. English form only (no symbol — see design principles below). |
| `$a △ $b` | `$a.symmetric_difference($b)` | Elements in exactly one of `$a` or `$b` — the two-sided "what's not shared." |

**Predicates** (return a boolean):

| Symbol | Method | Description |
|---|---|---|
| `$a ⊂ $b` | `$a.proper_subset_of?($b)` | True if every element of `$a` is in `$b` AND `$b` has at least one element not in `$a`. |
| `$a ⊆ $b` | `$a.subset_of?($b)` | True if every element of `$a` is in `$b`. Equal arrays satisfy this. |
| [none] | `$a.disjoint?($b)` | True if `$a` and `$b` share no elements. English form only (no standard Unicode symbol exists). |
| `$a.∅?` | `$a.empty?` | True if `$a` has no elements. Already in the array spec's [Query and predicates table](https://puck.uno/documentation/requirements/caspian/built-in-classes/array#query-and-predicates); repeated here because empty-set is a natural fit for the section. |
| `$a.∃?` | `$a.any?` | True if `$a` has at least one element. Complement of `.empty?`. Already in the array spec's [Query and predicates table](https://puck.uno/documentation/requirements/caspian/built-in-classes/array#query-and-predicates) with the `∃?` alias added. |

### Design principles

- **Dual naming** (Unicode + English). Every set operation gets both a Unicode mathematical symbol and a plain-English method name; both compile to the same call. Reads well in math-heavy code (`if $selected ⊆ $allowed ...`) and prose-y code (`if $selected.subset_of?($allowed) ...`).
- **English aliases for Unicode operators.** `⊂` → `proper_subset_of?`, `⊆` → `subset_of?`, `∪` → `union`, etc.
- **Symbol forms are no-dot with a space, parens optional.** `$a ⊂ $b` — no `.` separator, space between receiver and symbol, parens optional (Caspian's general rule for any method call). The English forms keep the dot (`$a.subset_of?($b)`). See [no-dot-methods](https://puck.uno/documentation/ideas/no-dot-methods) for the general rule.
- **`.difference` gets no symbol form.** The mathematical `\` and Unicode `∖` both render identically to a backslash in most fonts; the visual clash isn't worth the symbol. English name only. Every other set operation has a visually distinctive symbol; difference is the outlier.

### Output ordering

Always return in left-array element order. The old spec's `ordered: true` kwarg is dropped.

- `union` returns `$a`'s elements in order followed by `$b`-only elements in `$b`'s order.
- `intersection` returns `$a`'s elements that are also in `$b`, in `$a`'s order.
- `difference` returns `$a`'s elements that aren't in `$b`, in `$a`'s order.
- `symmetric_difference` returns `$a`'s exclusive elements in `$a`'s order, followed by `$b`'s exclusive elements in `$b`'s order.

### Equality basis

Set operations compare elements with `==`. Caspian's `==` does a full recursive comparison of the structure — nested arrays and hashes are walked all the way down, and both must be in the same order to match. No `by:` kwarg for V1; the deferred idea for a key-projection kwarg lives at [set-operations-by-key](https://puck.uno/documentation/ideas/set-operations-by-key).

## Rejected

Will not land in the array spec. Some may move into the [array spec's Excluded methods table](https://puck.uno/documentation/requirements/caspian/built-in-classes/array#excluded-methods) when the Accepted set is implemented.

### Ruby-style operator forms

Ruby uses `|`, `&`, and `-` as set operators on Array. None are proposed for Caspian.

- **`|` for union.** Pipe character is reserved for the pipe operator in Caspian.
- **`&` for intersection.** The mathematical `∩` and named `.intersection` cover this cleanly. Adding a third form is friction, not clarity.
- **`-` for difference.** Same reason as `&`. `.difference` is enough.

(The `+` operator for `.import`, which is settled in the array spec, is a separate operation — array concatenation preserves duplicates and is distinct from set union.)

### Set-theory symbols not adopted

- **`⊃` (proper superset) and `⊇` (superset or equal).** Reversed-argument form covers these — `$a.⊃($b)` is the same as `$b.⊂($a)`, so adding both directions is duplicate surface.
- **`∖` (U+2216 SET MINUS) as the symbol for difference.** Renders identically to a backslash in most fonts; visual clash defeats the point of using a symbol. `.difference` is English-only.

### Binary element-containment operators

The old spec had `∈`/`in` and `∉`/`not_in` as binary operators sitting between the element and the collection (`5 in $arr`). Rejected — element containment stays with the already-settled `.includes?($x)` and `.excludes?($x)` methods on the array.

## Undecided

None. Every array-side decision is made; the brainstorm is ready to implement into the array spec.
