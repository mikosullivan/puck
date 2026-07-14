# Test download and run mechanics

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_installation_download_and_run",
	"role": "spec for how `caspian --self-test` loads Bryton (via %puck) and downloads the test-tree tarball (via %chain.net, extracted into a %chain.tmp directory) — including the bryton.root marker at the archive's top level so Bryton recognizes the extract as a test root. Scope is deliberately limited to fetch mechanics — running the tests, rendering results, and handling failures belong to Bryton and the self-test renderer and are spec'd elsewhere. User-facing behavior lives in the sibling index.md.",
	"status": "spec — high-level pipeline enumerated; Bryton fetch defers to %puck (not re-spec'd here); test-tree fetch is a plain %chain.net tar.gz download extracted natively by the caspian binary into %chain.tmp; downstream stages (run, render, report) spec'd elsewhere. Exact tarball URL scheme TBD.",
	"audience": "implementers of `caspian --self-test`; developers building the shared test suite at https://caspian.uno/tests/"
}}
~~~

User-facing behavior lives in [self-test](./). This page covers **how `--self-test` fetches Bryton and the shared test suite into the local cache** — the download side of the pipeline. Running the tests, rendering results, and handling failures belong to Bryton and the self-test renderer and are spec'd elsewhere; this page treats those stages as opaque.

## Pipeline

`caspian --self-test` runs through four stages:

1. **Fetch** — load Bryton via [`%puck`](../../chain/methods/puck), and download the test-tree tarball via [`%chain.net`](../../chain/methods/net) into a fresh [`%chain.tmp`](../../chain/methods/tmp) directory.
2. **Discover and run** — hand the cached test-suite location to Bryton, which walks it and executes each test, producing a Xeme record per test.
3. **Render** — read the Xeme stream and print human-readable output to the terminal.
4. **Report** (only if failures) — offer to submit the failure report to the Caspian project.

## Fetch

`--self-test` needs two things: Bryton itself, and the test tree.

- **Bryton** — loaded via [`%puck`](../../chain/methods/puck) in the usual way.
- **The test tree** — downloaded as a **tar.gz archive** from a URL on `caspian.uno` (exact scheme TBD — probably under `/download/`) via [`%chain.net`](../../chain/methods/net) and extracted into a fresh [`%chain.tmp`](../../chain/methods/tmp) directory. The archive's top-level directory contains a [`bryton.root`](../../bryton/runner/#the-testing-root) marker file so Bryton recognizes the extract as a test root.

If either fetch or the extract fails, `--self-test` skips the rest of the pipeline and reports the failure per [self-test § If a class can't be downloaded](./#if-a-class-cant-be-downloaded). The install itself is unaffected — the binary and XDG directories are already in place.
