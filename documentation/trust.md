# Trust

vibecode: {
	"section": "overview",
	"role": "explains the unified trust model: every object carries a source tag, the engine maps sources to trust levels, %chain.trust provides explicit runtime overrides, and untrusted values are constrained at sinks (filesystem, eval, etc.)",
	"key_concepts": ["source_tag_per_object", "engine_source_to_trust_mapping",
		"chain_trust_override", "data_tainting", "cli_more_permissive_than_embedded",
		"transitive_trust_does_not_apply"]
}

Trust in Kiera is **derived from the source of every object**. When an object is
created — whether it is a function loaded from a cached library, a string parsed from
a request, a record fetched from a database, or a closure defined inline — the engine
tags it with the source it came from. The engine also holds a mapping from sources to
trust levels, so an object's trust is fully determined by where it originated.

This applies to every value, not just callables. A string fetched from a network
request is tainted the same way a function pulled from a database is. Sinks that act
on values — the filesystem, dynamic evaluation, query construction — check the trust
tag and either refuse the operation or require an explicit override.

KScript code can override trust at runtime via `%chain.trust`. The override is bounded
by the granter's own trust (you can never grant more than you have) and lives in the
current `%chain` frame, evaporating when that frame returns.

---

## Defaults: Command Line vs Embedded

vibecode: {
	"section": "defaults_cli_vs_embedded",
	"role": "documents that CLI execution gets more permissive defaults than embedded execution; the host always controls the trust policy",
	"key_concepts": ["cli_more_permissive", "embedded_minimal", "host_controls_policy"]
}

Trust defaults differ depending on how KScript is invoked. **The host always controls
the trust policy**, but the conventions differ.

### Command-line mode

When KScript runs at the command line, it is the host. By convention, it grants more
permissive defaults so the developer can do useful work without configuration overhead:

- The local filesystem is reachable, with whatever read/write permissions the user has
- The network is reachable, including the open internet if available
- The system-wide configuration directory (`/etc/kscript/`) contributes to trust setup
- The user configuration directory (`~/.config/kscript/`) contributes to trust setup

These defaults make CLI use feel similar to running a Perl, Python, or Ruby script —
the program has access to the surrounding environment until told otherwise.

### Embedded mode

When KScript runs inside a host program (Lua, Ruby, etc.), defaults flip the other way.
The embedded engine sees nothing by default — no filesystem, no network, no config
directories. Every capability and every trust grant must be **injected explicitly** by
the host program. This matches the principle that an embedded engine is a tool the
host owns; the host is responsible for deciding what it has access to.

The same trust model applies in both cases — what differs is the starting point.

---

## The Source Tag

vibecode: {
	"section": "source_tag",
	"role": "documents the per-object source tag set at creation, the storage-breaks-chain rule, and source identifier queryability",
	"key_concepts": ["set_at_creation", "immutable", "storage_breaks_source_chain",
		"queryable_via_dot_source"]
}

Every object the engine creates carries a **source tag** identifying where the object
originated. The tag is set once at creation and is immutable thereafter.

Examples of sources:

| Where the object came from | Source tag (informal) |
|----------------------------|-----------------------|
| Cached library at `~/.config/kscript/trusted/foo.com/bar/` | the path itself |
| Cached library at `~/.config/kscript/untrusted/baz.io/quux/` | the path itself |
| Bundled stdlib | `kiera.uno/...` |
| Function defined inline in a `.kscript` file | the file path |
| Closure created by `eval(str)` | `eval` plus originating context |
| Value fetched from a database | the database connection |
| String from a parsed network request | the request object |
| Function emitted by a code generator | the generator |

### Storage breaks the source chain

When an object is serialized and later retrieved (database, file, network), it gets a
**new** source tag corresponding to wherever it came back from. The original source is
discarded. This is the rule that prevents trust laundering: writing a trusted function
into a database and reading it back gives an object whose source is "the database,"
not "the original code that wrote it." The engine has no way to verify the storage
layer wasn't tampered with, so the conservative answer — new source on retrieval — is
the only safe one.

### Queryable

KScript code can ask `$foo.source` to find out where an object came from. The mechanism
is read-only; scripts can inspect the source for diagnostics, audit logging, or
conditional trust decisions, but cannot mutate it.

---

## The Engine's Source-to-Trust Mapping

vibecode: {
	"section": "engine_source_to_trust_mapping",
	"role": "documents how the engine maps source identifiers to trust levels at startup; the mapping is fixed for the lifetime of the engine",
	"key_concepts": ["startup_only_configuration", "structured_source_identifiers",
		"per_instance_granularity", "host_owns_the_mapping"]
}

The engine holds a mapping from source identifiers to trust levels. The mapping is
**configured at startup and fixed for the lifetime of the engine** — it cannot change
mid-execution. This makes the trust posture of a running engine a stable, auditable
property.

```
engine.trust_source('~/.config/kscript/trusted/*',   :trusted)
engine.trust_source('~/.config/kscript/untrusted/*', :untrusted)
engine.trust_source('kiera.uno/*',                   :trusted)
engine.trust_source('my-production-db',              :trusted)
engine.trust_source('analytics-scratch-db',          :untrusted)
engine.trust_source('network',                       :untrusted)
engine.trust_source('eval',                          :untrusted)
```

When an object is created, the engine looks up its source in the mapping and tags the
object with the resulting trust level. The lookup is one-time, at creation; thereafter
the trust is part of the object's identity.

### Per-instance granularity

Source identifiers are structured, not just type-level. The mapping can target specific
instances, not just categories — "my production DB is trusted, the analytics scratch DB
is not" is a valid configuration. The engine matches sources against the mapping with
whatever granularity the host configures.

### Runtime overrides require %chain.trust

The mapping itself doesn't change at runtime. Any per-object adjustment (elevating a
specific value that was vetted, downgrading a value before passing it on) happens
through `%chain.trust`, documented below.

---

## Filesystem-based Trust (CLI Mode)

vibecode: {
	"section": "filesystem_based_trust",
	"role": "documents the trusted/ and untrusted/ directory convention used for CLI library trust",
	"key_concepts": ["trusted_directory", "untrusted_directory", "system_and_user_levels",
		"manual_promotion", "per_library_and_per_version"]
}

In CLI mode, the engine consults two locations on disk to populate the source-to-trust
mapping for cached libraries:

- **System-wide**: `/etc/kscript/trusted/` and `/etc/kscript/untrusted/` — set by the
  system administrator, baseline for all users on the machine.
- **User-level**: `~/.config/kscript/trusted/` and `~/.config/kscript/untrusted/` — the
  developer's personal additions and overrides.

When the engine starts, it reads both locations and registers each library it finds at
the appropriate trust level. **User-level entries win on conflict** — the user is
closer to their own intent than the sysadmin.

A newly fetched library (pulled by the cache layer when a `%kiera[...]` lookup hits a
remote provider) lands in `~/.config/kscript/untrusted/<signer>/<uns>/<date>/...` by
default. To trust it, the developer reviews the code and moves it into `trusted/`. The
act of reviewing IS the trust decision.

### kiera.uno is inherently trusted

The `kiera.uno/...` standard library is bundled with the engine and is inherently
trusted. It does not go through the trusted/untrusted dance — the engine ships with
it, the engine owns it, the engine trusts it. This is the only built-in trust in the
system.

### Granularity: per-library and per-version

Trust granularity is implied by what the developer puts in `trusted/`:

- **Per-library trust** — the entire library directory is moved in. Every cached
  version of the library is trusted, including future versions that arrive later.

  ```
  trusted/foo.com/bar/             # whole library trusted (all versions)
  ```

- **Per-version trust** — only specific version subdirectories are moved in. Other
  versions of the same library remain untrusted.

  ```
  trusted/baz.io/quux/2026-04-15/  # only this version trusted
  trusted/baz.io/quux/2026-04-22/  # this one too
  ```

The two coexist. A developer can fully trust libraries they have a long-running
relationship with, and pin specific versions of libraries they are more cautious about.
At lookup time, the engine checks for a version-specific match first, then a
library-level match; either is sufficient to mark the code trusted.

### Revoking

To revoke trust, move the files back into `untrusted/`:

```
mv ~/.config/kscript/trusted/foo.com/bar ~/.config/kscript/untrusted/foo.com/bar
```

The next engine start reads the new location and runs the library untrusted. No undo
step beyond `mv` is required.

---

## Trust Applies to All Values, Not Just Callables

vibecode: {
	"section": "trust_applies_to_all_values",
	"role": "documents data tainting: strings, numbers, arrays, hashes all carry trust tags; combining tainted values produces tainted results; sinks check trust",
	"key_concepts": ["taint_propagation", "sinks_check_trust",
		"jails_can_accept_tainted_input"]
}

The trust tag lives on **every value**, not just callables. This is the data-tainting
model from security-aware languages (Perl's `-T` flag, Ruby's old `$SAFE`). The reason
matters: an untrusted string used as a filename allows path traversal; an untrusted
string used in a query allows injection; an untrusted string used as a URL can target
internal services.

### Propagation: taint poisons combinations

Operations that combine values follow a "taint poisons the result" rule:

- `"safe-prefix" + untrusted_str` → untrusted result
- An array containing any untrusted element → untrusted array
- A hash with any untrusted key or value → untrusted hash
- Pulling a value out of an untrusted structure → untrusted value

Trust never increases through combination. Trusted code wanting to use untrusted data
must either accept the resulting tainted value, sanitize and re-create it (the
validated copy is trusted because the validator was trusted code), or use
`%chain.trust` to override.

### Sinks check trust

Security-sensitive operations refuse to operate on untrusted values, or require explicit
acknowledgment. The initial set of trust-checking sinks:

| Sink | Why it matters |
|------|----------------|
| Filesystem (read, write, path operations) | Path traversal, sensitive file access |
| `eval` and dynamic code construction | Code injection |
| Q0 query construction | Query injection |

Other sinks (network operations, process spawn, format strings) become trust-aware as
they are added to the engine. The principle is the same: a sink that can be misused by
hostile input checks the trust tag before acting.

### Jails can accept tainted input

A capability that has intrinsic boundaries can safely accept untrusted values. A
filesystem jail (per [bootstrap.md](ideas/bootstrap.md)) clamps any path to within the
jail root, so even a malicious `../../../etc/passwd` cannot escape:

```
%docs.path($untrusted_path).read    # OK — jail clamps to its root
%fs.path($untrusted_path).read      # raises — bare filesystem has no clamp
```

The principle: capabilities that can't be escaped are allowed to accept tainted input;
capabilities with broad reach require trusted input.

---

## Runtime Overrides: `%chain.trust`

vibecode: {
	"section": "chain_trust",
	"role": "documents the runtime trust grant primitive, its scope, the min(granter, requested) safety rule, and the do-block form",
	"key_concepts": ["frame_scoped_grant", "min_granter_requested",
		"survives_crossing_into_untrusted", "evaporates_with_granting_frame",
		"do_block_form_for_temporary_grants"]
}

When the engine's source-to-trust mapping isn't enough — e.g., you fetched a specific
function from a generally-untrusted source but you've manually verified it —
`%chain.trust` adds an explicit grant.

### The basic form

```
%chain.trust $foo
```

This adds a trust grant for `$foo` to the current `%chain` frame. From that point on
within the frame, `$foo` is treated at the granter's trust level. When the frame
returns, the grant evaporates along with that version of `%chain`.

Effective trust at invocation:

```
effective_trust = max(intrinsic_trust, current_chain_grant_for_this_object)
```

A function loaded from `trusted/` is always trusted regardless of grants. A value from
an untrusted source starts at untrusted, but a `%chain.trust` grant in the current
frame elevates it for the duration of that frame.

### The do-block form

For a grant that should apply only to a specific block of code rather than the
remainder of the function:

```
%chain.trust $foo do
    &call_into_something_with_foo($foo)
end
# grant has reverted; $foo is back to its intrinsic level
```

The grant lives only inside the block. After the block returns, `%chain` reverts to
its previous state. Useful for narrow elevations where leaving the grant in place
across the rest of the function would be overly broad.

### The min(granter, requested) safety rule

```
trust_granted = min(granter's own trust, requested level)
```

Untrusted code calling `%chain.trust $foo` confers nothing — the grant is bounded by
the granter's own trust level, and untrusted code has no trust to grant. Only trusted
code can elevate. This means an attacker who smuggles a function into a database can't
elevate it from untrusted code by calling `%chain.trust` themselves.

### Grants survive crossing into untrusted code

A trust grant lives in `%chain` and propagates with calls. When the granting function
calls into untrusted code, the grant goes with it via inherited chain — the untrusted
code can use the granted-on object at the granted level. This is the whole point: it
lets trusted code hand vetted objects to less-trusted callers.

The carrier parts of `%chain` (user, request_id, locale) clear when crossing into
untrusted territory; **trust grants do not clear**. They are a distinct category of
chain content that survives boundaries by design.

### Grants don't bubble up

When the granting frame returns, its `%chain` is gone — and so is the grant. If the
granted-on object is returned to the caller, the caller sees it at its **intrinsic**
trust level, not the granted level. The rule is "grants live in the granting frame's
chain"; they do not propagate up through returns. To re-elevate the object in the
caller, the caller must issue its own `%chain.trust` call.

```
function &caller()
    $f = &grant_and_return()    # $f is untrusted here even though
                                  # grant_and_return granted trust to it
end

function &grant_and_return()
    $f = load_from_db()
    %chain.trust $f               # grant lives in this frame
    $f                             # return $f
end                                # frame ends, grant evaporates
```

---

## Transitive Trust Does Not Apply

vibecode: {
	"section": "transitive_trust_does_not_apply",
	"role": "states that a trusted caller calling an untrusted callee does not promote the callee",
	"key_concepts": ["callee_trust_is_its_own", "no_trust_laundering"]
}

When trusted code calls a function whose intrinsic trust is untrusted, the callee runs
**at its own trust level** — untrusted. The trusted caller does not promote the callee
just by being the caller.

The reason: if trust were transitive through calls, an attacker who got a single trusted
library to import their malicious package would have promoted that package to trusted
across the whole call tree. The cost of preventing this is that a fully-trusted program
requires every library in the tree to be in `trusted/` (or to be elevated via
`%chain.trust`). That's the right cost.

The only way trust flows from caller to callee is the explicit `%chain.trust` grant,
which is bounded by `min(granter, requested)` and visible in source.

---

## What Untrusted Means at Runtime

vibecode: {
	"section": "what_untrusted_means_at_runtime",
	"role": "summarizes the runtime restrictions applied when untrusted code or values are encountered",
	"key_concepts": ["security_boundary_at_call", "chain_carrier_cleared_grants_persist",
		"capabilities_not_inherited", "abort_caught_at_boundary"]
}

When the engine calls into untrusted code, a security boundary is established at the
call site. Inside that boundary:

- Carrier parts of `%chain` (user, request_id, locale) are cleared
- Trust grants in `%chain` persist (so the boundary doesn't break legitimate elevation)
- Capabilities are not auto-inherited — only what is explicitly passed in is visible
- Timeout budgets are constrained to the parent budget or tighter
- Filesystem access is restricted to whatever jails are explicitly granted
- Security-grade exceptions raised by the inner code (`%process.abort`, out-of-range
  library lookups, etc.) propagate to this boundary, where the trusted outer layer
  catches them and decides what to do

The same mechanism applies whenever an untrusted value is passed to a sink that checks
trust — the sink raises rather than acting. See [versioning.md](versioning.md) for how
out-of-range exceptions interact with these boundaries.

---

## Why This Model

vibecode: {
	"section": "why_this_model",
	"role": "summarizes the rationale for source-derived trust plus chain-scoped overrides plus data tainting",
	"key_concepts": ["source_is_concrete_and_auditable", "filesystem_review_forces_decision",
		"tainting_catches_data_borne_attacks", "chain_trust_is_explicit_and_greppable"]
}

The model is built around three principles:

- **Trust is derived from source, not asserted by code.** A library, a database value,
  a network response — each has a concrete origin, and trust follows from that origin
  via the engine's mapping. There is no in-script flag that promotes code to trusted.
- **Filesystem placement makes trust visible.** Anyone can `ls trusted/` and see
  exactly what's trusted. The act of `mv`ing a library into `trusted/` is itself the
  review and the decision. There is no policy DSL that lets you trust things you have
  never opened.
- **Tainting catches the data-borne attacks that pure-callable trust models miss.**
  Path traversal, injection, format-string vulnerabilities — these come from untrusted
  *data* reaching trusted *operations*. Tagging every value, propagating taint through
  combination, and checking at sinks closes the gap.

Runtime overrides via `%chain.trust` exist for the cases where source-derived trust
isn't enough (you fetched a value, validated it, want to elevate). Every override is
greppable in source, scoped to the granting frame, bounded by `min(granter, requested)`,
and disappears cleanly when the frame returns. The system has no permanent in-place
mutation of trust on objects — every elevation is bounded in time and space.

---

## Implementation Notes

vibecode: {
	"section": "implementation_notes",
	"role": "documents the implementation approach (uniform wrapping) and the strategies for keeping the runtime cost low; notes the wrap-on-taint escape hatch available if performance pressure justifies it",
	"key_concepts": ["uniform_wrapping", "shared_metatables", "interned_trust_constants",
		"compact_field_names", "single_combine_helper", "wrap_on_taint_escape_hatch"]
}

The runtime uses **uniform wrapping**: every KScript value is a wrapped object
carrying its source and trust alongside its raw value. There are no special-case
"untagged" values and no second-class types. This keeps the conceptual model simple
at the cost of always allocating a wrapper per value. The implementation aims to
keep that cost low.

Strategies for a lean wrapped-value runtime:

- **Shared metatables per type.** One metatable for wrapped strings, one for wrapped
  numbers, etc. Operations are defined once on the shared metatable, not per value.
- **Interned trust constants.** There are only a handful of trust levels (initially
  trusted and untrusted). They are defined once as module-level singletons; every
  wrapped value references the same shared marker. No per-value allocation for the
  trust field itself.
- **Compact field names.** Wrapped values use single-character field names (`v` for
  value, `t` for trust, `s` for source) to keep table layout small.
- **One combine helper.** All operators (`+`, `..`, `==`, etc.) call a single
  `combine_trust(a, b)` function rather than reimplementing the propagation rule.
  Keeps the trust logic in one place and the metamethods tiny.
- **Avoid double-wrapping.** When an operation produces a wrapped result whose inputs
  already had the right trust, the wrapper from one input can be reused rather than
  allocating a fresh one.

### Escape hatch: wrap-on-taint

If uniform wrapping becomes a real performance bottleneck, the spec leaves room for
an alternative implementation strategy: **wrap only tainted values**, leaving trusted
values as bare native primitives (the Perl `-T` model). Trusted values stay fast;
combining bare with wrapped produces wrapped; sinks check for wrapped inputs before
acting.

This is purely an implementation choice, not a spec change. Code written against the
uniform-wrapping model continues to behave the same way under wrap-on-taint, because
the externally observable rules (intersection on combination, sinks check trust,
`%chain.trust` overrides) are identical.

The current implementation uses uniform wrapping. Wrap-on-taint is documented here so
the option remains visible if profiling later shows it's needed.
