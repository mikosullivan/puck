# Xeme

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_bryton_xeme",
	"role": "cover page for Xeme, the JSON format Bryton uses for reporting test results. Owns the top-level intro, the Fields section (currently `success`), the group-vs-test framing (with the detailed group spec at groups.md), and the icons taxonomy. Being rewritten from scratch.",
	"status": "spec in progress — rewrite underway; `success` field under Fields, group/test framing, and icons taxonomy are here; group details live at groups.md",
	"audience": "anyone producing or consuming Xeme documents"
}}
~~~

**Xeme** is a JSON format for reporting test results. [Bryton](../), Caspian's testing framework, uses Xeme.

## Fields

A xeme is a JSON hash. Fields spec'd so far:

### `success`

Required on every xeme. The truthiness of the value indicates success, failure, or undecided:

| Value | Meaning |
|---|---|
| `true` | Success. |
| `false` | Failure. |
| `null` | Undecided. |

This xeme indicates that the test passed:

~~~json
{
	"success": true
}
~~~

### `result`

Optional. Carries more details about the result of a test or group. For a test, it holds test-specific information such as expected and actual values. For a group, it can specify why the group wasn't run successfully.

The `result` field is defined by the classes at [results](results/) — that page owns the shape of each result class and links to the failure and null subclass pages.

### `runtime`

Optional. How long it took to run the operation.

### `uuid`

Optional. A UUID isn't required, but it can be handy when referring to specific test results.

### `path`

For file and directory groups (`group/file`, `group/dir`). If the file or dir is nested within a dir group, the `path` can be relative to that outer group. The outermost dir group's `path` can be absolute or relative — the developer's choice.

### `warnings`

Optional. An array of warnings. These do not affect the success/failure of the xeme.

### `notes`

Optional. An array of notes. Notes have no implication about the success/failure of the xeme and do not indicate problems.

### `trimmed`

Optional. On the **top-level xeme only**, marks the tree as the result of trimming — the reduction that removes successful leaves so consumers can focus on failures and nulls. The only useful value is `true`; if the xeme wasn't trimmed there's no need for the field, and inner xemes don't carry it either.

See [trimming](trimming) for the full spec.

### `misc` and `corporate`

As in all Puck hashes, `misc` and `corporate` are reserved for use by developers.

- **`misc`** — free-form; any content.
- **`corporate`** — the same, but intended for planned-out, corporate-wide standards.

## Groups and tests

There are two basic types of xemes: **groups** and **tests**.

- **[Groups](groups)** — xemes that carry a `nested` field holding child xemes. A group's `success` is derived from its children (a parent cannot be more successful than any child).
- **[Tests](tests)** — the leaf case; a xeme without `nested`.

## Icons

The [`icons/`](./icons/) directory ships a set of SVGs that give a visual reference for the categories of results and tests Xeme currently covers.

~~~
icons/
├─ results/
│  ├─ success.svg
│  ├─ success/
│  │  └─ skipped.svg
│  ├─ failure.svg
│  ├─ failure/
│  │  ├─ runtime.svg
│  │  └─ runtime/
│  │     ├─ crashed.svg
│  │     ├─ exception.svg
│  │     ├─ missing.svg
│  │     ├─ not-executable.svg
│  │     ├─ not-hash.svg
│  │     ├─ timedout.svg
│  │     └─ unparseable.svg
│  ├─ null.svg
│  ├─ null/
│  │  └─ promise.svg
│  ├─ note.svg
│  ├─ trimmed.svg
│  └─ warning.svg
└─ tests/
   ├─ group.svg
   ├─ group/
   │  ├─ dir.svg
   │  ├─ file.svg
   │  ├─ file/
   │  │  ├─ caspian.svg
   │  │  ├─ java.svg
   │  │  ├─ js.svg
   │  │  ├─ py.svg
   │  │  └─ rb.svg
   │  ├─ remote.svg
   │  ├─ subprocess.svg
   │  └─ timer.svg
   ├─ test.svg
   └─ unknown.svg
~~~

Two top-level branches:

- **`results/`** — verdict-state icons. `success.svg`, `failure.svg`, and `null.svg` cover the three states of the required `success` field; more specific icons underneath name the reasons a result took a particular verdict (a runtime crash, a timeout, an unfulfilled promise, etc.).
- **`tests/`** — icons for the test-node kinds themselves. `test.svg` for a plain test, `group.svg` for a group, with specifics underneath (`group/dir.svg`, `group/file.svg`, per-language file icons under `group/file/`).
