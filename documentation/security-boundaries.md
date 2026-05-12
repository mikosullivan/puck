# Security Boundaries (Historical)

```
vibecode: {
    "section": "overview",
    "status": "superseded",
    "superseded_by": "roles.md",
    "role": "historical record of the security-boundary mechanics under the binary trust/untrust model; superseded by the role-based security model"
}
```

> **This document is superseded by [roles.md](roles.md).** The mechanics
> documented here — `%chain.allow_abort_escalation`,
> `%chain.allow_catch_security_exceptions`, the cannot-catch-your-own
> rule under the binary trust system, etc. — all belong to the
> previous trust model.
>
> Under the role model:
>
> - A security boundary is **any call into code the current role
>   doesn't own** (see [roles.md](roles.md) — Role Transitions).
> - **Alarms are unconditionally fatal.** No unwinding, no
>   `finally`-block hijacking, no chain permissions controlling
>   catchability. The engine takes over directly.
> - **`%chain.allow_abort_escalation` is gone.** Untrusted code can't
>   modify abort behavior because the alarms-are-fatal rule makes the
>   escalation distinction moot.
> - **`%chain.allow_catch_security_exceptions` is gone.** Security
>   alarms can't be caught from KScript code at all.
> - **`%chain.trust` is gone.** Trust is per-role-pair, not a
>   runtime-grantable property of values.
>
> See [roles.md](roles.md) — "Exceptions and Alarms" for the current
> model.
>
> The historical model is preserved below for reference. Most of the
> machinery described here is no longer present in the runtime.

---

## Historical: Trust-Boundary Mechanics

A **security boundary** in KScript was any point where the engine calculated trust.
There were exactly two such places:

1. **Engine initialization** — the host-to-script transition. Always exists.
2. **Every function/closure/method call** — the engine checks trust at every call site,
   not just calls into untrusted code.

Treating every call as a boundary is a deliberate simplification. Per-call checks
collapse into one uniform code path; the heavy work (clearing carrier `%chain`,
applying permission rules, setting up exception machinery) only happens when a trust
transition actually occurs.

`%chain.clear do...end` is treated as a security boundary too. Technically it is a
special form of the per-call boundary (the block runs as a closure call), but it is
useful to think of it as its own boundary in documentation and reasoning.

Pure data access and control flow are not boundaries — `$a.field`, `$arr[0]` (without
an `__index` method), `if $x`, loop bodies, and bare `do...end` blocks not invoked as
closures do not trigger trust calculation.

---

## What Happens at a Boundary

vibecode: {
	"section": "what_happens_at_a_boundary",
	"role": "summarizes the runtime checks performed at every security boundary; behavior depends on trust transition",
	"key_concepts": ["trust_check_every_call", "carrier_chain_clears_on_trust_drop",
		"trust_grants_persist", "capabilities_not_auto_inherited"]
}

At every function call, the engine:

1. Looks up the callee's trust level (intrinsic source plus any `%chain.trust` grants
   in the caller's chain — see [trust.md](trust.md)).
2. Compares the caller's trust to the callee's.
3. Sets up the callee's `%chain` frame, applying boundary rules based on the trust
   transition.

Boundary behavior by transition:

- **Same trust** (trusted → trusted, or untrusted → untrusted): chain inherits as
  normal. No special clearing, no special exception machinery. The boundary still
  exists conceptually (the engine calculated trust), but the call is otherwise
  unremarkable.
- **Trust drop** (trusted → untrusted): carrier parts of `%chain` clear (user,
  request_id, locale). `%chain.allow_abort_escalation` resets to the engine default
  for untrusted code (`false`). `%chain.allow_catch_security_exceptions` resets to
  `false`. Trust grants for specific objects (`%chain.trust $foo`) persist — they
  survive the boundary by design so trusted code can hand vetted objects to
  less-trusted callees.
- **Trust elevation** (untrusted → trusted): the engine restores the callee's
  intrinsic trust. `%chain.allow_abort_escalation` is set to the engine default for
  trusted code (`true`). Capabilities the callee declares as required may be
  automatically granted; capabilities not declared are not auto-inherited.
- **Engine init** (host → script): functionally a trust elevation from "no script"
  to the host's top-level program. Sets up the initial chain, capabilities, and trust
  mapping.

---

## Two Distinct Concepts

vibecode: {
	"section": "two_distinct_concepts",
	"role": "clarifies that abort propagation and security-exception catching follow different default models; abort defaults to catchable, security exceptions default to uncatchable",
	"key_concepts": ["abort_default_catchable", "security_default_uncatchable",
		"different_threat_models", "two_separate_chain_permissions"]
}

KScript distinguishes between two categories of "exceptional" exit conditions, each
with its own propagation model and its own chain permission. They are intentionally
asymmetric because they represent different threat models.

| | Abort | Security exception |
|---|---|---|
| Default catchability by ancestors | **Catchable** by anyone above | **Not catchable** by anyone |
| Engine-controlled chain permission | `%chain.allow_abort_escalation` | `%chain.allow_catch_security_exceptions` |
| Permission's purpose | Escalate to engine (kill process) | Allow a specific frame to catch |
| Engine default | `true` for trusted, `false` for untrusted | `false` for everyone |
| Can be set true by untrusted code? | Yes (bounded by trust scope) | No (raises `privilege_escalation`) |
| Cannot catch your own | Yes | Yes |
| Graceful unwind through frames? | Nested: yes. Escalating: no. | No. |

The reasoning behind the asymmetry:

- **Aborts are ordinary signals that happen to terminate a scope.** Default-catchable
  makes sense because the calling code generally knows how to deal with "the thing
  I called wanted to bail." The only thing that needs explicit permission is the
  much heavier "kill the whole process" action — which is `allow_abort_escalation`.
- **Security exceptions are integrity alarms.** Default-uncatchable makes sense
  because they signal that something has gone wrong with the deployment's integrity
  — silencing them in random library code would defeat the purpose. They have to
  reach the engine for visibility unless the host explicitly authorizes some inner
  layer to handle them.

---

## Abort: `%chain.allow_abort_escalation`

vibecode: {
	"section": "allow_abort_escalation",
	"role": "documents the chain permission that controls whether process.abort produces an escalating or nested abort; covers the trust-scope bounding rule",
	"key_concepts": ["controls_abort_propagation",
		"engine_default_true_trusted_false_untrusted",
		"untrusted_can_set_true_in_own_scope",
		"escalation_bounded_by_trust_scope",
		"cannot_catch_own_abort"]
}

`%chain.allow_abort_escalation` is a boolean permission on `%chain` that controls
whether `%process.abort` produces an escalating abort (which propagates to the engine
and terminates the process) or a nested abort (a normal catchable exception).

### Engine defaults

- **Trusted code**: `%chain.allow_abort_escalation = true`
- **Untrusted code**: `%chain.allow_abort_escalation = false`

The value propagates through chain like other chain content. At a trust drop boundary
the engine resets it to the untrusted default (`false`).

### What `%process.abort` does

```
if %chain.allow_abort_escalation
    # raise kiera.uno/error/abort
    # — escalating abort
    # — uncatchable by user code via ordinary try/catch
    # — does NOT gracefully unwind (no finally blocks, no cleanup)
    # — propagates to the engine, which terminates the OS process
else
    # raise kiera.uno/error/nested_abort
    # — ordinary exception
    # — catchable by ordinary try/catch in any ancestor frame
    # — propagates through frames with normal exception unwinding
    #   (finally blocks fire, chain unwinds gracefully)
end
```

The same `%process.abort` call site produces different exception types depending on
`allow_abort_escalation` at the moment of the call.

### Untrusted code may set it true (within its own trust scope)

Untrusted code is allowed to set `%chain.allow_abort_escalation = true` in its own
chain frame. This is **not** a privilege escalation — the value's effect is bounded
by the trust scope where it was set.

```
function &untrusted_outer
    %chain.allow_abort_escalation = true   # allowed; effect bounded
    &untrusted_inner                        # if inner aborts, it kills outer too
end
```

If `&untrusted_inner` calls `%process.abort`, the abort will be the escalating type
(because `allow_abort_escalation` is true at that frame), and it will propagate up
through `&untrusted_outer`, killing it as well.

But the abort does **not** propagate past the boundary back into trusted code above.
At that boundary the engine demotes the escalating abort to a nested abort, because
the authorization to escalate was set within the untrusted region and does not extend
upward into trusted territory.

The principle: a frame can grant escalation authority within its own trust region,
but cannot reach into a higher-trust caller. The engine enforces this at the
trust-elevation boundary.

### Cannot catch your own

A frame that calls `%process.abort` cannot catch the resulting exception in its own
`try`/`catch`. The exception always propagates at least one frame upward before
becoming eligible to be caught (in the nested case) or escalating to the engine (in
the escalating case). This rule applies uniformly regardless of trust level or
`allow_abort_escalation` value.

---

## Nested Abort

vibecode: {
	"section": "nested_abort",
	"role": "documents the catchable nested-abort exception that ordinary try/catch can intercept; propagates with normal exception unwinding",
	"key_concepts": ["ordinary_catchable_exception",
		"propagates_with_finally_running",
		"chain_unwinds_naturally",
		"uncaught_at_top_is_just_uncaught"]
}

`kiera.uno/error/nested_abort` is the exception type raised when `%process.abort` is
called from a frame where `%chain.allow_abort_escalation` is `false`. It is a normal
exception in every respect:

- Catchable by ordinary `try`/`catch` in any ancestor frame.
- Propagates up through frames using the standard exception unwinding mechanism.
  Each frame's `%chain` modifications evaporate as the frame is popped, identical to
  what happens on normal returns. `finally` blocks fire on the way up.
- If nothing catches the nested abort, it reaches the top of the call stack as an
  ordinary uncaught exception. Standard uncaught-exception behavior applies; there
  is no special-case handling for "nested abort reached the top." The host treats
  it however it treats any other uncaught exception.

The "containment" of a nested abort is not that the exception cannot propagate — it
propagates normally — but that it cannot kill the OS process directly. The worst
case is that nobody catches it and the program exits via the usual uncaught-exception
path, not via a deliberate process abort.

---

## Security Exceptions: `%chain.allow_catch_security_exceptions`

vibecode: {
	"section": "allow_catch_security_exceptions",
	"role": "documents the chain permission that allows a frame to catch security exceptions raised in its callees; default is false for everyone",
	"key_concepts": ["default_false_for_everyone",
		"granted_only_by_engine_explicitly",
		"untrusted_setting_true_raises_privilege_escalation",
		"cannot_catch_own_security_exception",
		"security_exceptions_no_graceful_unwind"]
}

`%chain.allow_catch_security_exceptions` is a boolean permission on `%chain` that
controls whether a frame can catch security exceptions raised in its callees.

### Engine defaults

- **All code, trusted or untrusted**: `%chain.allow_catch_security_exceptions = false`

Security exceptions, by default, do not get caught by any KScript code. They
propagate all the way to the engine, which is the only thing that catches them
without explicit permission.

The engine grants this permission only when the host explicitly configures it,
typically to a specific outer-layer frame that wraps engine execution and acts as
the security responder. It is not part of any KScript program's normal permission
set.

### Untrusted code cannot set it true

Setting `%chain.allow_catch_security_exceptions = true` from a context that does
not have this permission raises `kiera.uno/error/privilege_escalation`. Unlike
`allow_abort_escalation`, this permission's effect is **not** bounded by trust
scope — once a frame catches a security exception, the exception is suppressed
from reaching the engine. So the engine cannot allow untrusted code to grant
itself the ability to silence alarms.

### Security exceptions

Current security exception types:

- `kiera.uno/error/out_of_range` — version cutoff violation. Raised when a library
  lookup returns nothing dated on or before `%chain.cutoff`. See
  [versioning.md](versioning.md).
- `kiera.uno/error/privilege_escalation` — explicit upgrade attempt on a chain
  permission whose effect is not bounded to the caller's own trust scope. See
  "Privilege Escalation" below.

Future security exception types are expected to follow the same model. All of them
share the same propagation rules described in the rest of this section.

### Behavior when raised

When a security exception is raised:

1. The exception escapes the raising frame immediately. The raising frame **cannot
   catch its own security exception**, even if it holds
   `allow_catch_security_exceptions = true`.
2. The exception propagates up through frames **without graceful unwinding**:
   - No `finally` blocks fire.
   - No cleanup hooks run.
   - Chain frame contents are discarded, not popped through normal exception
     mechanics.
3. At each frame above the throw site, the engine checks
   `%chain.allow_catch_security_exceptions`. If `true`, that frame may catch the
   exception via ordinary `try`/`catch`. If `false`, the exception passes through
   unobserved.
4. If no frame catches, the exception reaches the engine. The engine handles it
   per host configuration (typically: log to audit channel, terminate, or alert).

The forensic payload (the operation that triggered the exception, the chain state,
the call stack, signer/source identifiers) is preserved through the propagation and
is what the catcher sees.

### Why no graceful unwind

Security exceptions are integrity alarms, not control flow. Allowing intermediate
frames to interpose cleanup logic would let a malicious or buggy library mask the
alarm, log to attacker-controlled destinations, mutate state to obscure forensics,
or otherwise interfere with the security responder's view of what happened.

The trade-off: resources may leak, locks may not be released, pending I/O may not
be flushed. This is acceptable because the engine catching the exception is going
to take action that makes the leak moot. It is the SIGKILL of the KScript exception
model — no opportunity for code to interpose itself between the alarm and the
responder.

The same rule applies to escalating aborts (`kiera.uno/error/abort`): they are also
uncatchable by user code and represent a deliberate kill signal, so they likewise
do not gracefully unwind. The two share the rule "if user code cannot catch it,
user cleanup code does not run either."

---

## Privilege Escalation

vibecode: {
	"section": "privilege_escalation",
	"role": "documents the loud-failure rule when code attempts to grant itself a chain permission whose effect is not bounded to its own trust scope",
	"key_concepts": ["scope_bounded_permissions_are_freely_settable",
		"cross_scope_permissions_require_authority_from_above",
		"loud_failure_not_silent_no_op",
		"raises_kiera_uno_error_privilege_escalation"]
}

The privilege escalation rule governs which `%chain` permission assignments are
allowed and which raise.

The principle: **a permission can be set freely if its effect is bounded to the
setter's own trust scope; otherwise it must be granted from above. Setting a
not-granted permission whose effect crosses trust boundaries upward raises
`kiera.uno/error/privilege_escalation`** — a security exception.

Applied to current permissions:

- **`allow_abort_escalation`**: scope-bounded. Untrusted code may set it `true`;
  the engine enforces at the trust-elevation boundary that aborts originating in
  untrusted code with self-set escalation cannot reach trusted callers above. So
  there is nothing to gain by lying about it; the engine enforces the bound. **Free
  to set.**
- **`allow_catch_security_exceptions`**: not scope-bounded. A frame catching a
  security exception suppresses it from the engine. The engine cannot transparently
  un-suppress, so this permission must be granted from above. **Untrusted code
  setting it true raises `privilege_escalation`.**

This refines the earlier framing of "any chain permission upgrade by untrusted code
fails loudly." The actual rule is more nuanced: the permission's effect determines
whether self-grant is safe.

The exception itself follows the rules in the previous section — escapes the frame,
no graceful unwind, propagates to the engine (or to a frame with
`allow_catch_security_exceptions`), carries a forensic payload (which permission
was being set, what value, the call stack, the assigning code's actual trust level).

---

## Why These Are Boundaries

vibecode: {
	"section": "why_these_are_boundaries",
	"role": "summarizes the rationale for the per-call boundary model, the asymmetric default behaviors of abort vs security exceptions, and the no-graceful-unwind rule for uncatchable exceptions",
	"key_concepts": ["uniform_call_check_path", "different_threat_models_warrant_asymmetry",
		"alarms_are_not_control_flow", "no_user_cleanup_for_uncatchable"]
}

Three design principles drive the model:

- **Uniform per-call checks.** One code path, taken at every call. No conditional
  "is this a boundary?" branching in the interpreter. The cost of a same-trust
  call is a couple of pointer comparisons; the boundary work only happens on real
  trust transitions.
- **Different threat models warrant different defaults.** Aborts are ordinary
  control flow that happens to terminate a scope; default-catchable is the natural
  choice. Security exceptions are integrity alarms; default-uncatchable is the
  natural choice. Forcing both into a single model would either over-constrain
  control flow (making aborts unreasonably hard to handle) or under-constrain
  alarms (letting library code silence them).
- **Alarms are not control flow.** The exceptions that bypass user `try`/`catch`
  also bypass user cleanup — no `finally` blocks, no destructors, no chain unwind.
  This is the same principle: if user code is not allowed to interpose itself
  between an alarm and the responder, then user code is not allowed to do anything
  along the way out either. SIGKILL semantics, not SIGTERM.

---

## Implementation Notes

vibecode: {
	"section": "implementation_notes",
	"role": "documents that the abort and security-exception escalation logic share underlying mechanism and could share code; optimization is desirable but deferred",
	"key_concepts": ["shared_underlying_mechanism", "code_sharing_desirable_but_deferred",
		"future_chain_permissions_likely_to_follow_same_pattern"]
}

The two concepts (`allow_abort_escalation` and `allow_catch_security_exceptions`)
share underlying mechanism: a chain-borne boolean permission, an exception that
respects "cannot catch your own," propagation rules that depend on the permission's
value, and (for the uncatchable cases) a no-graceful-unwind path.

Future chain permissions in the same family (further controls on escalation, other
catch authorizations) are likely to follow this same pattern. To the extent
practical, the implementation should share code between the two paths so the
addition of new permissions is cheap and consistent.

This optimization is **not blocking** for initial development. If sharing code
slows progress, the two paths can be implemented independently first and refactored
to share later. The model itself is what matters; the implementation can converge
over time.
