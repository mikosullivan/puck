# SQLite database design

~~~vibecode
{"vibecode": {
	"doc": "ideas_fiona_spec_sqlite",
	"role": "SQLite schema spec for Fiona — table shapes, columns, indexes, and the SQL surface the engine uses to read and write. This is the on-disk implementation layer; the conceptual model (hsa + relationships, immutability, graph-not-tree) lives at ../../. Being spec'd against SQLite specifically because that's the bundled DBMS in Caspian's Cache tier (lsqlite3).",
	"status": "stub"
}}
~~~

SQLite schema and access-pattern spec — the concrete DBMS layer under Fiona's conceptual model at [../../](../../).

The source of truth for the schema is `../build/src/fiona.sql`. This page reads that file on every render, so edits to the SQL show up here immediately.

<!-- file: ../build/src/fiona.sql -->

