# Filesystem Access in Charlie

~~~json
{"vibecode": {
	"doc": "filesystem",
	"role": "spec for Charlie filesystem access via directory jails — host-injected directory-scoped handles that hide the real path. The directory jail is the FUNDAMENTAL UNIT of filesystem access in Charlie: nothing outside a granted jail is reachable. Covers jails themselves, files, directories, copy/move/delete, and sub-jails.",
	"key_concepts": ["directory_jail_is_the_only_filesystem_handle",
		"no_access_outside_a_granted_jail",
		"real_path_hidden_from_charlie_code",
		"subscript_sugar", "sub_jails"],
	"example_universe": "Narnia"
}}
~~~

**The fundamental unit for accessing the filesystem in Charlie is a
directory jail.** A directory jail is a host-injected handle scoped to one
directory tree. Charlie code can only see, read, and write files inside
the jail's tree — there is no way to reach anything outside it, and no
way to learn the underlying real path on disk. No filesystem access
exists in Charlie without a directory jail. See
[The Directory Jail](#the-directory-jail) below for the full mechanism.

---

<a id="file-objects"></a>
## File Objects

~~~json
{"vibecode": {
	"section": "file_objects",
	"operations": ["append", "copy", "delete", "execute", "exists?", "jail",
		"move", "name", "path", "read", "sha256", "size", "write"],
	"aliases": {"copy_to": "copy", "move_to": "move"},
	"copy_returns": "new_file_object_at_destination",
	"move_mutates": "object_path_in_place",
	"execute_returns": "integer_exit_code",
	"notes": ["move_is_only_operation_that_changes_objects_own_path"]
}}
~~~

A file object holds its path relative to the jail root. All operations work from that
path alone.

```
$file = $jail['docs/readme.txt']
```

<a id="file-append"></a>
### `append`

```
$file.append($data)   # appends $data to the file
```

Requires write permission.

<a id="file-copy"></a>
### `copy` (alias: `copy_to`)

```
$new_file = $file.copy('other/path.txt')      # copies file; returns new file object at destination
$new_file = $file.copy_to('other/path.txt')   # exact same thing
```

The original `$file` is unchanged. The return is a new file object
pointing at the destination path within the same jail.

`copy_to` is an alias — same method, more explicit name for code
that reads better with the preposition (`file.copy_to('archive/')`).

<a id="file-delete"></a>
### `delete`

```
$file.delete   # deletes the file
```

Requires write permission.

<a id="file-execute"></a>
### `execute`

```
$file.execute(*args)               # runs the file as a process; returns exit code
$file.execute(*args, timeout: 20)  # same, but kills the child after 20s
$file.execute(*args, detach: true) # spawns, returns immediately with a fork handle
```

Runs the file as a process. Positional args are passed as
command-line arguments. By default the call is **synchronous**: it
blocks until the process exits and returns the integer exit code.
Requires execute permission.

Output capture, stdin piping, and async/streaming are deferred —
v1 returns the exit code only (synchronous) or a fork handle
(detached).

**`timeout: N`** — sets a hard wall-clock deadline in whole seconds
on the synchronous call. If the child process doesn't exit by then,
it's killed with SIGKILL (signal 9) — no SIGTERM courtesy, no chance
for the child to clean up — and `.execute` raises a
`puck.uno/error/timeout` in the caller's scope. That's the same
class users catch from `%utils.timeout`, so a single `catch` clause
can handle either source. Without `timeout:`, the synchronous call
waits indefinitely.

**`detach: true`** — spawns the process and returns immediately with
a **fork handle** (the same handle shape returned by
[`%forks`](../syntax/system-methods.md)). The caller can use the
handle to check whether the process is still running, wait for it,
retrieve its exit code, or kill it. The process keeps running after
`.execute` returns and is the caller's responsibility from that
point on — Charlie does not auto-reap detached children when the
parent's scope ends.

`timeout:` and `detach:` are mutually exclusive — `timeout:`'s
contract is to raise in the caller's scope, which has no meaning
for a detached call. Passing both is an error.

<a id="file-exists"></a>
### `exists?`

```
$file.exists?   # returns true/false
```

Metadata-only — does not require any permission and keeps working on
a fully ratcheted-down reference.

<a id="file-jail"></a>
### `jail`

```
$inner_jail = $file.jail($perms)   # derive a restricted jail scoped to this file
```

See [Deriving Restricted Jails](#deriving-restricted-jails) for the
full mechanism.

<a id="file-move"></a>
### `move` (alias: `move_to`)

```
$file.move('new/path.txt')      # moves the file; updates $file's path in place
$file.move_to('new/path.txt')   # exact same thing
```

**`move` is the only operation that changes the object's own path.**
All other file operations leave `$file.path` alone; `move` mutates
it in place to reflect the new location.

`move_to` is an alias — same method, more explicit name for code
that reads better with the preposition.

<a id="file-name"></a>
### `name`

```
$file.name   # filename only, no path
```

Metadata-only.

<a id="file-path"></a>
### `path`

```
$file.path   # full path from the jail root (never the real OS path)
```

Metadata-only. The path is always relative to the jail root; the
underlying real filesystem path stays hidden.

<a id="file-read"></a>
### `read`

```
$file.read   # returns file contents as a string
```

Requires read permission; raises if `.readable` has been ratcheted off.

<a id="file-permissions"></a>
### `readable` / `writable` / `executable`

Boolean properties that report and control whether the file object
can be read, written, or executed.

```
$file.readable           # true if reading is currently allowed
$file.readable = false   # ratchet off; cannot be re-enabled

$file.writable           # current write state
$file.writable = false   # ratchet off

$file.executable         # current execute state
$file.executable = false # ratchet off
```

**Permissions are downgrade-only.** Assigning `false` succeeds;
assigning `true` after a property has been set to `false` is an
error. Once a permission is gone, it's gone for that object's
lifetime. A developer who hands a downgraded file to less-trusted
code can be certain the recipient cannot re-elevate it.

File objects inherit their initial permissions from the jail they
come from — a file pulled out of a read-only jail starts read-only.
The ratchet can take permissions away from there, but a file from a
read-only jail can never gain write through any API.

Permission-gated operations (`read`, `size`, `sha256`, `write`,
`append`, `delete`, `execute`) raise when the relevant permission has
been ratcheted off. Metadata operations (`name`, `path`, `exists?`)
keep working regardless — useful for logging or inspecting a
downgraded reference.

<a id="file-sha256"></a>
### `sha256`

```
$file.sha256   # SHA-256 hex digest of contents
```

Requires read permission.

<a id="file-size"></a>
### `size`

```
$file.size   # size in bytes
```

Requires read permission.

<a id="file-write"></a>
### `write`

```
$file.write($data)   # overwrites the file with $data
```

Requires write permission; raises if `.writable` has been ratcheted off.

---

<a id="directory-objects"></a>
## Directory Objects

~~~json
{"vibecode": {
	"section": "directory_objects",
	"operations": ["children", "create", "delete", "dirs", "exists?",
		"files", "name", "path"],
	"subscript": "$dir['name'] returns file or directory object based_on_what_exists",
	"lazy": "object_created_without_hitting_filesystem_failure_on_actual_operation",
	"chaining": "$jail.dir('a').dir('b')['file.txt'].read"
}}
~~~

A directory object holds its path relative to the jail root.

```
$dir = $jail.dir('docs/narnia')
```

<a id="dir-children"></a>
### `children`

```
$dir.children   # all entries — files and directories
```

Returns an array of file and directory objects for everything
directly under `$dir`.

<a id="dir-create"></a>
### `create`

```
$dir.create   # creates the directory
```

Creates the directory at `$dir.path`. Requires write permission on
the jail.

<a id="dir-delete"></a>
### `delete`

```
$dir.delete   # deletes the directory
```

Removes the directory. Requires write permission on the jail.

<a id="dir-dirs"></a>
### `dirs`

```
$dir.dirs   # directory objects only
```

Returns an array of directory objects for the subdirectories directly
under `$dir`. Skips regular files.

<a id="dir-exists"></a>
### `exists?`

```
$dir.exists?   # returns true/false
```

Metadata-only.

<a id="dir-files"></a>
### `files`

```
$dir.files   # file objects only
```

Returns an array of file objects for the regular files directly
under `$dir`. Skips subdirectories.

<a id="dir-name"></a>
### `name`

```
$dir.name   # directory name only, no path
```

Metadata-only.

<a id="dir-path"></a>
### `path`

```
$dir.path   # full path from the jail root
```

Metadata-only. The path is relative to the jail root; the underlying
real filesystem path stays hidden.

<a id="dir-subscript"></a>
### Subscript navigation

```
$dir['caspian.txt']   # returns a file object
$dir['subdir']        # returns a directory object
```

`[]` returns the appropriate type based on what exists at that path.
It is **lazy** — the object is created without hitting the
filesystem; failure occurs on the actual operation.

Directories can be chained:

```
$text = $jail.dir('docs').dir('narnia')['caspian.txt'].read
```

---

<a id="the-directory-jail"></a>
## The Directory Jail

~~~json
{"vibecode": {
	"section": "the_directory_jail",
	"concept": "directory_scoped_handle_injected_by_host",
	"real_path": "never_exposed_to_charlie_code",
	"access": "%engine['name']",
	"subscript_sugar": "$jail['path'] == $jail.file('path')",
	"jail_is_directory": true,
	"shorthand": "often_referred_to_just_as_a_jail_after_first_use"
}}
~~~

A directory jail is itself a directory object rooted at the injected path.
All operations are relative to that root. After first use in a given
context, "jail" alone is the conventional shorthand.

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

<a id="jail-permissions"></a>
### Permissions

~~~json
{"vibecode": {
	"section": "jail_permissions",
	"permissions": ["read", "write", "execute"],
	"execute_default": false,
	"set_by": "host_at_injection_time",
	"violation": "permission_error_regardless_of_disk_state"
}}
~~~

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

<a id="deriving-restricted-jails"></a>
### Deriving Restricted Jails

~~~json
{"vibecode": {
	"section": "deriving_restricted_jails",
	"method": ".jail(perms)",
	"available_on": ["jails", "directory_objects", "file_objects"],
	"produces": "new_jail_with_reduced_permissions",
	"permissions_bounded_by_source": true,
	"use_case": "pass_capability_to_callee_without_giving_them_original_object"
}}
~~~

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

<a id="why-this-exists"></a>
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

<a id="relationship-to-the-property-ratchet"></a>
### Relationship to the Property Ratchet

The property ratchet (`$file.readable = false`) mutates the existing
object permanently. The jail derivation (`$file.jail('r')`) creates a
new object with reduced permissions, leaving the original untouched.

Use the ratchet when the caller wants to permanently restrict their own
file's powers (defensive coding). Use jail derivation when handing
something to other code that should only see a restricted view.

---

<a id="scoped-permission-restriction"></a>
## Scoped permission restriction

~~~json
{"vibecode": {
	"section": "scoped_permission_restriction",
	"method": ".readonly",
	"available_on": ["files", "directories", "jails"],
	"scope": "dynamic — applies for the synchronous duration of the block",
	"no_rebind": "block sees the same reference; no parameter binding",
	"interaction_with_ratchet": "compatible; ratchet is permanent, this is per-block",
	"interaction_with_derive": ".jail() calls inside the block are bounded by the active restriction",
	"variants_deferred": [".readwrite", ".writable", ".executable"]
}}
~~~

`.readonly do ... end` restricts the object to read-only access for
the duration of the block. Inside, any write, delete, or execute
attempt through the same reference raises a permission error;
outside the block, the object's permissions are unchanged.

```charlie
$file.readonly do
    $file.read         # OK
    $file.write('x')   # raises puck.uno/error/permission
end

$file.write('x')       # works — the restriction was block-scoped
```

Available on files, directory objects, and jails. The block uses the
same reference — no parameter binding — so existing code paths that
already say `$file` (or `$dir`, `$jail`) can be wrapped without
changes.

**Versus the property ratchet.** `$file.writable = false` mutates
the object permanently. `.readonly do` is the nondestructive form
for "this section of code should not write."

**Versus `.jail('r')`.** `.jail('r')` derives a new object with
reduced permissions, introducing a new name. `.readonly do` keeps
the same name in scope — useful when the block calls existing
code that already references the object by name.

**Bounded by existing restrictions.** If a permission is already
off (ratcheted or inherited from a read-only jail), `.readonly do`
is harmless — it can't grant anything. A `.jail()` derivation
inside the block respects the active restriction: requesting more
than read either fails or silently caps at read, per the existing
`.jail()` rule.

**Variants** (deferred until use cases appear): `.readwrite do`,
`.writable do`, `.executable do` — same shape, different permission
subsets.

---

<a id="authorizing-untrusted-paths"></a>
## Path strings from other roles

~~~json
{"vibecode": {
	"section": "path_strings_from_other_roles",
	"method": "$dir.use_path",
	"returns": "file_or_directory_entry_at_resolved_path",
	"accepts": "strings_from_any_role",
	"framing": "explicit_cross_role_authorization_at_the_filesystem_boundary",
	"normalization": "automatic_inside_use_path",
	"unsafe_path_behavior": "yields_non_existent_entry",
	"see_also": "roles.md_filesystem_directory_jails_and_cross_role_trust"
}}
~~~

A directory jail has its own role — engine-injected jails are owned by
the engine, derived subjails are owned by their deriver (see
[roles.md § Filesystem: directory jails](../roles.md#filesystem-directory-jails)).
Strings used as paths also have roles: a literal in your code carries
the role of the code that wrote it, while strings from STDIN, env,
command-line args, HTTP request bodies, etc. each carry their
faucet's role (see [roles.md § Faucets](../roles.md#faucets)).

Two ways to obtain a file or directory entry from a directory:

```charlie
# Literal string — carries the caller's own role.
$file = $dir['readme.txt']

# Any string, from any role — explicit cross-role authorization.
$file = $dir.use_path($string)
```

`use_path` is the **per-call authorization gesture** for using a
string from another role as a path against this directory. It is
analogous in spirit to `%chain.isolate` for role transitions, but
narrowly scoped: one filesystem lookup, one call site, one
explicit decision.

`$dir.use_path` returns the same kind of entry `$dir[]` returns — a
file object or directory object, depending on what exists at the
resolved path. Lazy in the usual way: the entry is returned even
for non-existent paths and operations fail when actually attempted;
use `$entry.exists?` to check first. Unsafe paths (illegal
characters, escape attempts) yield a non-existent entry
indistinguishable from a missing file, so the caller's `.exists?`
check covers both cases without special-handling.

`use_path` is a superset of `[]`: it works for any string regardless
of role. The `[]` form is a shortcut for the common case where the
role match is trivial (literal in your own code). A developer who
prefers a single API can always write `$dir.use_path('readme.txt')`;
the `[]` form just trims a few keystrokes.

**`use_path` normalizes automatically.** Filesystem-side normalization
(`//` collapse, `.` and `..` resolution or rejection, control-character
and null-byte rejection, etc.) happens inside `use_path` before
resolution. Callers don't normalize beforehand. (URL decoding,
query-string parsing, and other non-FS concerns are upstream — by the
time you call `use_path`, the string is just a path.)

<a id="rules"></a>
### Rules

- **Explicit cross-role authorization.** Strings from another role
  only reach the filesystem through `use_path` — never silently.
  The call site is conspicuous; a reviewer can grep for `use_path`
  and see every authorization point.
- **Tied to one directory.** `use_path` is a method on a directory;
  the returned entry is bounded to that directory's jail. There is
  no cross-directory authorization — to use a string against a
  different directory, call `use_path` on that one.
- **Authorization is per-call, not per-string.** The `use_path` call
  itself is the positive declaration of intent. The framework
  provides the boundary (the directory's root and the
  normalization); the developer provides the intent at the moment
  of use. (No Perl-style untaint-via-regex; no flag set on the
  string that persists.)
- **The returned entry is a normal entry.** Once obtained, the file
  or directory object behaves identically to one obtained from a
  literal path. It can be stored, passed, returned. The
  authorization is a one-time gate at the call site, not a property
  of the resulting object. The directory's jail boundary is
  structural; the entry can't escape it regardless of how it's used
  later.

The exact rules for which strings need `use_path` — i.e., which
role-to-role transitions count as "crossing" — depend on the
cross-role trust mechanics still being settled. See
[roles.md § Cross-Role Trust](../roles.md#cross-role-trust) and
its [open questions](../roles.md#open-questions). What is stable:
literals in the caller's own code don't need `use_path`; strings
from external faucets do.

---

<a id="iteration"></a>
## Iteration

~~~json
{"vibecode": {
	"section": "iteration",
	"iterables": ["children", "files", "dirs"],
	"pattern": "$dir.X.each do($item) end"
}}
~~~

```
$dir.children.each do($child)
    puts $child.name
end

$dir.files.each do($file)
    puts $file.path
end

$dir.dirs.each do($dir)
    puts $dir.name
end
```

---

<a id="notes"></a>
## Notes

~~~json
{"vibecode": {
	"section": "notes",
	"path_restriction": "relative_to_jail_root_only",
	"rejected": ["absolute_paths", "dotdot_traversal"],
	"api_status": "basics_covered_more_may_be_added"
}}
~~~

- All paths are relative to the jail root. Absolute paths and `..` traversal are rejected
  by the runtime.
- This API covers the basics. Additional features may be added later.
