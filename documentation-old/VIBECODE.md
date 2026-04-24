# VIBECODE

## Purpose

This file describes the project as it exists now.

Use this document for present-tense implementation guidance.

## Current Product State

Mikobase is an engine-based database system with active PostgreSQL and SQLite implementations.

The current codebase stores tenant-scoped classes and records with append-only history.

The current implementation centers on these concepts:

- tenants
- classes and `classes_history`
- records and `records_history`
- append-only versioning
- engine-specific adapters for PostgreSQL and SQLite

## Current Engine Model

Mikobase separates shared Ruby logic from engine-specific database behavior.

The active engines are:

- PostgreSQL
- SQLite

Engine open mode is currently implemented as:

- `rw` or `wr`: read/write
- `r`: read-only
- `w`: reserved but not implemented

Mode parsing is case-insensitive and rejects surrounding whitespace.

## Current Data Model

### Tenants

- Tenants have stable identities.
- Tenant rows are append-only after insert.

### Classes

- Classes have identity rows plus append-only history rows.
- Class history supports inheritance.
- Inheritance must reference the latest visible parent version.
- Circular inheritance is rejected.
- Cross-tenant inheritance is rejected.
- Class deletes are append-only tombstones.
- Deleted class tombstones clear class business payload.

### Records

- Records have identity rows plus append-only history rows.
- Record history stores `bucket`, `class_pk`, and `custom_classes`.
- Record deletes are append-only tombstones.
- Deleted record tombstones clear record business payload.

### Current Visibility Rules

- Current state is the latest visible history row per identity.
- Historical reads may use a cutoff timestamp.
- Current record/class views exclude identities whose latest visible history row is inactive.

## Current Custom Object Encoding

`bucket` stores JSON-object payload data.

`custom_classes` maps UUID marker keys inside bucket hashes to client-defined class names.

This is currently how Mikobase represents custom nested objects inside record payloads.

One supported custom class is `mikobase.com/reference`.

A `mikobase.com/reference` object points to another record by `pk`.

## Current Tree Support

The current engines support class tree configuration.

A class may define tree behavior in class config, including:

- the parent reference field
- optional single-root enforcement

Current engines validate:

- parent must be a reference object
- parent cannot reference self
- parent must be in the same class tree
- single-root constraints when configured

## Current Q0 State

Q0 is the built-in query language currently implemented in both engines.

Today, the implemented Q0 scope is:

- PostgreSQL: `action: "select"`
- SQLite: `action: "select"` and a minimal `action: "create"` for records

Current supported behavior includes:

- class-based select
- path-based select
- nested `then`
- `where`
- `any`
- equality operators, including case-insensitive string equality
- SQLite record create with a required `bucket`
- SQLite record create with an optional string `class`
- SQLite record create responses shaped as `{ "success": true, "results": { "pk": ... } }`

Current normalization rules include:

- top-level `misc` is ignored
- top-level `enterprise` is ignored

Nested query operators are not stripped by that normalization.

## Current Runtime Environment

Project execution happens remotely on `autolycus.idocs.com`.

The mounted local workspace is the editing surface.

## Current Testing Workflow

Tests live under `command-line/tests`.

Preferred remote test runner:

```bash
ssh autolycus.idocs.com \
	'mb-test /home/miko/mounts/oberon/projects/ruby/mikobase/working/command-line/tests'
```

Use the final top-level JSON result as the authoritative outcome.

## Current Documentation Roles

- `documentation/VIBECODE.md`: present-facing description of the current codebase
- `documentation/ISSUES.md`: future-facing plans, open questions, and proposed features
- `documentation/CHANGELOG.md`: concise past-facing log of completed changes

## Design References

- [documentation/postgresql/DESIGN.md](documentation/postgresql/DESIGN.md)
- [documentation/sqlite/DESIGN.md](documentation/sqlite/DESIGN.md)
- [documentation/ruby/DESIGN.md](documentation/ruby/DESIGN.md)
