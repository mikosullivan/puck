# CaspianJ on-disk cache (`caspj/` subdir)

~~~json
{"vibecode": {
	"doc": "caspj_cache",
	"role": "design for an on-disk cache of transpiled CaspianJ next to source .casp files; skip lexer/parser/transpiler on subsequent runs when source hasn't changed",
	"placement": "caspj subdir next to source, fallback to user cache dir, last fallback in-memory only",
	"validity": "source mtime + sha256 + engine_version stamped in cache file header",
	"atomicity": "temp file plus rename",
	"naming_note": "caspj subdir name chosen to match the existing 'bucket' subdir convention",
	"status": "brainstorm — design recorded for the implementation slice that wires this in"
}}
~~~

CaspianJ is the engine's canonical runtime format. Today every run
of a `.casp` file re-pays the lexer + parser + transpiler cost to
turn source into the JSON tree the dispatcher actually executes.
Caching that JSON tree on disk skips three pipeline stages on every
subsequent run.

Notable beneficiary: [Bryton](caspian/packages/bryton/bryton.md)
subprocess-invokes every test file independently, so a 50-file test
suite re-parses 50 times today. With the cache in place, only the
files that actually changed get re-parsed.

The cache convention is **one `caspj/` subdirectory next to source
files**, matching the existing `bucket/` subdir pattern Caspian
already uses for similar per-directory data:

```
src/
├─ hello.casp
├─ utils.casp
└─ caspj/
   ├─ hello.caspj
   └─ utils.caspj
```

---

<a id="lookup-order"></a>
## Lookup order

When the engine is asked to run `path/to/foo.casp`, it walks a
fixed lookup order to decide what to actually load:

1. **Side-by-side cache:** look for `path/to/caspj/foo.caspj`.
   If present and valid (see [validity](#validity) below), load it
   directly — skip lexer/parser/transpiler entirely.
2. **User cache:** look for `~/.cache/caspian/<hash>.caspj` where
   `<hash>` is sha256 of the source's absolute path. Same validity
   rules. This handles read-only source directories (system installs,
   Docker layers, NFS-mounted scripts) where the side-by-side cache
   can't be written.
3. **In-memory only:** parse the source, dispatch the resulting
   tree directly, write nothing. Last-resort path for one-shot
   invocations where both cache locations are inaccessible.

Whichever location was used for the read is also the location used
for the write — so a script run from a read-only directory always
populates the user cache, never wastes effort trying side-by-side.

---

<a id="validity"></a>
## Cache validity

A cached `caspj/foo.caspj` is **valid** only when:

| Check | Value |
|---|---|
| Engine version | matches the current engine |
| Transpiler version | matches the current transpiler (may bump independently of the engine) |
| Source mtime | matches the source file's current mtime |
| Source SHA-256 | matches the source file's current content hash |

All four must match. The hash defends against mtime-spoofing edge
cases (`touch -t`, git checkouts with funny clock setups, files
written within a single mtime tick). The version stamps invalidate
caches when the engine or transpiler output shape changes — old
caches are silently rejected and regenerated.

If any check fails, the cache is treated as missing: re-parse,
re-write.

---

<a id="cache-file-format"></a>
## Cache file format

A cached `.caspj` is a JSON object, not a bare JSON array
(distinguishing it from hand-written CaspianJ fixtures). Two
top-level keys:

```json
{
  "meta": {
    "engine_version":     "1.0.0",
    "transpiler_version": "1.0.0",
    "source_mtime":       1716568231,
    "source_sha256":      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "cached_at":          1716568232
  },
  "tree": [
    [{"value": "hello"}, "to_string"]
  ]
}
```

The dispatcher unwraps `meta`, validates it, then executes `tree`.

Hand-written `.caspj` files (test fixtures, the V0.01 hello-world
file, etc.) stay as bare arrays — they have no `meta` and no
validation overhead. The engine distinguishes by checking whether
the top-level JSON value is an object (cached) or an array
(hand-written / source-of-truth).

---

<a id="atomicity"></a>
## Writing the cache safely

The write is atomic: temp file in the same directory, then `rename`:

```
write_to:    path/to/caspj/.foo.caspj.tmp.<pid>
rename_to:   path/to/caspj/foo.caspj
```

`rename(2)` is atomic on every reasonable filesystem within the
same mount point. Two processes that try to write the same cache
file at the same time will both succeed individually; the later
rename wins, but both wrote the same content (deterministic
transpiler output), so the user sees no inconsistency.

The temp filename starts with `.` so it's hidden from `ls` if a
process crashes mid-write. A cleanup pass on engine startup deletes
stale `.foo.caspj.tmp.*` files older than an hour in any `caspj/`
the engine touches.

---

<a id="poisoning-defense"></a>
## Defending against cache poisoning

The cache file is read before the source is parsed, so a malicious
write to `caspj/foo.caspj` could replace the executed program if no
defenses are in place. The validity checks above handle this:

- **mtime check** stops the simplest attack (drop a `.caspj` for an
  unrelated source).
- **sha256 check** stops the more careful attack (drop a `.caspj`
  with a forged mtime matching the real source). The hash is
  computed from the actual source bytes, not from anything in the
  cache file — attackers would need to write `caspj/foo.caspj`
  carrying a correct hash of `foo.casp`, which means knowing exactly
  what `foo.casp` contains, which means they'd have to be able to
  read it, in which case they could just read it directly.

Net effect: any tampered cache file fails validation and triggers a
re-parse from the genuine source. The attacker accomplishes nothing
beyond a small CPU cost on the next run.

---

<a id="syntax-errors"></a>
## Syntax errors

If `foo.casp` doesn't parse cleanly, no cache file exists yet (or
the existing cache is for an earlier valid version). The lookup
falls through to source parsing, which reports the error normally.

On a successful parse after a previously-failing source, the cache
gets written as usual — the next run picks it up.

---

<a id="bryton-interaction"></a>
## Bryton interaction

This is where the cache pays for itself most. Bryton (V0.1
[Glenstorm](../development/v1/glenstorm.md)) subprocess-invokes
every test file, so a 50-file test suite that runs in 2 seconds
today might spend ~600 ms re-parsing source on every invocation.
With cached `.caspj` next to each `tests/foo.casp`, the parse cost
collapses to "only the tests whose source actually changed" —
typically zero or one file per re-run.

For test suites under active development, this is the difference
between "Bryton feels snappy" and "Bryton has a perceptible parse
tax." Worth landing before Bryton becomes the primary feedback loop
for Caspian development.

---

<a id="cleanup"></a>
## Cleanup and orphans

When a `.casp` file is deleted, its `caspj/*.caspj` file orphans.
Two options:

- **Periodic sweep:** engine startup walks recently-touched
  `caspj/` dirs and deletes `.caspj` files whose sibling `.casp`
  no longer exists. Free, automatic, no user intervention.
- **`caspian cache clean` subcommand:** explicit user-driven sweep
  across a directory tree. Useful for "I'm about to commit this and
  want a clean working dir."

Both. The periodic sweep is best-effort and conservative (only
touches dirs the engine just used); the subcommand is the
sledgehammer.

---

<a id="gitignore"></a>
## `.gitignore`

Recommend users `.gitignore` the `caspj/` directories project-wide.
Cache files are derived artifacts; checking them into version
control causes spurious diffs on every machine that runs the code.

A single line in the project root suffices:

```
caspj/
```

`caspian init` (whenever that lands) should add this line to a
generated `.gitignore`.

---

<a id="open-questions"></a>
## Open questions

~~~json
{"vibecode": {"open_questions":
["whether_to_cache_when_running_one_off_caspian_dash_e_invocations",
"whether_to_expose_caspian_cache_disable_flag_or_just_env_var",
"how_to_handle_caspj_files_committed_to_a_repo_by_accident",
"whether_validation_should_be_fail_loud_or_silent_when_meta_present_but_corrupt",
"whether_the_caspj_subdir_should_be_named_caspj_or_dot_caspj_or_caspjcache_or_other"]}}
~~~

- **One-off invocations.** `caspian -e "puts 'hi'"` parses an inline
  string, not a file — nothing to cache against. Just skip the
  cache path for these. Decided.
- **Disable flag / env var.** Some environments may want the cache
  off entirely (e.g., testing the parser itself). `CASPIAN_NO_CACHE=1`
  env var; `--no-cache` CLI flag. Both pass through to the lookup
  step which then forces in-memory parse-and-execute.
- **Accidentally-committed `caspj/` dirs.** The `.gitignore`
  recommendation catches new repos. For existing repos that
  predate the recommendation, `caspian cache clean` is the answer;
  no special engine handling needed.
- **Corrupt cache files.** If the JSON parse of a `.caspj` itself
  fails (truncated write, disk corruption, etc.), treat it as
  invalid — same fall-through as a hash mismatch. Don't crash.
- **Naming.** `caspj/` matches the existing `bucket/` convention.
  Alternatives considered: `__caspj__/` (Python-style), `.caspj/`
  (hidden), `caspj-cache/` (explicit). Going with plain `caspj/`
  for consistency with `bucket/`.
