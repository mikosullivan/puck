# `%engine.config` — script-level resource declaration

> ⚠ **Tentative spec — review required before implementation.** The syntactic shape (`%engine.config` as a no-op-at-runtime method-call form), the schema inside the JSON heredoc, and the [extractor tool](#extractor-tool) are design proposals from this session. The construct's runtime semantics (silently ignored) and the position-at-top-of-script requirement are settled in principle; exact field names, schema validation, and tooling details are open.

~~~vibecode
{"vibecode": {
	"doc": "engine_config",
	"role": "spec for %engine.config — a script-level declarative construct that records what resources the script needs to run. Looks like a method call on %engine; at runtime, %engine silently ignores it. The value comes from static extraction: tools (host pre-flight, CI gates, sandboxing systems) can read the config without executing the script.",
	"status": "TENTATIVE — runtime semantics and position requirement are settled; schema and extractor tool details are open",
	"audience": "Caspian script authors declaring resource needs; tool authors writing pre-flight checks against scripts",
	"key_concepts": ["declarative_resource_requirements_at_top_of_script",
		"looks_like_method_call_but_is_no_op_at_runtime",
		"json_heredoc_body_with_schema",
		"statically_extractable_without_running_script",
		"caspian_extract_config_tool",
		"top_of_script_position_enforced"]
}}
~~~

A script can declare what resources it needs to run by placing one or more `%engine.config` blocks at the top of the file:

```caspian
%engine.config <<EOF('json')
{
    "container": {},
    "required": {
        "stdin": true
    }
}
EOF
```

The body is a JSON document describing the script's resource requirements. Hosts, deployment systems, CI runners, sandbox managers, and other tooling can read this declaration **without running the script** to decide whether to launch it and how to provision its environment.

---

## Runtime semantics: no-op

**`%engine.config` is a no-op at runtime.** When the engine executes a script that contains a `%engine.config` call, the call is dispatched, recognized as the config construct, and ignored. No state is read, no state is written, no exceptions are raised based on the config contents. The engine treats it as a comment that happens to be syntactically a method call.

The construct exists for **static consumers only** — anyone reading the source text (the extractor tool, an IDE, a deployment system) sees the declaration and can act on it. At runtime, the script behaves as if the `%engine.config` blocks weren't there.

This is deliberate. Putting the resource declarations in a runtime-execution path would let the script DECIDE at runtime what it claimed to need — but the value of the declaration is precisely that it's known BEFORE the script runs. A pre-flight host needs to know what the script needs before deciding to launch it; a runtime-evaluated declaration is unhelpful.

---

## Syntax

The construct is a method-call shaped statement with a JSON heredoc body:

```caspian
%engine.config <<EOF('json')
{ ...JSON body... }
EOF
```

- **The receiver is `%engine`.** Any other receiver isn't recognized as the config construct.
- **The method is `config`.** Other methods on `%engine` are real runtime methods; only `config` is the no-op declaration.
- **The argument is a heredoc** with the `'json'` [type hint](../index.md#heredoc-type-hints). The body is JSON.

Multiple `%engine.config` blocks may appear, each contributing fields to the merged config. Repeated keys across blocks raise an extractor-level warning (the merge semantics aren't yet specified — first-wins, last-wins, deep-merge are open design points).

---

## Position: top of script

`%engine.config` blocks must appear before any executable statement in the script. Anything that isn't a config block, a comment, a `%vibecode` block, or a `require` statement counts as "executable" for this purpose. After the first executable statement, no more `%engine.config` blocks are allowed; the extractor stops scanning at that point.

This rule means the extractor never needs to parse the full script — it scans from the top, collects config blocks, and stops at the first executable line.

```caspian
%vibecode <<EOF
{...vibecode metadata...}
EOF

%engine.config <<EOF('json')
{...config metadata...}
EOF

require 'foo.com/bar'

%engine.config <<EOF('json')
{...this would be REJECTED — comes after require...}
EOF

# (executable code starts here)
$x = ...
```

(Whether the parser raises on a misplaced `%engine.config` or just ignores it like the runtime does is an open design point. Raising is more helpful; ignoring is consistent with the no-op stance.)

---

## Schema

The structure inside the JSON body is open-ended for V1 — only a few top-level keys are recognized initially, more added as needs emerge. Unknown keys are ignored by the extractor; only the known shape gets surfaced to consumers.

**V1 starter set:**

| Key | Type | Meaning |
|---|---|---|
| `container` | object | If present, the script wants to run inside a container. Currently the empty object `{}` means "default container"; future keys can refine the isolation (`isolation: 'strict'`, etc.). |
| `required` | object | Host resources the script needs to function. Each key is a resource name; the value is a boolean or further structure describing the requirement. |

**`required` resource names** (V1 starter):

- `stdin: true` — script reads from stdin
- `stdout: true` — script writes to stdout
- `stderr: true` — script writes to stderr
- `network: [...]` — script needs network access; the array narrows to specific hosts (`['api.example.com']`) or is `true` for any
- `fs: {read: [...], write: [...]}` — script needs filesystem access for specific paths
- `env: [...]` — script reads specific environment variables

**Engine-side requirements:**

| Key | Type | Meaning |
|---|---|---|
| `engine` | object | Engine constraints — e.g., `{min_version: '0.5.0'}` requires at least that engine version. |

The schema is intentionally minimal in V1. Adding fields is non-breaking — old extractors will ignore unknown keys; new extractors will surface them.

---

## Extractor tool

A CLI flag on the `caspian` binary extracts the merged config without running the script:

```
caspian --extract-config path/to/script.casp
```

Output is the merged JSON config on stdout. Exit code 0 if the script has at least one valid config block; nonzero if not (no config blocks found, or a malformed JSON body).

Tooling integration:

```bash
# Pre-flight check before launching
if caspian --extract-config script.casp | jq -e '.required.network'; then
    setup_network_access
fi
caspian script.casp
```

The extractor must NOT execute the script — only scan the top-of-file text for `%engine.config` blocks and emit their merged body. Implementation can be a small text scanner (find the construct's opening line, read until the matching heredoc terminator, repeat) without invoking the full Caspian parser.

---

## Why a method-call shape?

Other declarative constructs in Caspian use dedicated keywords (`require`, `class`, etc.) or sigils (`%vibecode`). `%engine.config` deliberately reuses the method-call form for three reasons:

- **No new keyword.** Adding a new top-level keyword has knock-on effects on the parser and reserved-word list. The method-call form is already legal syntax.
- **Runtime engine sees the call, can choose to ignore it.** The engine's dispatch table needs an entry for `%engine.config` that returns immediately. No new parse-tree node, no new evaluation path. Just one no-op handler.
- **Visually appropriate.** Reading `%engine.config <<EOF ... EOF` at the top of a script reads as "telling the engine about this script" — which is exactly what it is, semantically.

The cost of this choice: a reader might think `%engine.config` is a real method and try to use it dynamically (`%engine.config(my_dynamic_body)`). Documentation has to be clear that it's a static declaration only; the no-op behavior should make misuse obvious quickly.

---

## Relationship to other declarations

- **`%vibecode`** — documentation metadata, also at the top of the file. Different audience: `%vibecode` targets humans and AI agents reading the source; `%engine.config` targets hosts and tooling deciding whether and how to run the script.
- **`require`** — library declarations. Can also appear at the top of the script. `require` is per-library and runtime-effective (loads the library); `%engine.config` is for non-library resource declarations.
- **CLI `--allow-*` flags** (per [Frank slice](../../development/v1/caspian/frank.md#permission-flags)) — runtime permission grants supplied by the launcher. `%engine.config` declares what the script NEEDS; the launcher's `--allow-*` flags declare what the host GRANTS. A pre-flight tool can match the two to validate that a launch attempt will succeed.

---

## Open design points

- Merge semantics for multiple `%engine.config` blocks (first-wins, last-wins, deep-merge).
- Whether a misplaced `%engine.config` (after the first executable statement) raises or is silently ignored.
- Schema validation: should the extractor validate against a schema and fail on unknown keys, or pass them through?
- Exit code conventions for the extractor when no config blocks are present.
- Whether the extractor should also accept a script's stdin (for piped input) or only file paths.

---

## See also

- [`%vibecode` heredocs](../index.md#heredoc-type-hints) — the type-hint convention used in the JSON body.
- [`require`](require.md) — library declarations; sibling top-of-script construct.
- [CLI `--allow-*` flags](../../development/v1/caspian/frank.md#permission-flags) — runtime permission grants matching what `%engine.config` declares.
- [CLI flag form](../cli.md#flag-form) — where `--extract-config` will live when shipped.
