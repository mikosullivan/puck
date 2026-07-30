# Jail and service

~~~vibecode
{"vibecode": {
	"doc": "ideas_jail_and_service",
	"role": "design doc for two related but distinct narrowing wrappers — the ocap-shaped `.jail(...)` (methods run in the caller's role, no authority transfer) and the broker-shaped `.service(...)` (methods run in the owner's role, deliberate authority transfer). Same interface-narrowing surface, opposite dispatch semantics; both useful, one has confused-deputy risk that the author accepts on purpose.",
	"status": "brainstorm — shape settled from design conversation (jail = ocap facet, service = deliberate deputy); syntax, naming, and edge cases still open",
	"context": "started after noticing that Caspian's current `.jail(...)` implementation IS confused-deputy-shaped (methods run as owner's role, so untrusted callers trigger owner-authority work). Two behaviors were being asked of one primitive; the fix is to name them separately."
}}
~~~

Caspian needs two narrowing wrappers with the same interface-narrowing surface and opposite dispatch semantics. Current `.jail(...)` conflates them — the interface is jail-shaped but the dispatch is service-shaped, which is exactly the confused-deputy vulnerability. This doc splits them.

## The two shapes

### Jail — narrow-and-shift

A **jail** wraps an object and exposes only a named subset of its methods. Method calls through the jail dispatch on the underlying object BUT run in the CALLER's role, not the owner's. The caller gets to invoke a restricted set of operations, using their own authority — same authority they'd have if they were doing the work themselves. The jail is a role-boundary as much as an interface-narrowing.

Analogy: a **facet** in E — the wrapper carries no authority beyond what the caller already has; it just makes the interface smaller.

Use it when: user has a private-state-bearing object and wants untrusted code to be able to read specific fields, but doesn't want untrusted code to gain any authority it didn't already have. The jail's methods can only do what the untrusted role could do on its own.

~~~caspian
$widget = Widget.new()
$jail = $widget.obj.jail(:read, :position)
$untrusted_library.render($jail)
# Inside the library:
#   $jail.read runs in $untrusted_library's role
#   any ambient operation inside .read (%fs, %net, etc.) runs at library's auth
#   .read can only touch $widget's public state, not user's ambient anything
~~~

### Service — narrow-and-broker

A **service** wraps an object and exposes only a named subset of its methods. Method calls through the service dispatch on the underlying object AND run in the OWNER's role. Untrusted code can invoke a restricted set of operations, and each operation runs with the owner's full authority. This is a deliberate authority transfer; the owner is saying "yes, please do this on my behalf, with my authority."

Analogy: a **waiter** in a restaurant. The customer orders from a menu (narrowed interface); the waiter takes the order and submits it to the kitchen (owner-authority operation on the customer's behalf). Customer can't enter the kitchen; waiter can.

Use it when: the owner wants untrusted code to be able to request specific operations that require the owner's authority to complete — writing to a log file only the owner can reach, publishing to a queue only the owner has credentials for, saving state to storage only the owner knows how to address.

~~~caspian
$log_writer = LogWriter.new()
$service = $log_writer.obj.service(:log, :warn)
$untrusted_library.attach_logger($service)
# Inside the library:
#   $service.log('hello') runs as the owner (user)
#   %fs.append(...) inside .log runs at user's auth — writes the log
#   The library couldn't do this write on its own; the service is doing it for them
~~~

## The interface layer is the same; only dispatch differs

Both wrappers narrow the same way — a named subset of the underlying object's public methods is exposed; every other method dispatch through the wrapper raises. The DSL for construction is identical up to the keyword:

~~~caspian
$foo.obj.jail(:read, :update)      # narrowed AND role-shifted
$foo.obj.service(:read, :update)   # narrowed, NOT role-shifted
~~~

The wrappers' `.obj.X` surfaces are their own — `.jail`'s and `.service`'s `.obj.isa?` reports their respective classes (`Jail`, `Service`), neither reveals the underlying object, neither has an `.unjail` / `.unservice` / `.prisoner` escape.

## Comparison

| | Jail | Service |
|---|---|---|
| Purpose | Narrow interface without authority transfer | Narrow interface WITH authority transfer |
| Method dispatch role | Caller's role | Owner's role |
| Ambient authority inside methods | Caller's | Owner's |
| Analogy | E-language facet | Waiter / broker |
| Real-world | Sealed record with getters, no privilege | Front desk agent acting on office's behalf |
| Confused-deputy risk | None (no authority transfer) | Yes — author's deliberate choice, must design accordingly |
| Right choice when | The recipient should not gain new authority | The owner is deliberately delegating specific tasks |

## What makes each safe

**A jail is safe because it transfers no authority.** Whatever the caller could do on their own, they can now do via a narrower interface. That's an upper bound, not a lower bound — the interface can be narrower than the caller's authority (some methods might raise inside the jail because the caller lacks authority to make them work), but never wider.

**A service is safe because the owner writes the service methods knowing they'll run with owner authority on behalf of arbitrary callers.** Confused deputy is not something the service accidentally introduces; it's something the service is designed to be, and the design responsibility is on the author. The author must:

- Check that the caller's request is one the owner actually wants performed on their behalf (validation before delegation).
- Refuse requests whose parameters would let the caller cause the owner to do something the caller shouldn't be able to trigger (the classic Hardy pattern — untrusted-supplied filename that the owner has permission for but shouldn't write on the caller's behalf).
- Log or account for actions taken on callers' behalf, since audit-time it may matter that the OWNER did work the caller can't be independently traced to.

A poorly-written service is a confused-deputy vulnerability. Nothing at the language level prevents this because the whole point is to run with owner authority; the author's discipline is where the safety lives.

## Design questions

### Naming

- `.jail(...)` and `.service(...)`?
- `.facet(...)` and `.service(...)` — matches E's terminology?
- `.limit(...)` (jail-like) and `.expose(...)` (service-like)?

The current `.jail(...)` documentation describes service-shaped behavior. If we adopt this split, the safest migration is: rename the current method to `.service(...)` (matching what it actually does), and introduce `.jail(...)` as the new role-shifting variant. That inverts the naming for existing code but matches the confused-deputy critique — code that was calling `.jail(...)` expecting jail semantics was ACTUALLY getting service semantics, and the rename surfaces the discrepancy loudly.

Alternatively: keep `.jail(...)` for the interface-narrowing surface (its current shape) and add `.service(...)` as an explicit "with authority transfer" variant. Then existing code stays as-is; new code opts into the safer form (jail with role shift) via a rename. This is the smaller migration but leaves `.jail(...)` doing confused-deputy things by default.

Third option: keep `.jail(...)` but flip its dispatch semantics to role-shifting (the safer default). Add `.service(...)` as the explicit authority-transfer form. Any existing code that was implicitly using service behavior via `.jail(...)` breaks noisily — every method call raises because the caller's role can't complete the operation. Painful but the failure mode is obvious and the fix (rename `.jail` → `.service` case-by-case) is mechanical.

### Confused-deputy defense for services

If services are the deliberate confused-deputy shape, what primitives help the author write them safely?

- **`%call.role`** — the service method can check who's calling and validate. Already available.
- **`%call.trusted?`** — quick boolean check for "same role or user." Already available; less useful for services since services are BY DEFINITION called across role boundaries.
- **`%call.originating_role`** (proposed elsewhere) — the outermost non-owner role in the call chain. Would let the service check "did this originally come from an untrusted role?" even if the immediate caller is another trusted intermediary.
- **A "safe-args" pattern** — the service accepts only specific value shapes (integers within a range, enums, structured data), never callables or complex objects that could carry hidden authority.

None of these are jail-and-service specific; they're the general confused-deputy toolkit. But a service doc should point at them prominently.

### Can a service wrap a jail (or vice versa)?

Composition question. `$foo.obj.jail(:read).obj.service(:read)` — probably doesn't make sense (the jail's `.read` runs as caller; wrapping in a service tries to make it run as owner-of-jail = user, but the operation still runs against a jail that requires caller-role auth). What does the engine do?

Same question the other way. `$foo.obj.service(:log).obj.jail(:log)` — the jail wraps a service; does the jail's role-shift override the service's role-preservation? Which layer wins?

Cleanest rule: the outermost wrapper decides the role. Inner wrappers just narrow the surface. That's simple but might have odd cases we haven't found yet.

### Does the current `.obj.jail(:name)` example everywhere need to become `.obj.service(:name)`?

Probably yes for most existing spec examples. Most of them are using it as "here's a widget, expose its `.name` and `.label` to a library" — that's service-shaped (untrusted library needs to invoke widget methods that presumably touch widget state; the widget owner is delegating). Sweep needed.

## Examples

### File access

User has a class `LogFile` that internally uses `%fs` to append to a file. User wants an untrusted plugin to be able to log messages, but nothing else.

~~~caspian
class # LogFile
	field :path

	method &init($path)
		@path = $path
	end

	method &append_line($msg)
		%fs[@path].write $msg + "\n", :append
	end

	method &recent_lines($n)
		$content = %fs[@path].read
		# ... parse and return last $n lines
	end

	method &clear()
		%fs[@path].delete
	end
end

$log = LogFile.new('/var/log/plugin.log')
~~~

Three ways to hand this to a plugin — same interface question, three different answers.

**Pass `$log` directly.** Wrong — the plugin gets every method, including `.clear`. All methods run as user (the object's owner), so the plugin can delete the log file whenever it wants. The interface wasn't narrowed at all.

**Wrap in a jail: `$log.obj.jail(:append_line)`.** The interface is right — only `.append_line` is exposed. But jail semantics shift the dispatch role to the CALLER (the untrusted plugin). Inside `.append_line`, the `%fs[@path].write` call needs `%fs`, and the plugin doesn't have `%fs`. Every call raises.

Jail is the WRONG choice here — the operation genuinely needs user's authority to complete. The plugin can't do the write on its own, and that's exactly what the plugin is asking user's help with.

**Wrap in a service: `$log.obj.service(:append_line)`.** The interface is right. Service semantics keep the dispatch role at the OWNER (user). Inside `.append_line`, `%fs[@path].write` uses user's `%fs` and succeeds. The plugin can log; it cannot read past lines and cannot clear the file.

This IS confused-deputy-shaped — the owner is deliberately doing work with owner authority on the plugin's behalf. That's the whole point. User is the waiter; plugin is the customer; the log file is the kitchen. Customer can order a log line but can't get behind the counter.

**Author's responsibility for the service.** By choosing `.service(:append_line)`, the owner accepts that `.append_line` will run with user authority on behalf of arbitrary callers. That means checking:

- Can `$msg` cause something more than a simple append? (A log format that interprets `$msg` as a directive would be the problem.)
- Can the caller cause the file to grow unboundedly, or the disk to fill?
- Does the caller need to be rate-limited?
- Does the append need to be attributed to the caller in the log line itself, so the audit trail records "plugin X wrote this," not just "user wrote this"?

These are decisions the service author makes, deliberately, at authoring time. The jail/service split doesn't answer them — it just makes the framing loud so the questions get asked.

### Database access

User has a database handle produced by their DB library. The handle wraps an internal connection object as a field:

~~~caspian
class # DBHandle
	field :conn

	method &init($conn_str)
		@conn = %db.connect($conn_str)   # engine-issued connection capability
	end

	method &append($table, $row)
		@conn.insert $table, $row
	end

	method &read($table, $key)
		return @conn.select $table, $key
	end

	method &delete($table, $key)
		@conn.delete $table, $key
	end
end

$handle = DBHandle.new('postgres://...')
~~~

User wants a plugin to be able to append rows but do nothing else. Three options.

**Pass `$handle` directly.** Wrong — plugin can call `.read`, `.delete`, or any other method. All run as user (the object's owner) and touch the database with user's full authority.

**Wrap in a jail: `$handle.obj.jail(:append)`.** The interface is narrowed to just `.append`. Under jail semantics, `.append` runs in the plugin's role. Inside `.append`, the call `@conn.insert(...)` dispatches on `@conn`, which is user-owned; per Caspian's normal rule, method calls on `@conn` run in `@conn`'s role (user). The database write succeeds using `@conn`'s intrinsic authority.

Jail is the RIGHT choice here — `.append` uses an internal capability (`@conn`) rather than ambient authority (`%db`, `%fs`, etc.). Caller-role dispatch on `.append` doesn't affect the inner `@conn.insert(...)` call because that call runs in `@conn`'s owner-role. The plugin gets to trigger the operation; no ambient authority is transferred.

**Wrap in a service: `$handle.obj.service(:append)`.** The interface is narrowed; `.append` runs in user's role. Works, but transfers more authority than the operation needs. If `.append` also touches something ambient (an internal `%stdout` log call, a `%net` notification), that ambient use runs at user's authority on the plugin's behalf. Service is the wrong tool for a job the jail can do; you're paying for confused-deputy exposure you don't need.

### Contrast with the file case

The file example needed a service because `LogFile.append_line` used `%fs` DIRECTLY — an ambient global — for its file access. There was no owned capability inside the class doing the work.

The database example works with a jail because `DBHandle.append` uses `@conn` — an owned capability. The class author put the ambient authority into an owned field at construction time, and every method operates through the field, never via a fresh ambient lookup.

That distinction — ambient use inside the method body vs. owned-capability use — is the discriminator. A class written with owned capabilities (accepting authority at construction, storing it in a field, going through the field on every operation) is jail-friendly. A class written with ambient lookups (`%fs`, `%net`, `%stdout` reached fresh in each method body) needs a service to make its methods work from a jail-shifted role.

This is a general principle worth naming: **classes designed for capability-passing are safer to expose narrowly**. If untrusted callers might ever need a subset of the class's surface, wire the authority through owned fields at construction time so a jail can narrow the surface without breaking the operations.

### When each choice fits

The file-access example maps cleanly to the general rule:

- **Use a jail** when the exposed methods can accomplish their work using only what the caller already has authority for. Reads from `%bucket`, method calls on already-passed capabilities, computations on the receiver's own state.
- **Use a service** when the exposed methods genuinely need the owner's authority — access to a file only the owner has, a network connection only the owner can reach, a resource only the owner is authorized to touch. The owner has decided the caller can request the operation but not perform it directly.

If the exposed method doesn't need ambient authority AND the interface narrowing is enough — use a jail. If it does need ambient authority — use a service, and take the confused-deputy discipline seriously.

### Note on engine-issued capabilities

For raw file access (not wrapped in a user class), the cleanest path is an engine-issued attenuated capability — `%fs['/path'].readonly` returns a new engine-issued handle that only supports reads, and the engine enforces the narrowing at the primitive layer. Neither jail nor service is needed for that shape; the handle itself IS the reduced authority. Jail-and-service are for USER-DEFINED CLASSES whose methods use ambient authority internally.

## Related

- [ideas/roles-critique § Confused deputy](https://puck.uno/ideas/roles-critique#confused-deputy-is-the-obvious-hole) — the diagnosis that surfaced this split.
- [ideas/roles-prior-art](https://puck.uno/ideas/roles-prior-art) — E's facet pattern, Newspeak's module wiring, WASI's preopened handles, etc.
- [requirements/built-in-classes/object/methods § .jail(...)](tag:obj-methods) — the current spec for `.jail`, which today conflates the two shapes and will need updating whichever direction the naming decision goes.
