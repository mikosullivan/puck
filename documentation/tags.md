# Tag index

<span class="tag">tag-index</span>

~~~vibecode
{"vibecode": {
	"doc": "documentation_tags",
	"role": "dynamic index of every tag defined in the ecoverse. Tags are declared inline in the target doc via `<span class=\"tag\">NAME</span>` right after the heading whose scope they represent (H1 for whole-page tags, H2+ for section-scoped tags). Orlando's tag resolver greps documentation/ for markers; this page renders the current inventory via the `<!-- tag-list -->` directive. Duplicate tag definitions (the same NAME in two different docs) show up as an audit error with a `duplicate` badge — the resolver returns only the first source's URL and the second source's tag is dead.",
	"status": "spec — dynamic listing settled; audit tooling (surface duplicates as GitHub issues) still to be wired into the audit protocol",
	"audience": "doc authors adding cross-references; Orlando's tag-resolution service; anyone auditing tag consistency"
}}
~~~

Docs reference concepts via `[text](tag:name)` in markdown links or `puck.uno/tag/name` as a shareable HTTP URL. Orlando resolves both to the target listed below.

## Adding a tag

Put a marker right after the heading whose scope the tag represents:

~~~markdown
# My concept

<span class="tag">my-concept</span>
~~~

For section-scoped tags, put the marker after an H2 or deeper heading — the resolver will append the heading's anchor to the target URL automatically:

~~~markdown
## Some section

<span class="tag">some-section-tag</span>
~~~

**Uniqueness.** A tag name may appear in at most one doc. Two docs carrying the same `<span class="tag">NAME</span>` is an audit error — the listing below flags it, and the resolver picks the first match (making the second source's marker effectively dead).

**Naming.** Kebab-case: lowercase, hyphens between words, no punctuation.

## Table

<!-- tag-list -->
