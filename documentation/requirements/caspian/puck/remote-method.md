# `remote method`

~~~vibecode
{"vibecode": {
	"doc": "remote_method",
	"role": "spec for the `remote method` syntax — Caspian sugar for a method that delegates to %puck.call. Lets remote-first classes (where almost every method is a network round-trip) write declarations without spelling out the %puck.call body each time.",
	"parent_doc": "puck/index.md",
	"key_concepts": ["sugar_over_percent_puck_dot_call",
		"remote_first_class_declaration_pattern",
		"chain_forwarded_automatically",
		"interchangeable_with_explicit_form"]
}}
~~~

`remote method` is Caspian sugar for a method that delegates to [`%puck.call`](index.md#puckcall). It lets remote-first classes — where almost every method is a network round-trip — write each method without spelling out the `%puck.call` body.

The geo class is a typical example:

~~~caspian
class
    field :lat
    field :long
    field :alt

    remote method &address
    end

    remote method &distance_to($other)
    end

    remote method &city
    end
end
~~~

`remote method &address` is equivalent to:

~~~caspian
method &address
    %puck.call(self, :address)
end
~~~

Pure syntactic sugar; the two forms are interchangeable. `%chain` is forwarded automatically in both.

## See also

- [`%puck.call`](index.md#puckcall) — the explicit form `remote method` desugars to.
- [`%puck`](index.md#puck) — the system method behind both forms.
- [Puck protocol](../../puck/index.md) — the language-agnostic protocol underneath.
