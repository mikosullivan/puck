# Modules

## Status

```
vibecode: {
	"section": "status",
	"design_status": "provisional",
	"rationale": "adopted_to_solve_mutual_function_reference_problem"
}
```

Provisional design. The approach is adopted for now to solve the mutual function reference
problem. Further experience with the language may refine or replace it.

---

## The Problem

```
vibecode: {
	"section": "the_problem",
	"problem": "functions_cannot_call_each_other_at_same_scope_level",
	"cause": "functions_do_not_capture_outer_scope"
}
```

Functions in KScript do not capture outer scope. This means two functions defined at the
same level cannot call each other:

```
$foo = function() do
end

$bar = function() do
    &foo    # $foo is invisible here — functions don't see outer scope
end
```

Passing functions as explicit parameters works but becomes obnoxious at scale. A shared
context is needed — something both functions can see without threading it through every
call.

---

## The Approach

```
vibecode: {
	"section": "the_approach",
	"concept": "module_is_object_functions_become_methods",
	"bare_call_resolution": "&foo inside module == self.foo",
	"effect": "mutual_function_calls_work_as_plain_method_calls_on_self"
}
```

A module is an object. Functions defined inside it are methods on that object. `&foo`
inside a module method is syntactic sugar for `self.foo` — the same rule that already
exists inside class method bodies.

```
#module
    function &foo
    end

    function &bar
        &foo    # same as self.foo
    end
end
```

The module instantiates an anonymous object. Every function defined inside becomes a
method on that object. When `&bar` calls `&foo`, it is calling `self.foo` — a plain
method call on the current object. No new lookup rules are introduced; the class method
semantics already handle it.

The mutual-call problem dissolves. It was always just a method call on `self`.

---

## Implicit Top-Level Module

```
vibecode: {
	"section": "implicit_top_level_module",
	"concept": "every_program_wrapped_in_implicit_top_level_module",
	"effect": "top_level_functions_can_call_each_other",
	"notes": ["not_special_same_rules_as_any_module", "no_explicit_module_block_needed"]
}
```

Every KScript program is implicitly wrapped in a top-level module. Functions defined at
the top level of a file are methods on the top-level module object. This means top-level
functions can call each other without any explicit module declaration:

```
function &foo
end

function &bar
    &foo    # works — both are methods on the implicit top-level module object
end

&bar
```

The implicit top-level module is not special in any way. It is a module like any other.
It just has no `#module ... end` written by the programmer. All the same rules apply.

---

## Syntax

```
vibecode: {
	"section": "syntax",
	"sigil": "#module",
	"behavior": "creates_and_instantiates_anonymous_object",
	"body": "same_structure_as_class_body",
	"available_inside": ["fields", "helpers", "properties", "class_machinery"]
}
```

```
#module
    function &foo
    end

    function &bar
        &foo
    end
end
```

A `#module` block creates and immediately instantiates an anonymous object. The block is
its definition body, following the same structure as a class body. Fields, helpers,
properties, and other class machinery are all available inside a module.

The `#` sigil distinguishes modules from class definitions (`class 'UNS'`) and variables
(`$name`).

---

## What `&foo` Means Inside a Module

```
vibecode: {
	"section": "what_ampfoo_means_inside_a_module",
	"resolution": ["1_look_up_foo_as_method_on_self", "2_call_if_found",
		"3_raise_if_not_found"],
	"notes": ["same_as_inside_class_method_body",
		"dollar_foo_variable_still_invisible",
		"function_isolation_rule_intact"]
}
```

Inside any module method, a bare function call `&foo` resolves as follows:

1. Look up `foo` as a method on `self` (the module object)
2. If found, call it
3. If not found, raise an error

This is identical to how `&foo` works inside a class method body. The module object is
`self` for the duration of any method call on it.

`$foo` (the variable) is still invisible inside a function. Only `&foo` (method call
form) gets the `self` lookup. This keeps the function isolation rule intact — functions
don't see outer variables, but they can call sibling methods through `self`.

---

## Nesting

```
vibecode: {
	"section": "nesting",
	"behavior": "inner_module_is_own_object_with_own_self",
	"cross_boundary_calls": "not_possible_via_ampfoo_must_pass_reference_explicitly"
}
```

Modules can be nested. An inner module is its own object with its own `self`. Functions
inside the inner module cannot see the outer module's methods via `&name` — `self` is
the inner module:

```
#module
    function &outer_foo
    end

    #module
        function &inner_bar
            &outer_foo    # error — self is the inner module, not the outer
        end
    end
end
```

To call across module boundaries, pass a reference explicitly as a parameter.

---

## Relationship to Classes

```
vibecode: {
	"section": "relationship_to_classes",
	"module_is": "sugar_for_anonymous_class_defined_and_instantiated_in_one_step",
	"use_formal_class_when": ["uns_name_needed", "schema_needed",
		"multiple_instances_needed", "inheritance_needed"],
	"use_module_when": "local_grouping_of_functions_single_instance_no_schema"
}
```

A module is syntactic sugar for an anonymous class that is defined and instantiated in
one step and never named. The two are equivalent in the object system:

```
# these are conceptually equivalent:

#module
    function &foo
    end
end

# ...is roughly:

class '<anonymous>'
    function &foo
    end
end

$anon = %kiera['<anonymous>'].new
```

Formal classes (`class 'UNS' ... end`) are for objects that need:
- A UNS name and a place in the Kieraverse
- A schema (fields, types, validation)
- Multiple instances
- Inheritance

Modules are for local grouping of functions that need to call each other. They are
single-instance, anonymous, and have no schema requirements.

---

## Why Not Just Use a Class?

```
vibecode: {
	"section": "why_not_just_use_a_class",
	"answer": "module_is_lighter_syntax_signals_lighter_intent",
	"signals": "grouping_functions_not_modeling_data"
}
```

You could. A module is just a lighter syntax for the same thing. The `#module` form
exists because the common case — grouping functions, not modeling data — doesn't need
field declarations, UNS names, or the full class apparatus. The lighter syntax signals
the lighter intent.

---

## Open Questions

- Can a module be assigned to a variable and passed around as an object from outside?
- Does a module's anonymous class inherit from `kiera.uno/object` directly?
- Can modules be named for later reference, or are they always anonymous?
- How does the implicit top-level module interact with `%engine` and the bootstrapping
  sequence?
