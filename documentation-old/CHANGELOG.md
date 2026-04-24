# Changelog

## 2026-04-08

- Tightened engine mode parsing so mode strings are explicit, case-insensitive, whitespace-sensitive, and reject unsupported write-only mode cleanly.
- Fixed Q0 normalization to ignore top-level `misc` and `enterprise` metadata while preserving nested query operators.
- Changed SQLite and PostgreSQL delete tombstones to clear record/class business payload instead of copying live bucket/config data into deleted history rows.
- Added descendant-record blocking for PostgreSQL class deletes so ancestor classes cannot be deleted while active subclass records still exist.
- Updated engine tests to cover the stricter tombstone semantics and the newer connection mode rules.

## 2026-04-09

- Added a current SQLite Q0 `create` action for records, plus a public SQLite schema init helper for non-SQL setup code.
- Refactored the Borg experimental loader to create class-definition records through Q0 instead of writing SQLite rows directly.
- Added SQLite Q0 create coverage and updated current-state docs to reflect the new behavior.
