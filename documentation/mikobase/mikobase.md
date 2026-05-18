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

**Worldlets are the primary use case for mikobase** — packaged, portable mikobases
used for scenarios, scratch state, AI conversation captures, and similar
short-lived or snapshot-shaped workloads. Other use cases (microservices, larger
services) are supported, but worldlets drive design decisions.

---

## v1 Scope

Mikobase is large by ambition. The v1 release keeps the surface
focused:

- **Three storage engines ship in v1:**
  1. **SQLite file-backed** — long-lived, file-persisted databases.
  2. **SQLite in-memory** (`:memory:`) — ephemeral SQLite-backed
     databases. Same SQLite backend as file-backed; only the
     storage target differs. Q0 queries are just SQL in both cases.
  3. **Worldlet-direct** — operates on the worldlet JSON structure
     directly, with no SQLite import/export step. Built for very
     short-lived workloads (AI2AI conversations, scratch sessions
     measured in milliseconds) where the import/export cost would
     dominate the actual work. Q0 queries are implemented against
     the JSON structure instead of via SQL.

  Mikobase still supports multiple engines as pluggable backends;
  these three are what ships in v1. Other backends (Postgres,
  etc.) come later as add-ons.
- **Time-travel stays in core.** It's well-designed already, not
  particularly expensive, and the toggle exists via
  [temporal vs non-temporal mode](#temporal-vs-non-temporal-mode)
  for cases that don't want it (opt in via `"temporal": false`).
- **Mikobase-as-filesystem: not in v1.** That whole brainstorm
  (see [ideas/mikobase-as-filesystem.md](../ideas/apps/mikobase-as-filesystem.md))
  is speculative. The filesystem-shaped interface, the
  SSH/SSHFS access pattern, the RCS-style versioning use case —
  none of it lands in v1. Revisit later.
- **Delta storage: deferred.** v1 ships with chunk storage only.
  The delta-based revision storage discussion is for later, when
  the filesystem-mode use case becomes real (which is also
  later). **And when we revisit it, deltas may turn out to be the
  *only* storage shape, not an alternative alongside chunks** —
  one mechanism covering everything (chunks for static content is
  trivially a degenerate delta against an empty base). Not
  decided; flagged so the eventual revisit doesn't assume the
  two-modes framing.

---

## Temporal vs Non-temporal Mode

vibecode: {
	"section": "temporal_mode",
	"role": "specifies the per-database mode flag that controls whether records keep version history",
	"key_concepts": ["temporal", "non_temporal", "mode_flag", "history", "worldlet", "immutable_at_init"]
}

A mikobase is either **temporal** (every write appends a history row; older versions are
recoverable) or **non-temporal** (each record is stored as a single object; writes
overwrite in place). The choice is a per-database flag set at initialization and is
**immutable** for the life of the database.

**Temporal is the default. Non-temporal must be opted into explicitly** via the
top-level flag:

```json
{
    "temporal": false,
    ...
}
```

A database without the `temporal` key — or with `"temporal": true` — is temporal.

Non-temporal mode was added because **worldlets are the primary use case for
mikobase** (see [overview](#overview)), and most worldlets don't
benefit from history — they're snapshots of conversations, scenarios, or
scratch state, not audit logs. After working with worldlets in temporal mode,
reading through history records that each only appeared once was annoying;
non-temporal mode is the direct fix.

The same logic applies beyond worldlets: a microservice that doesn't need to
audit past versions of its records probably doesn't need a temporal database
either. Non-temporal isn't a niche mode; it's the right choice for any
workload where version history adds clutter without payoff.

### Single read and write paths

The mode is encapsulated in two methods. Everywhere else in the engine is mode-agnostic:

- One **retrieval** method understands how to find the latest version of a record. In
  temporal mode it scans history for the latest `updated_at`; in non-temporal mode it
  reads the record directly. Callers don't branch.
- One **save** method understands how to persist a write. In temporal mode it appends a
  history row; in non-temporal mode it overwrites in place. Callers don't branch.

For SQLite-backed mikobases, the retrieval abstraction can be a database view named
`latest_records` that resolves to either `SELECT current rows from history` or
`SELECT * FROM records` depending on mode. The engine queries the view; the database
itself encodes the mode.

### Temporal-only operations on a non-temporal database

Operations that only make sense on a temporal database — rollback, version-at-timestamp,
history scans, audit queries — raise an exception when called on a non-temporal database.
No silent degradation, no empty results. The caller knows immediately that the operation
isn't supported.

### Changing modes later

The flag is immutable at the database level. To convert a non-temporal database to
temporal (or vice versa), import the data into a new database created with the desired
mode. A future engine release may add a refactor tool, but the chosen mode is permanent
for the database it was set on.

### Worldlets and the temporal flag

A worldlet is a **serialized export** of a mikobase, not a mikobase itself
(see [Export formats](#export-formats) below). The worldlet JSON captures
the source mikobase's `temporal` setting at the top level; on import, a
fresh mikobase is created with the same temporal mode. Worldlets that
represent a snapshot of a conversation, scenario, or scratch space — where
version history adds nothing — were typically exported from a non-temporal
mikobase and re-import into a non-temporal one. Worldlets that *do* care
about version history come from temporal mikobases and round-trip the
history block.

**Open: a worldlet with both `records` populated as current-state AND a
populated `history` block.** Combining the two modes' shapes in one export
isn't specified and isn't a priority to resolve.

---

## Export formats

```
vibecode: {
    "section": "export_formats",
    "role": "frames worldlets as one of multiple serialized export formats of a mikobase; the live mikobase is always engine-backed (currently SQLite)",
    "key_concepts": ["export_format_not_engine", "worldlet_as_one_format",
                     "second_export_format_tbd", "import_function_needed",
                     "live_mikobase_is_always_sqlite_backed_in_v1"]
}
```

A mikobase is always **live and engine-backed** (see
[Class Hierarchy](#class-hierarchy-olympic)). **Exports** serialize a
mikobase to a portable format that can be stored, shared, or
re-imported. Exports are not live — they're pure data on disk.

Mikobase v1 will support at least two export formats:

| Format | Status | Description |
|---|---|---|
| **Worldlet** (JSON) | Format defined — [worldlet.md](worldlets/worldlet.md) | Single JSON document; portable; human-readable; suitable for sharing, AI conversation captures, snapshots |
| (Second format) | TBD | A second export format is planned; shape not yet specified |

### Worldlets play two roles

Worldlet JSON is **both** an export format (from any engine) **and**
the live storage of the [`kiera.uno/mikobase/worldlet`](#class-hierarchy-olympic)
engine. From a SQLite-backed mikobase, exporting to a worldlet
serializes the database; from the worldlet engine, the worldlet IS the
database (no serialization step).

This means:

- **SQLite engine + worldlet file**: the worldlet is a snapshot. Load
  via import (incurs the import cost); save via export (incurs the
  export cost). Suitable for long-lived databases that occasionally
  exchange data.
- **Worldlet engine + worldlet file**: the worldlet is the live store.
  Load by reading the file (parse JSON, done); save by writing the
  file (serialize JSON, done). Suitable for very short-lived
  workloads where import/export overhead would dominate.

The choice of engine is the choice between persistence-cost and
serialization-cost. Both engines speak the same `kiera.uno/mikobase`
interface; KScript code that doesn't care which backend it's on works
identically against either.

### Import / export functions

The pipeline between an engine-backed mikobase and an export format is
exactly two functions per format:

- **Export** — read the live mikobase, produce the format's bytes.
- **Import** — read the format's bytes, produce a fresh engine-backed
  mikobase.

For the SQLite engines, both functions involve real work: import maps
JSON shape to SQL schema, inserts every row; export reads tables, serializes
to JSON. For the worldlet engine, "import" is just parsing the JSON
into the engine's in-memory structure (and "export" is just serializing
it back) — there's no schema-mapping step because the worldlet IS the
storage shape.

Neither function is specified in detail yet. Open work for the worldlet
import in particular:

- Method signature and ownership: instance method on the mikobase
  (`$mb.export_worldlet()`, `$mb.import_worldlet(json)`), free function
  (`%kiera['kiera.uno/mikobase'].import_worldlet(json)`), or a
  constructor (`kiera.uno/mikobase.from_worldlet(json) → mikobase`).
- Schema mapping for the temporal flag (the worldlet's
  `"temporal": false` must produce the corresponding SQLite schema for
  the SQLite engines).
- UUID and timestamp preservation on import (`updated_at` on temporal
  history rows must round-trip exactly; `created_at` on non-temporal
  records must round-trip exactly).
- Error handling for malformed JSON, unknown `format_version`,
  unknown classes, etc.
- Round-trip equivalence guarantee (export then import should produce
  a mikobase indistinguishable from the original modulo file handles).
- For the worldlet engine: how Q0 queries are implemented against the
  JSON structure (joins, aggregations, indexes), and whether the
  engine supports both temporal and non-temporal modes or only
  non-temporal.

---

## Single-process vs. cross-fork use

vibecode: {
	"section": "single_process_vs_cross_fork",
	"role": "distinguishes local mikobase use from fork-shared mikobase use; both are KScript features (cross-fork requires the opt-in forking feature)",
	"key_concepts": ["KScript", "local_object_store", "fork_sharing", "opt_in_forking"]
}

Mikobases are a KScript feature — a mikobase is a useful local object store on its own.
Sharing a mikobase between forked processes uses the opt-in **forking** feature of KScript
(engine-granted via `%forks` / `%tmp`; off by default). See
[ideas/plusplus/threads.md](../ideas/plusplus/threads.md) for the forking design.

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
| `kiera.uno/mikobase/worldlet` | Worldlet-backed engine — operates directly on the worldlet JSON structure; no SQLite import/export step; built for very short-lived workloads (AI2AI conversations, scratch sessions) where import/export cost would dominate |
| `kiera.uno/mikobase/http` | HTTP server that exposes a mikobase over the network |
| `kiera.uno/mikobase/server` | Managed mikobase server for fork-based coordination |

The two SQLite implementations run on the same backend — the only difference is
whether SQLite is pointed at memory or a file. Q0 is just SQL in both cases, with
no separate in-memory query engine needed. The worldlet engine is a third backend
that implements Q0 against the worldlet's JSON structure directly (no SQLite
involvement).

KScript code interacts only with the `kiera.uno/mikobase` interface and is unaware of the backend.

---

## Managed Mikobase Server (`kiera.uno/mikobase/server`)

vibecode: {
	"section": "managed_mikobase_server",
	"role": "documents the server class that manages mikobase lifetime around a fork pool",
	"key_concepts": ["kiera.uno/mikobase/server", "fork_coordination", "block_scoped_lifetime", "clean_shutdown"]
}

`kiera.uno/mikobase/server` is a managed mikobase server designed for fork-based coordination.
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

Serving a mikobase over HTTP doesn't require the forking feature. A single-process script
can serve a mikobase, and other KScript processes — including forks from the opt-in
forking feature — can connect to it as a shared mikobase.

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

### POSTable Updates

`kiera.uno/mikobase/http` exposes a POST endpoint for submitting append-only updates
without opening a live connection. This is a distinct ingress mode — not a replacement
for hot/cold connections or Q0, but a stateless path for depositing history entries.

#### The payload is a worldlet

The request body is a standard worldlet JSON object. A history-only worldlet is a valid
payload. No new wire format is needed — the worldlet format already supports this.

```
POST /worldlet
Content-Type: application/json

{
    "history": {
        "f1a2b3c4-0001-0001-0001-000000000001": {
            "record":     "e1b2c3d4-0001-0001-0001-000000000001",
            "class":      "foo.com/reading",
            "updated_at": "2026-05-03T12:00:00.000Z",
            "bucket":     {"value": 42.7}
        }
    }
}
```

#### Engine behaviour on receipt

1. Validate the worldlet shape and all UUID v4 constraints.
2. For each history entry: skip if an identical entry already exists; reject if an entry
   with the same UUID exists with different content.
3. If all entries pass, append them and recompute current state. If any entry fails,
   reject the entire payload — no partial writes.

#### Response

The response reports what happened to each entry:

```json
{
    "accepted": ["f1a2b3c4-0001-0001-0001-000000000001"],
    "skipped":  [],
    "rejected": []
}
```

#### Authorization

In v1, authorization is coarse-grained: either a caller may POST updates to this
mikobase or it may not. The `post_updates` auth flag is set when configuring the server.
Fine-grained per-class or per-record permissions are deferred to a future version.

#### Use cases

- **Worldlet deltas** — the natural format for AI-to-AI update exchanges
- **Offline agents** — work from a snapshot, submit results later
- **Write-only participants** — auditors, validators, sensors, importers, summarizers
- **Submission inboxes** — public or semi-public inboxes for proposals, bug reports, votes
- **Webhook integration** — outside systems deposit state changes as history entries
- **AI-to-AI mail** — a message is a mikobase update
- **Audit-native APIs** — every integration call is already a history entry

#### Deferred

Signatures, replay protection, timestamp authority, distributed merge, and fine-grained
permissions are not part of v1.

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

See [worldlet.md](worldlets/worldlet.md) for the worldlet file format.

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