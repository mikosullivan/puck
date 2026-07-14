# Bryton runner

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_bryton_runner",
	"role": "spec for the Bryton test runner — the process that discovers, executes, and reports tests. Being spec'd from scratch.",
	"status": "spec in progress — core model settled (directory/file-based, executables in any language, xeme as last STDOUT block); exceptions to the 'run every executable' rule still to be specified",
	"audience": "anyone running Bryton, writing tests, or building Bryton-integrated tooling"
}}
~~~

The **Bryton runner** discovers, executes, and reports tests.

## The model

Bryton is **directory and file based**. It starts in a top-level directory and runs each executable file within the tree (with some exceptions still to be specified).

The executables themselves can be written in any language. Bryton is language-agnostic about what runs; it just cares that the file is executable.

Each executable is expected to **output a xeme to STDOUT as the last text on the stream**. Bryton parses that xeme and folds the result into the run. See [xeme](../xeme/) for the format.

STDOUT can contain anything before the xeme — debug output, progress messages, prints from libraries, whatever. The rule is only about what's at the tail. The trailing JSON hash doesn't have to start on a new line and doesn't have to stay on a single line; the runner finds the tail-most parseable JSON hash and uses that as the xeme.

## Scripts don't need libraries

A script that emits a xeme JSON hash to STDOUT **is** a Bryton test. No imports, no boilerplate, no framework tax:

~~~
#!/usr/bin/env bash
echo '{"success": true}'
~~~

That's a complete, working Bryton test — the runner sees the trailing JSON, parses it, folds it into the tree. Nothing more required.

The [Caspian testing tools](../testing-tools/) (`$bryton.assert`, `.eq`, `.done()`, and the rest) are **convenience**, not requirement. They let a Caspian test skip the JSON-formatting work, honor `fail-fast`, auto-generate UUIDs and timestamps, and produce human-readable output when invoked at the CLI. Real value — but every one of those benefits is optional. A script in any language that can print JSON can be a Bryton test.

The executable must also **exit with status 0**. Any non-zero exit status is treated as a failure to execute the file properly; the file is marked as failed regardless of what appeared on STDOUT.

## Failure modes

When execution goes wrong, the runner classifies the failure by producing a xeme whose result class names what happened. Consumers can rely on the classification to distinguish "the test itself declared it failed" from "we never got a clean answer from the test."

| What happened | Result class |
|---|---|
| File listed in `bryton.json` doesn't exist | [`failure/runtime/missing`](../xeme/results/failure#missing) |
| File exists but can't be executed (no exec bit, no interpreter, etc.) | [`failure/runtime/not-executable`](../xeme/results/failure#not-executable) |
| Executable exited with non-zero status | [`failure/runtime/crashed`](../xeme/results/failure#crashed) |
| Exit 0, but no parseable JSON at the tail of STDOUT | [`failure/runtime/unparseable`](../xeme/results/failure#unparseable) |
| Exit 0, trailing JSON parses but isn't a hash | [`failure/runtime/not-hash`](../xeme/results/failure#not-hash) |
| Exit 0, exceeded the configured [timeout](bryton-json/#timeout) | [`failure/runtime/timedout`](../xeme/results/failure#timed-out) |

When any of the above happens, the runner constructs a runtime-failure xeme itself and folds it into the tree in place of what the executable would otherwise have produced.

**When execution is clean** (exit 0, trailing STDOUT is a valid JSON hash), the runner passes the xeme through unchanged — the file's `success` and result class are whatever the executable declared. A test that reports `{"success": false, ...}` is a normal, non-runtime failure; the failure classification above only kicks in when the runner can't get a clean xeme out of the executable at all.

## The `BRYTON` environment variable

Before executing a file, the runner sets a **`BRYTON` environment variable** containing a JSON hash. Test scripts can read the hash to pick up runtime settings from the runner.

Currently spec'd fields:

- **`fail-fast`** — boolean. Indicates that the tests inside this file should behave as fail-fast.
- **`trim`** — boolean. Advisory to the test script: emit an already-[trimmed](../xeme/trimming) xeme (successful leaves omitted). Set by the runner when [`trim: true`](bryton-json/#trim) is in effect via the bryton.json chain. The runner will trim the file's result on the way out regardless of what the script does, so this is an optimization hint rather than a correctness requirement.
- **`human-readable`** — boolean. Tells the script to emit human-readable output instead of a xeme. Not for runner-driven runs (see below); useful when a developer runs a script directly at the shell and wants readable output.
- **`pretty`** — boolean. Advisory: emit prettified (indented, multi-line) JSON rather than compact JSON. Purely cosmetic — the xeme is the same either way; only the whitespace differs. `$bryton.done()` respects this setting.

Additional fields may be added as concrete needs surface.

**The runner strips `human-readable` and `pretty` from `BRYTON` before invoking any script.** The runner needs compact xeme JSON to parse; it can't work with human-readable output, and prettified whitespace is wasted overhead when the output is only ever read by another program. Even if a developer has either set in their shell's `BRYTON`, the runner removes those keys before spawning each test process. Every other key is preserved (and shallow-merged over as described below).

Typical shell-set defaults:

- **`human-readable: true`** — get readable output when running individual scripts directly. Stripped when the runner takes over.
- **`trim: true`** — get short xeme output (successful leaves omitted) when running scripts directly, avoiding walls of successful-leaf JSON. Preserved by the runner.
- **`pretty: true`** — get indented, scannable xeme JSON instead of compact output when running scripts directly. Stripped when the runner takes over.

**V1 is advisory.** In V1 the `BRYTON` hash is passed through purely for the test script to consult; the runner itself doesn't act on what the script does (or doesn't do) with the values. Subsequent releases may add in-script functionality that responds to these settings automatically.

### Merging with a pre-existing `BRYTON`

If `BRYTON` is already set in the environment when the runner starts, the runner **shallow-merges its computed hash on top of the existing one**. Pre-existing keys act as defaults; the runner's values override on key collision.

Use case: a developer sets defaults in their personal shell configuration ("always run with `fail-fast: true` for me") and the runner respects those unless a `bryton.json` in the tree overrides them.

**If the pre-existing `BRYTON` can't be parsed as a JSON hash, the runner raises an exception.** A malformed `BRYTON` is a mistake, not something to silently ignore.

A command-line switch (TBD) lets the developer tell the runner to **ignore** any pre-existing `BRYTON` entirely — useful for reproducibility runs where the shell state shouldn't influence anything.

## The output

The entire run produces a **single xeme** with every test nested within it.

- **Every directory is a group.** The tree structure of the results mirrors the filesystem structure — the root directory is the top-level group, subdirectories are nested groups.
- **Every file is a group.** Even a file that produces just one test result is a group; its child xeme is the test itself. That keeps the file/test relationship uniform regardless of how many tests a file contains.

The runner might display this xeme directly, or it might present a short human-readable summary instead. The xeme is the structured form; how the runner surfaces it is a UI concern.

## The testing root

The root of a testing tree is marked by a file named **`bryton.root`** in the top directory. Its presence is what makes the directory a root; the content of the file is irrelevant.

## Starting anywhere in the tree

The runner **doesn't have to be invoked in the testing root.** It can be started in any directory inside the tree, and it will just run the files in that directory (and its subtree). This supports the bottom-up workflow of fixing a specific bug, then broadening scope one level at a time.

Even when started deep in the tree, files still **inherit propagated settings from ancestor directories.** The runner walks upward from the invocation directory, gathering `bryton.json` at each level, until it reaches the directory containing `bryton.root`. That's where it stops.

This is why `bryton.root` exists — without a marker file, the runner wouldn't know where to stop walking upward when collecting inherited config.

## Files Bryton skips

### `dev.*` files

Files whose names match the pattern **`dev.*`** are never run. This is convenient for experimenting with code before actually writing the tests — a scratch file named `dev.py` or `dev-idea.sh` sits alongside the real tests without being executed.

### `bryton.*` files

Files whose names match the pattern **`bryton.*`** are reserved for meta information about the directory (configuration, tags, per-directory settings, etc.). Bryton reads these itself; it does not execute them as tests.

Settings about a directory are stored in [`bryton.json`](bryton-json).

## Test order

By default, there is **no specified order** for tests.

There are legitimate reasons to want a specific order, though — fail-fast, for example, needs a defined sequence so it's clear which test stopped the run. Order is declared in the [`files`](bryton-json/files/) hash of `bryton.json` — listed files run in the order they appear, before any unlisted files.

## Still to be spec'd

Both Bryton and Xeme will be refined once we actually start running tests — some of the details only surface when real fixtures are hitting real code, and that feedback will drive the next round of edits to both specs.

Specifically:

- **How to launch the runner** is not yet spec'd. The command-line surface, arguments, environment expectations, and CLI-level behaviors are pending.
- **V1 needs a JSON-in-text parser** — a class that can find a JSON hash (or scalar) at the leading edge, embedded in the middle, or at the trailing edge of a larger text stream. The runner's trailing-xeme rule depends on it; other tooling likely will too. Small piece of infrastructure, not yet built.
