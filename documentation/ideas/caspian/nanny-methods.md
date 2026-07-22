# Nanny methods on held objects

<span class="tag">nanny-methods</span>

~~~vibecode
{"vibecode": {
	"doc": "ideas_nanny_methods",
	"role": "design analysis for a Caspian pattern that's emerging: certain methods on user-role objects that a non-user holder is refused from calling, despite the general holding-is-access rule. Currently two known instances (.execute, .cd()); the shape is that the method reaches beyond the handle's scope to mutate process-global or system-external state. Miko has explicitly called this nanny code — accepted as such, not going away, needs a general treatment rather than accreting one-off carve-outs. This doc catalogs the pattern and enumerates likely future instances. The grant mechanism designed here (.grant(...) and .dirjail(grant:)) has been promoted to authoritative spec at requirements/caspian/filesystem/dirs/grants — this page keeps the design analysis, that page owns the API.",
	"status": "design analysis — nanny pattern settled; grant mechanism promoted to requirements/caspian/filesystem/dirs/grants",
	"audience": "Miko; anyone reasoning about Caspian's holding-is-access rule and where it bends"
}}
~~~

## The tension

Caspian's general rule for object access is **holding is access**: if a non-user role holds a reference to an object, it can call any of the object's methods. Owners narrow what callees can do by handing over jail-wrapper objects (a `readonly: true` dirjail instead of a full dir, etc.), not by the engine second-guessing dispatches.

But two known methods break this rule:

- **`.execute`** on file and dir objects — spawns a subprocess with the user's OS privileges. See [linux-support](https://puck.uno/documentation/requirements/caspian/linux-support/#executing-from-a-directory).
- **`.cd()`** on dir objects — mutates the process's current working directory (in both its permanent and block-scoped forms). See [dirs § .cd()](https://puck.uno/documentation/requirements/caspian/filesystem/dirs/#cd).

For all three, the engine refuses the call from non-user roles — even when the callee legitimately holds the object.

This IS nanny code. Miko's stated position: nanny hasn't left the house on this class of methods, and the pattern will grow rather than shrink. Rather than accrete one-off carve-outs, define a coherent pattern.

## What unifies the nanny methods

Look at what each mutates:

- `.execute` spawns a subprocess. The subprocess inherits the user's OS privileges — the process's PID, its filesystem visibility, its network access, its ambient capabilities. That's system-external state, way beyond the handle.
- `.cd()` changes the process's cwd (permanently or for the duration of a block). Cwd is process-global — every subsequent relative-path resolution in the process (in any frame) sees the new cwd.

Both step outside the scope the handle represents:

- The **handle's scope** is what holding-is-access is designed for — the file's bytes, the dir's contents. Manipulating those affects only what the handle points at.
- **Beyond the handle** is process-global state (cwd, umask, signal handlers, rlimit) or system-external state (subprocesses, network sockets, hardware). Manipulating those affects the whole process, or the world outside the process, in ways the handle's identity doesn't reflect.

The rule that emerges: **methods that mutate process-global or system-external state require the process-owning role; holding-is-access covers the rest.**

Under this framing, the nanny is defensible on principle rather than looking like arbitrary caselaw. New nanny methods that arrive later inherit the rule automatically.

## Likely future instances

Once the framing is clear, more Caspian surfaces predictably need the same treatment:

- **`umask` mutations** — process-global.
- **Process limits (`setrlimit`)** — process-global.
- **Signal handler installation** — process-global.
- **`chroot`, `prctl`, capability-set changes** — system-external.
- **`nice` / scheduling-policy changes** — process-global.
- **Environment-variable mutation** — process-global (all frames see it).
- **Network interfaces, raw sockets, packet capture** — system-external.

Most probably don't ship in V1 — but when they do, they should refuse non-user callers by the same rule that guards `.cd()` and `.execute`.

Read-side observers of the same state (`%fs.cwd` getter, reading `umask`, listing env vars) don't need the nanny treatment; only mutations do.

## Grant mechanism — promoted to spec

The design of `.grant(...)` and `.dirjail(grant: [...])` was drafted here and has been promoted to the authoritative spec at [requirements/caspian/filesystem/dirs/grants](https://puck.uno/documentation/requirements/caspian/filesystem/dirs/grants). That page owns the API, the subset-only invariant, the file-inheritance rule, and the introspection surface.

This ideas doc keeps the surrounding design analysis (above): the nanny pattern itself, what unifies the nanny methods, and the catalog of likely future instances. Both remain in scope for design-thinking; the grant spec is what implementation follows.

## Not the same thing as role delegation

Related but distinct from:

- [role-delegation](role-delegation) — one role transferring some of its authority to code running in another role. That's a role-level thing.
- [grantable-permissions-beyond-capabilities](grantable-permissions-beyond-capabilities) — `%chain.role.grant` handing capabilities to a role. Also role-level.

The nanny-methods grant is **per-object**: the user hands a specific dir to a specific callee, and this callee gets `.cd()` on this dir. Different scope than role-level grants. May share design vocabulary with role-delegation and grant-permissions; probably not the same machinery.

## Related

- [concepts § Security](https://puck.uno/documentation/requirements/caspian/concepts#security) — where holding-is-access is stated.
- [concepts § No nanny code](https://puck.uno/documentation/requirements/caspian/concepts#no-nanny-code) — the general anti-nanny principle that this class of methods deliberately breaks.
- [dirs § .cd()](https://puck.uno/documentation/requirements/caspian/filesystem/dirs/#cd) — one of the two current nanny methods.
- [linux-support § Executing from a directory](https://puck.uno/documentation/requirements/caspian/linux-support/#executing-from-a-directory) — the other current nanny method.
- [role-delegation](role-delegation), [grantable-permissions-beyond-capabilities](grantable-permissions-beyond-capabilities) — role-scoped grant mechanisms; related design vocabulary, not the same thing.
