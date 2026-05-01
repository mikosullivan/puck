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
	"methods": ["%chain", "%engine", "%kiera", "%call", "%bucket", "%object",
		"%self", "%scope", "%timeout", "%process", "%now", "%blocks",
		"%document", "%vibecode", "%role", "%sys"]
}
```

| Method | Description |
|--------|-------------|
| `%chain` | Scoped ambient context — carries request-scoped values (user, request ID, locale, etc.) down the call stack. Cleared at security boundaries. Use sparingly. |
| `%engine` | Top-level gateway to host-injected resources. Only visible in the outermost script scope; non-capturable. The primary entry point for bootstrapping. |
| `%kiera` | Access to the Kieraverse object namespace by UNS address. `%kiera['foo.com/bar']` returns the registered object (class, capability, etc.) at that address. |
| `%call` | The current call object — function or closure. Provides access to dispatcher, blocks, return, and call metadata. |
| `%bucket` | The current object's private data hash. `@foo` is shorthand for `%bucket['foo']`. Instance variables live here. |
| `%object` | The root class — foundation of the object system. All classes ultimately inherit from it. |
| `%self` | The current object instance. `self` (bare word) is shorthand. |
| `%scope` | The current lexical scope. Holds variables and is used for bare word command (bwc) resolution. `$foo` is shorthand for `%scope['foo']`. |
| `%timeout` | Wraps a block with a hard time limit (whole-second granularity). A compliant engine must make this undefeatable by KScript code. |
| `%process` | Process control. `%process.exit` is graceful (unwinds stack); `%process.abort` is immediate (no cleanup). Abort is a capability — unavailable to untrusted code. |
| `%now` | Returns the current timestamp object. |
| `%blocks` | The array of `do` blocks passed to the current function call. Used in multi-block functions alongside `%call.dispatcher`. |
| `%document` | Saves a documentation block as a statement in the KScriptJSON command array. Takes a MIME type (`text/plain`, `text/markdown`, `text/vibecode`, etc.) and a heredoc or string. Shorthand type names: `text`, `markdown`, `vibecode`. All documentation rules (storage, `side` field, attachment TBD) apply regardless of type. |
| `%vibecode` | Shorthand for `%document 'vibecode' <<EOF...`, which is shorthand for `%document 'text/vibecode' <<EOF...`. Saves an AI-readable JSON documentation block. An optional `side` field indicates attachment intent: `"target"` for the left-hand side of an assignment, `"value"` for the right-hand side. Omit `side` for statements with no assignment. |
| `%role` | Reserved for possible future use. Not part of early versions. |
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
