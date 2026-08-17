# Vibecode fields

<span class="tag">vibecode-fields</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_vibecode_fields",
	"role": "canonical spec of the fields conventionally used in vibecode blocks across the ecoverse docs. Vibecode is JSON-shaped metadata inside `~~~vibecode ~~~` fences, meant primarily for AI readers (the docs are written for AI implementation per requirements/index.md § Written for an AI implementer). This page enumerates the current conventional fields, when to use each, and the rule for adding new ones. Ad-hoc fields in specific docs are still fine when they carry meaning; formalizing a field here happens when the field is broadly useful across many docs.",
	"status": "spec — conventional fields settled at V1 (doc, role, audience, status, related); `related` uses tag references per tag:tag-index; further structured fields (candidate: `meta` wrapper, `tags` list, etc.) deferred until real cross-doc needs surface",
	"audience": "doc authors adding vibecode blocks; AI readers parsing vibecode across docs",
	"related": ["tag-index"]
}}
~~~

## Conventional fields

Every field is optional. Include the ones that carry meaning; omit the rest.

### `doc`

**Type:** string (identifier, snake_case).

**Meaning:** the doc's canonical identifier. Used by tooling and cross-doc queries to name a specific doc without depending on its path (which can change).

**When to use:** always, in the top-level vibecode block of every doc.

**Example:**

~~~
"doc": "requirements_syntax_pipes"
~~~

### `role`

**Type:** string (prose).

**Meaning:** what this doc owns. Answers "is this the canonical doc for X, or is it referencing X?" Also carries the reasoning, nuance, and design rationale that structure can't easily hold.

**When to use:** always, in the top-level vibecode block. Prose is fine — long prose is fine — the AI reads the whole field.

**Example:**

~~~
"role": "syntax spec for Caspian's pipe operators. Two operators: `|` (basic pipe) and `|&` (null-safe pipe — sticky through the rest of the chain). Two RHS forms: `&fn` / `$obj.method` (piped value fills first positional argument slot) and `.method()` (piped value BECOMES the receiver of a method call). Same shape as Elixir's `|>` ..."
~~~

### `audience`

**Type:** string (prose, semicolon-separated audience descriptions).

**Meaning:** who reads this doc. Helps a reader assess whether the doc is relevant to them and at what level of depth.

**When to use:** most docs; omit when audience is universally "anyone touching the ecoverse."

**Example:**

~~~
"audience": "developers writing Caspian; tooling authors (parsers, formatters, syntax highlighters, LSPs) implementing the pipe operators"
~~~

### `status`

**Type:** string (bounded vocabulary).

**Meaning:** the doc's current state in the spec lifecycle. Bounded values so cross-doc queries can filter by status.

**Values (as they've been used so far):**

- `spec` — settled, ready to implement against.
- `draft` — provisional, may change.
- `stub` — placeholder for a spec that hasn't been written yet.
- `archived` — no longer authoritative; kept for historical context.

**When to use:** most docs that have progressed past initial creation.

**Example:**

~~~
"status": "spec — basic `|` and null-safe `|&` operators settled; both RHS forms spec'd; ..."
~~~

### `related`

**Type:** array of strings (tag references, optionally with `#anchor` suffix).

**Meaning:** other docs this doc references or is related to. Uses [tags](tag:tag-index) — stable identifiers that survive doc renames.

**When to use:** any doc that meaningfully references concepts spec'd elsewhere.

**Example:**

~~~
"related": ["grants", "nanny-methods#speccing-the-grant-system", "plumbing"]
~~~

**How references resolve:** `grants` looks up in the [tag index](tag:tag-index); `nanny-methods#speccing-the-grant-system` resolves to the nanny-methods URL with the section anchor appended.

**Not to be confused with:** the prose `## Related` section at the bottom of many docs. That section is human-facing with descriptions per link. The vibecode `related` field is metadata for AI cross-doc queries. Both can coexist.

## Adding a new conventional field

Fields that appear only in one or a few docs are **ad-hoc** — fine to include, don't need a spec here. Formalize a field on this page when:

- Multiple unrelated docs would benefit from having it.
- AI readers would want to query across docs on the field's value.
- A bounded vocabulary would help (like `status`) rather than each doc inventing its own values.

Adding a new conventional field: add its spec here first (name, type, meaning, when-to-use, example), then start using it in docs.

## Not (yet) in the conventional set

The following have come up in design conversations but aren't spec'd yet — use them ad-hoc if useful; formalize when the shape settles:

- **`meta` wrapper** — a nested object grouping structured metadata (as opposed to prose fields). Considered but deferred; current top-level fields are working. May land when there are more structured fields than fit flat at the top level.
- **`tags` list** — a list of topics this doc is about (as distinct from `related`, which is docs this doc references). Deferred until a real cross-doc need surfaces.
- **`landing_concepts` or similar** — what concepts a doc introduces vs. references. Interesting idea, no concrete need yet.

Neither of these blocks anything; ad-hoc usage in specific docs is fine while the shape settles.
