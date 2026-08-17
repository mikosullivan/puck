~~~vibecode
{"doc": "sprint-index", "sprint": "stopgap-for-variable-objects",
	"role": "Deferred sprint. The current language design supports variables-as-objects (`$$var` syntax); the CVM does not yet. Keeping the parser support in place; adding tests + requirements notes so the not-yet-supported case fails loudly, without ripping parser code that would just have to be reintroduced later.",
	"status": "deferred — no work now; queued for after the engine has a working run loop"}
~~~

# Stopgap for variable objects

`$$var` — variables-as-objects syntax — parses in the current parser. The CVM doesn't yet support the shape at runtime. Rather than gut the parser code (only to reintroduce it later when V1+ actually adds runtime support), leave the parser as-is and add a loud failure at use time.

## Deferred scope

**Nothing to implement now.** When the engine has a running run loop and the surrounding infrastructure to drive this end-to-end, this sprint's actual work becomes:

- **Tests** that `$$var` parses cleanly (parser produces the CaspM shape) but crashes when the runtime tries to use it (loud, specific error at the earliest layer that can detect).
- **Requirements notes** at the affected `requirements/` pages: `$$var` is not supported in this release.

## Why we're keeping the sprint dir

As a marker. When later work runs into "should we implement variables-as-objects?", this dir is the pointer to "no — deliberate deferral; here's why."

## Status

**Deferred.** Sprint kicked off; scope decided; no implementation work until the engine's run loop supports enough for the tests to be meaningful.
