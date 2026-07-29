# Bryton testing tools

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_testing_tools",
	"role": "spec for the tools test authors use inside test files — the assertion primitives, expectation helpers, setup/teardown scaffolding, fixture support, and anything else that lets a test file produce a xeme without having to hand-write the JSON envelope. Sibling of runner/ and xeme/. Being spec'd from scratch and expected to be the hardest part of Bryton to settle.",
	"status": "stub — content pending; expected to be the hardest part of Bryton to spec",
	"audience": "test authors writing Bryton-runnable tests; anyone building or maintaining a Bryton-compatible testing library"
}}
~~~

The **Bryton testing tools** are used within Caspian to generate test reports in [Xeme](../xeme/). They cover the assertion primitives, expectation helpers, setup and teardown scaffolding, fixtures, and everything else that turns test logic into a well-formed xeme on STDOUT without the author having to hand-write JSON.

Because Bryton itself is language-agnostic (the [runner](../runner/) executes any executable that produces a xeme on STDOUT), test authors writing in other languages produce xemes their own way. The tools spec'd here are the Caspian-side helpers that ship with Bryton; other-language equivalents would be separate.

The tools live at:

~~~caspian
%('https://puck.uno/bryton/tools/')
~~~

Test authors download the tools through the normal Puck object surface and use them from their Caspian test files.

## Instantiating a test runner

Create a test runner by calling `.new()` on the downloaded tools class:

~~~caspian
$bryton = %('https://puck.uno/bryton/tools/').new()
~~~

`$bryton` is the handle the test file uses to declare tests and produce a xeme.

## `$bryton.done()`

At the end of the file, you **must** call `$bryton.done()` to positively assert that every test in the file has completed:

~~~caspian
$bryton.done()
~~~

`.done()` does two things:

1. **Outputs the xeme for the file** to STDOUT — this is the block the [runner](../runner/) reads and folds into the run. If `$bryton.env['pretty']` is truthy, `.done()` emits prettified (indented, multi-line) JSON instead of compact.
2. **Exits the program** — the test file's process ends inside `.done()`; any code written after it doesn't execute.

Because `.done()` is the call that emits the xeme AND terminates the process, it's also what tells Bryton the file's run finished cleanly. Without it, Bryton has no way to distinguish "the test process ran everything and finished" from "the test process died partway through" — a bare successful exit could still be masking an incomplete run.

## `$bryton.required`

`.required` returns an array of test names that should be run in this file. Push names into it to register the expected set:

~~~caspian
$bryton.required.push 'test 1'
~~~

When `$bryton.done()` is called, any tests in `required` that were not actually run are added to the emitted xeme as failed tests with a result class of [`failure/missing`](../xeme/results/failure#missing).

**Nested groups have their own `.required`.** A group returned by [`$bryton.group`](groups) supports the same mechanism — push expected test names into `$group.required`, and any that are missing when the file's `.done()` runs surface as `failure/missing` under that group.

## `$bryton.env`

Reads the [`BRYTON` environment variable](../runner/#the-bryton-environment-variable) the runner set before executing the file. Accessed as a hash:

~~~caspian
$fail_fast = $bryton.env['fail-fast']
~~~

`$bryton.env` **always returns a frozen hash**. If the `BRYTON` environment variable isn't set, it returns an **empty** frozen hash — callers can index into `$bryton.env` without null-checking the accessor itself.

**Implementation detail.** `$bryton.env` reads and parses the `BRYTON` environment variable **on every call** — no caching. Repeated access is expected to be cheap, and the fresh-read rule ensures the accessor never returns stale state.

## `$bryton.minimum`

`.minimum` sets a minimum number of tests that should run within a block. Serves a similar purpose to `.required` but by count instead of by name — useful when the tests inside the block are conditional and you want to guarantee that at least *N* of them actually executed.

~~~caspian
$bryton.minimum(1) do
	if $something
		$bryton.assert true
	end
end
~~~

If fewer than the specified minimum ran by the end of the block, the shortfall surfaces as `failure/missing` in the emitted xeme.

*Spec pending — this is expected to be the hardest part of Bryton to settle, so it comes after the [runner](../runner/) and [xeme](../xeme/) surfaces are stable.*
