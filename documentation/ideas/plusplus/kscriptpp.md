# KScript++

## Status

```
vibecode: {
	"section": "status"
}
```

Design only. KScript++ is not yet in active development.

## Lua Implementation Note

Lua has no native fork support. When implementing forking in the Lua reference
implementation, prefer an existing Lua library over writing a C extension from scratch.
The goal is to avoid reimplementing Kiera in C just to handle forking.

---

## Overview

At this point, the only thing KScript++ adds over KScript is forking. It has not been
ruled out that forking may eventually move into KScript proper. For now it remains a ++
feature.

Everything in KScript is available in KScript++. The additions are opt-in — a program
that doesn't use forking is just KScript.

---

## Relationship to KScript

KScript is single-threaded by design. It is lightweight, embeddable, and safe to run
untrusted code in. KScript++ builds on top of it and adds concurrency capabilities.

KScript has a core security model (`untrusted()`, `%chain` sandboxing). KScript++ extends
that security model to cover forking — for example, a fork can be restricted from spawning
its own child forks. The security model is not weakened by KScript++; it is extended.

---

## Forking

KScript++ introduces `%forks`, a system method that returns the fork manager for the
current context. Each fork runs a single-threaded KScript interpreter independently.
Forks do not share memory — all coordination happens through mikobases.

See [threads.md](threads.md) for the full `%forks` API and threading model.

---

## Hives

Hives are implemented in KScript — a mikobase is a useful local object store on its own.
KScript++ adds the ability to share a mikobase between forked processes, making it the
coordination mechanism for concurrent forks.

See [mikobase.md](../mikobase.md) for the full mikobase design.

---

## Security Extensions

KScript++ extends KScript's core security model for the forking context:

- `%role` — identity and context store passed down the call chain. Probably a KScript++
  feature. See [roles.md](roles.md) for the full design.
- A forked process can be restricted from spawning its own child forks. This is the
  primary mechanism for preventing untrusted code from escaping its sandbox through
  forking.
- Further security design is TBD.

---

## What Stays in KScript

The following are KScript features, not KScript++:

- All language primitives, classes, functions, closures, exceptions, warnings
- `untrusted()`, `%chain` sandboxing
- The core security model
- Single-threaded execution context
- Hives as local object stores, including file-backed (`kiera.uno/mikobase/sqlite`)
