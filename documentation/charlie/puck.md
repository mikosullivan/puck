# Charlie's Interface to Puck

~~~json
{"vibecode": {
	"doc": "charlie-puck",
	"role": "spec for the Charlie-specific syntax and system methods that interact with the Puck protocol — %puck, %puck.call, remote function; the protocol itself is documented language-agnostic in puck/puck.md",
	"key_concepts": ["%puck_system_method", "puck_bracket_lookup_shorthand",
		"%puck.call_remote_invocation", "remote_function_sugar",
		"puck_scoping_via_%chain"],
	"example_universe": "Star Trek"
}}
~~~

This doc covers how Charlie code talks to the [Puck protocol](../puck/puck.md).
The protocol itself is language-agnostic; this doc is about the Charlie
syntax and system methods that wrap it.

---

<a id="puck"></a>
## 1 `%puck`

`%puck` is a Charlie system method that returns a **puck object** — the
client-side resolver for UNS lookups. See [puck/puck.md § The puck object](../puck/puck.md#the-puck-object)
for what a puck is and what it holds; this section covers the Charlie
sugar around it.

`%puck[UNS]` is shorthand for the puck's `lookup` method:

~~~charlie
$officer = %puck['starfleet.com/character/picard']
$officer.greet
~~~

<a id="shorthand-for-built-in-classes"></a>
### 1.1 Shorthand for built-in classes

Bare names in `%puck[...]` — any key without a domain — resolve to
`puck.uno/...`:

~~~charlie
%puck['null']             # same as %puck['puck.uno/null']
%puck['true']             # same as %puck['puck.uno/true']
%puck['mikobase/memory']  # same as %puck['puck.uno/mikobase/memory']
~~~

`puck.uno` is the default namespace for `%puck` lookups.

<a id="scoping-via-chain"></a>
### 1.2 Scoping via `%chain`

`%puck` is scoped via `%chain` — the current puck lives in the chain.
Because `%chain` is wiped at role boundaries (see [roles.md](roles.md)),
the current puck does not propagate across role boundaries; **each role
gets its own world.** When there is no puck in the chain, `%puck`
returns plain `null`.

**The engine decides what puck (if any) populates each role boundary.**
The engine may install a puck on entry to a new role — typically a
restricted/derived puck per the role's trust profile — or it may leave
`%puck` null for that role. Per-role policy, not global.

---

<a id="puckcall"></a>
## 2 `%puck.call`

`%puck.call` is the Charlie syntax for an explicit remote method call:

~~~charlie
%puck.call($officer, :greet, name: 'Jean-Luc')
~~~

Three arguments:

1. **Target object** — what to call the method on
2. **Method name** — a symbol
3. **Keyword parameters** — passed through to the remote method

`%puck.call` automatically forwards the current `%chain` to the remote
call — the same chain the calling function is running under.

For the protocol-level remote-invocation model (request shape, response
shape, error catalog), see [puck/puck.md § Remote method invocation](../puck/puck.md#remote-method-invocation).

<a id="return-and-error-handling-in-charlie"></a>
### 2.1 Return and error handling in Charlie

- **Return value** — the remote method's result, marshaled back as a
  puck object reference (or a primitive). Callers don't see "this was
  remote"; the value behaves like any local call result.
- **Exceptions** — the protocol error catalog
  (`puck.uno/error/not_found`, `puck.uno/error/transport`,
  `puck.uno/error/auth`, etc.) is raised as ordinary Charlie exceptions.
  Catch with `catch` as usual:

~~~charlie
$result = catch('puck.uno/error/transport')
    %puck.call($officer, :greet, name: 'Jean-Luc')
end
~~~

If the remote method itself raises, that exception propagates to the
caller as if thrown locally, with the remote stack trace preserved (per
[charlie-runtime.md § stack traces](charlie-runtime.md#all-exceptions-carry-a-stack-trace)).

---

<a id="remote-function"></a>
## 3 `remote function`

`remote function` is Charlie sugar for a method that delegates to
`%puck.call`. Inside a class definition:

~~~charlie
class 'starfleet.com/character'
    remote function &greet(name:)
    end
end
~~~

is equivalent to:

~~~charlie
class 'starfleet.com/character'
    function &greet(name:)
        %puck.call(self, :greet, name: name)
    end
end
~~~

Pure syntactic sugar; the two forms are interchangeable. `%chain` is
forwarded automatically in both.

---

<a id="versioning"></a>
## 4 Versioning

The Puck protocol takes a deliberately light approach to versioning
— see [puck/protocol.md § Versioning](../puck/protocol.md#versioning).
Charlie doesn't add a `restrict` block or any other syntax for
version windows; to use a specific API version, look it up at its
versioned UNS:

~~~charlie
$geo = %puck['puck.uno/geo/v2']
~~~

Charlie's blockchain-signed versioning of library identity is a
separate story; see [blockchain.md](../blockchain.md).
