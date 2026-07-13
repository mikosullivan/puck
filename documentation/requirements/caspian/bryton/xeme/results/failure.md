# Failure

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_bryton_xeme_results_failure",
	"role": "spec for the failure family of result classes — the base `failure` class and its subclasses (runtime failures and their specific kinds). Broken out of results/index.md because the failure hierarchy has enough branches to warrant its own page.",
	"status": "spec in progress — base class settled; subclasses pending",
	"audience": "anyone producing or consuming Xeme failure results"
}}
~~~

The **failure** family of result classes covers the ways a xeme can end in a `false` verdict.

## Base class

<img src="../icons/results/failure.svg" width="32" height="32" alt="failure result icon" style="float: left; margin: 0 12px 4px 0;" />

The base failure class is **`failure`**.

<div style="clear: both;"></div>

**Most failures do not need a subclass.** If a xeme is marked `"success": false` and the intended result class is just `failure`, it's usually not necessary to give the result an explicit class at all — `failure` is the default result class for a failed test.

## Subclasses

### Runtime

<img src="../icons/results/failure/runtime.svg" width="32" height="32" alt="failure/runtime icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime`** covers errors that result from a failure to run — or a failure to get results back from — a test or group.

<div style="clear: both;"></div>

#### Crashed

<img src="../icons/results/failure/runtime/crashed.svg" width="32" height="32" alt="failure/runtime/crashed icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/crashed`** — the test process crashed (segfault, abend, or the host runtime terminated abnormally) before it could report a result.

<div style="clear: both;"></div>

#### Exception

<img src="../icons/results/failure/runtime/exception.svg" width="32" height="32" alt="failure/runtime/exception icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/exception`** — the test raised an uncaught exception.

<div style="clear: both;"></div>

#### Missing

<img src="../icons/results/failure/runtime/missing.svg" width="32" height="32" alt="failure/runtime/missing icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/missing`** — the test file (or the test itself) couldn't be found where it was expected.

<div style="clear: both;"></div>

#### Not executable

<img src="../icons/results/failure/runtime/not-executable.svg" width="32" height="32" alt="failure/runtime/not-executable icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/not-executable`** — the test file exists but couldn't be run (missing executable permission, no valid shebang, or otherwise not launchable).

<div style="clear: both;"></div>

#### Not hash

<img src="../icons/results/failure/runtime/not-hash.svg" width="32" height="32" alt="failure/runtime/not-hash icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/not-hash`** — the test's output parsed as JSON but the top-level value wasn't a hash (Xemes must be JSON hashes).

<div style="clear: both;"></div>

#### Timed out

<img src="../icons/results/failure/runtime/timedout.svg" width="32" height="32" alt="failure/runtime/timedout icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/timedout`** — the test didn't complete within its allowed time limit.

<div style="clear: both;"></div>

#### Unparseable

<img src="../icons/results/failure/runtime/unparseable.svg" width="32" height="32" alt="failure/runtime/unparseable icon" style="float: left; margin: 0 12px 4px 0;" />

**`failure/runtime/unparseable`** — the test's output couldn't be parsed as JSON at all.

<div style="clear: both;"></div>
