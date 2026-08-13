~~~vibecode
{"doc": "sprint-index", "sprint": "larry",
	"role": "Concept-capture sprint. Larry is the first Runner subclass — see the runner sprint for the base class shape. Intended for running Caspian programs from tests, but written well enough that its patterns can inform shipping runners (CLI first) when those get built. Specs TBD; not implementing yet.",
	"status": "concept noted; specs TBD; not implementing yet",
	"depends_on": ["runner"]}
~~~

# larry

## Goal

**Larry is the first Runner subclass.** See the [runner sprint](../runner/) for what a Runner is (the base class asserted). Larry specializes the base for a specific purpose: running Caspian programs from within tests.

## Test-scoped intent

Larry's primary job is being a test tool. When a test needs to run a Caspian program end-to-end — load source, dispatch, get output back — it instantiates a Larry, hands it the source, and asserts on the result. That's the immediate use case.

**Not every test uses Larry.** Unit tests that exercise a specific class or function still work directly with that object — no engine, no Runner, no source-string round-trip. Larry is for tests that need a program to actually RUN, end-to-end. Whether a given test reaches for Larry or works with its subject directly is a judgment call that'll settle as we accumulate examples.

## Not throwaway

Because Larry is the first Runner subclass to exist, it's also the testbed for figuring out what a Runner subclass actually looks like. Patterns that prove out in Larry are the patterns that the CLI runner (and any other future runners) will start from. Ones that turn out awkward get replaced BEFORE they harden into a shipping runner.

That framing changes how Larry is written. It's test-scoped, but not throwaway test scaffolding — it's built as if it might graduate. Clean structure, thoughtful naming, real separation of concerns. The next Runner subclass reads Larry and either extends the shape or diverges deliberately from it.

## Specs

**TBD.** Not designing Larry's shape here — just noting its role as first-subclass + testbed.

## Status

**Concept noted. Not implementing yet.**
