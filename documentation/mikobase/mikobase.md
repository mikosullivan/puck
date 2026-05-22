# Mikobase

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"role": "introduces the mikobase as a live object store with Q0, class definitions, history, and locking",
	"key_concepts": ["mikobase", "object_store", "live_process", "Q0", "shared_objects"]
}}
~~~

A mikobase is a full object store — in memory, file-backed, or served over a network.
It supports Q0 queries, class definitions, transactions, and locking.
Any process that connects to a mikobase can reach in and use its objects at any time.

Objects in the mikobase are always alive for as long as the mikobase exists. A
process's local objects stay local. If an object needs to be shared, it must live
in the mikobase.

A mikobase can live in a database backend like SQLite, or in memory.
A small mikobase packaged as a single JSON file is called a
**worldlet** — see [Worldlets: Mikobase on a microscale](#worldlets-mikobase-on-a-microscale).

<a id="record-identity"></a>
### Record identity

Every record has a primary key. By convention that key is a **UUID v4**,
but Mikobase is not fussy about it. Currently, Mikobase actually accepts
anything for primary key fields called "uuid". We'll revisit the subject
of cryptographically strong UUIDs if the community wants to do so.

---

<a id="v1-scope"></a>
## v1 Scope

Mikobase is large by ambition. The v1 release keeps the surface
focused:

- **Three storage engines ship in v1:**
  1. **SQLite file-backed** — long-lived, file-persisted databases.
  2. **SQLite in-memory** (`:memory:`) — ephemeral SQLite-backed
     databases. Same SQLite backend as file-backed; only the
     storage target differs. Q0 queries are just SQL in both cases.
  3. **Worldlet** — in memory native Mikobase. Built for very
     short-lived workloads. See [AI2AI](AI2AI/AI2AI.md) for an example.

  Mikobase supports multiple engines as pluggable backends;
  these three are what ships in v1. Other backends (Postgres,
  etc.) come later as add-ons.

---

<a id="single-process-vs-cross-fork-use"></a>
## Single-process vs. cross-fork use

~~~json
{"vibecode": {
	"section": "single_process_vs_cross_fork",
	"role": "distinguishes local mikobase use from fork-shared mikobase use; both are Charlie features (cross-fork requires the opt-in forking feature)",
	"key_concepts": ["Charlie", "local_object_store", "fork_sharing", "opt_in_forking"]
}}
~~~

Mikobases are a Charlie feature — a mikobase is a useful local object store on its own.
Sharing a mikobase between forked processes uses the opt-in **forking** feature of Charlie
(engine-granted via `%forks` / `%tmp`; off by default). See
[ideas/plusplus/threads.md](../ideas/plusplus/threads.md) for the forking design.

---

<a id="the-maintaining-process"></a>
## The Maintaining Process

~~~json
{"vibecode": {
	"section": "maintaining_process",
	"role": "explains that a mikobase always requires a live process; not a passive file",
	"key_concepts": ["live_process", "maintaining_process", "in-memory", "server_process", "remote_service"]
}}
~~~

A mikobase is not a passive data store — it requires a process to maintain it. "Always alive"
means alive for as long as the maintaining process is running. That process might be:

- A local in-memory object passed around within an application
- A server process on the same machine
- A remote service accessed over a network

There is no concept of a mikobase without something running it. Connecting to a mikobase means
connecting to a live process, not reading from a file.

---

<a id="object-ownership"></a>
## Object Ownership

~~~json
{"vibecode": {
	"section": "object_ownership",
	"role": "states that the mikobase owns objects; processes connect and interact, not pass objects directly",
	"key_concepts": ["mikobase_ownership", "connect_and_interact", "no_direct_passing"]
}}
~~~

The mikobase owns its objects. Processes do not pass objects to each other directly — instead,
they connect to the mikobase and interact with whatever is already there.

---

<a id="class-hierarchy"></a>
## Class Hierarchy

~~~json
{"vibecode": {
	"section": "class_hierarchy",
	"role": "lists all mikobase implementation classes and their relationships",
	"key_concepts": ["puck.uno/mikobase", "puck.uno/mikobase/memory", "puck.uno/mikobase/sqlite",
		"puck.uno/mikobase/http", "abstract_base_class"]
}}
~~~

| Class | Description |
|---|---|
| `puck.uno/mikobase` | Abstract base class (`abstract true`); full Q0 interface, locking, transactions |
| `puck.uno/mikobase/memory` | SQLite in-memory database (`:memory:`) |
| `puck.uno/mikobase/sqlite` | SQLite file-backed database |
| `puck.uno/mikobase/worldlet` | Worldlet-backed engine — operates directly on the worldlet JSON structure; no SQLite import/export step; built for very short-lived workloads (AI2AI conversations, scratch sessions) where import/export cost would dominate |
| `puck.uno/mikobase/http` | HTTP server that exposes a mikobase over the network |

The two SQLite implementations run on the same backend — the only difference is
whether SQLite is pointed at memory or a file. Q0 is just SQL in both cases, with
no separate in-memory query engine needed. The worldlet engine is a third backend
that implements Q0 against the worldlet's JSON structure directly (no SQLite
involvement).

Charlie code interacts only with the `puck.uno/mikobase` interface and is unaware of the backend.

---

<a id="field-declarations"></a>
## Field declarations

~~~json
{"vibecode": {
	"section": "field_declarations",
	"role": "spec for the JSON shape that declares a single field on a class — the field-level constraint vocabulary",
	"keys": ["class", "items", "required", "default", "enum", "format"],
	"collection_element_typing": "use `items` to declare what an array or hash holds"
}}
~~~

Each field on a class is declared as a small object:

```json
"field_name": {"class": "<type>", ...}
```

`class` is required; everything else is optional. The recognized keys:

| Key | Applies to | Meaning |
|---|---|---|
| `class`    | every field | The type. Either a primitive (`string`, `number`, `array`, `hash`, etc.) or a UNS class name (`foo.com/widget`). |
| `items`    | `array` / `hash` fields | The class definition for elements in the hash or array. |
| `required` | any field | `true` if the field must be present. |
| `default`  | any field | Value to use when the field is omitted. |
| `enum`     | `string` fields with a closed vocabulary | List of allowed values. |
| `format`   | `string` fields | Shape hint — e.g., `"uuid"` for a UUID reference, `"identifier"` for an arbitrary external identifier. |

For collection fields, **`items` declares the element (or value) type**:

```json
"participants": {"class": "array", "items": "puck.uno/ai/agent"}
"tags":         {"class": "array", "items": "string"}
"by_name":      {"class": "hash",  "items": "foo.com/person"}
```

A consumer reading these can validate `participants` element-by-element as agent UUIDs, `tags` as plain strings, and the values of `by_name` as person references — without needing to scrape the surrounding prose.

For fields whose `class` is already a UNS class name (e.g., `"class": "foo.com/widget"`), the class itself is the type constraint — `items` only applies when the outer `class` is a collection.

---

<a id="http-mikobase"></a>
## HTTP Mikobase

~~~json
{"vibecode": {
	"section": "http_mikobase",
	"role": "documents the HTTP transport wrapper including Unix sockets, TCP, and authentication options",
	"key_concepts": ["puck.uno/mikobase/http", "Unix_domain_sockets", "TCP", "auth_peer", "auth_token", "auth_open"]
}}
~~~

`puck.uno/mikobase/http` wraps any mikobase and exposes it over HTTP. The mikobase's locking model
handles concurrent connections — the HTTP server is a transport layer only. Connection-level
concurrency lives in the C layer, not in Charlie.

Serving a mikobase over HTTP doesn't require the forking feature. A single-process script
can serve a mikobase, and other Charlie processes — including forks from the opt-in
forking feature — can connect to it as a shared mikobase.

<a id="unix-domain-sockets-preferred"></a>
### Unix Domain Sockets (preferred)

For local communication, Charlie steers developers toward Unix domain sockets. They use a
file path instead of a port number, bypass the network stack entirely, and access is
controlled by filesystem permissions — faster and more secure than TCP for local use.

```
$mikobase = %puck['puck.uno/mikobase/sqlite'].new('/path/to/db')
$server = %puck['puck.uno/mikobase/http'].new(mikobase: $mikobase, socket: '/var/run/myhive.sock', auth: :peer)
$server.start
```

<a id="tcp-for-network-access"></a>
### TCP (for network access)

Port-based listening is supported when the mikobase needs to be reachable over a network:

```
$server = %puck['puck.uno/mikobase/http'].new(mikobase: $mikobase, port: 8080, auth: :token, token: 'mysecrettoken')
$server.start
```

Unix domain sockets are the default and recommended approach for local use. TCP is for
cases where remote access is explicitly needed.

<a id="authentication"></a>
### Authentication

The `auth:` parameter is required — there is no default. Three options:

**`:peer`** — peer credentials via `SO_PEERCRED`. The kernel verifies the connecting
process's identity (UID, GID, PID). No shared secrets, no setup. Only available for
Unix domain sockets.

```
$server = %puck['puck.uno/mikobase/http'].new(
    mikobase: $mikobase,
    socket: '/var/run/myhive.sock',
    auth: :peer
)
```

**`:token`** — access token (password). The client sends a token as part of the connection
handshake. Works for both Unix sockets and TCP.

```
$server = %puck['puck.uno/mikobase/http'].new(
    mikobase: $mikobase,
    socket: '/var/run/myhive.sock',
    auth: :token,
    token: 'mysecrettoken'
)
```

**`:open`** — no authentication. Anyone who can reach the socket or port can connect.
Use only in controlled environments.

```
$server = %puck['puck.uno/mikobase/http'].new(
    mikobase: $mikobase,
    socket: '/var/run/myhive.sock',
    auth: :open
)
```

<a id="postable-updates"></a>
### POSTable Updates

`puck.uno/mikobase/http` exposes a POST endpoint for submitting append-only updates
without opening a live connection. This is a distinct ingress mode — not a replacement
for hot/cold connections or Q0, but a stateless path for depositing history entries.

<a id="the-payload-is-a-worldlet"></a>
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

<a id="engine-behaviour-on-receipt"></a>
#### Engine behaviour on receipt

1. Validate the worldlet shape and that all primary keys are unique
   (see [Record identity](#record-identity); UUID v4 is the recommended
   shape but not strictly enforced for now).
2. For each history entry: skip if an identical entry already exists; reject if an entry
   with the same key exists with different content.
3. If all entries pass, append them and recompute current state. If any entry fails,
   reject the entire payload — no partial writes.

<a id="response"></a>
#### Response

The response reports what happened to each entry:

```json
{
    "accepted": ["f1a2b3c4-0001-0001-0001-000000000001"],
    "skipped":  [],
    "rejected": []
}
```

<a id="authorization"></a>
#### Authorization

In v1, authorization is coarse-grained: either a caller may POST updates to this
mikobase or it may not. The `post_updates` auth flag is set when configuring the server.
Fine-grained per-class or per-record permissions are deferred to a future version.

<a id="use-cases"></a>
#### Use cases

- **Worldlet deltas** — the natural format for AI-to-AI update exchanges
- **Offline agents** — work from a snapshot, submit results later
- **Write-only participants** — auditors, validators, sensors, importers, summarizers
- **Submission inboxes** — public or semi-public inboxes for proposals, bug reports, votes
- **Webhook integration** — outside systems deposit state changes as history entries
- **AI-to-AI mail** — a message is a mikobase update
- **Audit-native APIs** — every integration call is already a history entry

<a id="deferred"></a>
#### Deferred

Signatures, replay protection, timestamp authority, distributed merge, and fine-grained
permissions are not part of v1.

---

<a id="hot-and-cold-connections"></a>
## Hot and Cold Connections

~~~json
{"vibecode": {
	"section": "hot_and_cold_connections",
	"role": "defines hot vs cold connection modes and per-query overrides",
	"key_concepts": ["cold_connection", "hot_connection", "local_copy", "live_object", "per-query_override", "hot_true"]
}}
~~~

Every connection to a mikobase is either **cold** (the default) or **hot**. The mode is set
at connection time and applies to all objects retrieved through that connection.

<a id="cold-default"></a>
### Cold (default)

A cold connection returns local copies of records. You fetch a record, work with it
locally, and save it back explicitly:

```
$mikobase = %puck['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer)

$record = $mikobase.q0(...)
$record['foo'] = 'bar'
$record.save
```

Cold is the default because most database interaction is traditional, and accidentally
using a cold connection is safe — you just work with a local copy.

<a id="hot"></a>
### Hot

A hot connection returns live objects. Every read and write is a round trip to the mikobase,
with locking applied automatically. There is no local copy and no explicit save:

```
$mikobase = %puck['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer, hot: true)

$mikobase['clients'].shift   # atomic read-and-remove, one round trip
$mikobase['results'] << $result   # atomic write, one round trip
```

Hot connections are the correct choice when multiple forks share a mikobase — every operation
needs to be atomic and consistent across concurrent readers and writers.

<a id="local-mikobases"></a>
### Local mikobases

The same `hot:` parameter applies to local mikobases:

```
$mikobase = %puck['mikobase/memory'].new(hot: true)
$mikobase = %puck['mikobase/sqlite'].new('/path/to/db', hot: true)
```

On a local mikobase, hot means every field access hits SQLite directly. Cold means load the
record into memory, work with it locally, save explicitly.

<a id="multiple-connections-different-modes"></a>
### Multiple connections, different modes

Two connections to the same mikobase can have different modes:

```
$hot  = %puck['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer, hot: true)
$cold = %puck['mikobase/http'].connect(socket: '/var/run/myhive.sock', auth: :peer)
```

This is valid — for example, one hot connection for fork coordination and one cold
connection for bulk record processing.

<a id="per-query-override"></a>
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

<a id="locking"></a>
## Locking

~~~json
{"vibecode": {
	"section": "locking",
	"role": "describes automatic shared/exclusive locking model for reads and writes",
	"key_concepts": ["shared_lock", "exclusive_lock", "automatic_locking", "no_explicit_lock_api"]
}}
~~~

Mikobase access follows database-style locking:

- **Reads** use shared locks — multiple processes can read simultaneously.
- **Writes** use exclusive locks — one process acquires an exclusive lock, writes, commits,
  and releases. No other process can read or write during a write transaction.

The mikobase detects whether an operation is a read or write and acquires the appropriate lock
automatically. There is no explicit lock/unlock API in normal usage.

---

<a id="transactions"></a>
## Transactions

~~~json
{"vibecode": {
	"section": "transactions",
	"role": "documents the nested transaction model with commit, rollback, and auto-rollback on exit",
	"key_concepts": ["transaction", "nested_transactions", "commit", "rollback", "auto-rollback", "exit"]
}}
~~~

Mikobases support transactions using the following model:

- `transaction()` begins a transaction and returns a handle.
- Nesting is supported — each call creates a new transaction nested under the current one.
- A transaction block that exits without an explicit `commit()` is automatically rolled back.
- `commit()` commits the transaction and keeps execution running.
- `exit()` rolls back and immediately exits the block.

---

<a id="bucket-in-the-mikobase"></a>
## `%bucket` in the Mikobase

~~~json
{"vibecode": {
	"section": "bucket_in_mikobase",
	"role": "explains how %bucket can be backed by a mikobase for transparent fork coordination",
	"key_concepts": ["%bucket", "include_private", "mikobase_backed", "fork_private_vars", "@foo"]
}}
~~~

Setting `include_private = true` on a mikobase causes `%bucket` to be backed by the mikobase for
any fork that connects to it. The fork's `@foo` reads and writes go directly to a live
object in the mikobase — child forks don't need to reference the mikobase explicitly at all.

```
$mikobase = %puck['puck.uno/mikobase/memory'].new
$mikobase.include_private = true

%forks.run(mikobase:$mikobase) do($mikobase)
    @foo = 'bar'    # reads and writes go directly to the mikobase
end
```

`%bucket` is synced to its own mikobase, not any mikobases that are explicitly passed through.

---

<a id="record-change-signals"></a>
## Record Change Signals

~~~json
{"vibecode": {
	"section": "record_change_signals",
	"role": "documents the listener system for before_save and after_save signals on records",
	"key_concepts": ["listen", "before_save", "after_save", "change_object", "Q0_query_target", "network_boundary"]
}}
~~~

<a id="listening-to-records"></a>
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

<a id="before_save-and-after_save"></a>
### `before_save` and `after_save`

**`:before_save`** fires within the transaction, before the commit. If the handler raises
an error, the entire transaction is rolled back. This is the mechanism for enforcing
consistency rules.

**`:after_save`** fires after the transaction is committed. The change cannot be
cancelled. This is the mechanism for side effects — notifications, derived records,
background work.

<a id="signals-stay-within-the-mikobase"></a>
### Signals stay within the mikobase

By default, `:before_save` signals are dispatched within the mikobase process only. They are
not forwarded over the network to remote clients. This is intentional — a network round
trip inside a transaction would be slow and fragile.

Pre-save validation is the developer's responsibility. The recommended approach is to
validate on the client side before saving, or to register `:before_save` handlers as
part of the mikobase server's own setup code.

<a id="listener-matching"></a>
### Listener matching

A listener fires when the record being saved matches its target:

- A record target matches only that specific record.
- A Q0 query target matches any record that satisfies the query after the change is
  applied. This includes records transitioning into the match set.

<a id="future-remote-validation"></a>
### Future: remote validation

The current design puts remote validation responsibility on the developer. 
A future addition could provide a structured layer on top of `:before_save` signals — a declarative way to attach remote validation to the :before_save process.

---

<a id="temporal-vs-non-temporal-mode"></a>
## Temporal vs Non-temporal Mode

~~~json
{"vibecode": {
	"section": "temporal_mode",
	"role": "specifies the per-database mode flag that controls whether records keep version history; opt-in feature for workloads that need audit history",
	"key_concepts": ["temporal", "non_temporal", "mode_flag", "history",
		"opt_in", "immutable_at_init"]
}}
~~~

By default a mikobase is **non-temporal**: each record is stored as a single
object, and writes overwrite in place. Most workloads want this — snapshots,
scenarios, scratch state, conversation captures, and most service-backing
databases just want the current value of each record.

A mikobase can be set to **temporal** mode at initialization, in which case
every write appends a history row and older versions are recoverable. Use it
when audit history is a real requirement: regulatory logging, recoverable
edits, time-travel queries.

The choice is a per-database flag set at initialization and is **immutable**
for the life of the database. Temporal mode is opted into explicitly via the
top-level flag:

```json
{
    "temporal": true,
    ...
}
```

A database without the `temporal` key — or with `"temporal": false` — is
non-temporal.

<a id="single-read-and-write-paths"></a>
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

<a id="temporal-only-operations-on-a-non-temporal-database"></a>
### Temporal-only operations on a non-temporal database

Operations that only make sense on a temporal database — rollback, version-at-timestamp,
history scans, audit queries — raise an exception when called on a non-temporal database.
No silent degradation, no empty results. The caller knows immediately that the operation
isn't supported.

<a id="changing-modes-later"></a>
### Changing modes later

The flag is immutable at the database level. To convert a non-temporal database to
temporal (or vice versa), import the data into a new database created with the desired
mode. A future engine release may add a refactor tool, but the chosen mode is permanent
for the database it was set on.

---

<a id="worldlets-mikobase-on-a-microscale"></a>
## Worldlets: Mikobase on a microscale

~~~json
{"vibecode": {
	"section": "worldlets",
	"role": "small-scale mikobases packaged as a single JSON file; covers format, dual role (export + native engine storage), contents, capabilities, lifecycle, use cases, and temporal-flag interaction",
	"key_concepts": ["worldlet", "single_json_file", "small_scale_mikobase",
		"export_format_and_native_engine_storage", "capabilities_manifest",
		"portable_distribution"]
}}
~~~

A **worldlet** is a mikobase packaged as a single JSON file — the
small-scale form of mikobase. Worldlets are suitable for snapshots,
scratch state, AI conversation captures, test fixtures, and any
short-lived or portable workload where the full machinery of a
SQLite-backed mikobase would be overkill.

The file format is specified in [worldlet.md](worldlets/worldlets.md).

<a id="dual-role-export-format-and-native-engine-storage"></a>
### Dual role: export format and native engine storage

A worldlet JSON file plays two roles:

- **As an export format** from any engine. A SQLite-backed mikobase can
  export to a worldlet (serializes the database to JSON) and import from
  one (parses JSON back into the database). The worldlet is a snapshot;
  load and save incur import/export cost.
- **As the live storage** of the `puck.uno/mikobase/worldlet` engine. For
  this engine the worldlet IS the database — there's no serialization
  step. Load is JSON parse, save is JSON write. Suitable for very
  short-lived workloads where import/export overhead would dominate.

Both engines speak the same `puck.uno/mikobase` interface; Charlie code
that doesn't care which backend it's on works identically against either.

<a id="contents-1"></a>
### Contents

A worldlet may include:

- **Class definitions** — the schema, including fields, joins, and constraints
- **Records** — seed objects or full data exports
- **Charlie** — methods and behavior attached to those classes
- **Hooks** — `before_save` / `after_save` listeners
- **Capabilities** — a manifest declaring what the worldlet requires to run
- **Scheduled jobs** — time-based tasks (not yet designed)
- **External connectors** — outbound integrations (not yet designed)

Class names inside a worldlet use UNS — the publisher's domain provides a
globally unique namespace automatically. A worldlet published by `borg.com`
installs classes like `borg.com/character`, `borg.com/ship`. No registration
required, no collision possible.

<a id="capabilities-manifest"></a>
### Capabilities Manifest

A worldlet declares what it needs before it is installed. The host asks the
user to approve these capabilities explicitly — nothing is granted silently.

```
requires:
  network:
    - api.example.com
  schedule:
    - every 5 minutes
  storage:
    - create objects: PricePoint
```

This connects directly to Charlie's security model. The capabilities
declaration is essentially an upfront jail configuration — the worldlet runs
with only the permissions it declared. Undeclared capabilities are
unavailable.

<a id="lifecycle"></a>
### Lifecycle

```
Author packages worldlet
        ↓
Worldlet shared (file, URL, registry)
        ↓
Recipient imports worldlet into their running mikobase
        ↓
Capabilities reviewed and approved
        ↓
Classes, records, and Charlie installed
        ↓
Worldlet runs inside recipient's environment
```

A worldlet can also be sent to a remote system for execution via Puck,
without installing it locally:

```
send worldlet → remote mikobase → execute → return result
```

<a id="temporal-flag"></a>
### Temporal flag

A worldlet captures the source mikobase's `temporal` setting at the top
level; on import, a fresh mikobase is created with the same temporal mode.
Most worldlets are non-temporal (the default) — snapshots of conversations,
scenarios, or scratch space where version history adds nothing. Worldlets
that *do* care about version history come from temporal mikobases and
round-trip the history block. See
[Temporal vs Non-temporal Mode](#temporal-vs-non-temporal-mode) for the
full mode rules.

**Open: a worldlet with both `records` populated as current-state AND a
populated `history` block.** Combining the two modes' shapes in one export
isn't specified and isn't a priority to resolve.

<a id="use-cases-1"></a>
### Use cases

**Test fixtures** — seed a mikobase with a known starting state for testing.
Worldlets are deterministic and portable across machines.

**Reproducible bugs** — ship the exact mikobase state that triggered a bug.
The recipient gets the object structure, the data, and the behavior in one
file. No setup required.

**AI conversation captures** — see [AI2AI.md](AI2AI/AI2AI.md).

**Portable computation** — send a worldlet to a remote system, run its
logic there, and get a result back. The computation travels with its data.

**Small installable apps** — a recipe manager, a home inventory, a research
notebook. Publish a worldlet; others install a working system, not a blank
schema.

<a id="what-is-not-yet-designed"></a>
### What is not yet designed

- The full worldlet file format (depends on CharlieJSON format design)
- The capabilities manifest syntax and enforcement mechanism
- Scheduled jobs
- External connectors
- A worldlet registry or distribution mechanism
- Worldlet import/export method signatures and ownership (instance method
  vs free function vs constructor)
- Round-trip equivalence guarantees and error handling for malformed JSON,
  unknown `format_version`, unknown classes