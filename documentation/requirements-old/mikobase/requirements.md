# Mikobase Engine Requirements

## Overview

~~~vibecode
{"vibecode": {
	"section": "overview",
	"role": "introduces the mikobase engine requirements: clients, engines, Q0, and the Python SQLite implementation",
	"key_concepts": ["mikobase_engine", "clients", "engines", "Q0", "chained_engines", "Python_SQLite"]
}}
~~~

A mikobase is the object store layer of the Puck ecoverse. It defines a protocol by which
clients in various programming languages can access objects in a live object store. It is
a NoSQL solution with a class-based object model.

See [overview.md](../overview.md) for the full picture.

The system consists of:

- **Clients** — language-specific modules that speak the Q0 query language and communicate
  with engines in the same language
- **Engines** — translate Q0 queries into queries for a specific DBMS (e.g. SQLite), or
  forward Q0 queries to another engine (e.g. over HTTP/HTTPS)
- **Q0** — the built-in query language, expressed as JSON objects

Engines can be chained. A client talks to an engine; that engine may talk to another engine
or directly to a DBMS.

The first implementation is a Python SQLite engine with no network connection. The client
is out of scope for now — only the engine is being developed at this stage.

---

## Universal Namespace

Class names use UNS. See [UNS](../../ideas/uns/).

---

## Object Model

~~~vibecode
{"vibecode": {
	"section": "object_model",
	"role": "specifies the record, classes (platter stack), bucket, and built-in class model",
	"key_concepts": ["records", "classes", "platters", "bucket", "built-in_classes",
		"record_pk", "append-only_history", "tombstone", "no_reserved_bucket_keys"]
}}
~~~

### Records

- Records are the primary data objects in a mikobase.
- Every record has a stable identity (`record_pk`) and an append-only version history.
- The current state of a record is its latest active history row.
- A record whose latest history row has `active = false` is considered deleted.
- Historical reads use a cutoff timestamp to view the state of records at a past point in time.

### Classes

A record's class identity lives in its **`stack`** — an ordered hash of platters,
each contributing a class. This matches the universal Puck object shape (see
[ecoverse/objects/](../ecoverse/objects/) for the structural spec).

```json
{
    "bucket": {...},
    "stack": {
        "shadow": {},
        "character": {"class": "foo.com/character"},
        "trivet_node": {"class": "puck.uno/trivet/node",
                        "bucket": {"parent": "...", "children": "...", "id": "..."}}
    }
}
```

Rules:

- Every record has a shadow platter at position 1 — either written explicitly
  or implicitly present-and-empty when no `"shadow"` key appears in the stack
  hash. Records typically also have a primary-class platter; additional platters
  arrive when mix-ins, marker classes, or warnings get added. Non-shadow
  platters can be added, removed, or reordered freely.
- Each platter can optionally carry its own private bucket via the `bucket` field —
  state that belongs to that platter's class, separate from the record's shared
  top-level `bucket`. Mix-in classes (Trivet is canonical) use the per-platter
  bucket to avoid colliding with the host's bucket keys.
- Class names are UNS strings.
- Classes are themselves stored as records, using the **whole-hash form** that
  `puck.uno/class` opts into: at the record's top level, `class: "puck.uno/class"`
  plus sibling `name`/`inherits`/`fields`/`methods` properties. See
  [worldlet.json](../ecoverse/worldlets/worldlet.json) records `a`-`f` for the
  canonical examples.
- **Inheritance** (class-definition-level) is still explicit via the `inherits`
  field on a class-definition record. Inheritance describes how class definitions
  relate; it's orthogonal to the per-instance platter stack.
- A record can be queried by any class in its stack (see
  [query semantics](#querying-by-class) — `engine.by_class('foo.com/character')`
  returns records that include that class in their stack, regardless of what
  other platters they carry).

### `bucket`

- Each record version stores its **shared payload** in `bucket`, a JSON object.
- **Buckets have no reserved keys.** No `uns` slot, no `_meta`, no engine-claimed
  keys at all. Every key inside a bucket is the class designer's choice.
- **Buckets are always hashes** — never scalars, arrays, or null.
- Mix-in or cross-cutting class state goes in the relevant platter's bucket, not
  in the record's shared bucket.
- The same policy applies recursively: every platter's bucket follows the same
  "always a hash, no reserved keys" rule.
- Fields not defined in any platter's class are stored as-is without validation.

### Nested class instances in buckets

When a nested class instance is embedded inline in a bucket (e.g., an inline
sub-record without its own `record_pk`), it carries its own `{bucket, stack}`
shape directly in place. The nested shape is the structural cue that says
"this isn't plain data, it's a class instance with state." No sidecar tables
or UUID markers are needed — the nested object is fully self-describing.

(Whether inline nested class instances persist as a Mikobase concept at all,
versus a references-only model using `puck.uno/reference`, is an open design
question — see [#341](https://github.com/mikosullivan/puck/issues/341).)

### Built-in Classes

The following classes are seeded as database records on initialization:

- `puck.uno/record` — base class for all records (the default platter for any new record)
- `puck.uno/class` — class for class definitions (records of this class use the whole-hash form)
- `puck.uno/reference` — reference to another record by `record_pk`
- `puck.uno/dbfile` — file attachment

---

## Database Properties

~~~vibecode
{"vibecode": {
	"section": "database_properties",
	"role": "documents metadata properties of the database instance itself, readable by any client",
	"key_concepts": ["database_metadata", "executable", "advisory", "client_readable"]
}}
~~~

A mikobase may declare properties about itself that any client can read upon connecting.
These are database-level metadata, not record-level data.

### `executable`

A boolean advisory indicating that code stored in this mikobase may be executed.
Allowing execution requires a positive assertion — the default is `false`, meaning
code in records is data only, to be read and interpreted, not run.

This is an advisory, not an enforcement mechanism. The database does not prevent
execution; it signals the publisher's intent. Respecting this advisory is the
responsibility of the client or agent.

Default: `false`.

---

## Connection

~~~vibecode
{"vibecode": {
	"section": "connection",
	"role": "documents connection modes rw/r/w, cutoff timestamps, and the Python API",
	"key_concepts": ["connection_modes", "rw", "r", "cutoff_timestamp", "read-only_historical", "Python_API"]
}}
~~~

Connections are opened with an explicit mode. There is no default mode.

Valid modes:

- `rw` or `wr` — read/write (normalized to `rw`)
- `r` — read-only
- `w` — reserved, not yet implemented

Mode parsing is case-insensitive. Surrounding whitespace is rejected.

Opening a connection with a cutoff timestamp makes the entire connection read-only (historical
snapshot).

### Python API

A Python client illustrates the shape of the conceptual API:

```python
import mikobase.engine.sqlite as mb

with mb.connect('/path/to/database.db', 'rw') as engine:
    pass
```

For historical read-only connections, supply a cutoff timestamp:

```python
with mb.connect('/path/to/database.db', 'r', cutoff='2026-01-01T00:00:00.000') as engine:
    pass
```

---

## Queries

~~~vibecode
{"vibecode": {
	"section": "queries",
	"role": "documents engine.q0() API, lazy resultsets, response shapes, and convenience methods",
	"key_concepts": ["engine.q0", "lazy_resultset", "select_response", "create_response", "delete_response",
		"record_dict_shape", "convenience_methods"]
}}
~~~

All queries are sent via `engine.q0()`, which accepts a Q0 dict.

### `select` responses

`select` returns a lazy resultset object. It fetches one record at a time from the SQLite
cursor rather than loading all results into memory.

The resultset has:

- `success` — boolean
- `errors` — list of error dicts (empty on success)
- `count` — number of records actually returned (after `limit`/`offset`)
- iterable — yields record dicts one at a time on success

```python
results = engine.q0({"action": "select", "class": "foo.com/character"})
if results.success:
    for record in results:
        print(record)
else:
    print(results.errors)
```

The `class` argument to `select` matches records whose platter stack
includes the named class. A record with `classes = {<uuid>: {class: "foo.com/character", ...}}`
matches; a record without that class anywhere in its stack does not.

### `create`, `update`, `delete` responses

These actions return a plain dict with `success`, `errors`, and `results`.

`create` includes the new `pk` in `results`:

```python
{"success": True, "results": {"pk": "92677339-df86-4f68-9397-999e40cf2c40"}}
```

`delete` includes the `pk` and a `deleted` boolean in `results`:

```python
{"success": True, "results": {"pk": "92677339-...", "deleted": True}}
```

### Record dict shape

Each record dict yielded by a `select` resultset has the following fields:

```python
{
    "pk": "92677339-df86-4f68-9397-999e40cf2c40",
    "bucket": {...},
    "stack": {
        "shadow": {},
        "character": {"class": "foo.com/character"}
    },
    "updated_at": "2026-04-21T14:32:00.123"
}
```

### Convenience methods

The base engine also provides convenience methods that build Q0 dicts internally:

- `engine.record_by_pk(pk)` — fetches a single record by primary key
- `engine.by_class(class_name)` — returns all active records of a given class and subclasses

---

## Records as Python Objects

~~~vibecode
{"vibecode": {
	"section": "records_as_python_objects",
	"role": "describes future client behavior: wrapping dicts into typed Python objects via decorator",
	"key_concepts": ["future_client", "mikobase_record_decorator", "class_registration", "field_ordering"]
}}
~~~

*This section describes future client behaviour. The client is out of scope for the current
implementation — only the engine is being developed at this stage.*

The engine returns raw dicts. The client will wrap them into Python objects.

- A class in the record's `stack` is used to look up the corresponding Python class.
  Multi-platter records may match more than one registered Python class; the client decides
  which platter to use as the primary (typically the first non-shadow platter, or by configured priority).
- Python classes declare their Mikobase class id via a class-level attribute.
- Python classes are registered with the client using the `@mikobase.record` decorator,
  which handles both registration and field introspection.

```python
@mikobase.record
class Character:
    mikobase_class_id = "foo.com/character"
    name: str
    age: int
```

### Field Ordering

Records returned from queries present fields in this order:

1. Fields from ancestor classes (outermost first)
2. Fields defined in the record's own class, in definition order
3. Undefined fields, in their stored order

---

## Transactions

~~~vibecode
{"vibecode": {
	"section": "transactions",
	"role": "documents the future Python transaction API with nesting, commit, and exit",
	"key_concepts": ["engine.transaction", "nested_transactions", "commit", "exit", "auto-rollback",
		"context_manager", "future_client"]
}}
~~~

*This section describes future client behaviour. The client is out of scope for the current
implementation — only the engine is being developed at this stage.*

Transactions are created via `engine.transaction()`. Nesting is supported — each call
creates a new transaction nested under the current one.

```python
with engine.transaction() as tx1:
    with engine.transaction() as tx2:
        engine.q0({"action": "create", ...})
        tx2.commit()
    tx1.commit()
```

Rules:

- A transaction block that exits without an explicit `commit()` is automatically rolled back.
- `commit()` commits the transaction and keeps it alive — execution continues after the call.
- `exit()` rolls back the transaction and immediately exits the block (raises an exception
  that unwinds the context manager stack, even across nested transactions).
- Committing an outer transaction from inside a nested block cascades commits inward-first.
- All transactions are managed via `engine.transaction()` — never via a transaction handle.
- Transaction handles (`tx1`, `tx2`) are used only for `commit()` and `exit()` calls.

---

## Error Handling

~~~vibecode
{"vibecode": {
	"section": "error_handling",
	"role": "documents error return policy: engine never raises, always returns dict with errors array",
	"key_concepts": ["no_exceptions_from_engine", "success_false", "errors_array", "MikobaseError", "error_id"]
}}
~~~

- The engine never raises exceptions. It catches all internal errors (including SQLite
  exceptions) and returns a response dict with `"success": false` and an `"errors"` array.
- Each error has an `"id"` and a `"details"` dict.
- The client raises a `MikobaseError` exception carrying the full errors array.

```python
raise MikobaseError(errors=[
    {"id": "invalid_request", "details": {...}}
])
```

---

## SQLite Engine

~~~vibecode
{"vibecode": {
	"section": "sqlite_engine",
	"role": "SQLite-specific implementation details: locking, schema init, historical reads, Q0 translation",
	"key_concepts": ["SQLite", "tenancy", "locking", "schema_initialization", "historical_reads",
		"Q0_to_SQL", "json_extract", "recursive_CTE", "validation"]
}}
~~~

### Tenancy

Each SQLite database file is a single logical database. There is no tenant concept.

### Locking

- `rw` mode acquires an exclusive lock immediately on `connect()`.
- `r` mode acquires a shared lock immediately on `connect()`.

### Schema Initialization

On `connect()`, the engine checks whether the `records` table exists. If it does not, the
engine runs the full schema initialization and seeds the built-in class records. This makes
`connect()` idempotent — connecting to an uninitialized database automatically sets it up.

### Schema

See [sqlite-schema.md](sqlite-schema.md) and [sqlite.sql](sqlite.sql).

### Database Initialization

Built-in classes are recognized by the engine directly by their UNS name. No records are
seeded for them on initialization. The `records` table starts empty.

### Historical Reads

When a connection is opened with a cutoff timestamp, the engine uses a direct parameterized
query against `records_history` with the cutoff injected as a parameter:

```sql
where updated_at <= ?
```

Present-time queries use the `current_records` view. Historical queries bypass the view and
query `records_history` directly with the cutoff timestamp.

### Q0 Execution Strategy

The engine should translate Q0 operations to SQL where efficient and practical:

- `path` equality conditions → SQL `WHERE` clauses using `json_extract`
- `any` (OR narrowing) → SQL `OR` conditions
- `all` (AND narrowing) → SQL `AND` conditions
- `class` filtering → two-step lookup:
  1. Recursive CTE to traverse the inheritance tree and resolve the target class
     and all of its subclasses (using the `inherits` field on class-definition
     records).
  2. Filter records whose `classes` hash contains a platter whose `class` field
     matches any name in the resolved set. The platter lookup walks each
     record's `classes` JSON object looking for matching `class` values.
- Complex cases (e.g. deep `then` chains, nested `path` filtering) may be executed in
  Python after fetching candidate rows from SQLite

Example recursive CTE for class filtering (the inheritance-tree resolution
step is unchanged; only the final match-against-records step differs because
a record may now carry multiple classes in its platter stack):

```sql
with recursive subclasses(name) as (
    select json_extract(bucket, '$.name') from current_records
    where json_extract(bucket, '$.name') = 'foo.com/character'
    union all
    select json_extract(cr.bucket, '$.name') from current_records cr
    join subclasses s on json_extract(cr.bucket, '$.inherits') = s.name
)
select * from current_records cr
where exists (
    select 1
    from json_each(cr.classes) platter
    where json_extract(platter.value, '$.class') in (select name from subclasses)
);
```

Correctness takes priority over efficiency.

### Validation

- Record writes are validated against the latest active class definition at write time.
- Previously written records are not retroactively invalidated by class changes.
- Required fields, type constraints, and string/number/array/hash constraints are all
  enforced at write time.
- Unique constraints (`uniques`) are enforced at write time across active records of that class.
- Join field immutability is enforced at write time — `update` may not change fields listed in `join`.
- Unknown fields in a bucket are stored without validation.

---

## Engine Architecture

~~~vibecode
{"vibecode": {
	"section": "engine_architecture",
	"role": "defines package structure, base engine interface, and validator design",
	"key_concepts": ["package_structure", "base_engine", "q0_method", "validator", "run_all",
		"placeholders_check", "uns_check", "fields_check", "action_check"]
}}
~~~

### Package Structure

```
lib/
    mikobase/
        __init__.py
        client.py
        engine/
            __init__.py
            base.py
            validator.py
            sqlite.py
tests/
    test_sqlite.py
    test_client.py
documentation/
    ...
```

Additional engines (e.g. `postgres.py`, `http.py`) are added as new files in `lib/mikobase/engine/`.

### Base Engine

`engine/base.py` defines the abstract base class that all engines must implement.

Every engine must implement:

- `q0(query)` — accepts a Q0 dict and returns results

The base class also provides default convenience methods implemented via Q0. Subclasses may
override these with more efficient engine-specific implementations:

- `record_by_pk(pk)` — fetches a single record by its primary key
- `by_class(class_name)` — returns all active records of a given class and its subclasses
- `validate(query)` — convenience shorthand for `engine.validator.run_all(query)`

### Validator

Every engine exposes a `validator` property that returns a `Validator` instance. The
`Validator` class lives in `engine/validator.py`.

```python
engine.validator.run_all(query)       # runs all validation methods
engine.validator.placeholders(query)  # placeholder resolution and circular reference checks
engine.validator.uns(query)           # UNS class name format checks
engine.validator.fields(query)        # required fields, invalid types, unknown fields
engine.validator.action(query)        # action validity checks
```

Each method may also be called independently. `run_all` calls all of them and aggregates
their results.

All validation runs without executing the query. Only checks that can be performed
statically are included.

Validator results may include both `errors` and `warnings`. Warnings are non-fatal —
they indicate redundant or suspicious usage that does not prevent execution. The `fields`
check reports warnings when redundant field pairs are used together (`class` + `classes`,
`sort` + `sorts`).

---

## File Storage

~~~vibecode
{"vibecode": {
	"section": "file_storage",
	"role": "documents file deduplication by sha256, chunk ordering, and immutability rules",
	"key_concepts": ["files_table", "file_chunks_table", "sha256_deduplication", "chunk_index",
		"last_chunk", "immutable_once_written"]
}}
~~~

Files are stored in `files` (identity and metadata) and `file_chunks` (binary content).

- Files are deduplicated by `sha256`.
- Chunks are ordered by `chunk_index` starting at 0.
- The final chunk is marked `last = 1`.
- Empty files have a single chunk row with `content = ''` and `last = 1`.
- File rows and chunk rows are immutable once written.

---

## Schema Import and Export

~~~vibecode
{"vibecode": {
	"section": "schema_import_and_export",
	"role": "documents import_schema and export_schema methods including file variants",
	"key_concepts": ["import_schema", "import_schema_file", "export_schema", "export_schema_file"]
}}
~~~

The engine provides methods for importing and exporting schemas.

**Import:**

- `engine.import_schema(dict)` — accepts a schema dict directly
- `engine.import_schema_file(path)` — reads a JSON file and calls `import_schema` internally

**Export:**

- `engine.export_schema()` — returns the current schema as a dict
- `engine.export_schema_file(path)` — writes the current schema to a JSON file

See [class-definition.md](class-definition.md) for schema format and import rules.

---

## General Guidelines

~~~vibecode
{"vibecode": {
	"section": "general_guidelines",
	"role": "implementation constraints: stdlib only, sqlite3, pytest, broad Python compatibility",
	"key_concepts": ["stdlib_only", "sqlite3", "pytest", "broad_Python_compat", "no_logging",
		"temp_files_for_tests", "auto-rollback_on_exit"]
}}
~~~

- Use Python's standard library only — no third-party dependencies for the SQLite engine.
- Use `sqlite3` from the standard library for SQLite access.
- Use `pytest` for testing.
- Aim for broad Python version compatibility — avoid features requiring recent Python versions.
- No logging for now.
- Tests use temporary files on disk, not in-memory databases.
- Connection context manager rolls back any open transactions on exit if not explicitly committed.

---

## Open Questions

- Class registration mechanism: explicit `mikobase.register()` call vs. automatic discovery
  via decorator at definition time.
- Field type definitions for Python class attributes (e.g. `mikobase.Reference(Planet)`).
