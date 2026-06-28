# Jasmine in Caspian

~~~vibecode
{"vibecode": {
	"doc": "jasmine-in-caspian",
	"role": "Caspian-side API for writing entries to Jasmine logs. The whole API is %chain.log[key] = value, written from inside any function; the function call is the entry boundary. Companion to jasmine.md, which spec's the file format and storage layer.",
	"key_concepts": ["chain_log_writes", "function_call_is_entry_boundary",
		"nested_call_frames", "auto_exception_recording",
		"auto_warning_capture", "role_boundary_wipe"]
}}
~~~

The Caspian-side API for logging is one line:

```
%chain.log['user_id'] = $user.id
```

That's the whole user-facing surface. Any function can write to
`%chain.log[key]` and the entry is scoped to that function call.
When the function returns, the entry is flushed (if a framework
configured a destination) or nested into the caller's entry as a
child frame. The Jasmine file format and storage layer live in
[jasmine.md](index.md).

---

## Function-call scope

`%chain.log` is a sub-feature of `%chain`. Per
[system-methods.md](../../syntax/system-methods.md), **`%chain` isolation
is at function boundaries only** — the callee gets its own chain
inherited from the caller's; writes in the callee do not propagate
back up. The same rule applies to `%chain.log`:

- Every function call has its own log entry.
- Writes via `%chain.log[key] = value` go to that entry.
- When the function returns, the entry is either flushed (at a
  framework-demarcated boundary) or attached to the caller's entry
  as a nested frame in `calls` (otherwise).
- No `if %chain.log` guards needed; the write either lands somewhere
  or is a no-op. Either way, the code reads the same.

```
%vibecode <<~VIBECODE
{"comment": "log a few fields for the request handler"}
VIBECODE
function &handle_request($req)
    %chain.log['method']  = $req.method
    %chain.log['path']    = $req.path
    %chain.log['user_id'] = $req.user.id
    process($req)
end
```

No setup block, no logger object to pass around. The function call
IS the entry; writes accumulate; the framework collects them at the
boundary it cares about.

---

## Nested call frames

When a function calls another function, **the callee has its own
fresh entry**. Anything the callee writes to `%chain.log[key]` goes
into its own entry, not the caller's. When the callee returns, its
entry is appended to the caller's `calls` array as a nested frame.

The result is a tree of log entries that mirrors the call tree:

```json
{
    "uuid": "...",
    "timestamp": "...",
    "method": "GET",
    "calls": [
        {
            "function": "process",
            "entry": {
                "cache_hit": true,
                "calls": [
                    {"function": "authenticate",
                     "entry": {"user_id": "abc123"}}
                ]
            }
        }
    ]
}
```

Each call frame contains:

- **`function`** — identifier for the function that generated the
  frame.
- **`entry`** — the entry that function built up, possibly with
  its own `calls` array of further nested frames.

The framework handles this transparently — user code just writes
to `%chain.log` as normal.

---

## Why this design

The "every Caspian function call is its own entry" rule solves
several things at once:

- **Untrusted code is structurally contained.** Each function only
  sees and writes its own entry. Can't exfiltrate from the caller's
  entry (different frame, invisible). Can't inject into the
  caller's entry (only the framework knows where to append). Can't
  pollute the caller's log (its writes go into its own bucket).
- **Free debugging / observability.** The call tree IS the log.
  Every function's contribution is structurally distinguishable.
- **Library authors can use `%chain.log` freely.** No risk of
  polluting their callers' audit trails. No coordination between
  unrelated libraries.
- **Composability.** Two libraries that both log don't conflict;
  each ends up under its own call frame.

---

## Empty entries are omitted

If a function doesn't write to `%chain.log`, **no frame is appended**
to the caller's `calls` array on return. Only functions that
actually recorded something contribute to the tree, so the log
stays compact.

The flip side: there's no record that "function X was called but
recorded nothing." For most logging use cases this is the right
tradeoff. A future opt-in "record every call" mode is noted as a
possibility, not in scope for v1.

---

## Source line numbers in frames

For code originally written in Caspian source (rather than
hand-built CaspianJ), each call frame can include the source
line number where the call was made. Enabled by
[CaspianJ's source-position annotations](../../caspianj.md#source-position-annotations).
For hand-built CaspianJ with no known source line, the field
is absent; tools just check for presence.

---

## Automatic exception recording

When an exception propagates out of a function call, the function's
entry **records the exception before being attached or flushed**.
The record typically includes the exception type, message, source
location, and any other fields the exception carries.

```json
{
    "exception": {
        "type": "puck.uno/error/something",
        "message": "...",
        "line": 142,
        "file": "..."
    },
    "calls": [...]
}
```

The exception is **still re-raised** — Jasmine doesn't swallow it.
The recording is an observation, not a catch. The exception
continues unwinding the stack and is caught (or not) by whoever
was going to catch it anyway.

**On by default.** A debugging tool that drops what went wrong is
missing half its job. Most logging libraries (log4j, structlog,
Sentry, etc.) do this by default for the same reason. A per-logger
flag (working name `record_exceptions = false`) turns it off.

---

## Automatic warning capture

Warnings raised inside a function — via `%chain.warn` or `.raise`
on a warning object — are **captured by the function's entry**
and recorded in its `warnings` array. Warnings don't need to
escape the function to be recorded; the entry catches them
actively.

The captured warning shape matches Xeme's `warnings` array
(`{"id": ..., "details": {...}}`) so a tool that reads Xeme
warnings can read Jasmine warnings without translation.

```json
{
    "warnings": [
        {"id": "duplicate_cookie_name",
         "details": {"name": "session", "scopes": [...]}}
    ],
    "calls": [...]
}
```

**On by default**, same reasoning as exception recording. A
per-logger flag (`record_warnings = false`) turns it off.
**Interaction with explicit `heed()`**: an inner `heed('class')`
block still works as written — it catches the warning before
Jasmine's implicit catch sees it. Jasmine's capture is the
catch-all at the function boundary; explicit `heed`s inside are
finer-grained collectors that get first crack.

---

## Interaction with %chain's role-boundary wipe

`%chain` is wiped at role boundaries (see [roles.md](../../roles.md)).
A called role sees a fresh `%chain.log` — anything it writes goes
into its own frame, and the caller sees it only after return, as
part of the assembled tree.

The security properties:

- Untrusted code can't read the caller's log (different frame).
- Untrusted code can't inject directly into the caller's log (its
  contribution is structurally tagged as its own frame).
- Trusted code sees what untrusted code recorded only at the
  end-of-call merge, in clearly attributed form. That's the audit
  trail working as intended.
