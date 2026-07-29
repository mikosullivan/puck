# Global methods
<!--index: 7 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_methods_root",
	"role": "spec for how Caspian's global methods (%X-prefixed identifiers) work. Two flavors: capability objects (%import, %stdout, %fs, %net, etc. — anything the program uses to reach a host resource) that inherit from core:capability and share a uniform surface for presence check, grant, revoke, and ungranted-access errors; and context objects (%call, %self, %role, %engine) that are specific-purpose per-frame surfaces. Rules on the capability-object surface: truthy iff granted; %X.grant/.revoke are block-scoped and single-boundary by default; ungranted access returns a specialized null whose method calls raise with an informative message. Formal spec for the core:capability class is pending; catalog of individual capabilities is pending relocation from the retired chain/methods/ directory. Bareword commands (documentation, vibecode, puts, print, field, method, etc.) are NOT globals.",
	"audience": "Caspian programmers learning the surface; documentation authors relocating individual capability specs from chain/methods/; engine implementers building the runtime"
}}
~~~

Caspian's globals are the `%X`-prefixed identifiers reachable from any Caspian code without an import. Two flavors, distinguished by what they do:

- **Capability objects** — the program's gateway to host resources. `%import`, `%stdout`, `%stderr`, `%stdin`, `%fs`, `%net`, `%tmp`, `%timer`, `%encryption`, and similar. All inherit from `core:capability` (spec pending) and share a common surface: presence check, grant, revoke, and informative errors when ungranted. Documented uniformly below.
- **Context objects** — per-frame surfaces that describe the current execution. `%call` (the current call), `%self` (the current instance inside a method), `%role` (the current frame's role), `%engine` (the host-resource gateway, user-role only). Each is its own specific-purpose thing; documented per-object.

Bareword commands (`documentation`, `vibecode`, `puts`, `print`, `field`, `method`, etc.) are NOT globals — they're a separate parser category (bwcs). Downloadable core objects (`%('core:now')`, `%('core:random')`) are not globals either — they're plain values reached through `%import`.

## Capability objects

Every capability object is an instance of `core:capability` (spec pending). All capability objects share the following surface, provided by the class:

### Presence check via truthiness

Reading a capability returns the capability object if granted in the current frame, or a specialized null if not:

~~~caspian
if %stdout
	%stdout.puts 'hello'
end
~~~

The `if %stdout` idiom is the canonical presence check. No `.granted?` predicate, no `%capabilities.has?(:stdout)` — the capability object is either truthy (present) or falsy (absent). Granted capability objects are ALWAYS truthy; the "capability might legitimately be `null` / `false` / `0` / `""`" case does not exist by invariant of the surface.

### Ungranted access returns a flavored null

When a capability is not granted, reading it returns a **specialized null** that carries context about the capability. Attempting to use that null (method call, field access) raises with an informative message:

~~~caspian
# Under a role that doesn't have %stdout:
%stdout.puts 'hello'
# raises: cannot call .puts on %stdout — capability not granted in this frame.
#          role: library-x
#          fix: caller must grant %stdout across the role boundary,
#               or run this code under a role that has it by default.
~~~

Under Caspian's "everything is an object, including null" model, the specialized null is a real object with the necessary context baked in. The dispatcher's null-receiver handling consults the flavor and reports the actual reason for the absence.

The specialized null still compares equal to plain null (`%stdout == null` is true when ungranted) and still evaluates falsy in `if` context — the truthy-check idiom keeps working.

### Unknown globals raise

A reference to a name that isn't a registered global raises:

~~~caspian
if %stdaut  # typo
end
# raises: unknown global %stdaut
~~~

The engine holds a fixed registry of known global names. Known-but-not-granted returns the flavored null (checkable via `if`). Unknown-name raises, so typos are caught at first use instead of silently taking the wrong branch. Fail-loudly-early — the two cases are semantically different and are treated as such.

### Grant and revoke

Grants and revokes are methods on the capability object itself:

~~~caspian
%stdout.grant do
	# %stdout is available across the immediate role boundary
	&some_library_function
end
# outside the block, the grant is gone

%stdout.grant(global: true) do
	# %stdout is available across every role boundary in the whole stack
	&some_library_that_calls_other_libraries
end

%stdout.revoke do
	# %stdout is withheld from anything called from inside this block
	&some_untrusted_thing
end
~~~

Rules:

- **Block-scoped.** The grant or revoke is active for the duration of the block and gone the moment the block exits. There is no persistent-grant form. Exception-safe: if the block raises, the grant/revoke reverts.
- **Single boundary by default.** A plain `%X.grant do ... end` hands the capability across the first role boundary the block crosses — the immediate callee gets it. If that callee then calls another library (further role boundary), the further library does NOT get the grant unless the intermediate code re-grants inside its own frame.
- **`global: true` for whole-stack.** `%X.grant(global: true) do ... end` propagates the grant across every role boundary in the call chain inside the block. Explicit opt-in to the more permissive form; the default (single boundary) is safer.
- **Same shape for `.revoke`.** Withholds the capability from callees; supports `global: true` for whole-stack withholding.
- **Grant on an ungranted capability raises.** You can't hand down what you don't hold. If `%stdout` is a flavored null in the current frame, calling `.grant` on it raises with the same informative message as calling any other method on that null.
- **Nested grants stack additively.** `%stdout.grant do %stderr.grant do ... end end` — inside the inner block, both capabilities are granted; both revert when their blocks exit.

### Two-layer grant model

A capability is available to code only if BOTH:

1. **The engine granted the capability at startup.** The host (CLI launcher, embedded runtime, custom host) decides per-capability what to provision. If the engine didn't provision `%net`, no amount of `.grant` conjures it — the underlying resource simply isn't there.
2. **The chain has the capability in the current frame.** Once the engine has granted the capability, whether descendant frames see it depends on the capability's default-grant flag and any explicit grants / revokes along the chain.

### Default-grant flag

Each capability declares its cross-role-boundary behavior:

- **Default-granted** — automatically visible in any callee, including callees in a different role. `%import` is default-granted (library loading is a common need); a few others are too. Fall-back model: available unless explicitly revoked.
- **Default-deny** — descendants get the flavored null unless the caller explicitly grants the capability across the boundary. `%stdout`, `%fs`, `%net`, and most other side-effect-carrying capabilities are default-deny. Explicit-only: unavailable unless explicitly granted.

The default-grant flag is a per-capability attribute declared in each capability's spec.

## Context objects

The four context objects are specific-purpose per-frame surfaces; each has its own spec.

### `%call`

The current call object. Owned by the caller's role. Inside any function or closure body, `%call` exposes the caller's role (`%call.role`), early-exit (`%call.return`), and the array of passed blocks as callable values (`%call.blocks`). Yielding is calling — `yield` is a bwc that desugars to `%call.blocks[0].call`. Canonical: [`call/`](call/).

### `%engine`

The host-resource gateway. Reachable only from `user`-role code — every slot on `%engine` is a runtime error from any non-user role. Hosts populate `%engine` with the resources the program is allowed to touch; the user either uses those slots directly or grants them across role boundaries via the corresponding capability object. Canonical: [`engine/`](../engine/).

### `%role`

The current frame's role. Always unconditionally available regardless of what capabilities are granted; unlike capabilities, `%role` is not chain-mediated. Reading `%role` inside any frame returns the role that owns that frame. Canonical: [`roles/`](../roles/#role).

### `%self`

The current object instance inside a method body. Outside a method (free-standing function, closure, top-level code), `%self` is not available. Always written with the `%` sigil — there is no bare `self` shortcut. `%self.object.role` returns the instance's owning role; `%self.object.*` reaches the standard object surface. See [`built-in-classes/object/methods`](../built-in-classes/object/methods/) for the full `.object` surface.

**`%self` is a reference, not an access token.** Calling a method through `%self` from inside the class body reaches every method the class carries, including private methods — see [functions/method § Calling sibling methods](../functions/method#calling-sibling-methods). The engine's private-method check consults [`%call.method_class`](call/#call-method-class) — the class the currently-executing method was defined on — not the reference itself. From inside a sibling method, `%call.method_class` is the same class that carries the private method, so access is allowed. Capturing `%self` and returning it does NOT grant private access to the receiver of the returned reference; access is always checked at dispatch time against the current frame, never against the reference's provenance.

## Testing

- **`%call` reachable in every function body** — reading `%call` inside a bare function, closure, or method returns the call object without any grant.
- **`%role` reachable in every frame** — reading `%role` returns the current frame's role in any frame, regardless of grants or revokes.
- **`%engine` reachable only from user role** — in a user-role frame, `%engine` returns the engine surface; in a non-user role frame, referencing `%engine` (or any slot on it) raises.
- **`%self` reachable inside method body** — a method body reading `%self` returns the receiver.
- **`%self` raises inside bare function body** — `function() %self end` invoked errors.
- **`%self` raises inside closure body with no enclosing method** — `closure() %self end` at top level errors.
- **`%self` reachable inside closure body with enclosing method** — a closure defined inside a method's body reads `%self` as the method's receiver.
- **Capability truthy iff granted** — for any capability `%X`, `if %X ... end` executes the body iff the current frame has `%X` granted; the body is skipped when the capability is a flavored null.
- **Ungranted capability method call raises with informative message** — calling any method on an ungranted `%X` raises with a message that names the capability, the current role, and the fix path.
- **Unknown global raises** — reading `%X` where `X` is not a registered global name raises "unknown global"; distinct from known-but-ungranted (which returns the flavored null).
- **Granted capability is truthy** — the invariant: no granted capability ever evaluates falsy. Granted `%stdout`, `%fs`, etc. are always truthy.
- **`%X.grant do ... end` propagates one boundary** — inside a plain grant block, the immediate cross-role callee has the capability; a further-nested callee (two boundaries down) does not, unless the intermediate frame re-grants.
- **`%X.grant(global: true) do ... end` propagates whole stack** — every cross-role callee inside the block has the capability, arbitrary depth.
- **`%X.grant` reverts on block exit** — after the `do ... end` exits, subsequent code across a role boundary sees the capability with its default-grant status (not the granted state).
- **`%X.grant` reverts on exception** — if the block raises, the grant is still reverted (block-scoped is exception-safe).
- **`%X.revoke do ... end` mirrors `%X.grant`** — withholds the capability from callees inside the block; `global: true` is available.
- **Grant on ungranted capability raises** — `%stdout.grant do ... end` under a role that doesn't have `%stdout` raises immediately (same informative-message pattern as any method call on the flavored null).
- **Nested grants stack** — `%stdout.grant do %stderr.grant do ... end end` — inside the inner block, both are granted; both revert on their respective block exits.
- **Default-granted capability crosses without explicit grant** — for a capability marked default-granted, a callee in a different role sees the capability without the caller explicitly granting.
- **Default-deny capability blocked without explicit grant** — for a capability marked default-deny, a callee in a different role sees the flavored null unless the caller explicitly granted.
- **Engine-startup grant gates presence** — if the host does not install `%X` at startup, no chain-level grant can conjure it; even inside a `%X.grant` block (from a role that HAS %X), the callee only gets the capability if the engine has it at all.
- **Downloadable core objects are not globals** — `%('core:now')` and `%('core:random')` are plain downloads via `%import`, not entries in the globals catalog; they don't participate in the grant/revoke machinery.
