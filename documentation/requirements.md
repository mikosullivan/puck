# Mikobase Requirements

## Overview

Mikobase is a middleware database system. It defines a protocol by which clients in various
programming languages can access objects in a database. It is a NoSQL solution with a
class-based object model.

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

## Universal Namespace (UNS)

Class names use UNS — a URL without the `https://` protocol prefix. The domain provides a
globally unique namespace.

Examples:

- `mikobase.com/record`
- `mikobase.com/record/class`
- `mikobase.com/reference`
- `mikobase.com/dbfile`
- `foo.com/bar`
- `mycompany.com/character`

---

## Object Model

### Records

- Records are the primary data objects in Mikobase.
- Every record has a stable identity (`record_pk`) and an append-only version history.
- The current state of a record is its latest active history row.
- A record whose latest history row has `active = false` is considered deleted.
- Historical reads use a cutoff timestamp to view the state of records at a past point in time.

### Classes

- Every record has a class. The default class is `mikobase.com/record`.
- Classes are themselves stored as records with class `mikobase.com/record/class`.
- A class definition is stored in the record's `bucket` field.
- Class names are UNS strings.
- Inheritance is always explicit via the `inherits` field. There is no path-implied inheritance.
- A class is a **record class** if it inherits from `mikobase.com/record` (directly or
  transitively). Otherwise it is an **object class**.
- `"record_class": true` is shorthand for `"inherits": "mikobase.com/record"`.

### `bucket`

- Each record version stores its payload in `bucket`, a JSON object.
- Fields not defined in the class are stored as-is without validation.

### `custom_classes`

- `custom_classes` maps UUID marker keys to class references for nested objects in `bucket`.
- A UUID marker key is embedded inside a nested object in `bucket` with value `true`.
- The client scans `bucket` for these UUID keys, removes them, and instantiates the
  appropriate class for each nested object.
- This avoids field name collisions while supporting arbitrary nested objects.
- `custom_classes` values have the shape `{"class": "foo.com/bar"}`.

### Built-in Classes

The following classes are seeded as database records on initialization:

- `mikobase.com/record` — base class for all records
- `mikobase.com/record/class` — class for class definitions
- `mikobase.com/reference` — reference to another record by `record_pk`
- `mikobase.com/dbfile` — file attachment

---

## Connection

Connections are opened with an explicit mode. There is no default mode.

Valid modes:

- `rw` or `wr` — read/write (normalized to `rw`)
- `r` — read-only
- `w` — reserved, not yet implemented

Mode parsing is case-insensitive. Surrounding whitespace is rejected.

Opening a connection with a cutoff timestamp makes the entire connection read-only (historical
snapshot).

### Python API

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
    "class": "foo.com/character",
    "updated_at": "2026-04-21T14:32:00.123",
    "bucket": {...},
    "custom_classes": {...}
}
```

### Convenience methods

The base engine also provides convenience methods that build Q0 dicts internally:

- `engine.record_by_pk(pk)` — fetches a single record by primary key
- `engine.by_class(class_name)` — returns all active records of a given class and subclasses

---

## Records as Python Objects

*This section describes future client behaviour. The client is out of scope for the current
implementation — only the engine is being developed at this stage.*

The engine returns raw dicts. The client will wrap them into Python objects.

- The record's `class` field is used to look up the corresponding Python class.
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
- `class` filtering → recursive CTE to traverse the inheritance tree, then filter records
  by matching the `class` column against the resolved set of subclass names
- Complex cases (e.g. deep `then` chains, nested `path` filtering) may be executed in
  Python after fetching candidate rows from SQLite

Example recursive CTE for class filtering:

```sql
with recursive subclasses(record_pk) as (
    select record_pk from current_records
    where json_extract(bucket, '$.name') = 'foo.com/character'
    union all
    select cr.record_pk from current_records cr
    join subclasses s on json_extract(cr.bucket, '$.inherits') =
        (select json_extract(bucket, '$.name') from current_records where record_pk = s.record_pk)
)
select * from current_records
where class in (select name from subclasses);
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

Files are stored in `files` (identity and metadata) and `file_chunks` (binary content).

- Files are deduplicated by `sha256`.
- Chunks are ordered by `chunk_index` starting at 0.
- The final chunk is marked `last = 1`.
- Empty files have a single chunk row with `content = ''` and `last = 1`.
- File rows and chunk rows are immutable once written.

---

## Schema Import and Export

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
