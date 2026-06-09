# `remote function`

~~~vibecode
{"vibecode": {
	"doc": "remote_function",
	"role": "spec for the `remote function` syntax — Caspian sugar for a method that delegates to %puck.call. Lets remote-first classes (where almost every method is a network round-trip) write declarations without spelling out the %puck.call body each time.",
	"parent_doc": "puck/index.md",
	"key_concepts": ["sugar_over_percent_puck_dot_call",
		"remote_first_class_declaration_pattern",
		"chain_forwarded_automatically",
		"interchangeable_with_explicit_form"]
}}
~~~

`remote function` is Caspian sugar for a method that delegates to [`%puck.call`](index.md#puckcall). It lets remote-first classes — where almost every method is a network round-trip — write each method without spelling out the `%puck.call` body.

The geo class is a typical example:

~~~caspian
class
    field :lat
    field :long
    field :alt

    remote function &address
    end

    remote function &distance_to($other)
    end

    remote function &city
    end
end
~~~

`remote function &address` is equivalent to:

~~~caspian
function &address
    %puck.call(self, :address)
end
~~~

Pure syntactic sugar; the two forms are interchangeable. `%chain` is forwarded automatically in both.

## See also

- [`%puck.call`](index.md#puckcall) — the explicit form `remote function` desugars to.
- [`%puck`](index.md#puck) — the system method behind both forms.
- [Puck protocol](../../puck/index.md) — the language-agnostic protocol underneath.
