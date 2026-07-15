# Grants

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_grants",
	"role": "spec for the two grant mechanisms on dir / file / dirjail objects. Nanny methods (methods that mutate process-global or system-external state, like .cd() and .execute) refuse non-user callers by default. Grants are how the user explicitly authorizes a callee to invoke those methods on a specific handle. Two entry points: .grant(cd:true, exec:true) for grants without narrowing visibility, .dirjail(grant: ['cd', 'exec']) for grants with narrowing. Both produce grant-carrying handles subject to a subset-only downstream invariant, an immutable-per-object rule, and a common introspection surface. Grants on a dirjail propagate to files reached via indexing so 'exec' is useful on a dirjail.",
	"status": "spec — API surface (.grant, .dirjail(grant:), .permissions, .can?, subset-only, file-inheritance) settled; several details still TBD — exception class for nanny-refuse, snapshot serialization behavior, role-delegation composition; both landing post-V1 per the V1 walking-skeleton scope",
	"audience": "Caspian developers writing code that hands dir / file handles to callees running under a different role; engine implementers building the grant mechanism; security reviewers auditing authorization chains"
}}
~~~

The **nanny methods** on Caspian handles — methods that mutate process-global state (`.cd()`) or system-external state (`.execute`) — refuse non-user callers by default, breaking the general holding-is-access rule for this small category. **Grants** are how the user explicitly authorizes a callee to invoke a specific nanny method on a specific handle.

The design doctrine: nanny methods aren't blocked forever for non-user callers; they're blocked by default, and grants are the mechanism to explicitly authorize otherwise. Explicitness at the grant site.

## When to use each mechanism

Two methods produce grant-carrying handles:

| Situation | Method |
|---|---|
| Narrow method-set only, keep full visibility | `.grant(cd:true, exec:true)` |
| Narrow method-set AND visibility (jail + grant) | `.dirjail(grant: ['cd', 'exec'])` |
| Narrow visibility only (no grant) | `.dirjail()` or `.dirjail(readonly:true)` |
| Neither (raw handle, no restrictions) | pass the raw `$dir` |

Neither method replaces the other. `.grant()` hands off an unjailed dir with limited nanny-method access. `.dirjail(grant: [...])` hands off a jailed view that also carries specific grants. Both produce handles subject to the same rules below.

## `.grant(...)`

Per-permission kwargs. Absent kwarg = not granted.

~~~caspian
$granted = $dir.grant(cd:true, exec:true)
&callee $granted
~~~

Inside `&callee`, when the callee (running under a non-user role) calls `$granted.cd()`, the engine checks the handle's grants — `cd:true` is present → call proceeds. `.write(...)` is an ordinary dir method that works regardless of grants. A nanny method NOT granted (say `.execute` on a handle that granted `cd:true` only) raises as if the handle weren't granted at all.

**Same base object.** `$granted` proxies through to `$dir` for everything except nanny-method permission checks — same underlying inode/path, same filesystem contents, same reads/writes. It's a permission-annotated view, not a copy. Visibility is unchanged (no jail).

**Immutable.** `$granted` is a distinct object from `$dir`. Aliasing `$dir` elsewhere does not confer the grant; the grant lives on the specific handle returned by `.grant(...)`.

Block form:

~~~caspian
$dir.grant(cd:true, exec:true) do ($granted)
	&callee $granted
end
# $granted no longer valid after block exit
~~~

`.grant()` is available on both **dir objects** and **file objects**. On files, the primary grantable method is `'exec'` (a file with `'exec'` granted can be executed by a non-user holder). Grant kwargs that don't apply to the receiver type (e.g., `cd:true` on a file, where `.cd()` doesn't exist) are legal but no-ops — the resulting handle simply doesn't have anything to authorize.

## `.dirjail(grant: [...])`

The existing `.dirjail(...)` gains a `grant:` kwarg — a list of strings naming the granted nanny methods.

~~~caspian
$jail = $dir.dirjail(grant: ['cd', 'exec'])
&callee $jail
~~~

The dirjail narrows what the callee can see (rooted at `$dir`; can't escape) AND grants the specified nanny methods on operations reachable through it. Composes with the existing `readonly:` kwarg — `.dirjail(readonly:true, grant: ['exec'])` produces a read-only jail with `'exec'` grant.

**File-inheritance.** Files reached through a granted dirjail (via `[path]` indexing) inherit the applicable grants:

~~~caspian
$jail = %fs.root['project/build'].dirjail(grant: ['exec'])
# callee holds $jail
$tar_bin = $jail['tar']    # file object
$tar_bin.execute            # works because 'exec' is granted on the dirjail
~~~

Without this rule, `'exec'` on a dirjail would be dead weight — `.execute` on a dir itself is the bare-name-search form on `%fs`, while executing a specific binary needs a file handle. The rule threads the grant through the natural path (dirjail → file via indexing) so `'exec'` behaves as expected.

Block form:

~~~caspian
$dir.dirjail(grant: ['cd', 'exec']) do ($jail)
	&callee $jail
end
~~~

## Introspection

Both mechanisms produce handles with the same introspection surface:

~~~caspian
$granted.permissions   # => ['cd', 'exec']
$granted.can?('cd')     # => true
$granted.can?('umask')  # => false
~~~

`.permissions` returns the granted set as a list of strings regardless of which API produced the handle. `.can?('name')` is the boolean predicate. Callee code can introspect what it's been given before attempting anything expensive.

## Subset-only downstream

Both mechanisms enforce the same invariant: a callee holding a granted handle can create further-narrowed handles from it, but only with a subset of what it already holds. Cannot elevate.

~~~caspian
# callee code, holding $granted with cd + exec
$narrower = $granted.grant(cd:true)          # OK — subset
&sub_callee $narrower

$narrower = $granted.grant(umask:true)       # RAISES — not in $granted's set

$sub_jail = $granted.dirjail(grant: ['cd'])   # OK — subset, and adds a jail
$sub_jail = $granted.dirjail(grant: ['umask']) # RAISES — same rule
~~~

The user (top of stack) creates the initial grant with whatever permissions they want; downstream code can narrow, never widen. This makes the chain of authority auditable — a leaf method's permission set is guaranteed to be a subset of every ancestor's, all the way back to the user's initial grant.

## Reaching dirs through `%fs`

`%fs` is a namespace, not a dir. Use `%fs.root` to get the actual root dir handle, then narrow to a subdir before granting — most callees want a scoped view rather than root-level authority.

~~~caspian
# Scope to a specific subdir with a grant (the common handoff shape)
$build_jail = %fs.root['project/build'].dirjail(grant: ['cd', 'exec'])
&build_script $build_jail

# Or grant without narrowing, for a scoped dir
$build_dir = %fs.root['project/build']
$granted = $build_dir.grant(cd:true, exec:true)
&build_script $granted
~~~

`%fs.root.grant(cd:true)` and `%fs.root.dirjail(grant: ['cd'])` are legal but usually wrong — you're handing out a permission on the entire filesystem tree. Reserve for the narrow cases where the callee really does need root-level authority.

## Not the same as role-level grants

The grants spec'd here are **per-object**: the user hands a specific dir or file to a specific callee, and this callee gets `.cd()` / `.execute` on this specific handle. Different scope than the sort of role-scoped grants where a whole role would receive an ambient capability. Different machinery too — should any role-scoped grant mechanism ever land in Caspian, it'll be spec'd on its own terms; the per-object grants here don't extend into it.

## Testing

- **`.grant(cd:true)` returns a distinct object** — `$dir.grant(cd:true).object.id != $dir.object.id`.
- **Aliasing the receiver does not confer the grant** — after `$granted = $dir.grant(cd:true)`, calling `$dir.cd()` from a non-user role still raises; only `$granted.cd()` succeeds.
- **`.permissions` returns the granted set** — `$dir.grant(cd:true, exec:true).permissions` equals `['cd', 'exec']` (order unspecified; treated as a set).
- **`.can?('name')` returns true for granted methods** — `$dir.grant(cd:true).can?('cd')` is `true`.
- **`.can?('name')` returns false for ungranted methods** — `$dir.grant(cd:true).can?('exec')` is `false`.
- **`.can?('name')` on unknown permission returns false** — `$dir.grant(cd:true).can?(:nonexistent)` is `false`, not a raise.
- **Non-user calling ungranted nanny method raises** — non-user role invoking `.cd()` on a plain (non-granted) `$dir` raises.
- **Non-user calling granted nanny method succeeds** — non-user role invoking `.cd()` on `$dir.grant(cd:true)` succeeds.
- **Non-user calling ungranted nanny method on a partially-granted handle raises** — non-user role calling `.execute` on `$dir.grant(cd:true)` (no `exec:true`) raises.
- **Subset-narrowing succeeds** — `$granted.grant(cd:true)` where `$granted` has `cd:true, exec:true` produces a handle with `['cd']`.
- **Elevation raises** — `$granted.grant(umask:true)` where `$granted` doesn't include `'umask'` raises.
- **`.dirjail(grant: ['cd'])` returns a dirjail with the grant** — the resulting handle both jails visibility and carries `['cd']` in `.permissions`.
- **File reached through granted dirjail inherits the grant** — a file object obtained via `$jail['tar']` on a `$jail` with `grant: ['exec']` has `'exec'` in its `.permissions`, and `.execute` succeeds from non-user roles.
- **Grant + readonly compose on dirjail** — `.dirjail(readonly:true, grant:['exec'])` produces a read-only jail whose `'exec'` grant is honored.
- **Block form disposes the handle at block exit** — the `$granted` bound in `.grant(...) do ($granted) ... end` is no longer usable after the block returns.
- **File-object `.grant(exec:true)` grants execution** — `$file.grant(exec:true).execute` succeeds from a non-user role that holds the granted file.
- **`.grant()` with a non-applicable kwarg is a no-op** — `$file.grant(cd:true)` on a file (which has no `.cd()`) is legal; the resulting handle simply has nothing to authorize.

## Related

- [dirs § .cd()](https://puck.uno/documentation/requirements/caspian/filesystem/dirs/#cd) — one of the current nanny methods this spec grants.
- [linux-support § Executing from a directory](https://puck.uno/documentation/requirements/caspian/linux-support/#executing-from-a-directory) — `.execute`, the other current nanny method.
- [%fs](https://puck.uno/documentation/requirements/caspian/global-methods/fs) — where `.dirjail(...)` (which grants extend) is spec'd.
- [concepts § Security](https://puck.uno/documentation/requirements/caspian/concepts#security) — the holding-is-access rule that grants slot into.
