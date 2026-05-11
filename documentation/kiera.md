# Kiera

Kiera is a foreign object API — a protocol for working with remote objects across different
languages and systems. It is the umbrella that holds the mikobase, KScript, and Q0 together.
See [overview.md](overview.md) for the full picture.

Class names in Kiera use UNS strings (URLs without the `https://` prefix), providing a
globally unique namespace. For example: `kiera.uno/mikobase`, `foo.com/character`.

The mikobase, Q0, and the object model are all Kiera components under the `kiera.uno` namespace.

See [ideas/marina.md](ideas/marina.md) for a prior design exploration.

---

## `%kiera`

vibecode: {
	"section": "kiera_system_method",
	"role": "documents the %kiera system method for accessing the global Kiera object namespace",
	"key_concepts": ["%kiera", "UNS_lookup", "built-in_objects", "kiera.uno_default_namespace", "bare_name_shorthand"]
}

`%kiera` is a KScript system method that provides access to the global Kiera object
namespace. `%kiera[UNS]` returns the object registered at that UNS address.

In the first version, only a predefined set of built-in objects are available. When
remote object retrieval lands, libraries will be resolved on demand — the engine pulls
from a configurable chain of providers (typically a local cache first, then remote
sources), with no install step. See [overview.md — Libraries Are Cached, Not Installed](overview.md#libraries-are-cached-not-installed).

### Shorthand for built-in classes

Bare names in `%kiera[...]` — any key without a domain — resolve to `kiera.uno/...`:

```
%kiera['null']         # same as %kiera['kiera.uno/null']
%kiera['true']         # same as %kiera['kiera.uno/true']
%kiera['mikobase/memory']  # same as %kiera['kiera.uno/mikobase/memory']
```

`kiera.uno` is the default namespace for `%kiera` lookups.

---

## `%kiera.call`

vibecode: {
	"section": "kiera_call",
	"role": "documents the %kiera.call method for explicit remote method invocation",
	"key_concepts": ["%kiera.call", "remote_method_call", "target_object", "method_symbol", "keyword_params", "%chain_forwarding"]
}

`%kiera.call` makes an explicit remote method call on a Kiera object:

```
%kiera.call($person, :save, name: 'Jean-Luc')
```

The three arguments are:
1. The target object
2. The method name (a symbol)
3. Any keyword parameters to pass

`%kiera.call` automatically forwards the current `%chain` context to the remote call —
the same chain the calling function is running under. `%role` is reserved for possible
future use and is not part of early versions.

---

## `remote function`

vibecode: {
	"section": "remote_function",
	"role": "documents the remote function syntactic sugar for delegating to %kiera.call",
	"key_concepts": ["remote_function", "syntactic_sugar", "%kiera.call_delegation", "interchangeable_forms"]
}

`remote function` is a shorthand for defining a method that delegates to `%kiera.call`.
Inside a class definition, this:

```
remote function &save(name:)
end
```

is equivalent to generating a wrapper that calls:

```
%kiera.call(self, :save, name: name)
```

It is purely syntactic sugar — there is no separate remote dispatch mechanism. The
explicit `%kiera.call` form and the `remote function` shorthand are interchangeable.

---

## `kiera.uno` Namespace

vibecode: {
	"section": "kiera_uno_namespace",
	"role": "catalogs all built-in classes in the kiera.uno namespace",
	"key_concepts": ["kiera.uno/null", "kiera.uno/true", "kiera.uno/false", "kiera.uno/mikobase", "kiera.uno/exception", "kiera.uno/record", "kiera.uno/reference", "kiera.uno/dbfile"]
}

### Language and Runtime

| Class | Description |
|---|---|
| `kiera.uno/null` | Null class; always falsey; subclassable |
| `kiera.uno/true` | True class; always truthy; subclassable |
| `kiera.uno/false` | False class; always falsey; subclassable |
| `kiera.uno/mikobase` | Abstract mikobase base class |
| `kiera.uno/mikobase/memory` | SQLite in-memory mikobase (`:memory:`) |
| `kiera.uno/mikobase/sqlite` | SQLite file-backed mikobase |
| `kiera.uno/mikobase/http` | HTTP server exposing a mikobase over the network |
| `kiera.uno/mikobase/server` | Managed mikobase server for KScript++ fork coordination |
| `kiera.uno/helper` | Base helper class |
| `kiera.uno/loop` | Loop object |
| `kiera.uno/exception` | Base exception class |
| `kiera.uno/exception/error` | Runtime error |
| `kiera.uno/exception/return` | Function return |
| `kiera.uno/exception/exit` | Process exit (graceful — unwinds stack, runs GC) |
| `kiera.uno/exception/abort` | Process abort (violent — no unwind, no GC) |
| `kiera.uno/warning` | Base warning class |

### Object Store

| Class | Description |
|---|---|
| `kiera.uno/record` | Base record class |
| `kiera.uno/record/class` | Class definitions |
| `kiera.uno/reference` | Record reference |
| `kiera.uno/dbfile` | File attachment |
