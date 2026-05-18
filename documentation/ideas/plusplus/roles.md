# Roles

~~~json
{"vibecode": {
	"doc": "plusplus-roles",
	"role": "early-stage Charlie++ design for %role, a chain-scoped identity/context store distinct from access control; covers scoping, unset patterns, and privilege-escalation pitfalls",
	"key_concepts": ["role_object", "chain_scoped_role", "identity_context",
		"not_permissions", "unset_patterns"],
	"status": "brainstorm"
}}
~~~

<a id="status"></a>
## 1 Status

This is an early design idea, not yet in active development.

---

<a id="overview"></a>
## 2 Overview

`%role` is a system method that returns the current role object for the scope. It is
an identifier and context store — a way of passing identity and related data down the
call chain without threading it through every function signature.

`%role` is not a permission system. It does not enforce access control by itself. It
is simply an object in the chain that code can read and use however it needs to.

---

<a id="behavior"></a>
## 3 Behavior

- `%role` follows the same scoping rules as `%chain` — values flow down, changes do
  not propagate back up.
- If `%role` is null, there is no current role.
- Over-reliance on `%role` can lead to privilege escalation if the developer forgets
  to unset it before running untrusted code.

---

<a id="unsetting-the-role"></a>
## 4 Unsetting the Role

Several ways to clear `%role`:

```
# Direct assignment
%role = null

# Block-scoped — role is null inside, restored after
%role.none do
end

# Clear everything in the chain including role
%chain.clear do
end
```

---

<a id="marking-a-function-as-untrusted"></a>
## 5 Marking a Function as Untrusted

Trust lives on the function object rather than at the call site. `untrusted()` wraps
a function so that `%role` is automatically set to null whenever it is called:

```
$foo = function()
end

$foo = untrusted($foo)
&foo   # %role is null for the duration of this call
```

The trust decision is made once when the function is wrapped. Every subsequent call
automatically gets a null role — no forgetting at call sites.

`untrusted()` is implemented as a wrapper that intercepts the call, sets `%role` to
null, then delegates to the original function. It composes naturally with jail.

---

<a id="open-questions"></a>
## 6 Open Questions

- What properties does a role object expose beyond being a context store?
- How do roles interact with firewall rules?
- Can roles be narrowed (permissions removed) rather than fully cleared?
- Should there be a `trusted()` counterpart to `untrusted()`?
- How do roles interact with multi-tenancy and audit logging?
