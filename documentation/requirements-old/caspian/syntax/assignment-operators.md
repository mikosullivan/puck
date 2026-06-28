# Assignment Operators

## Overview

~~~vibecode
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

## The Receiver Object

~~~vibecode
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

## Operator Classes

~~~vibecode
{"vibecode": {
	"section": "operator_classes",
	"flag": "is_assignment: true",
	"effect": "interpreter_passes_receiver_as_extra_param",
	"signatures": {
		"=": "evaluate($right, $receiver)",
		"+=": "evaluate($left, $right, $receiver)",
		"||=": "evaluate($left, $right: {lazy:true}, $receiver)"
	}
}}
~~~

Assignment operator classes set `is_assignment: true`. The interpreter detects this and
passes the receiver as the final parameter. Classes that need the current value call
`$receiver.get`; all classes write back via `$receiver.set`.

### `=`

`=` is the baseline assignment operator: write the right-hand value into the target the receiver wraps. There is no `$left` parameter because `=` discards whatever the target previously held — nothing needs to be read before writing.

`$receiver` arrives automatically because the class is marked `is_assignment true`. The receiver knows how to write to the target regardless of whether the target is a plain variable, an object property, or an array index ([see § The Receiver Object](#the-receiver-object)), so the body just delegates the write.

```
class
    is_assignment true

    method evaluate($right, $receiver) do
        $receiver.set($right)
    end
end
```

This is the floor every compound operator builds on. `+=`, `||=`, and the rest differ only in what they compute before calling `$receiver.set` — typically reading the current value with `$receiver.get`, deriving a new value, and writing that back.

The same operator handles every kind of target because the receiver hides the differences:

| Source | What the operator sees | Effect |
|--------|------------------------|--------|
| `$foo = 1` | `$right = 1`, `$receiver` wraps the variable `$foo` | the variable now holds `1` |
| `$obj.name = 'Hamlet'` | `$right = 'Hamlet'`, `$receiver` wraps `$obj` + property `name` | `$obj.name` is now `'Hamlet'` |
| `$arr[0] = 99` | `$right = 99`, `$receiver` wraps `$arr` + index `0` | `$arr[0]` is now `99` |

In all three cases the operator body is identical — `$receiver.set($right)` — because the receiver, not the operator, knows how to perform the write.

### `+=`

```
class
    is_assignment true

    method evaluate($left, $right, $receiver) do
        $receiver.set($left + $right)
    end
end
```

### `||=`

```
class
    is_assignment true

    method evaluate($left, $right: {lazy: true}, $receiver) do
        if (! $left)
            $receiver.set($right.call)
        end
    end
end
```

### `&&=`

```
class
    is_assignment true

    method evaluate($left, $right: {lazy: true}, $receiver) do
        if ($left)
            $receiver.set($right.call)
        end
    end
end
```

---

## Built-in Assignment Operators

~~~vibecode
{"vibecode": {
	"section": "built_in_assignment_operators",
	"registered_in": "scope.operators",
	"all_have": "is_assignment: true"
}}
~~~

| Operator | Class | Desugars to |
|----------|-------|-------------|
| `=` | `caspian.uno/assign` | direct assignment |
| `+=` | `caspian.uno/assign_add` | `$foo = $foo + val` |
| `-=` | `caspian.uno/assign_sub` | `$foo = $foo - val` |
| `*=` | `caspian.uno/assign_mul` | `$foo = $foo * val` |
| `/=` | `caspian.uno/assign_div` | `$foo = $foo / val` |
| `%=` | `caspian.uno/assign_mod` | `$foo = $foo % val` |
| `**=` | `caspian.uno/assign_pow` | `$foo = $foo ** val` |
| `\|\|=` | `caspian.uno/assign_or` | assign if left is falsy |
| `&&=` | `caspian.uno/assign_and` | assign if left is truthy |

---

## Increment and Decrement

~~~vibecode
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

## Open Questions

- Should `++` and `--` ever be added as prefix operators? Currently postfix only.
- What should `String.incremented` and `String.decremented` do? Not yet defined.
- Should assignment operators be overrideable per scope, like binary operators?
