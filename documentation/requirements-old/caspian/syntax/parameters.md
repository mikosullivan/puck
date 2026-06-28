# Parameter System

## Overview

~~~vibecode
{"vibecode": {
    "section": "overview",
    "concept": "every_parameter_is_an_object_with_a_metadata_hash",
    "declaration_forms": ["inline_in_signature", "programmatic_on_function_object"],
    "forms_are_equivalent": true,
    "consolidated_from": ["parameters.md_metadata_focus",
                           "params.md_call_site_focus"],
    "consolidated_on": "2026-05-17"
}}
~~~

Every parameter in a Caspian function is an object with a metadata hash.
That metadata controls how the parameter behaves — whether it is evaluated
lazily, what types it accepts, whether it is optional, what its external
(call-site) name is, and so on.

Parameter metadata can be declared inline in the function signature or set
programmatically on the function object after definition. Both forms are
equivalent.

This document covers both the declaration side (what you write when you
define a function) and the call site (how callers pass arguments and how
the runtime binds them).

---

## Basic Definition

~~~vibecode
{"vibecode": {
    "section": "basic_definition",
    "signature_form": "function($private1, $private2, ...)",
    "params_order": "left_to_right",
    "names": {"private": "with_$_inside_the_function",
              "public": "without_$_at_the_call_site_default_is_private_minus_$"}
}}
~~~

A function's parameters are declared in its signature, left to right:

```
$foo = function($name, $rank)
    # body
end
```

Each parameter has two names:

- **Private name** — the `$`-prefixed name used inside the function body.
- **Public name** — the name used at the call site for keyword arguments.
  By default it's the private name with the leading `$` stripped (so
  `$name` → `name`); this can be overridden via the `public` metadata
  property (see [Public and Private Names](#public-and-private-names)).

---

## Bucket-binding parameters

~~~vibecode
{"vibecode": {
    "section": "bucket_binding_parameters",
    "form": "@param_name in the parameter list",
    "expansion": "$param_name positional binding plus %bucket['param_name'] = $param_name; then the local binding is dropped",
    "observable_effect": "the argument value lands in the bucket at the same key name; no $param_name local exists in the body",
    "applicability": "only meaningful in methods (anywhere %bucket is in scope); raises in functions that have no %bucket"
}}
~~~

A parameter declared with the `@` sigil writes its argument directly into the object's bucket under the same key name. The verbose form is purely mechanical:

```
class
    method init($play_id)
        %bucket['play_id'] = $play_id
    end
end
```

The shorthand:

```
class
    method init(@play_id)
    end
end
```

Both define a method whose call sets `%bucket['play_id']` to the argument value. The `@` sigil at the parameter position means "write this parameter into the bucket at this key" — same `@` sigil that's used to read and write bucket entries inside the body, just doing the same job from a new position.

**No local binding.** The `@` form sets the bucket entry and that is its entire effect. There is no `$play_id` local inside the body — if the body needs to read the value, it reads `@play_id` (i.e., `%bucket['play_id']`). Pick the verbose form (`$play_id` parameter with manual `@play_id = $play_id`) when the body needs both a local and a bucket write.

**Applicability.** The shorthand is meaningful anywhere `%bucket` is in scope — inside any method on a class. Using `@param` in a function that has no `%bucket` (top-level functions, etc.) raises.

**Composes with other parameter features.** Defaults, lazy parameters, keyword names, type constraints all apply the same way:

```
class
    method init(@play_id, @rank: 'unknown', @config: {lazy: true})
    end
end
```

Equivalent to:

```
class
    method init($play_id, $rank: 'unknown', $config: {lazy: true})
        %bucket['play_id'] = $play_id
        %bucket['rank']    = $rank
        %bucket['config']  = $config
    end
end
```

**Reading the signature.** Mixing the two forms in one signature tells the reader at a glance which parameters become bucket state and which are local-use-only:

```
method init(@play_id, @rank, $log_level)
    # @play_id and @rank go into the bucket; $log_level is a local for this method only
end
```

---

## Inline Metadata Declaration

~~~vibecode
{"vibecode": {
    "section": "inline_declaration",
    "syntax": "$param: {key: value, key: value}",
    "spacing_convention": "colon_space; no_space_before_comma; space_after_comma",
    "example": "function &evaluate($left: {lazy: true}, $right: {lazy: true})"
}}
~~~

Metadata is attached to a parameter using a hash literal after the
parameter name:

```
function &evaluate($left: {lazy: true}, $right: {lazy: true}) do
end

function &greet($name: {classes: ['string']},
                $rank: {classes: ['string'], optional: true}) do
end
```

**Formatting convention.** Inside the metadata hash:
- Colon followed by a single space (`lazy: true`, not `lazy:true`).
- Commas: no space before, single space after (`lazy: true, classes: ['string']`).

The inline hash is sugar for setting properties on the param object. The
two forms below are identical:

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

## Known Metadata Properties

~~~vibecode
{"vibecode": {
    "section": "known_metadata_properties",
    "properties": ["lazy", "classes", "optional", "default", "nullable", "public"]
}}
~~~

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `lazy` | Boolean | false | If true, the argument is not evaluated before the call. Instead, a zero-argument block is passed; the function calls `.call` to evaluate it. Enables short-circuit and deferred evaluation. |
| `classes` | Array of strings | nil | Accepted types or UNS class names. If set, passing a value of a non-matching type raises an error. Multiple entries mean any of the listed types are accepted. |
| `optional` | Boolean | false | If true, the parameter is optional and **all subsequent parameters become optional too** (propagation rule — see [Required and Optional Parameters](#required-and-optional-parameters)). An optional parameter with no default receives `nil` if omitted. |
| `default` | Any | nil | Value used when the argument is omitted. Setting a default implicitly makes the parameter optional. |
| `nullable` | Boolean | false | If true, `nil` is accepted even when `classes` is set. |
| `public` | String | private name minus `$` | The external (call-site) keyword name for this parameter. |

---

## Public and Private Names

~~~vibecode
{"vibecode": {
    "section": "public_private",
    "mapping": "public_to_private",
    "default_public": "strip_leading_$_from_private_name",
    "call_binding": "public_only",
    "override_via": "public_metadata_property"
}}
~~~

Each parameter has a private name (used inside the function) and a public
name (used at the call site for keyword arguments).

**Default mapping.** Strip the `$` from the private name. So `$name`'s
public name is `name`; `$rank`'s is `rank`.

```
$foo = function($name, $rank)

&foo name: 'Picard', rank: 'Captain'   # keyword args use public names
```

**Override.** Set the `public` metadata property to use a different
external name:

```
$foo = function($name, $title_sent: {public: 'title'})

&foo 'Picard', title: 'Captain'   # public name 'title' binds to $title_sent
```

Inside the function, the parameter is `$title_sent`; outside, it's `title`.
Calling with `title_sent:` (the private name) is an error — the call site
can only use public names.

---

## Required and Optional Parameters

~~~vibecode
{"vibecode": {
    "section": "optional_params",
    "default": "required",
    "opt_out": "optional: true",
    "propagation_rule": "once_one_param_is_optional_all_following_are_implicitly_optional",
    "rationale": "positional_calls_need_unambiguous_truncation_point"
}}
~~~

Parameters are **required by default**. To make one optional, set
`optional: true` in its metadata:

```
$foo = function($name, $rank: {optional: true}, $phrase)
```

**Propagation rule.** Once a parameter is marked `optional: true`, **all
parameters after it are implicitly optional too** — you don't have to mark
them. So the signature above is equivalent to:

```
$foo = function($name,
                $rank:   {optional: true},
                $phrase: {optional: true})
```

| Parameter | Status |
|---|---|
| `$name` | required |
| `$rank` | optional (explicitly) |
| `$phrase` | optional (inherited) |

**Why the propagation rule.** Positional calls bind left to right. If only
`$rank` were optional and `$phrase` were required, a call like
`&foo 'Picard'` would be ambiguous — the caller skipped one argument, but
which one? The propagation rule eliminates the ambiguity: once optional
starts, the caller may stop providing positional arguments at any point
from that index onward.

**Defaults.** An omitted optional parameter takes its `default` value if
one is set, otherwise `nil`:

```
$foo = function($name, $rank: {optional: true, default: 'Ensign'})

&foo 'Picard'              # $rank = 'Ensign'
&foo 'Picard', 'Admiral'   # $rank = 'Admiral'
```

Setting a `default` implicitly makes the parameter optional, so writing
`{default: 'X'}` is equivalent to `{optional: true, default: 'X'}`.

---

## Type Constraints

~~~vibecode
{"vibecode": {
    "section": "type_constraints",
    "property": "classes",
    "accepted_forms": ["built_in_type_strings", "full_UNS_addresses"],
    "enforcement": "raises_exception_at_call_time_on_type_mismatch",
    "nil_handling": "rejected_by_default_when_classes_set; nullable_true_permits_it"
}}
~~~

`classes` accepts an array of accepted type names. Built-in type names are
strings; user-defined class names use the full UNS address:

```
$foo.params['bar'].classes    = ['string']
$foo.params['gup'].classes    = ['string', 'number']
$foo.params['person'].classes = ['foo.com/person']
```

Multiple entries mean any of the listed types are accepted. A type
mismatch raises an exception at call time.

**`nil` handling.** When `classes` is set, `nil` is rejected by default
(it doesn't match any type). To permit `nil` while still enforcing the
type constraint for non-nil values, set `nullable: true`:

```
$foo.params['bar'].classes  = ['string']
$foo.params['bar'].nullable = true

&foo 'hello'   # ok
&foo nil       # ok (nullable)
&foo 42        # error (wrong type)
```

---

## Lazy Parameters

~~~vibecode
{"vibecode": {
    "section": "lazy_params",
    "option": "lazy: true",
    "effect": "argument_wrapped_in_zero_arg_block",
    "use_cases": ["binary_operators", "deferred_evaluation", "short_circuit"],
    "call_syntax": "$param.call_to_evaluate"
}}
~~~

A `lazy: true` parameter is the mechanism behind binary operator
evaluators and any other construct that needs deferred evaluation.

When a parameter is lazy, the caller's expression is wrapped in a
zero-argument block before the call. Inside the function, `.call`
evaluates it:

```
class
    method evaluate($left:  {lazy: true},
                       $right: {lazy: true}) do
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

`$right.call` is never reached if `$left.call` returns false — true
short-circuit evaluation with no special parser support.

---

## Rest Positional Parameters: `*args`

~~~vibecode
{"vibecode": {
    "section": "rest_positional",
    "syntax": "*args",
    "binding": "array_of_remaining_positional_arguments",
    "position": "after_normal_positional; before_double_star_named_rest"
}}
~~~

A `*args` parameter captures all remaining positional arguments into an
array:

```
$foo = function($name, *args)

&foo 'Picard', 'Admiral', 'flagship'

# Inside:
# $name = 'Picard'
# $args = ['Admiral', 'flagship']
```

If no extra positional arguments are passed, `$args` is an empty array.

---

## Rest Named Parameters: `**opts`

~~~vibecode
{"vibecode": {
    "section": "rest_named",
    "syntax": "**opts",
    "binding": "hash_of_remaining_named_arguments_keyed_by_public_name",
    "position": "last_in_signature"
}}
~~~

A `**opts` parameter captures all remaining named arguments into a hash,
keyed by their public names:

```
$foo = function($name, **opts)

&foo 'Picard', ship: 'Enterprise', class: 'Galaxy'

# Inside:
# $name = 'Picard'
# $opts = {ship: 'Enterprise', class: 'Galaxy'}
```

If no extra named arguments are passed, `$opts` is an empty hash.

**Effect on error handling.** Without `**opts`, an unknown named argument
at the call site is an error. With `**opts`, any unknown named arguments
are quietly absorbed into the hash.

---

## Combined Rest Parameters

~~~vibecode
{"vibecode": {
    "section": "combined_rest",
    "supports": ["normal", "*args", "**opts"],
    "order_in_signature": "normal -> *args -> **opts",
    "constraint": "at_most_one_*args_and_one_**opts"
}}
~~~

A signature can combine normal parameters, `*args`, and `**opts` — in
that order:

```
$foo = function($name, *args, **opts)

&foo 'Picard', 'Admiral', 'flagship', ship: 'Enterprise'

# Inside:
# $name = 'Picard'
# $args = ['Admiral', 'flagship']
# $opts = {ship: 'Enterprise'}
```

At most one `*args` and one `**opts` per signature.

---

## Call-Site Splat Expansion

~~~vibecode
{"vibecode": {
    "section": "call_site_splat",
    "forms": ["*array_for_positional", "**hash_for_named"],
    "sigil_note": "*$args_and_*args_are_equivalent; the_$_is_optional_at_the_call_site"
}}
~~~

At the call site, `*` expands an array into positional arguments and `**`
expands a hash into named arguments. The `$` is optional in either form.

```
# Positional expansion
$args = ['Admiral', 'flagship']
&foo 'Picard', *$args
&foo 'Picard', *args    # same thing — the $ is optional at the call site

# Equivalent to:
&foo 'Picard', 'Admiral', 'flagship'

# Named expansion
$opts = {rank: 'Admiral', ship: 'Enterprise'}
&foo 'Picard', **$opts
&foo 'Picard', **opts   # same thing

# Equivalent to:
&foo 'Picard', rank: 'Admiral', ship: 'Enterprise'
```

---

## Calling Functions

~~~vibecode
{"vibecode": {
    "section": "calling",
    "call_types": ["positional", "named", "mixed"],
    "named_format": "public_name: value",
    "style_preference":
        "no_parens_when_return_value_unused; parens_when_return_value_captured_per_formatting_md"
}}
~~~

A function can be called positionally, with named arguments, or with a
mix:

```
# Positional
&foo 'Picard', 'Admiral'

# Named
&foo name: 'Picard', rank: 'Admiral'

# Mixed
&foo 'Picard', rank: 'Admiral'
```

**Style note.** The preferred form when the return value is unused omits
parens (`$foo.bar 1, 2, 3`); the preferred form when the return value is
captured uses parens (`$gup = $foo.bar(1, 2, 3)`). Parser-agnostic;
formatter-enforced.

---

## Positional-Until-Named Rule

~~~vibecode
{"vibecode": {
    "section": "positional_named_rule",
    "rule": "positional_until_named",
    "constraint": "no_positional_after_named"
}}
~~~

Arguments are positional until the first named argument. After a named
argument appears, all remaining arguments must be named.

```
# Valid
&foo 'Picard', 'Admiral'
&foo 'Picard', rank: 'Admiral'
&foo name: 'Picard', rank: 'Admiral'

# Invalid — positional after named
&foo name: 'Picard', 'Admiral'
```

---

## Valid Calls

Given `$foo = function($name, $rank: {optional: true}, $phrase)` (where
`$phrase` is implicitly optional via propagation):

```
&foo 'Picard'
&foo 'Picard', 'Admiral'
&foo 'Picard', rank: 'Admiral'
&foo 'Picard', phrase: 'engage'
&foo 'Picard', 'Admiral', phrase: 'engage'
```

---

## Invalid Calls

~~~vibecode
{"vibecode": {
    "section": "invalid_calls",
    "error_types": ["positional_after_named", "duplicate_assignment",
                    "unknown_named_when_no_**opts", "type_mismatch_when_classes_set"]
}}
~~~

```
# Positional after named
&foo name: 'Picard', 'Admiral'

# Duplicate assignment ($name set both positionally and by name)
&foo 'Picard', name: 'Riker'

# Unknown named (no **opts to absorb it)
&foo 'Picard', ship: 'Enterprise'
```

---

## Argument Binding Algorithm

~~~vibecode
{"vibecode": {
    "section": "binding_algorithm",
    "ordered_steps": ["bind_positional_left_to_right",
                       "enforce_no_positional_after_named",
                       "bind_named_by_public_name",
                       "error_on_duplicate",
                       "unknown_named_to_**opts_or_error",
                       "fill_optional_with_default_or_nil",
                       "enforce_classes_type_constraints"]
}}
~~~

When a call is made, the runtime binds arguments to parameters in this
order:

1. **Bind positional arguments left to right** until either positional
   arguments run out or a named argument appears.
2. **Enforce no positional after named.** If a positional argument
   follows a named one, raise an error.
3. **Bind named arguments by public name.** Each named argument matches
   the parameter whose public name equals the argument's keyword.
4. **Error on duplicate assignment.** A parameter cannot be assigned
   twice (once positionally and again by name).
5. **Unknown named arguments** flow into `**opts` if present, otherwise
   raise an error.
6. **Fill omitted optional parameters** with their `default` value or
   `nil`.
7. **Enforce `classes` type constraints** (and `nullable` permissions).
   A type mismatch raises an error.

---

## Definition Errors

~~~vibecode
{"vibecode": {
    "section": "definition_errors",
    "types": ["duplicate_public_name", "public_private_collision",
              "multiple_*args", "multiple_**opts"]
}}
~~~

These errors are raised when the function is defined (not when called):

```
# Duplicate public names
$foo = function($a: {public: 'x'},
                $b: {public: 'x'})

# Public/private collision
$foo = function($title_sent: {public: 'title'},
                $title)

# Multiple *args
$foo = function(*a, *b)

# Multiple **opts
$foo = function(**a, **b)
```

---

## Programmatic Access

~~~vibecode
{"vibecode": {
    "section": "programmatic_access",
    "api": "$foo.params['bar'].lazy = true",
    "storage": "params hash in %bucket",
    "key_format": "parameter_name_without_dollar_sign",
    "use_cases": ["frameworks", "validators", "generated_functions"]
}}
~~~

Every function object exposes a `params` hash in `%bucket`. Each key is a
parameter name (without `$`); each value is the param metadata object.

```
$foo = function($bar, $gup) do
end

$foo.params['bar'].lazy     = true
$foo.params['bar'].classes  = ['string', 'number']
$foo.params['gup'].optional = true
```

This allows param metadata to be built dynamically — useful for
frameworks, validators, and generated functions.

---

## Freezing Functions

~~~vibecode
{"vibecode": {
    "section": "freezing_functions",
    "concern": "functions_are_mutable_params_can_be_modified_by_anyone_with_reference",
    "freeze_all": "$foo.object.freeze",
    "freeze_params_only": "$foo.object.bucket.freeze",
    "note": "params_lives_in_%bucket_so_bucket_freeze_suffices"
}}
~~~

Since functions are mutable objects, `params` can be modified by anyone
with a reference to the function. Before passing a function around,
freeze it:

```
$foo.params['bar'].lazy = true   # configure
$foo.object.freeze               # lock everything
```

If you only want to lock the params without freezing the whole object:

```
$foo.object.bucket.freeze
```

Since `params` lives in `%bucket`, this is sufficient to prevent param
modification.

---

## Style Guidelines

~~~vibecode
{"vibecode": {
    "section": "style",
    "guidelines": ["required_first_optional_last", "avoid_aliasing",
                   "prefer_positional_for_simple_cases",
                   "use_named_for_clarity_in_calls_with_many_args",
                   "prefer_hash_splat_for_calls_with_several_named_args"],
    "nanny_note":
        "permissive_call_shape_mixing_declared_param_names_with_**opts_absorbed_names_in_arbitrary_order_is_allowed_but_carries_silent_typo_risk; hash_splat_style_recommended_as_partial_mitigation_per_slob_principle_developer_choice_visibly_recorded"
}}
~~~

- **Required parameters first, optional last.** Since `optional: true`
  propagates forward, putting a required parameter after an optional one
  silently re-marks it optional — confusing. Keep all required params at
  the start of the signature.
- **Avoid aliasing.** Use `public` to override the public name only when
  the private name would be a poor external API. Aliasing on a whim adds
  cognitive load.
- **Prefer positional arguments for simple calls.** `&greet 'Picard'` is
  cleaner than `&greet name: 'Picard'` when the function takes one
  argument and the argument's role is obvious.
- **Use named arguments for clarity** when a call passes many arguments,
  or when the meaning of a positional argument isn't obvious from
  context.
- **Prefer the hash-splat form for calls with several named arguments.**
  When a call would pass several named arguments inline — and
  especially when `**opts` is in play — build the argument hash
  explicitly and splat it with `**`:

  ```
  # Less preferred — names scattered across the call site
  &something name: 'Picard', rank: 'Captain', bar: 1

  # Preferred — names centralized in one auditable hash
  $args = {name: 'Picard', rank: 'Captain', bar: 1}
  &something **$args
  ```

  Mechanically these are identical (see
  [Call-Site Splat Expansion](#call-site-splat-expansion));
  stylistically the splat form is easier to scan and audit. The
  partial [nanny benefit](https://puck.uno/documentation/overview#no-nanny-code): a typo in a declared param name (e.g.,
  `ranck:` for `rank:`) still silently absorbs into `**opts`, but it
  happens in one centralized hash-construction line rather than
  scattered through the call site, so it's easier to spot during
  review.

Recommended signature shape:

```
$foo = function($required1,
                $required2,
                $optional1: {optional: true},
                $optional2)
```

(`$optional2` is implicitly optional via propagation.)

---

## Summary

~~~vibecode
{"vibecode": {
    "section": "summary",
    "core_rules": ["positional_until_named", "optional_propagates_forward",
                    "public_names_for_call_site_binding",
                    "no_duplicate_binding", "*args_and_**opts_supported",
                    "metadata_hash_form_equivalent_to_programmatic"]
}}
~~~

- Parameters are objects; metadata is a hash on each one.
- Inline metadata and programmatic access are equivalent.
- Positional binding until the first named argument; no positional after
  named.
- `optional: true` propagates forward; required params must come before
  optional ones.
- Public name (default: private name minus `$`) is used at the call site.
- `*args` and `**opts` capture remaining positional and named arguments.
- `*` and `**` at the call site expand arrays and hashes into arguments.
- `lazy: true` defers evaluation by wrapping the caller's expression in a
  zero-argument block.
- `classes` constrains type at call time; `nullable: true` permits `nil`
  even with `classes` set.

---

## Open Questions

- Should type checking be enforced at definition time (static) or call
  time (dynamic)? Current assumption: call time.
- Should `classes` accept a mix of built-in type names and UNS addresses
  in the same array?
- Are there additional metadata properties needed for keyword arguments
  specifically (e.g. documentation strings, units, validators)?
- Should setting a `default` value that's an expression evaluate at
  definition time (once) or at call time (per omission)? Current text
  doesn't say; probably definition time for simple values, but lazy
  for expressions that might depend on call-time context — not settled.
