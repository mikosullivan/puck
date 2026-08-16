~~~vibecode
{"doc": "sprint-note", "sprint": "first-variable",
	"role": "Running list of small things to catch during eventual assimilation of first-variable's design into shipping. Not a full integration plan — this is the 'don't forget' file."}
~~~

# Integration notes

Loose list. Add entries as they surface; work through them when the sprint assimilates into shipping.

## Strip "popped-but-captured" from `frame.lua`

**File:** [src/engine/cvm/frame.lua](../../src/engine/cvm/frame.lua) — the phrase appears in the JSON `role` at line 4 and in the "Two runtime states" section at lines 31–38 of the module docstring.

Under this sprint's invariants — every frame has exactly one parent, frames are destroyed when finished — the "popped-but-captured" state doesn't happen. Closures capture the locals hash directly (see [closures.md](closures.md)); no frame gets kept alive past its execution.

Remove the two-state description; the docstring should just say the frame is an on-stack execution unit that's destroyed when done. No code change needed — nothing consumes the phrase.
