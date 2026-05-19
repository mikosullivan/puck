# Assignment Operators

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"operators": ["=", "+=", "-=", "*=", "/=", "%=", "**=", "||=", "&&=", "++", "--"],
	"model": "all_desugar_to_simple_assignment_via_receiver_object",
	"extension_point": "assignment_operator_classes_registered_in_scope"
}}
~~~

Assignment operators write a value back to a target. All compound forms desugar to a
simple assignment at the transpiler level. The runtime never sees compound assignment —
only the expanded form.

Every assignment operator is backed by a class, following the same pattern as binary
operators. The class is flagged with `is_assignment: true`, which causes the interpreter
to pass a **receiver object** as an extra parameter.

---

<a id="the-receiver-object"></a>
## The Receiver Object

~~~json
{"vibecode": {
	"section": "receiver_object",
	"role": "encapsulates_write_back_to_assignment_target",
	"methods": ["get", "set"],
	"targets": ["simple_variable", "object_property", "array_index"],
	"note": "operator_does_not_need_to_know_target_type"
}}
~~~

The receiver is a thin object that encapsulates how to read from and write to the
assignment target, regardless of what that target is.

| Method | Description |
|--------|-------------|
| `get` | Returns the current value of the target |
| `set($value)` | Writes `$value` back to the target |

Examples of what a receiver wraps:

| Target | Receiver behaviour |
|--------|--------------------|
| `$foo` | wraps the variable; `set` updates the variable |
| `$foo.bar` | wraps the object + property name; `set` calls the property setter |
| `$array[0]` | wraps the array + index; `set` calls `[]=` on the array |

The operator calls `$receiver.set($new_value)` without caring what the target is.

---

<a id="operator-classes"></a>
## Operator Classes

~~~json
{"vibecode": {
	"section": "operator_classes",
	"flag": "is_assignment: true",
	"effect": "interpreter_passes_receiver_as_extra_param",
	"signatures": {
		"=":   "evaluate($right, $receiver)",
		"+=":  "evaluate($left, $right, $receiver)",
		"||=": "evaluate($left: {lazy:true}, $right: {lazy:true}, $receiver)"
	}
}}
~~~

Assignment operator classes set `is_assignment: true`. The interpreter detects this and
passes the receiver as the final parameter. Classes that need the current value call
`$receiver.get`; all classes write back via `$receiver.set`.

<a id="section-3-1"></a>
### `=`

```
class 'charlie.uno/assign'
    is_assignment true

    function &evaluate($right, $receiver) do
        $receiver.set($right)
    end
end
```

<a id="section-3-2"></a>
### `+=`

```
class 'charlie.uno/assign_add'
    is_assignment true

    function &evaluate($left, $right, $receiver) do
        $receiver.set($left + $right)
    end
end
```

<a id="section-3-3"></a>
### `||=`

```
class 'charlie.uno/assign_or'
    is_assignment true

    function &evaluate($left: {lazy:true}, $right: {lazy:true}, $receiver) do
        if (! $left.call)
            $receiver.set($right.call)
        end
    end
end
```

<a id="section-3-4"></a>
### `&&=`

```
class 'charlie.uno/assign_and'
    is_assignment true

    function &evaluate($left: {lazy:true}, $right: {lazy:true}, $receiver) do
        if ($left.call)
            $receiver.set($right.call)
        end
    end
end
```

---

<a id="built-in-assignment-operators"></a>
## Built-in Assignment Operators

~~~json
{"vibecode": {
	"section": "built_in_assignment_operators",
	"registered_in": "scope.operators",
	"all_have": "is_assignment: true"
}}
~~~

| Operator | Class | Desugars to |
|----------|-------|-------------|
| `=` | `charlie.uno/assign` | direct assignment |
| `+=` | `charlie.uno/assign_add` | `$foo = $foo + val` |
| `-=` | `charlie.uno/assign_sub` | `$foo = $foo - val` |
| `*=` | `charlie.uno/assign_mul` | `$foo = $foo * val` |
| `/=` | `charlie.uno/assign_div` | `$foo = $foo / val` |
| `%=` | `charlie.uno/assign_mod` | `$foo = $foo % val` |
| `**=` | `charlie.uno/assign_pow` | `$foo = $foo ** val` |
| `\|\|=` | `charlie.uno/assign_or` | assign if left is falsy |
| `&&=` | `charlie.uno/assign_and` | assign if left is truthy |

---

<a id="increment-and-decrement"></a>
## Increment and Decrement

~~~json
{"vibecode": {
	"section": "increment_decrement",
	"operators": ["++", "--"],
	"form": "postfix_only",
	"mechanism": "calls_incremented_or_decremented_method_on_receiver_value",
	"extensible": "any_class_can_support_by_defining_incremented_and_decremented"
}}
~~~

`++` and `--` are postfix-only. They call `incremented` or `decremented` on the current
value and assign the result back via the receiver:

```
$foo++   →   $receiver.set($receiver.get.incremented)
$foo--   →   $receiver.set($receiver.get.decremented)
```

The operator doesn't hardcode `+ 1` — it delegates to the type. Number defines
`incremented` as `+ 1` and `decremented` as `- 1`. Any other class can support `++`
and `--` by defining those methods.

```
$count = 0
$count++     # 1
$count++     # 2
$count--     # 1

$word = 'aa'
$word++      # 'ab'  (if String defines incremented)
```

---

<a id="open-questions"></a>
## Open Questions

- Should `++` and `--` ever be added as prefix operators? Currently postfix only.
- What should `String.incremented` and `String.decremented` do? Not yet defined.
- Should assignment operators be overrideable per scope, like binary operators?
