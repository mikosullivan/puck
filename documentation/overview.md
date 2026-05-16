# Project Overview

## What Is This?

vibecode: {
	"section": "what_is_this",
	"role": "introduces the Kiera ecoverse and its three core components",
	"key_concepts": ["Kiera_ecoverse", "Mikobase", "KScript", "Kiera_protocol", "Q0", "UNS"]
}

This project is the **Kiera ecoverse** — a suite of interconnected tools for storing,
querying, and programming with objects across different languages and systems. The core
components are:

- **Mikobase** — a live, portable object store with a class-based model and a JSON query language (Q0)
- **KScript** — a lightweight, embeddable programming language
- **Kiera** — a protocol for working with remote objects across languages and systems

---

## The Components

vibecode: {
	"section": "the_components",
	"role": "summarizes each major component: Mikobase, KScript, Kiera, and Packaged Mikobases",
	"key_concepts": ["Mikobase", "KScript", "Kiera", "packaged_mikobases", "UNS", "Q0", "KScriptJSON"]
}

### Mikobase

A mikobase is a live object store. You define classes, store records, and query them using
**Q0** — a JSON-based query language. It is NoSQL and class-based.

Key ideas:
- Records have a class, a stable identity, and an append-only version history
- Class names use **UNS** (Universal Namespace) — a URL without `https://`, e.g. `foo.com/character`
- Queries are JSON objects: `{"action": "select", "class": "foo.com/character"}`
- A mikobase can be in-memory, file-backed, or served over HTTP
- A mikobase is always a live process — not a passive file

The first implementation is a Python SQLite engine. See [requirements.md](mikobase/requirements.md)
and [q0.md](mikobase/q0.md).

### KScript

KScript is the programming language of the Kiera ecoverse. It handles computation and
control flow — the things Q0 deliberately does not do.

Key ideas:
- Lightweight and embeddable — small enough to run inside a mikobase engine
- Single-threaded by design
- Humans write KScript; it transpiles to **KScriptJSON** for execution
- Classes, functions, closures, exceptions, and a security model are all built in
- Mikobases are KScript's object store

See [kscript/kscript.md](kscript/kscript.md) for the language reference and
[kscript/kscriptjson.md](kscript/kscriptjson.md) for the runtime format.

### Forking (opt-in KScript feature)

KScript is single-threaded by default. **Forking** is an opt-in feature
the engine grants on request: a script that doesn't need it sees `%forks`
and `%tmp` as `null` and runs as a normal single-threaded program. A
script that does use forking spawns isolated KScript processes that
coordinate through shared mikobases — no shared-memory primitives, no
locks. (Previously documented as a separate language variant called
"KScript++"; that's been merged into KScript.)

See [ideas/plusplus/threads.md](ideas/plusplus/threads.md) for the design
notes.

### Kiera

Kiera is a protocol for working with objects across different languages and systems.
All class names use UNS strings. `%kiera[UNS]` in KScript retrieves a registered object
by its UNS address. Remote methods are called via `%kiera.call($object, :method, params)`.

See [kiera.md](kiera/kiera.md).

### Packaged Mikobases

A mikobase can also be packaged as a portable, self-contained file — a complete object
environment bundling class definitions, KScript behavior, seed records, and a capabilities
manifest. A packaged mikobase can be shared, imported into any running mikobase, or sent
to a remote system for execution via Kiera.

See [mikobase.md](mikobase/mikobase.md).

---

## Implementation Status

vibecode: {
	"section": "implementation_status",
	"role": "tracks the development status of each Kiera ecoverse component",
	"key_concepts": ["active_development", "design_phase", "Python_SQLite_engine", "Q0", "KScript"]
}

| Component | Status |
|---|---|
| Mikobase Python SQLite engine | In active development |
| Q0 query language | Designed; implemented in Python engine |
| KScript | Design phase |
| KScriptJSON | Design phase |
| Forking (opt-in KScript feature) | Early design; not in active development |
| Kiera protocol | Early design |
| Packaged mikobase | Early design |

---

## How It Fits Together

vibecode: {
	"section": "how_it_fits_together",
	"role": "shows the data flow from KScript source through to SQLite and back",
	"key_concepts": ["KScript_to_KScriptJSON", "interpreter", "mikobase", "SQLite", "Q0", "opt_in_forking_concurrency"]
}

```
Developer writes KScript
        ↓
Transpiles to KScriptJSON
        ↓
KScript interpreter runs it
        ↓
Reads/writes to a Mikobase (object store)
        ↓
Mikobase is backed by SQLite (memory or file)
        ↓
Queries expressed in Q0 (JSON)
```

When the opt-in forking feature is enabled, multiple KScript processes share a mikobase,
turning it into the coordination mechanism for concurrent work.

---

## Key Concepts

vibecode: {
	"section": "key_concepts",
	"role": "glossary of the most important concepts in the Kiera ecoverse",
	"key_concepts": ["UNS", "Q0", "KScript_syntax", "mikobase_live_process", "single-threaded", "pass-through_fields",
		"vibecode", "comment", "misc", "enterprise"]
}

**UNS (Universal Namespace)** — class names are URLs without `https://`. Your domain
gives you a globally unique namespace: `mycompany.com/character`. Built-in classes use
`kiera.uno/...`.

**Q0** — the query language. Every query is a JSON object. `select`, `create`, `update`,
`delete`. Engines translate Q0 to SQL or forward it over HTTP.

**KScript** — `$foo` is a variable, `&foo` calls it as a function, `$$foo` is the
variable object. Blocks end with `end`. Classes use a DSL. Safe navigation with `&.`.
Code is shared as KScript source; KScriptJSON is the compiled runtime form.

**Mikobase** — not a passive file. Always a live process. Objects in the mikobase are always
alive as long as the process is running.

**KScript is single-threaded by default.** One execution context, no concurrency
primitives. Concurrency arrives via an opt-in forking feature (engine-granted; off by
default).

**Reserved pass-through fields** — every Kieraverse object has four reserved keys that
travel with it silently: `vibecode` (AI-readable context), `comment` (human-readable
notes), `misc` (informal ad hoc data), and `enterprise` (formally defined standards).
All four are always passed through; never stripped. See [vibecode.md](ecoverse/vibecode.md).

**Libraries are cached, not installed** — KScript has no install step. Libraries are
referenced by UNS in source code and resolved on the fly. See the section below.

**No nanny code** — the system declines to second-guess deliberate developer choices.
Restrictions exist for safety, not for paternalism, and every restriction has an
explicit override. See "No Nanny Code" below.

---

## No Nanny Code

vibecode: {
	"section": "no_nanny_code",
	"role": "states the design principle that Kiera avoids paternalistic API restrictions; safe defaults and security guarantees remain, but blocking legitimate operations because the designer disapproves is rejected",
	"key_concepts": ["no_paternalism", "explicit_override_for_every_safe_default",
		"security_guarantees_are_not_nanny_code", "structural_rules_are_not_nanny_code",
		"borrowed_from_perl_enough_rope"]
}

Kiera follows a principle borrowed from Perl: **the system gives you enough rope to
hang yourself.** When the system declines to do something by default, there are
ways to override it if you choose.

The clean way to phrase it:

- **Nanny code** says "you can't, because I think you shouldn't."
- **Safe defaults** say "you have to be explicit if you want to."
- **Security guarantees** say "you can't, because allowing this would break the
  trust model the rest of the system depends on."

The first is what we avoid. The second and third stay. When in doubt: if a developer
wants to do something legitimate that the API blocks without giving them a way through,
that's nanny code.

---

## Libraries Are Cached, Not Installed

vibecode: {
	"section": "libraries_are_cached_not_installed",
	"role": "explains that KScript has no library installation step — libraries are referenced by UNS and resolved on demand from a provider chain that may include a cache",
	"key_concepts": ["no_install_step", "uns_reference", "engine_resolves_on_demand", "provider_chain", "cache"]
}

KScript has no library installation step. There is no `kscript install foo.com/bar`,
no `package.json`, no lockfile, no manifest. A library is **referenced** directly in
source code by its UNS:

```
%kiera['foo.com/bar'].new
```

When the engine encounters that reference, it resolves the UNS through whatever
**provider chain** it has been configured with. A typical chain checks a local cache
first, then one or more remote providers; if the library isn't cached, the engine
fetches it on the fly and stores it for future use. Subsequent references to the same
UNS hit the cache with no network round-trip.

The provider chain is the engine's concern, not the script's. A developer's machine
might check a local cache, then a corporate mirror, then the canonical UNS host. A
locked-down production engine might be restricted to a single trusted source. The
script is unaware of where its libraries came from.

The cache holds **multiple versions** of the same library side by side. Versioning in
Kiera is **date-pinned**: the kiera object carries a cutoff timestamp (the *version
window*) that governs the entire library tree it serves, and each `(UNS, version, date)`
triple is its own cached artifact. Different programs running through the same engine
with different kiera cutoffs each get the appropriate version with no cross-interference.
See [kiera.md](kiera/kiera.md) and [versioning.md](kscript/versioning.md) for the full model.

This is a design intent for how remote object resolution will work in KScript. Today's
engines resolve only the built-in `kiera.uno/...` classes; remote resolution is not yet
implemented. When it lands, it will work this way — there will be no install step, at
least not initially.
