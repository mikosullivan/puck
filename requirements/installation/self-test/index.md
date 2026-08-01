# Post-install self-test

~~~vibecode
{"vibecode": {
	"doc": "requirements_installation_self_test",
	"role": "index page for the post-install self-test — `caspian --self-test`, the comprehensive build-verification suite that runs as the last step of installation and can be re-run any time. Runs Bryton against the shared Caspian test suite. Bryton and the test files are fetched at install time and cached under XDG cache. Directory contains the user-facing spec (this file) plus self-test-process.md for implementer-facing mechanics.",
	"status": "spec — command shape, Bryton-driven model, cache prewarming, and download-failure behavior settled; specific test coverage is whatever the shared test suite at https://caspian.uno/tests/ contains at any given time",
	"audience": "release maintainers implementing the install-time cache prewarm; developers running `caspian --self-test` to diagnose their install; developers maintaining the shared test suite"
}}
~~~

Every Caspian install ends with a self-test. It runs **[Bryton](../../bryton/runner/) against the same test suite Caspian's own development uses** — a full build-verification pass, not a smoke test. If the binary you just downloaded doesn't correctly implement the runtime — a subtly-wrong C binding, an integer-width mismatch, a UTF-8 edge case broken on your architecture — the self-test is what catches it.

## The `caspian --self-test` subcommand

The `caspian` binary exposes `--self-test` as a subcommand. Same command whether it's invoked automatically at install time or by the user later to diagnose an install. It launches Bryton against the cached test suite.

## How Bryton and the test tree are loaded

`--self-test` needs Bryton itself and a tree of tests.

- **Bryton** — loaded via `%fetch`, the usual way.
- **The test tree** — downloaded as a **tar.gz** from `caspian.uno` and extracted into a fresh `%tmp` directory. Bryton runs against the extracted tree.

See [self-test process](self-test-process) for the mechanics.

## Why the tests live outside the binary

- **Updatable independently of the binary.** Fix a flaky test, add coverage for a newly-discovered edge case, adjust a threshold — no need to re-release the whole runtime.
- **Dogfoods `%fetch`.** Loading Bryton is `%fetch`'s first real workload on a fresh install. If that fetch/verify/cache path works, a big chunk of Caspian's on-demand model has just been proven live on the user's system.
- **Dogfoods Bryton.** The install-time verification is Bryton's first real workload on the user's box. If Bryton runs the test tree successfully, Bryton is proven working too — free coverage of the test framework itself.
- **Exercises the blockchain path (if opted in) as a side effect.** When the user has opted into blockchain verification, the `%fetch` Bryton fetch travels the blockchain-verified path. That's live coverage of blockchain infrastructure the user just opted into.
- **One test tree, two use cases.** The tests packaged into the tar.gz are the same tests Caspian's own developers run against a build. There's no separate "install-verification" suite drifting out of sync with the "real" suite.

## What the self-test covers

The self-test covers **whatever the shared test suite covers**. Not spec'd here in detail — the tests themselves are the spec. Broadly, the suite exercises:

- Every bundled C binding — LPeg pattern matching, luasodium primitives (hashing, signing, secure random, etc.).
- Runtime primitives that can vary by build or architecture — integer widths, floating-point behavior, UTF-8 handling, string operations, file I/O across paths with unusual characters.
- End-to-end language behavior — parsing every syntax construct, executing representative programs, checking return values.
- Blockchain verification, if the user opted in.

The design intent is **as many actual build-verification tests as is practical**. Where "practical" tops out will shake out as the suite grows; the default assumption is that `--self-test` runs everything in the shared suite unless a specific test is explicitly excluded.

## How errors are reported

Bryton produces per-test [Xeme](../../bryton/xeme/) records. `--self-test` renders those into **human-readable output** — no splatter of stack traces, no wall of unfiltered technical data. Each check reports one line describing what was tested and the outcome.

Two severity levels:

- **Warning** — a non-blocking issue that doesn't invalidate the install. The self-test continues past it; the summary notes the warning.
- **Stop** — a blocking failure that makes further tests meaningless (e.g. the Lua interpreter itself won't start, so nothing downstream can be tested). The self-test aborts after reporting cleanly; the summary shows the stop reason.

Within a single run, **all reachable failures are collected and reported together** — no fix-one-find-another cycle. A stop only cuts off tests it makes impossible.

When a check produces more detail than fits on a line (a full error message, a stack trace, a diff against expected output, the raw Xeme record), that detail is **written to a log file, not the terminal**. The failure line references the log path. The terminal stays readable.

Illustrative shape (exact wording, glyphs, and layout are the renderer's call, not spec'd here):

```
Caspian self-test — Bryton, 247 tests
─────────────────────────────────────
✓ Binary runs (v0.01)
✓ Lua interpreter functional
✓ LPeg — 42 tests
✗ luasodium — 1 failure of 38 (see ~/.cache/caspian/self-test.log)
✓ UTF-8 handling — 19 tests
✓ File I/O — 24 tests
✓ Parse / execute — 96 tests
- Skipped: blockchain (not opted in) — 27 tests

Result: 1 failure, 27 skipped, 219 passed
```

## Reporting failures back

When the self-test finishes with one or more failures, it asks the user's permission to submit the failure report to the Caspian project. Failure reports are hugely valuable to maintainers — they surface architecture-specific bugs, subtle binding issues, and platform quirks the core team can't reproduce on its own hardware.

Sample prompt (illustrative wording):

```
Some tests failed.

Send an anonymous report of what went wrong to the Caspian project?
This helps us track down bugs on architectures and setups we can't
reproduce locally.

[y/n] _
```

No default — the user picks `y` or `n`. Nothing is submitted without an explicit `y`. The prompt is per-run; each failing invocation asks fresh (no "remember my answer" — a user who wants perpetual auto-send or perpetual auto-decline can set that explicitly in `~/.config/caspian/config.json` at implementation time).

What gets sent:

- The failed test IDs and their Xeme records.
- The `--self-test` log file contents (whatever the terminal referred users to for detail).
- System information — OS, architecture, distro/version, kernel version, Caspian version.

What does **not** get sent:

- Passing test results.
- User configuration (`~/.config/caspian/config.json`).
- Filenames from `$HOME`, environment variables, or anything else that could carry personal detail.

If the submission itself fails (network error, server down), `--self-test` prints a note and moves on. The failure summary the user already saw is unaffected.

Submission target URL and exact payload shape are spec'd at implementation time.

## When it runs

- **At install time (opt-in, recommended).** If the user accepts the [self-test prompt](../#self-test-prompt) during install, `install.sh` invokes `caspian --self-test` as the last step of [install and setup](../#install-and-setup), before the [installation summary](../#installation-summary). This is when Bryton, the test suite, and their transitive dependencies get fetched and cached; the tests then run. `install.sh` captures the summarized result and includes it in the [installation summary](../#installation-summary). If the user declined the prompt, no fetches happen at install and this step is skipped.
- **On demand.** The user can re-run `caspian --self-test` any time — useful for diagnosing a broken install, checking a new environment, or confirming a config change didn't break anything. Cached classes are reused; the run stays offline unless something's missing.

## If a class can't be downloaded

If any of the required fetches (Bryton, the test suite, a transitive dependency) times out or fails, `caspian --self-test` states which class couldn't be downloaded and skips the run. The install itself is unaffected — the binary is on disk, `PATH` is set up, XDG directories exist. The user can re-run `caspian --self-test` later once network is available.

The install summary reflects this — the self-test line reads roughly:

    Self-test: skipped (couldn't download https://caspian.uno/tests/)

## Refreshing the cached classes

Deferred — inherits whatever cache-refresh mechanism the general downloadable-class system settles on. `--self-test` may or may not grow a `--refresh` flag for forcing a re-fetch; not spec'd here.

## Related

- [installation](../) — the install flow that invokes `--self-test` as its last step.
- [self-test process](self-test-process) — implementer-facing spec for the fetch, Bryton invocation, and rendering mechanics behind `--self-test`.
- [binary](../../core/binary) — what actually ships in the `caspian` binary itself. The `--self-test` subcommand is bundled; Bryton and the test suite it runs are not.
- [Bryton runner](../../bryton/runner/) — the test framework `--self-test` uses.
- [Xeme](../../bryton/xeme/) — Bryton's per-test result format, which `--self-test` renders into human-readable output.
- [cache-dir](../../cache-dir) — where the downloaded classes live on the user's system.
