# Schema

~~~vibecode
{"vibecode": {
	"doc": "ideas_fiona_spec_sqlite_schema",
	"role": "Live-rendered view of the Fiona SQLite schema. Sources of truth are ../../../../src/fiona/fiona.sql (persistent) and ../../../../src/fiona/fiona-temp.sql (per-connection temp tables). This page reads both on every render so edits show up immediately.",
	"status": "live reference"
}}
~~~

Live-rendered view of the Fiona SQLite schema. Two files: `fiona.sql` for the persistent tables and triggers, `fiona-temp.sql` for the per-connection temp tables. Both are read on every render, so edits to either show up here immediately.

## Persistent schema (`fiona.sql`)

Applied once at fresh-DB creation. Holds `collections`, `relationships`, `meta`, all constraints and triggers.

<!-- file: ../../../../src/fiona/fiona.sql -->

## Per-connection temp schema (`fiona-temp.sql`)

Applied at every connection open. Holds the iterator scratch tables that live in the connection's temp schema (per-connection, don't survive close).

<!-- file: ../../../../src/fiona/fiona-temp.sql -->
