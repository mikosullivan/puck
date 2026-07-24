# REPL

~~~vibecode
{"vibecode": {
	"doc": "idea_caspian_repl",
	"role": "note that an interactive REPL is a deferred-until-post-V1 host for Caspian — read-eval-print loop, like python at the shell or irb for Ruby. Not in V1 scope. This page tracks the idea so it doesn't get forgotten and so future host enumeration doesn't accidentally re-include it as a V1 example.",
	"status": "deferred — not in V1 scope"
}}
~~~

A **REPL** (read-eval-print loop) would be a host that runs Caspian interactively: read a line from the user → parse and evaluate it → print the result → loop. The REPL loop itself is the host; it loads the engine module, hands each typed expression to `engine.run()`, and prints what comes back.

## Why this isn't in V1

- The V1 walking skeleton runs whole `.casp` files end to end. The piece-at-a-time evaluation model a REPL needs (preserve scope between lines, expose previous results, handle multi-line input gracefully) is a different lifecycle than the load-program → run-once shape V1 commits to.
- A useful REPL needs introspection surfaces (last result, scope inspection, error recovery without quitting) that aren't on the V1 roadmap.
- Test fixtures, the CLI runner, and embedded use cases cover the V1 hosting story without it.

## What it would look like eventually

Roughly: each typed line becomes a Caspian source string, gets parsed and transpiled into CaspianJ, runs against a long-lived engine instance whose state survives between calls, and the last-statement value gets printed back. A REPL-aware engine mode (or a REPL wrapper module) handles incomplete-input detection so multi-line expressions can be entered across multiple prompts.

The interesting design questions when this lands:

- **State persistence between lines.** Does the engine treat each line as its own program (with state explicitly threaded through `%chain` or similar)? Or does it carry a long-lived scope automatically?
- **Error recovery.** When a typed line raises, the REPL should drop the user back at the prompt with the rest of their session intact. The engine doesn't currently model "soft fault" the way a REPL needs.
- **Block continuation.** `if`/`while`/`function`/`class` blocks span multiple lines. The REPL needs to detect unbalanced opens and keep prompting until the block closes.
- **Variable preservation.** A user sets `$x = 5` on one line and references `$x` on the next; the REPL has to keep that scope alive.

None of these are hard, but they're all distinct from "run a complete program once." Real spec work waits until V1 ships.

## Until then

Removed from the bootstrap doc's example-hosts list ([engine-creation § Examples of hosts](https://puck.uno/documentation/requirements/bootstrap/engine-creation#examples-of-hosts)). When V1 host enumeration evolves, this idea page is the placeholder.
