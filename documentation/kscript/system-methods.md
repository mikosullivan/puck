# KScript System Methods

System methods are global methods provided by the KScript runtime. They are always
available without import or injection. All system methods use the `%` prefix.

User code cannot define new `%`-prefixed methods. The full list is fixed by the runtime.

---

## Reference

```
vibecode: {
	"section": "reference",
	"prefix": "%",
	"availability": "always_available_without_import",
	"user_defined": false,
	"methods": ["%chain", "%engine", "%forks", "%tmp", "%kiera", "%call", "%bucket",
		"%self", "%scope", "%timeout", "%process", "%now", "%blocks",
		"%document", "%vibecode", "%role", "%utils", "%sys"]
}
```

| Method | Description |
|--------|-------------|
| `%chain` | Ambient context — carries request-scoped values (user, request ID, locale, etc.) down the call stack. Isolation is at **function boundaries only**: a write to `%chain` inside a block (`if`, loop, bare block) persists after the block ends. The callee gets its own chain inherited from the caller; writes in the callee do not propagate back up. Use `%chain.scope do...end` for explicit block-level isolation. **Wiped at role boundaries** (see [roles.md](../roles.md)). Use `%chain.isolate do...end` for a voluntary inline wipe plus fresh ephemeral role. |
| `%engine` | Returns the engine object — the gateway to host-injected resources. The method only exists in the outermost scope; functions and closures cannot see it. The engine object itself is non-storable: it can be used directly but cannot be assigned to a variable. |
| `%forks` | Engine-granted fork manager. Returns `null` if the engine did not grant fork permission. If granted, returns the fork manager object used to spawn and coordinate forked processes. Guard all fork code with `if %forks`. See the forking documentation for the full API. |
| `%tmp` | Engine-granted temporary directory. Returns `null` if the engine did not grant tmp permission. If granted, returns a directory object for the engine-provided temp path. Typically used by forked server processes to create Unix domain socket files. |
| `%kiera` | Returns the current kiera object (scoped via `%chain`). The kiera resolves UNS addresses through its configured getters. `%kiera['foo.com/bar']` is a shorthand for the kiera's lookup method. Returns plain null if no kiera is in the chain. See [kiera.md](../kiera.md) for the full kiera-object model. |
| `%call` | The current call object — function or closure. Provides access to dispatcher, blocks, return, and call metadata. |
| `%bucket` | The current object's private data hash. `@foo` is shorthand for `%bucket['foo']`. Instance variables live here. |
| `%self` | The current object instance. `self` (bare word) is shorthand. |
| `%scope` | The current lexical scope. Holds variables and is used for bare word command (bwc) resolution. `$foo` is shorthand for `%scope['foo']`. |
| `%timeout` | Wraps a block with a hard time limit (whole-second granularity). A compliant engine must make this undefeatable by KScript code. The default timeout for engine-untrusted code is short to prevent surreptitious crypto mining. |
| `%process` | Process control. `%process.exit` is graceful (unwinds stack); `%process.abort` raises an abort exception immediately. Under the role model, abort behavior is governed by the alarm rules in [roles.md](../roles.md). |
| `%now` | Returns the current timestamp object. The returned timestamp is owned by the engine's `clock` role. |
| `%blocks` | The array of `do` blocks passed to the current function call. Used in multi-block functions alongside `%call.dispatcher`. |
| `%document` | Saves a documentation block as a statement in the KScriptJSON command array. Takes a MIME type (`text/plain`, `text/markdown`, `text/vibecode`, etc.) and a heredoc or string. Shorthand type names: `text`, `markdown`, `vibecode`. All documentation rules (storage, `side` field, attachment TBD) apply regardless of type. |
| `%vibecode` | Shorthand for `%document 'vibecode' <<EOF...`, which is shorthand for `%document 'text/vibecode' <<EOF...`. Saves an AI-readable JSON documentation block. An optional `side` field indicates attachment intent: `"target"` for the left-hand side of an assignment, `"value"` for the right-hand side. Omit `side` for statements with no assignment. |
| `%role` | Returns the role currently in effect — the owning role of the function-object currently executing. See [roles.md](../roles.md) for the role model. |
| `%utils` | Engine-granted convenience-utility capability. Provides common, low-sensitivity helpers (`%utils.now`, `%utils.rand.uuid`, etc.). Returns `null` if the engine did not grant it. Everything coming out of `%utils` is owned by the `utils` role. |
| `%sys` | Reserved for possible future use. Not part of early versions. |

---

## Shorthands

```
vibecode: {
	"section": "shorthands",
	"mappings": {
		"$foo": "%scope['foo']",
		"@foo": "%bucket['foo']",
		"self": "%self",
		"%vibecode <<EOF": "%document 'vibecode' <<EOF",
		"%document 'text' <<EOF": "%document 'text/plain' <<EOF",
		"%document 'markdown' <<EOF": "%document 'text/markdown' <<EOF"
	}
}
```

Several system methods have shorthands used so frequently that the long form is rarely
written:

| Shorthand | Expands to |
|-----------|------------|
| `$foo` | `%scope['foo']` |
| `@foo` | `%bucket['foo']` |
| `self` | `%self` |
| `%vibecode <<EOF...EOF` | `%document 'vibecode' <<EOF...EOF` → `%document 'text/vibecode' <<EOF...EOF` |
| `%document 'text' <<EOF...EOF` | `%document 'text/plain' <<EOF...EOF` |
| `%document 'markdown' <<EOF...EOF` | `%document 'text/markdown' <<EOF...EOF` |
