# `bryton.json`

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_runner_bryton_json",
	"role": "spec for the `bryton.json` per-directory settings file. Bryton reads this file (when present) in each directory it traverses; the file's fields configure how tests in that directory (and its subtree, unless overridden) run.",
	"status": "spec in progress — `files` field started; other fields to be added",
	"audience": "developers configuring Bryton test directories"
}}
~~~

**`bryton.json`** holds per-directory settings for Bryton. When Bryton traverses a directory, it reads `bryton.json` if present and applies the settings to the tests in that directory's subtree (unless overridden by a `bryton.json` deeper down).

## Fields

### `files`

Configures how individual files in this directory are handled — which are run, which are skipped, per-file overrides, and so on.

See [files](files) for the full spec.

### `exclusive`

Optional. Default `false`. When `true`, only the files explicitly listed in [`files`](files) are run; every other executable in the directory is skipped. Use it when the `files` list is meant to be authoritative.

### `skip`

Optional. Default `false`. When `true`, the entire directory is skipped. The directory is marked as [skipped](../../xeme/results/#skipped) in the results, and nested files and subdirectories are not mentioned at all — Bryton doesn't descend into the tree.

The same effect can be achieved from outside by listing this directory's name as `false` in the parent's [`files`](files) hash — the two are equivalent. Put `skip: true` in the directory's own `bryton.json` when the decision belongs with the directory; put `"dirname": false` in the parent's `files` when the parent owns the exclusion.

### `fail-fast`

Optional. Default `false`. Three legal values:

- **`false`** — nothing stops early; every test in scope runs to completion.
- **`true`** — the tests within this directory run in **fail-fast mode**: the first failure anywhere in scope stops the run of the remaining tests in scope.
- **`"children"`** — each direct child scope runs in fail-fast internally, but the directory as a whole doesn't. The runner keeps moving to the next child even if one child bailed out on a failure. Useful for "run each test file to first failure, but keep me moving through all files in this directory."

**Inherited down the directory chain.** A `fail-fast` value in a parent directory applies to every subdirectory beneath it unless a subdirectory's own `bryton.json` overrides it. A subdirectory can turn fail-fast back off with `"fail-fast": false`.

### `timeout`

Optional. Sets timeouts for the tests in this directory. The value can be either **a number** or **a hash**.

**Number form** — the number of seconds each test is allowed to run before being marked as [timed out](../../xeme/results/failure#timed-out). Applies to every test in the directory and its subdirectories individually — each test gets its own allowance, not a shared budget.

**Hash form** — a directory-level timer. Must have at least one of two fields to be useful:

- **`limit`** — a hard limit (in seconds) on how long the entire directory is allowed to run. If reached, the whole directory is marked as [timed out](../../xeme/results/failure#timed-out).
- **`warning`** — a soft limit (in seconds). If reached, a warning is added to the directory's xeme; the run continues.

**Scope.** In both forms, the setting applies to the entire directory and every nested test, including tests in subdirectories. A `timeout` establishes a single budget for the whole tree beneath it; a nested `timeout` in a subdirectory can only tighten that budget, never loosen it. If a subdirectory tries to set a value larger than the inherited one, the parent's stricter setting still applies.

### `tags`

Optional. Tags attached to the directory itself. Same shape as the xeme [`tags`](../../xeme/#tags) field — either an array (a flat list of tag names) or a hash (keys are tag names; values carry metadata).

**Tags are not inherited.** A tag declared here applies only to this directory. Files and subdirectories are not tagged by it; each declares its own tags where it wants them.

### `trim`

Optional. Default `false`. When `true`, results are [trimmed](../../xeme/trimming) — successful leaves are removed from the emitted xeme so consumers can focus on failures and nulls.

**Inherited down the directory chain.** A `trim: true` in a parent directory applies to every subdirectory beneath it unless a subdirectory overrides. Also **propagates into file settings** — when trim is in effect for a file, `BRYTON` includes `"trim": true` for the executable to read via `$bryton.env['trim']`.

**Advisory to the test script.** The script may honor the setting by emitting an already-trimmed xeme (skipping the successful-leaf overhead), but it doesn't have to — the runner will trim results as they come out regardless. Cooperating scripts save memory and bytes on the wire; non-cooperating scripts still end up with a trimmed final result.
