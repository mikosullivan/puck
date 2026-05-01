# Mikobase

## Overview

vibecode: {
	"section": "overview",
	"role": "introduces the mikobase as a live object store with Q0, class definitions, history, and locking",
	"key_concepts": ["mikobase", "object_store", "live_process", "Q0", "shared_objects"]
}

An mikobase is a full object store — in memory, file-backed, or served over a network.
It supports Q0 queries, class definitions, record history, transactions, and locking.
Any process that connects to a mikobase can reach in and use its objects at any time.

Objects in the mikobase are always alive for as long as the mikobase exists. A process's local
objects stay local. If an object needs to be shared, it must live in the mikobase.

---

## KScript vs. KScript++

vibecode: {
	"section": "kscript_vs_kscriptpp",
	"role": "distinguishes local mikobase use (KScript) from fork-shared mikobase use (KScript++)",
	"key_concepts": ["KScript", "KScript++", "local_object_store", "fork_sharing"]
}

Mikobases are a KScript feature — a mikobase is a useful local object store on its own. Sharing
a mikobase between forked processes is a KScript++ feature. See `ideas/plusplus/kscriptpp.md`.

---

## The Maintaining Process

vibecode: {
	"section": "maintaining_process",
	"role": "explains that a mikobase always requires a live process; not a passive file",
	"key_concepts": ["live_process", "maintaining_process", "in-memory", "server_process", "remote_service"]
}

A mikobase is not a passive data store — it requires a process to maintain it. "Always alive"
means alive for as long as the maintaining process is running. That process might be:

- A local in-memory object passed around within an application
- A server process on the same machine
- A remote service accessed over a network

There is no concept of a mikobase without something running it. Connecting to a mikobase means
connecting to a live process, not reading from a file.

---

## Object Ownership

vibecode: {
	"section": "object_ownership",
	"role": "states that the mikobase owns objects; processes connect and interact, not pass objects directly",
	"key_concepts": ["mikobase_ownership", "connect_and_interact", "no_direct_passing"]
}

The mikobase owns its objects. Processes do not pass objects to each other directly — instead,
they connect to the mikobase and interact with whatever is already there.

---

## Class Hierarchy

vibecode: {
	"section": "class_hierarchy",
	"role": "lists all mikobase implementation classes and their relationships",
	"key_concepts": ["kiera.uno/mikobase", "kiera.uno/mikobase/memory", "kiera.uno/mikobase/sqlite",
		"kiera.uno/mikobase/http", "kiera.uno/mikobase/server", "abstract_base_class"]
}

| Class | Description |
|---|---|
| `kiera.uno/mikobase` | Abstract base class (`abstract true`); full Q0 interface, locking, transactions |
| `kiera.uno/mikobase/memory` | SQLite in-memory database (`:memory:`) |
| `kiera.uno/mikobase/sqlite` | SQLite file-backed database |
| `kiera.uno/mikobase/http` | HTTP server that exposes a mikobase over the network |
| `kiera.uno/mikobase/server` | Managed mikobase server for KScript++ fork coordination |

Both SQLite implementations run on the same backend — the only difference is whether
SQLite is pointed at memory or a file. Q0 is just SQL in both cases, with no separate
in-memory query engine needed.

KScript code interacts only with the `kiera.uno/mikobase` interface and is unaware of the backend.

---

## Managed Mikobase Server (`kiera.uno/mikobase/server`)

vibecode: {
	"section": "managed_mikobase_server",
	"role": "documents the server class that manages mikobase lifetime around a fork pool",
	"key_concepts": ["kiera.uno/mikobase/server", "fork_coordination", "block_scoped_lifetime", "clean_shutdown"]
}

`kiera.uno/mikobase/server` is a managed mikobase server designed for KScript++ fork coordination.
It starts a server process, yields the mikobase to a block, waits for all forks spawned in
that block to complete, then shuts the server down cleanly:

```
%kiera['kiera.uno/mikobase/server'].run as $mikobase
    %forks.pool do
        %forks.run(mikobase: $mikobase, times: 4) do($mikobase)
        end
    end
    # all forks are done here
end
# server is shut down here
```

The server shuts down after the block exits — not before. Any forks still running when
the block exits will cause the server to wait before shutting down.

---

## HTTP Mikobase

vibecode: {
	"section": "http_mikobase",
	"role": "documents the HTTP transport wrapper including Unix sockets, TCP, and authentication options",
	"key_concepts": ["kiera.uno/mikobase/http", "Unix_domain_sockets", "TCP", "auth_peer", "auth_token", "auth_open"]
}

`kiera.uno/mikobase/http` wraps any mikobase and exposes it over HTTP. The mikobase's locking model
handles concurrent connections — the HTTP server is a transport layer only. Connection-level
concurrency lives in the C layer, not in KScript.

This is a KScript feature, not KScript++. A process can serve a mikobase over HTTP without
any forking. KScript++ forks can then connect to it as a shared mikobase.

### Unix Domain Sockets (preferred)

For local communication, KScript steers developers toward Unix domain sockets. They use a
file path instead of a port number, bypass the network stack entirely, and access is
controlled by filesystem permissions — faster and more secure than TCP for local use.

```
$mikobase = %kiera['kiera.uno/mikobase/sqlite'].new('/path/to/db')
$server = %kiera['kiera.uno/mikobase/http'].new(mikobase: $mikobase, socket: '/var/run/myhive.sock', auth: :peer)
$server.start
```

### TCP (for network access)

Port-based listening is supported when the mikobase needs to be reachable over a network:

```
$server = %kiera['kiera.uno/mikobase/http'].new(mikobase: $mikobase, port: 8080, auth: :token, token: 'mysecrettoken')
$server.start
```

Unix domain sockets are the default and recommended approach for local use. TCP is for
cases where remote access is explicitly needed.

### Authentication

The `auth:` parameter is required — there is no default. Three options:

**`:peer`** — peer credentials via `SO_PEERCRED`. The kernel verifies the connecting
process's identity (UID, GID, PID). No shared secrets, no setup. Only available for
Unix domain sockets.

```
$server = %kiera['kiera.uno/mikobase/http'].new(
    mikobase: $mikobase,
    socket: '/var/run/myhive.sock',
    auth: :peer
)
```

**`:token`** — access token (password). The client sends a token as part of the connection
handshake. Works for both Unix sockets and TCP.

```
$server = %kiera['kiera.uno/mikobase/http'].new(
    mikobase: $mikobase,
    socket: '/var/run/myhive.sock',
    auth: :token,
    token: 'mysecrettoken'
)
```

**`:open`** — no authentication. Anyone who can reach the socket or port can connect.
Use only in controlled environments.

```
$server = %kiera['kiera.uno/mikobase/http'].new(
    mikobase: $mikobase,
    socket: '/var/run/myhive.sock',
    auth: :open
)
```

---

## Hot and Cold Connections

vibecode: {
	"section": "hot_and_cold_connections",
	"role": "defines hot vs cold connection modes and per-query overrides",
	"key_concepts": ["cold_connection", "hot_connection", "local_copy", "live_object", "per-query_override", "hot_true"]
}

Every connection to a mikobase is either **cold** (the default) or **hot**. The mode is set
at connection time and applies to all objects retrieved through that connection.

### Cold (default)

A cold connection returns local copies of records. You fetch a record, work with it
locally, and save it back explicitly:

```
$mikobase = %kiera['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer)

$record = $mikobase.q0(...)
$record['foo'] = 'bar'
$record.save
```

Cold is the default because most database interaction is traditional, and accidentally
using a cold connection is safe — you just work with a local copy.

### Hot

A hot connection returns live objects. Every read and write is a round trip to the mikobase,
with locking applied automatically. There is no local copy and no explicit save:

```
$mikobase = %kiera['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer, hot: true)

$mikobase['clients'].shift   # atomic read-and-remove, one round trip
$mikobase['results'] << $result   # atomic write, one round trip
```

Hot connections are the correct choice when multiple forks share a mikobase — every operation
needs to be atomic and consistent across concurrent readers and writers.

### Local mikobases

The same `hot:` parameter applies to local mikobases:

```
$mikobase = %kiera['mikobase/memory'].new(hot: true)
$mikobase = %kiera['mikobase/sqlite'].new('/path/to/db', hot: true)
```

On a local mikobase, hot means every field access hits SQLite directly. Cold means load the
record into memory, work with it locally, save explicitly.

### Multiple connections, different modes

Two connections to the same mikobase can have different modes:

```
$hot  = %kiera['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer, hot: true)
$cold = %kiera['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer)
```

This is valid — for example, one hot connection for fork coordination and one cold
connection for bulk record processing.

### Per-query override

The connection mode can be overridden on any individual query. The query-level setting
takes precedence over the connection default:

```
# Cold connection, but this query returns a hot object
$record = $mikobase.q0({...}, hot: true)

# Hot connection, but this query returns a cold object
$record = $mikobase.q0({...}, hot: false)
```

---

## Locking

vibecode: {
	"section": "locking",
	"role": "describes automatic shared/exclusive locking model for reads and writes",
	"key_concepts": ["shared_lock", "exclusive_lock", "automatic_locking", "no_explicit_lock_api"]
}

Mikobase access follows database-style locking:

- **Reads** use shared locks — multiple processes can read simultaneously.
- **Writes** use exclusive locks — one process acquires an exclusive lock, writes, commits,
  and releases. No other process can read or write during a write transaction.

The mikobase detects whether an operation is a read or write and acquires the appropriate lock
automatically. There is no explicit lock/unlock API in normal usage.

---

## Transactions

vibecode: {
	"section": "transactions",
	"role": "documents the nested transaction model with commit, rollback, and auto-rollback on exit",
	"key_concepts": ["transaction", "nested_transactions", "commit", "rollback", "auto-rollback", "exit"]
}

Mikobases support transactions using the following model:

- `transaction()` begins a transaction and returns a handle.
- Nesting is supported — each call creates a new transaction nested under the current one.
- A transaction block that exits without an explicit `commit()` is automatically rolled back.
- `commit()` commits the transaction and keeps execution running.
- `exit()` rolls back and immediately exits the block.

---

## `%bucket` in the Mikobase

vibecode: {
	"section": "bucket_in_mikobase",
	"role": "explains how %bucket can be backed by a mikobase for transparent fork coordination",
	"key_concepts": ["%bucket", "include_private", "mikobase_backed", "fork_private_vars", "@foo"]
}

Setting `include_private = true` on a mikobase causes `%bucket` to be backed by the mikobase for
any fork that connects to it. The fork's `@foo` reads and writes go directly to a live
object in the mikobase — child forks don't need to reference the mikobase explicitly at all.

```
$mikobase = %kiera['kiera.uno/mikobase/memory'].new
$mikobase.include_private = true

%forks.run(mikobase:$mikobase) do($mikobase)
    @foo = 'bar'    # reads and writes go directly to the mikobase
end
```

`%bucket` is synced to its own mikobase, not any mikobases that are explicitly passed through.

---

## Record Change Signals

vibecode: {
	"section": "record_change_signals",
	"role": "documents the listener system for before_save and after_save signals on records",
	"key_concepts": ["listen", "before_save", "after_save", "change_object", "Q0_query_target", "network_boundary"]
}

### Listening to records

A process can register listeners on the mikobase for specific records or Q0 queries:

```
# listen to a specific record
$mikobase.listen $record, :before_save do($change)
end

$mikobase.listen $record, :after_save do($change)
end

# listen to every record matching a Q0 query
$mikobase.listen {class: 'foo.com/invoice'}, :before_save do($change)
end

# shortcut for class-level listening
$mikobase.listen 'foo.com/invoice', :after_save do($change)
    %forks.detach do
        &send_email($change.record)
    end
end
```

The change object carries:

```
$change.record    # the record that changed
$change.class     # its class
$change.fields    # hash of changed fields: {field: {old:, new:}}
```

### `before_save` and `after_save`

**`:before_save`** fires within the transaction, before the commit. If the handler raises
an error, the entire transaction is rolled back. This is the mechanism for enforcing
consistency rules.

**`:after_save`** fires after the transaction is committed. The change cannot be
cancelled. This is the mechanism for side effects — notifications, derived records,
background work.

### Signals stay within the mikobase

By default, `:before_save` signals are dispatched within the mikobase process only. They are
not forwarded over the network to remote clients. This is intentional — a network round
trip inside a transaction would be slow and fragile.

Pre-save validation is the developer's responsibility. The recommended approach is to
validate on the client side before saving, or to register `:before_save` handlers as
part of the mikobase server's own setup code.

### Listener matching

A listener fires when the record being saved matches its target:

- A record target matches only that specific record.
- A Q0 query target matches any record that satisfies the query after the change is
  applied. This includes records transitioning into the match set.

### Future: remote validation

The current design puts remote validation responsibility on the developer. 
A future addition could provide a structured layer on top of `:before_save` signals — a declarative way to attach remote validation to the :before_save process.

---

## Packaged Mikobases

vibecode: {
	"section": "packaged_mikobases",
	"role": "describes the packaged mikobase format: bundled schema, KScript, records, and capabilities",
	"key_concepts": ["packaged_mikobase", "worldlet", "capabilities_manifest", "portable_distribution",
		"use_cases", "lifecycle"]
}

### Worldlets

A **worldlet** is the marketing name for a packaged mikobase. The technical concept and
implementation are always referred to as a "packaged mikobase" in internal documentation
and developer-facing APIs. When speaking to end users or publishing to a registry, the
term is "worldlet."

See [worldlet.md](worldlet.md) for the worldlet file format.

---

A mikobase can be packaged as a portable, self-contained file. A packaged mikobase bundles
structure, behavior, and state into a single unit that can be shared, imported, or executed
remotely.

Traditional systems separate code, data, APIs, and runtime. A packaged mikobase unifies them:

| Concept | What it offers |
|---|---|
| Library | Reusable code |
| API | Interface to a system |
| Database dump | Static data snapshot |
| Container | Runtime environment |
| **Packaged mikobase** | **Code + data + behavior, as a living object world** |

A library says: "here are functions you can call."
A packaged mikobase says: "here is a functioning object ecosystem you can import."

### Contents

A packaged mikobase may include:

- **Class definitions** — the schema, including fields, joins, and constraints
- **KScript** — methods and behavior attached to those classes
- **Records** — seed objects or full data exports
- **Hooks** — `before_save` / `after_save` listeners
- **Capabilities** — a manifest declaring what the mikobase requires to run
- **Scheduled jobs** — time-based tasks (not yet designed)
- **External connectors** — outbound integrations (not yet designed)

Class names inside a packaged mikobase use UNS — the publisher's domain provides a globally
unique namespace automatically. A mikobase published by `borg.com` installs classes like
`borg.com/character`, `borg.com/ship`, etc. No registration required, no collision possible.

### Format

A packaged mikobase is a single file. The format is not yet defined in detail, but the
contents are:

- A mikobase export (class definitions and records as Q0-compatible JSON)
- KScript source for any attached methods and hooks
- A capabilities manifest

The format design should happen alongside the KScriptJSON format discussion.

### Capabilities Manifest

A packaged mikobase declares what it needs before it is installed. The host asks the user to
approve these capabilities explicitly — nothing is granted silently.

```
requires:
  network:
    - api.example.com
  schedule:
    - every 5 minutes
  storage:
    - create objects: PricePoint
```

This connects directly to KScript's security model. The capabilities declaration is
essentially an upfront jail configuration — the mikobase runs with only the permissions
it declared. Undeclared capabilities are unavailable.

### Lifecycle

```
Author packages mikobase
        ↓
Mikobase shared (file, URL, registry)
        ↓
Recipient imports mikobase into their running mikobase
        ↓
Capabilities reviewed and approved
        ↓
Classes, records, and KScript installed
        ↓
Mikobase runs inside recipient's environment
```

A packaged mikobase can also be sent to a remote system for execution via Kiera, without
installing it locally:

```
send packaged mikobase → remote mikobase → execute → return result
```

### Use Cases

**Open-source object systems** — publish a mikobase the way you publish a library.
Anyone who imports it gets the full schema and behavior, not just a data dump.

**Reproducible bugs** — ship the exact mikobase state that triggered a bug. The recipient
gets the object structure, the data, and the behavior in one file. No setup required.

**Test fixtures** — seed a mikobase with a known starting state for testing. Packaged
mikobases are deterministic and portable across machines.

**Portable computation** — send a packaged mikobase to a remote system, run its logic
there, and get a result back. The computation travels with its data.

**Installable data models** — a recipe manager, a home inventory, a CRM, a research
notebook. Publish a mikobase; others install a working system, not a blank schema.

### What Is Not Yet Designed

- The packaged mikobase file format (depends on KScriptJSON format design)
- The capabilities manifest syntax and enforcement mechanism
- Scheduled jobs
- External connectors
- A mikobase registry or distribution mechanism
- Storage backends beyond SQLite