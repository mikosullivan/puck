~~~vibecode
{"doc": "sprint-index", "sprint": "number-type-integer-only",
	"role": "Codex review finding #1698. `scalar_value` for `scalar_type = 'n'` accepts BOTH integer and real (`typeof(scalar_value) in ('integer', 'real')`). Codex asks whether Caspian is integers-only. Language-level design decision — schema follows whatever the answer is. Source: issue #1698.",
	"status": "active — design decision needed"}
~~~

# number-type-integer-only

Issue #1698. The `scalar_value` CHECK for numbers:

~~~sql
check (scalar_type is null or scalar_type != 'n'
	or typeof(scalar_value) in ('integer', 'real'))
~~~

Accepts both `integer` and `real`. Codex asks: is that intentional?

## Design decision

Caspian's number model is a language-level question. Two paths:

- **Caspian numbers are integer + real (unified).** The current CHECK is right; keep it. Downstream: engine arithmetic handles both storage classes uniformly. Common in dynamic languages (Lua, Python, JavaScript).
- **Caspian is integer-only.** Tighten to `typeof(scalar_value) = 'integer'`. Downstream: engine reject / coerce fractional literals at parse time; no real-valued scalar ever reaches storage.

If Caspian is meant to have separate int and float types down the road, that's a THIRD scalar_type value (e.g., `'i'` and `'f'` instead of one `'n'`), not just a CHECK tighten.

Miko to decide.

## Status

**Active.** Blocked on the language-level decision about the number type.
