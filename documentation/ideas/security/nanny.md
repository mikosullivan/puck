# The Nanny (idea)

**Status:** early-stage idea, deferred. Seed-planted in a discussion
about Jasmine's
[`no_writers_ok`](../../charlie/jasmine/jasmine.md#constructing-a-jasmine-log) escape
hatch — the first filed instance of a "Don't worry nanny" feature.

**Current direction (2026-05-13):** invent opt-out flags ad-hoc
per feature for now. Let real use cases accumulate, then look at
where they converge before designing a unified nanny object. The
exploration below stays filed as the eventual design space; we're
just not picking from it yet.

**Ideas that have come up in conversation** (noted, not specified):

- Nanny as an **opt-in developer helper**, not built into every
  object. A function or object that has quietable warnings can
  pull in a nanny helper to manage them; objects that don't need
  it ignore it entirely. Simple addition, not pervasive
  infrastructure.
- **Escalation** — turning warnings into exceptions based on
  configured severity, so strict deployments can promote
  warnings to hard failures without changing calling code. Miko
  flagged this as particularly appealing.

---

<a id="sketch-the-nanny-helper"></a>
## 1 Sketch: the nanny helper

(Written down while it was fresh. Not an official spec; still
deferred. Refined further as real use cases land.)

<a id="shape"></a>
### 1.1 Shape

A nanny is essentially a **hash of warning names → booleans**.
Keys are warning names (strings, chosen by the author). Values
are booleans: `true` means the warning is active (it will fire);
`false` means it's suppressed.

**The default for any unknown key is `true`.** Warnings are
active until explicitly silenced.

<a id="developer-api-configuring"></a>
### 1.2 Developer API (configuring)

Hash-style access on the nanny:

```
$foo.nanny['some_warning'] = false   # silence it
$foo.nanny['some_warning'] = true    # restore the default
$foo.nanny['some_warning']           # read current value
```

That's the whole surface for configuration.

<a id="author-api-reporting-concerns"></a>
### 1.3 Author API (reporting concerns)

Inside the code that has the nanny:

```
%self.nanny.warn('some_warning', 'something is off')
```

The `warn` method checks the hash:

- If the value for the key is `true` (or unset, which defaults to
  `true`), the warning fires — emitted to whatever destination
  the nanny is wired to (stderr, Jasmine, etc. — TBD).
- If the value is `false`, the warning is suppressed silently.

<a id="naming-convention"></a>
### 1.4 Naming convention

Warning names are author-chosen strings. There's no central
registry; each author picks names that describe their concerns
clearly. Suggested guidelines (not enforced):

- Lowercase with underscores.
- Descriptive of the *concern*, not the action
  (`no_writers`, `nowhere_to_go`, `unverified_input` — not
  `silence_me` or `ok_flag`).
- Discoverable via `$foo.nanny.keys` (or similar enumeration —
  TBD).

<a id="whats-not-in-the-sketch"></a>
### 1.5 What's not in the sketch

- **Where emitted warnings actually go.** stderr? Jasmine?
  Engine-configurable? Defer until we know.
- **Escalation** — promoting a warning to an exception. The
  appealing extension. Could be a second hash
  (`$foo.nanny.escalate['some_warning'] = true`) or a value type
  beyond boolean. Defer.
- **Listing known warnings** for documentation. Possible API:
  `$foo.nanny.warnings` returns the set of names the author has
  ever called `warn` with. Defer.

These are notes from design discussion, not commitments. Real
shape will develop as actual use cases accumulate.

---

<a id="whats-a-nanny"></a>
## 2 What's a "nanny"?

In Mikobase's no-nanny-code philosophy, a **nanny** is the part of
the framework that watches for likely misconfigurations or risky
patterns and warns the developer. The catch: the developer can flip
a named flag to silence the warning when they've made the call
deliberately ("Don't worry nanny" features).

Today, "the nanny" is conceptual — a design *pattern* expressed
ad-hoc per feature. Each feature that needs warn-then-silence
behavior implements it locally: `no_writers_ok` on Jasmine,
presumably others on the way. The framework doesn't have a unified
nanny *thing*.

---

<a id="what-would-first-class-object-mean"></a>
## 3 What would "first-class object" mean?

A few possible shapes (not mutually exclusive):

<a id="option-a-a-system-method"></a>
### 3.1 Option A: A system method

`%nanny`, accessible like `%chain`, `%role`, `%engine`. Lives in
the chain (or wherever it makes sense) and provides a unified API
for:

- Emitting warnings: `%nanny.warn('no-writers', "log has no stores")`
- Querying state: `%nanny.silenced?('no-writers')`
- Silencing: `%nanny.silence('no-writers')` (or scoped via flags)

Code anywhere in the call chain can ping the nanny without
threading anything through signatures.

<a id="option-b-a-class"></a>
### 3.2 Option B: A class

`kiera.uno/nanny` — a type you can instantiate and attach to
objects, chains, or applications. Each instance carries its own set
of silenced warnings. Useful if different parts of the program
should have different nanny tolerances (production stricter than
development, or per-tenant configs).

<a id="option-c-a-property-on-every-object"></a>
### 3.3 Option C: A property on every object

Every framework object exposes `.nanny`, returning the nanny that
governs it. Could be a shared nanny by default, but objects (or
their owning roles) can install their own.

<a id="option-d-some-hybrid"></a>
### 3.4 Option D: Some hybrid

The most likely shape — `%nanny` for ambient access, backed by a
`kiera.uno/nanny` class so it can be instantiated, with sensible
defaults that fall through to a system-wide nanny.

---

<a id="why-this-might-be-worth-promoting"></a>
## 4 Why this might be worth promoting

A few benefits a first-class nanny could give us:

- **Consistency.** Every warn-then-silence check works the same way
  (same opt-out shape, same emission channel, same listable surface
  of "what could the nanny warn me about?").
- **Discoverability.** Developers can ask the nanny what warnings
  exist for a given object, what's been silenced, what hasn't —
  rather than hunting through docs to find every `_ok` flag.
- **Composability with Jasmine.** Nanny emissions could nest into
  `%chain.log` automatically — every warning the nanny issued
  during an operation becomes part of the call frame, attributed by
  source. Audit trail for "what did the framework complain about,
  and did the dev shush it?"
- **Severity levels.** A nanny object can support a graduated
  surface (info / warn / error), not just on/off.
- **Centralized policy.** A nanny attached to a role or a chain can
  carry policy ("this code path runs with all nannies as errors,"
  "this batch job suppresses noisy warnings by default") instead of
  each call site reinventing it.

---

<a id="open-design-questions"></a>
## 5 Open design questions

- **Where does the nanny *live*?** Chain-scoped (so role-boundary
  wipes refresh it)? Object-scoped (so each object carries its
  own)? Both, with override semantics?
- **How are warnings named?** Strings (`"no-writers"`)? Structured
  identifiers like Kiera UNS-style? Per-feature enums?
- **How are warnings silenced?** Per-call (`no_writers_ok: true` at
  construction)? Per-instance (`$log.silence("no-writers")`)?
  Per-chain (`%nanny.silence(...)`)? Per-role?
- **How does silencing nest?** If a caller silences a warning and
  calls untrusted code, does the silence apply inside the call?
  (Probably no — silences shouldn't cross role boundaries any more
  than other chain state does.)
- **How does it interact with Jasmine?** Warnings appended to
  `%chain.log` automatically? Only when explicitly logged? A
  dedicated `nanny_warnings` field on entries?
- **Severity levels?** Is "info / warn / error" useful, or is
  "warn" the only level we need?
- **Can the nanny *block*?** I.e., is there ever a nanny check that
  refuses to proceed unless silenced? Or are all nanny outputs
  advisory-only?
- **Per-feature opt-out flags vs general silence API.** Do we keep
  named flags (`no_writers_ok`) as the developer-facing surface and
  treat `%nanny` as the *implementation*, or do we expose the
  generic silence API and deprecate named flags? (Probably keep
  named flags — they're more readable than string-keyed
  silencing — but that's a real choice.)

---

<a id="what-to-figure-out-first"></a>
## 6 What to figure out first

Before deep design, the load-bearing question is probably **what's
the developer-facing API**:

- Do developers continue using named per-feature flags
  (`no_writers_ok: true`), with `%nanny` as the plumbing they
  rarely touch directly?
- Or does `%nanny` become the primary surface, with named flags
  fading away?

That decision shapes everything else (warning identifiers, silence
scoping, etc.).

---

<a id="out-of-scope-for-now"></a>
## 7 Out of scope for now

This is exploration, not commitment. Filed so the idea has a home
while we iterate. Real spec when the design crystalizes.
