# Set up frame 0

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage_set_up_frame_0",
	"role": "canonical spec for the third and final sub-step of Stage — inserting the top-level frame into the frames table so the stack has an entry ready to be walked when execution begins. Frame 0's shape (callable? class?) is open design work.",
	"status": "V1 spec — brief; frame 0's shape is open design work"
}}
~~~

The third and final sub-step of [Stage](https://www.puck.uno/requirements/bootstrap/stage/). After the CaspM is in the MVM, the stack is empty. This sub-step pushes the top-level frame — the frame that represents "the entry program is about to run."

**The insert:**

- `process_pk` — from the current process (looked up in `current_process`; populated during Initialize VM).
- `idx` — 0 (this is the first frame; the stack starts here).
- `type` — `'function_call'` (currently the only valid frame type).
- `lexical_parent_pk` — null (there is no enclosing scope; frame 0 is the root).

**Open design question: does frame 0 have a callable?**

- **If yes** — some synthesized "top-level program" callable object goes in `method_pk`, and probably a matching class in `method_class_pk`. Simplifies dispatch (frame 0 looks like every other frame), at the cost of forcing the engine to synthesize a callable it will never dispatch through a normal call site.
- **If no** — `method_pk` / `method_class_pk` stay null. Frame 0 is a special-shape frame; dispatch code has to know about the null case.

After this sub-step returns, the MVM holds a seeded runtime state store, a loaded program, and a stack with one frame ready to be walked. Bootstrap is done; execution walks frame 0 as its first act.
