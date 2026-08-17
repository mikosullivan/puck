~~~vibecode
{"doc": "sprint-index", "sprint": "hash-key-unicode",
	"role": "Codex review finding #1689. Hash key CHECK uses ASCII-only character classes `[a-zA-Z_]` and `[a-zA-Z0-9_]`. Codex asks whether Caspian intends to support Unicode identifiers — if yes, the current rule rejects them. Source: issue #1689.",
	"status": "active — design decision needed"}
~~~

# hash-key-unicode

Issue #1689. The `refs_hash_key_must_be_identifier` trigger enforces:

- First char in `[a-zA-Z_]`
- Remaining chars in `[a-zA-Z0-9_]`

This is ASCII-only. Unicode identifiers (Greek, Cyrillic, ideographs, etc.) would be rejected.

## Design decision

Caspian's identifier grammar is a language-level decision, not a schema one. Two paths:

- **ASCII-only, intentional.** Match a small explicit character set to keep parser/tokenizer simple and predictable across environments. Common in systems languages (C, Go, older Python). If this is the intent, the sprint closes as documented — the schema correctly reflects the language.
- **Unicode-friendly.** Match Unicode identifier categories per UAX #31 or similar. Requires the CHECK to be rewritten (SQLite's GLOB doesn't do Unicode classes; would need a Lua UDF or a per-codepoint whitelist).

Miko to decide.

## Related

- `[[project_caspian_variables_lowercase]]` — Caspian variables must be lowercase. If ASCII lowercase-only is the rule, Unicode is out of scope.
- `[[project_caspian_utf8]]` — Caspian I/O is UTF-8. This is about STRING content, not identifier grammar; the two can differ.

## Status

**Active.** Blocked on the design decision.
