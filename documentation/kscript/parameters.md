# Parameter System

## Overview (Borath Vorta)

```
vibecode: {
	"section": "overview",
	"concept": "every_parameter_is_object_with_metadata_hash",
	"declaration_forms": ["inline_in_signature", "programmatic_on_function_object"],
	"forms_are_equivalent": true
}
```

Every parameter in a KScript function is an object with a metadata hash. That metadata
controls how the parameter behaves — whether it is evaluated lazily, what types it
accepts, whether it is required, and so on.

Parameter metadata can be declared inline in the function signature or set programmatically
on the function object after definition. Both forms are equivalent.

---

## Inline Declaration (Kilana)

```
vibecode: {
	"section": "inline_declaration",
	"syntax": "$param: {key: value}",
	"example": "function &evaluate($left: {lazy: true}, $right: {lazy: true})"
}
```

Metadata is attached to a parameter using a hash literal after the parameter name:

```
function &evaluate($left: {lazy: true}, $right: {lazy: true}) do
end
```

```
function &greet($name: {classes: ['string']}, $rank: {classes: ['string'], required: true}) do
end
```

The inline hash is sugar for setting properties on the param object. The two forms below
are identical:

```
# inline
function &foo($bar: {lazy: true}) do
end

# programmatic
$foo = function($bar) do
end
$foo.params['bar'].lazy = true
```

---

## Programmatic Access (Kilana Vorta)

```
vibecode: {
	"section": "programmatic_access",
	"api": "$foo.params['bar'].lazy = true",
	"storage": "params hash in %bucket",
	"key_format": "parameter name without dollar sign",
	"use_cases": ["frameworks", "validators", "generated_functions"]
}
```

Every function object exposes a `params` hash in `%bucket`. Each key is a parameter name
(without `$`); each value is the param metadata object.

```
$foo = function($bar, $gup) do
end

$foo.params['bar'].lazy = true
$foo.params['bar'].classes = ['string', 'number']
$foo.params['gup'].required = true
```

This allows param metadata to be built dynamically — useful for frameworks, validators,
and generated functions.

---

## Known Metadata Properties (Karemma)

```
vibecode: {
	"section": "known_metadata_properties",
	"properties": {
		"lazy": "Boolean default false wraps arg in block caller calls .call",
		"classes": "Array of strings accepted type or UNS names",
		"required": "Boolean default true false makes optional nil if omitted",
		"default": "Any nil value used when argument omitted implies optional",
		"nullable": "Boolean default false nil accepted even when classes set"
	}
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `lazy` | Boolean | false | If true, the argument is not evaluated before the call. Instead, a zero-argument block is passed. The function calls `.call` to evaluate it. Enables short-circuit and deferred evaluation. |
| `classes` | Array of strings | nil | Accepted types or UNS class names. If set, passing a value of a non-matching type raises an error. Multiple entries mean any of the listed types are accepted. |
| `required` | Boolean | true | If false, the parameter is optional. An optional parameter with no default receives nil if omitted. |
| `default` | Any | nil | Value used when the argument is omitted. Setting a default implicitly makes the parameter optional. |
| `nullable` | Boolean | false | If true, nil is accepted even when `classes` is set. |

---

## Lazy Parameters (Hanok)

```
vibecode: {
	"section": "lazy_params",
	"option": "lazy: true",
	"effect": "argument_wrapped_in_block",
	"use_cases": ["binary_operators", "deferred_evaluation", "short_circuit"],
	"call_syntax": "$param.call to evaluate"
}
```

A `lazy: true` parameter is the mechanism behind binary operator evaluators and any
other construct that needs deferred evaluation.

When a parameter is lazy, the caller's expression is wrapped in a zero-argument block
before the call. Inside the function, `.call` evaluates it:

```
class 'kiera.uno/ander'
    function &evaluate($left: {lazy: true}, $right: {lazy: true}) do
        if (! $left.call)
            return false
        end

        return $right.call
    end
end
```

`$foo && $bar` desugars to:

```
$evaluator = ander.new()
$evaluator.evaluate() do
    $foo
end do
    $bar
end
```

`$right.call` is never reached if `$left.call` returns false — true short-circuit
evaluation with no special parser support.

---

## Type Constraints (Karemma Hanok)

```
vibecode: {
	"section": "type_constraints",
	"property": "classes",
	"accepted_forms": ["built_in_type_strings", "full_UNS_addresses"],
	"enforcement": "raises_exception_at_call_time_on_type_mismatch"
}
```

`classes` accepts an array of type names. Built-in type names are strings; UNS class
names use the full UNS address:

```
$foo.params['bar'].classes = ['string']
$foo.params['gup'].classes = ['string', 'number']
$foo.params['person'].classes = ['foo.com/person']
```

A type mismatch raises an exception at call time.

---

## Freezing Functions (Karemma Merchant)

```
vibecode: {
	"section": "freezing_functions",
	"concern": "functions_are_mutable_params_can_be_modified_by_anyone_with_reference",
	"freeze_all": "$foo.object.freeze",
	"freeze_params_only": "$foo.object.bucket.freeze",
	"note": "params_lives_in_%bucket_so_bucket_freeze_suffices"
}
```

Since functions are mutable objects, `params` can be modified by anyone with a reference
to the function. Before passing a function around, freeze it:

```
$foo.params['bar'].lazy = true      # configure
$foo.object.freeze                  # lock everything
```

If you only want to lock the params without freezing the whole object, use:

```
$foo.object.bucket.freeze
```

Since `params` lives in `%bucket`, this is sufficient to prevent param modification.

---

## Open Questions (DaiMon Lurin)

- Should type checking be enforced at definition time (static) or call time (dynamic)?
  Current assumption is call time.
- Should `classes` accept a mix of built-in type names and UNS addresses in the same
  array?
- Are there additional metadata properties needed for keyword arguments specifically
  (e.g. the keyword name itself)?
