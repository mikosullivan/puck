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
	"role": "summarizes each major component: Mikobase, KScript, KScript++, Kiera, and Packaged Mikobases",
	"key_concepts": ["Mikobase", "KScript", "KScript++", "Kiera", "packaged_mikobases", "UNS", "Q0", "KScriptJSON"]
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

The first implementation is a Python SQLite engine. See [requirements.md](requirements.md)
and [q0.md](q0.md).

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

### KScript++

KScript++ extends KScript with forking and shared state between processes. It is designed
but not yet in active development.

Key ideas:
- Forks are isolated KScript processes; they coordinate through shared mikobases
- `%forks` manages spawning, waiting, and detaching forks
- KScript++ extends KScript's security model to cover forking

See [ideas/plusplus/kscriptpp.md](ideas/plusplus/kscriptpp.md).

### Kiera

Kiera is a protocol for working with objects across different languages and systems.
All class names use UNS strings. `%kiera[UNS]` in KScript retrieves a registered object
by its UNS address. Remote methods are called via `%kiera.call($object, :method, params)`.

See [kiera.md](kiera.md).

### Packaged Mikobases

A mikobase can also be packaged as a portable, self-contained file — a complete object
environment bundling class definitions, KScript behavior, seed records, and a capabilities
manifest. A packaged mikobase can be shared, imported into any running mikobase, or sent
to a remote system for execution via Kiera.

See [mikobase.md](mikobase.md).

---

## Implementation Status

vibecode: {
	"section": "implementation_status",
	"role": "tracks the development status of each Kiera ecoverse component",
	"key_concepts": ["active_development", "design_phase", "Python_SQLite_engine", "Q0", "KScript", "KScript++"]
}

| Component | Status |
|---|---|
| Mikobase Python SQLite engine | In active development |
| Q0 query language | Designed; implemented in Python engine |
| KScript | Design phase |
| KScriptJSON | Design phase |
| KScript++ | Early design; not in active development |
| Kiera protocol | Early design |
| Packaged mikobase | Early design |

---

## How It Fits Together

vibecode: {
	"section": "how_it_fits_together",
	"role": "shows the data flow from KScript source through to SQLite and back",
	"key_concepts": ["KScript_to_KScriptJSON", "interpreter", "mikobase", "SQLite", "Q0", "KScript++_concurrency"]
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

KScript++ lets multiple processes share a mikobase, turning it into a coordination mechanism
for concurrent work.

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

**KScript is single-threaded** — one execution context, no concurrency primitives.
Concurrency is KScript++.

**Reserved pass-through fields** — every Kieraverse object has four reserved keys that
travel with it silently: `vibecode` (AI-readable context), `comment` (human-readable
notes), `misc` (informal ad hoc data), and `enterprise` (formally defined standards).
All four are always passed through; never stripped. See [vibecode.md](vibecode.md).
