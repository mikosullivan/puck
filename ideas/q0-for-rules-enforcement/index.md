~~~vibecode
{"doc": "q0-for-rules-enforcement",
	"role": "Design placeholder for the CSS-analogy pattern: using ref key names (like `scopes`) as selectors for schema-level enforcement. Moved here from sprints/ — the sprint never got past a stub; keeping the design idea alive without pretending there's active work.",
	"status": "idea"}
~~~

# Q0 for rules enforcement

Placeholder for the CSS-analogy pattern that surfaced during the first-variable sprint:

Ref key names ("scopes") are doing selector work — schema triggers fire wherever the name appears in the graph, regardless of context. Two variants of the pattern showed up:

- **Broad selector** — enforce the rule anywhere the name appears (current form in first-variable).
- **Narrow selector** — enforce only when the parent is a specific kind of row (e.g., a frame's bucket).

Trade-offs to work through if this becomes active work:

- **Reservation semantics.** If the string name is reserved for one use forever, broad enforcement is fine. If it might get reused, broad enforcement blocks future flexibility.
- **Where the rule lives.** Column-level checks are hard-typed slots; name-selector rules live one step removed, keyed on runtime string comparison. The distinction affects debuggability and reuse.
- **View-based composition.** Views like `frame_buckets` could encapsulate the "narrow selector" test as a named concept, making triggers read at intent level.

Not implementing anything yet. When Miko says "back to Q0," this is where the design work lives.
