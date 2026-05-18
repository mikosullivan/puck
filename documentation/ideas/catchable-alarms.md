# Catchable Alarms (deferred)

~~~json
{"vibecode": {
	"doc": "catchable-alarms",
	"role": "deferred alternative design where alarms can be caught at role boundaries via boundary catchers, rather than the current always-fatal alarm model; recorded for possible revisit",
	"key_concepts": ["alarms_at_role_boundaries", "boundary_catcher", "alarm_to_exception_demotion",
		"considered_and_dropped"],
	"status": "deferred"
}}
~~~

**Status:** considered and dropped from current production. Recorded
here in case it's worth revisiting later.

The current role-model spec (see [roles.md](../charlie/roles.md)) treats alarms
as **always fatal**: they go directly to the engine with no
unwinding, no `finally` blocks, no catch handlers from Charlie code.
The engine terminates the process or handles it however it sees fit.

This document describes an alternative design that was sketched
during the brainstorm — one where alarms can be caught at role
boundaries — and explains why it was set aside.

---

<a id="the-alternative-design"></a>
## 1 The Alternative Design

The idea: alarms travel up the call stack past **ordinary** catch
handlers, but can be intercepted at **role boundaries** via a
specially-installed catcher.

<a id="mechanism"></a>
### 1.1 Mechanism

- When code crosses a role boundary (calling a function owned by a
  different role), the runtime automatically installs a **boundary
  catcher** in `%chain`. This is invisible to user code; it's part
  of the role-transition machinery.
- An alarm raised inside the called function travels upward past any
  local `catch` blocks — they don't intercept it.
- The alarm reaches the boundary catcher in the caller's `%chain`
  frame.
- The boundary catcher **re-emits** the alarm as a less destructive
  regular exception, which then unwinds normally through the
  caller's code via the standard `try/catch` mechanics.

The effect: an alarm from inside a different-role function
trampolines past that function's own catch blocks and lands in the
caller's boundary catcher. The caller (the boundary owner) sees a
regular exception in their own scope and can handle it.

<a id="use-cases-this-would-enable"></a>
### 1.2 Use Cases This Would Enable

- **Graceful recovery from foreign-role failures.** When `user` calls
  `bob`'s function and `bob` triggers an alarm, `user` could catch
  the resulting exception and recover (try a different call, present
  a friendly error to the user, etc.).
- **Wrapping third-party code.** A function that calls into
  potentially-buggy or potentially-malicious code could translate
  alarms into something it knows how to handle, rather than letting
  the engine kill everything.
- **Resource cleanup at the boundary.** The caller could run cleanup
  code in response to a foreign-role alarm before the failure
  propagates further.

---

<a id="why-it-was-dropped-for-now"></a>
## 2 Why It Was Dropped (For Now)

The use cases are real but narrow. Most of what they accomplish can
be done with **regular exceptions**:

- If a developer wants recoverable failures, they raise regular
  exceptions, not alarms. Alarms are explicitly the category for
  things that *aren't* meant to be recovered from.
- Resource cleanup already runs during regular-exception unwinding
  via `try/finally`. No special mechanism needed.
- Wrapping third-party code with translation is something the
  developer can do explicitly with their own catch blocks for
  regular exceptions; the runtime doesn't need to do it for them.

The cost of the elaborate design:

- More machinery in the runtime (boundary catchers, automatic
  installation on role transitions, re-emit semantics).
- More to explain in the spec.
- A second mechanism for error handling that developers have to
  understand (regular exceptions, alarms, *plus* alarm-to-exception
  conversion at boundaries).
- Subtle interactions with `%chain` (what happens if a developer
  modifies `%chain` in ways that interfere with the catcher? what
  happens to the catcher if the alarm fires while `%chain` is being
  rewritten?).

For the current pass, simpler wins: alarms are fatal, regular
exceptions are the only catchable thing, two categories with clean
semantics.

---

<a id="when-to-revisit"></a>
## 3 When to Revisit

- If a real-world use case for boundary-level alarm recovery
  surfaces that *can't* be cleanly expressed with regular exceptions.
- If the role model evolves in ways that change which kinds of
  failures need boundary-level handling.
- If a future design adds enough other `%chain`-installed machinery
  that the catcher's runtime cost becomes negligible by comparison.

If revisited, the natural home for the implementation is `%chain` —
the role boundary already maps onto a `%chain` frame, and
chain-scoped values are how the runtime already handles
boundary-respecting state.
