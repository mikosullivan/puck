# Filesystem Access in Charlie

Charlie filesystem access is provided through **jail objects** — directory-scoped handles
injected by the host. A jail gives access to a specific directory tree and nothing outside
it. The underlying real path is never exposed to Charlie code.

---

## The Jail

```
vibecode: {
	"section": "the_jail",
	"concept": "directory_scoped_handle_injected_by_host",
	"real_path": "never_exposed_to_charlie_code",
	"access": "%engine['name']",
	"subscript_sugar": "$jail['path'] == $jail.file('path')",
	"jail_is_directory": true
}
```

A jail is itself a directory object rooted at the injected path. All operations are
relative to that root.

```
$jail = %engine['docs']
```

The `[]` operator is a shorthand for `.file()`:

```
$jail.file('tmp/draft.txt')   # explicit
$jail['tmp/draft.txt']        # same thing
```

Because the jail is a directory object, all directory operations work directly on it:

```
$jail.files
$jail.dirs
$jail.children
$jail['readme.txt'].read
```

---

## File Objects

```
vibecode: {
	"section": "file_objects",
	"operations": ["read", "write", "append", "delete", "exists?", "name", "path",
		"size", "sha256", "copy", "move", "execute"],
	"copy_returns": "new_file_object_at_destination",
	"move_mutates": "object_path_in_place",
	"execute_returns": "integer_exit_code",
	"notes": ["move_is_only_operation_that_changes_objects_own_path"]
}
```

A file object holds its path relative to the jail root. All operations work from that
path alone.

```
$file = $jail['docs/readme.txt']
```

### Operations

```
$file.read              # returns file contents as a string
$file.write($data)      # overwrites the file with $data
$file.append($data)     # appends $data to the file
$file.delete            # deletes the file
$file.exists?           # returns true/false
$file.name              # filename only, no path
$file.path              # full path from jail root
$file.size              # size in bytes
$file.sha256            # SHA-256 hex digest of contents
$file.readable          # current read state; truthy if reading allowed
$file.readable = false  # permanent one-way ratchet down (see below)
$file.writable          # current write state
$file.writable = false  # permanent one-way ratchet down
$file.executable        # current execute state; truthy if execution allowed
$file.executable = false  # permanent one-way ratchet down
$file.execute(*args)    # runs the file as a process; returns integer exit code
$file.execute(*args, timeout: 20)  # same, but kills the child after 20s
$file.jail($perms)      # derive a restricted jail scoped to this file
```

Operations that depend on a permission fail when that permission has been
ratcheted off: `.read`, `.size`, `.sha256` fail without read; `.write`,
`.append`, `.delete` fail without write; `.execute` fails without execute.
Metadata operations that don't touch the filesystem (`.name`, `.path`,
`.exists?`) keep working regardless — useful for logging or inspecting a
downgraded reference.

`.execute(*args)` runs the file as a process. Positional args are passed
as command-line arguments to the process. The call is synchronous: it
blocks until the process exits and returns the integer exit code. Output
capture, stdin piping, async/streaming, and process-handle semantics are
deferred — v1 returns the exit code only.

An optional `timeout: N` keyword arg sets a hard wall-clock deadline (in
whole seconds). If the child process doesn't exit by then, it's killed
with SIGKILL (signal 9) — no SIGTERM courtesy, no chance for the child
to clean up — and `.execute` raises a `kiera.uno/error/timeout`
in the caller's scope. That's the same class users catch from
`%utils.timeout`, so a single `catch` clause can handle either source.
Without `timeout:`, the call waits indefinitely.

### Permissions Are Downgrade-Only

A file object's read and write permissions can be **ratcheted off but never
on**. Assigning `false` to `.readable` or `.writable` succeeds; assigning
`true` after the property has been set to `false` is an error. Once a
permission is gone, it's gone for that object's lifetime. A developer who
hands a downgraded file to less-trusted code can be certain the recipient
cannot re-elevate it.

File objects inherit their initial permissions from the jail they come
from — a file from a read-only jail starts read-only. The ratchet can
take permissions away from there, but a file from a read-only jail can
never gain write through any API.

### Operations that return a new file object

```
$new_file = $file.copy('other/path.txt')   # copies file; returns new file object at destination
```

### Operations that mutate the object's path

```
$file.move('new/path.txt')   # moves the file; updates $file's path in place
```

`move` is the only operation that changes the object's own path. All other operations
leave the path unchanged.

---

## Directory Objects

```
vibecode: {
	"section": "directory_objects",
	"operations": ["children", "files", "dirs", "exists?", "name", "path",
		"create", "delete"],
	"subscript": "$dir['name'] returns file or directory object based_on_what_exists",
	"lazy": "object_created_without_hitting_filesystem_failure_on_actual_operation",
	"chaining": "$jail.dir('a').dir('b')['file.txt'].read"
}
```

A directory object holds its path relative to the jail root.

```
$dir = $jail.dir('docs/shakespeare')
```

### Operations

```
$dir.children            # all entries — files and directories
$dir.files               # file objects only
$dir.dirs                # directory objects only
$dir.exists?             # returns true/false
$dir.name                # directory name only, no path
$dir.path                # full path from jail root
$dir.create              # creates the directory
$dir.delete              # deletes the directory
```

### Navigating

```
$dir['hamlet.txt']       # returns a file object
$dir['subdir']           # returns a directory object
```

`[]` returns the appropriate type based on what exists at that path. It is lazy — the
object is created without hitting the filesystem; failure occurs on the actual operation.

Directories can be chained:

```
$text = $jail.dir('docs').dir('shakespeare')['hamlet.txt'].read
```

---

## Jail Permissions

```
vibecode: {
    "section": "jail_permissions",
    "permissions": ["read", "write", "execute"],
    "execute_default": false,
    "set_by": "host_at_injection_time",
    "violation": "permission_error_regardless_of_disk_state"
}
```

A jail carries explicit permissions for what operations are allowed within it.
**Execution is a permission that is off by default** — any attempt to invoke a
`.charlie` file inside a jail without execute permission fails with a permission
error, regardless of what's on disk.

The host enables execute explicitly at jail injection time, and only when the
directory is intended to hold code that should run (e.g., a Robinson site root).
A jail holding user-uploaded content, generated assets, or anything else not
authored by the developer should never have execute on.

Read and write are independently controlled in the same way. A jail can be
read-only, read-and-execute, read-write, read-write-execute, etc., in any
combination. There are no implied permissions — turning one on doesn't imply
another.

The default-off stance on execute follows the project's general "no dangerous
defaults" principle: granting execute is a deliberate decision by the host,
never something that quietly happens.

---

## Deriving Restricted Jails

```
vibecode: {
    "section": "deriving_restricted_jails",
    "method": ".jail(perms)",
    "available_on": ["jails", "directory_objects", "file_objects"],
    "produces": "new_jail_with_reduced_permissions",
    "permissions_bounded_by_source": true,
    "use_case": "pass_capability_to_callee_without_giving_them_original_object"
}
```

Any jail, directory object, or file object can produce a **derived jail**
with a specified subset of its own permissions:

```
$ro_jail = $jail.jail('r')         # read-only jail rooted at $jail's root
$rw_sub = $dir.jail('rw')          # read-write jail rooted at this directory
$ro_file = $file.jail('r')         # read-only one-file jail
```

The argument is a permissions code — a string of single letters where
`r` = read, `w` = write, `x` = execute (e.g., `'r'`, `'rw'`, `'rx'`,
`'rwx'`).

**The derived jail's permissions are bounded by the source's.** A
derived jail can never have more permissions than the object it was
derived from. Requesting `'rw'` from a read-only source either fails or
silently returns a read-only jail (TBD).

### Why This Exists

The primary use case is **passing a capability to a callee** without
exposing the original object:

```
# caller holds the full-permission $file
&callee $file.jail('r')   # callee gets a read-only one-file jail
                           # caller's $file is untouched
```

The callee has a normal jail object — it can read, navigate, do
whatever jails allow with `r` permission — but it has **no reference to
the original `$file`**. It cannot write to `$file`, cannot escalate its
view, cannot pass anything back that would let other code reach the
original. The capability boundary is structural, not stateful.

This replaces several patterns that would otherwise need block scoping
or temporary mutation:

- **Pass-restricted-access-down-the-chain**: derive a jail and pass it.
- **Limit blast radius of an untrusted callee**: derive a jail with
  minimal permissions; callee can't exceed them.
- **Hand a file to logging code that should never write**: derive a
  read-only jail or set `$file.writable = false` on a fresh reference.

### Relationship to the Property Ratchet

The property ratchet (`$file.readable = false`) mutates the existing
object permanently. The jail derivation (`$file.jail('r')`) creates a
new object with reduced permissions, leaving the original untouched.

Use the ratchet when the caller wants to permanently restrict their own
file's powers (defensive coding). Use jail derivation when handing
something to other code that should only see a restricted view.

---

## Authorizing Untrusted Paths

```
vibecode: {
    "section": "authorizing_untrusted_paths",
    "method": "$dir.use_path",
    "returns": "file_or_directory_entry_at_resolved_path",
    "accepts": "trusted_or_untrusted_strings",
    "normalization": "automatic_inside_use_path",
    "unsafe_path_behavior": "yields_non_existent_entry"
}
```

**Untrusted strings cannot be used as paths directly.** Passing an untrusted
string to a directory's `[]` operator fails with a trust error. There is no
implicit elevation, no pattern-based untainting, no `%chain.trust` shortcut.

Two ways to obtain a file or directory entry from a directory:

```
# Literal string — trusted by construction.
$file = $dir['readme.txt']

# Any string, trusted or not — explicit elevation.
$file = $dir.use_path($string)
```

`$dir.use_path` returns the same kind of entry `$dir[]` returns — a file
object or directory object, depending on what exists at the resolved path.
Lazy in the usual way: returned even for non-existent paths; operations
fail when actually attempted; use `$entry.exists?` to check first. Unsafe
paths (illegal characters, escape attempts) yield a non-existent entry
indistinguishable from a missing file, so the caller's `.exists?` check
covers both cases without special-handling.

`use_path` is a superset of `[]`: it works for any string regardless of
trust. The `[]` form is a shortcut for the literal case. A developer who
prefers a single API can always write `$dir.use_path('readme.txt')`; the
`[]` form just trims a few keystrokes when the string is hardcoded.

**`use_path` normalizes automatically.** Filesystem-side normalization
(`//` collapse, `.` and `..` resolution or rejection, control-character
and null-byte rejection, etc.) happens inside `use_path` before
resolution. Callers don't normalize beforehand. (URL decoding,
query-string parsing, and other non-FS concerns are upstream — by the
time you call `use_path`, the string is just a path.)

### Rules

- **Explicit elevation.** Untrusted strings only reach the filesystem
  through `use_path` — never silently. The call site is conspicuous;
  a reviewer can grep for `use_path` and see every elevation point.
- **Tied to one directory.** `use_path` is a method on a directory; the
  returned entry is bounded to that directory's jail. There is no
  cross-directory authorization — to use a string against a different
  directory, call `use_path` on that one.
- **No pattern check required.** Unlike Perl's untaint-via-regex, the
  `use_path` call itself is the positive declaration of intent. The
  framework provides the boundary (the directory's root and the
  normalization); the developer provides the intent.
- **The returned entry is a normal entry.** Once obtained, the file or
  directory object behaves identically to one obtained from a literal
  path. It can be stored, passed, returned. The authorization isn't
  block-scoped — it's a one-time gate at the call site, and the result
  is just a regular entry from then on. The directory's jail boundary
  is structural; the entry can't escape it regardless of how it's used
  later.

---

## Iteration

```
vibecode: {
	"section": "iteration",
	"iterables": ["children", "files", "dirs"],
	"pattern": "$dir.X.each do($item) end"
}
```

```
$dir.children.each do($child)
    puts($child.name)
end

$dir.files.each do($file)
    puts($file.path)
end

$dir.dirs.each do($dir)
    puts($dir.name)
end
```

---

## Notes

```
vibecode: {
	"section": "notes",
	"path_restriction": "relative_to_jail_root_only",
	"rejected": ["absolute_paths", "dotdot_traversal"],
	"api_status": "basics_covered_more_may_be_added"
}
```

- All paths are relative to the jail root. Absolute paths and `..` traversal are rejected
  by the runtime.
- This API covers the basics. Additional features may be added later.
