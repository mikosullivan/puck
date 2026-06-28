# `caspian` CLI

~~~vibecode
{"vibecode": {
	"doc": "caspian_cli",
	"role": "canonical reference for the caspian command-line interface — what arguments mean, the two-form invocation rule (file vs flag), the admin flags currently defined, conventions for confirmation prompts and destructive actions",
	"audience": "Caspian programmers and tooling that drives the caspian binary",
	"two_form_rule": "bare argument is a path to a .casp file; double-dash argument is an admin flag",
	"key_concepts": ["file_form_vs_flag_form_disambiguation",
		"admin_flags_use_double_dash", "destructive_flags_require_confirmation_bypass_with_yes",
		"non_destructive_flags_run_silently"]
}}
~~~

`caspian` accepts arguments in two forms, disambiguated by the leading `--`:

- **File form** — `caspian <path>` runs the file as a Caspian program.
- **Flag form** — `caspian --<name>` runs an admin action against the Caspian install itself; no script involved.

The `--` prefix is the disambiguator. A file with `.casp` extension or any path-shaped argument is unambiguous; the flag form keeps admin actions from colliding with filenames even when filenames happen to share a name with an admin verb.

---

## File form

```
caspian path/to/program.casp
caspian ./script.casp
caspian /usr/local/lib/example.casp
```

The path resolves relative to the current working directory; absolute paths work too. Standard convention is the `.casp` extension. The engine parses the file, transpiles to CaspianJ, and runs it.

---

## Flag form

Admin flags don't run user code; they perform a maintenance or info action against the Caspian install.

### `--update-cache`

```
caspian --update-cache
```

Refresh every cached library to its latest version. Reaches the network through the configured fetcher chain (see [downloads/](downloads/)); fetches the most recent version of each cached library and replaces the cached entry. Skips libraries the fetcher chain can't reach (logged, but not fatal).

**Non-destructive.** Runs without a confirmation prompt. Older versions of refreshed libraries are no longer the "latest" in the cache but aren't deleted; the cache may retain historical versions until `--clear-cache` is run.

### `--clear-cache`

```
caspian --clear-cache
```

Wipe the cache entirely. Removes every cached library record from the on-disk cache directory.

**Destructive — prompts for confirmation by default:**

```
$ caspian --clear-cache
This will remove all 247 cached libraries (1.2 GB).
Cached libraries will be re-fetched on next reference.
Continue? [y/N]: 
```

**Bypass the prompt with `--yes` (or `-y`)** for automation contexts (CI, install scripts, etc.):

```
caspian --clear-cache --yes
caspian --clear-cache -y
```

The non-interactive forms exit nonzero without doing anything if the cache directory is missing or unreadable — same as the interactive form would.

---

## Conventions

These rules apply to every CLI flag, present and future:

- **Admin actions use double-dash long flags** (`--update-cache`, `--clear-cache`). Short single-dash forms like `-u` are reserved for modifiers (`-y` for yes-to-all, etc.), not for primary actions.
- **Destructive flags require confirmation by default**, bypassable with `--yes` / `-y`. "Destructive" means anything that removes data or makes an irreversible change.
- **Non-destructive flags run silently** unless they have something specific to report. Stay out of the user's way.
- **Each flag's exit code follows POSIX**: `0` for success, nonzero for failure. Specific codes documented per flag where relevant.

---

## Permission-grant flags

The Frank slice ([development/v1/caspian/frank.md § Permission flags](../../development/v1/caspian/frank.md#permission-flags)) defines the `--allow-*` family that grants the running program access to host resources (filesystem, network, env vars, fork). Those flags apply to the file-form invocation and govern what the program can reach.

Admin flags (`--update-cache`, `--clear-cache`) don't run user code, so the `--allow-*` flags don't apply to them. The cache itself is engine-managed; admin actions have engine-level access to it without any per-invocation permission grant.

---

## Reserved for future flags

The CLI surface is intentionally small. Likely additions as needs emerge:

- `--config` — print effective config, or open editor
- `--doctor` — diagnose install issues
- `--cache-info` — print cache size, library count, oldest/newest entries
- `--container` — **post-V1.** Run the script inside an isolated container. The intended invocation is via shebang for executable Caspian scripts:

  ```
  #!/usr/bin/caspian --container
  ```

  When the script runs (e.g., `./my-script.casp` after `chmod +x`), Caspian sees the `--container` flag and stages the engine inside a container — isolating filesystem access, network, environment, etc. — then runs the script there. The container's shape (what's isolated by default, what's grantable per `--allow-*`, how the host gets results back) is the work to figure out when this lands. Deferred from V1.0; idea-stage only.

None of these are committed for V1.0; they're listed so the design space stays visible and the namespace stays consistent (double-dash, action-named) as flags get added.

`--version` and `--help` have shipped — see [Flag form](#flag-form) above.
