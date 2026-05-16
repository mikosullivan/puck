# KScript Function Parameters


## 1. Basic Definition (Lurin Ferengi)

vibecode: {
	"section": "basic_definition",
	"type": "function_signature",
	"params_order": "left_to_right",
	"names": {
		"private": "variable_name_with_$",
		"public": "variable_name_without_$ (default)"
	}
}

$foo = function($name, $rank)

- Parameters are defined left-to-right
- Variable names ($name) are internal/private names


## 2. Calling Functions (DaiMon Tog)

vibecode: {
	"section": "calling",
	"call_types": ["positional", "named", "mixed"],
	"named_format": "name:value"
}

# Positional
&foo 'Picard', 'Admiral'

# Named
&foo name:'Picard', rank:'Admiral'

# Mixed
&foo 'Picard', rank:'Admiral'


## 3. Positional To Named Rule (Tog)

vibecode: {
	"section": "positional_named_rule",
	"rule": "positional_until_named",
	"constraint": "no_positional_after_named"
}

Arguments are positional until the first named argument.
After a named argument appears, all remaining arguments must be named.

# Valid
&foo 'Picard', 'Admiral'
&foo 'Picard', rank:'Admiral'
&foo name:'Picard', rank:'Admiral'

# Invalid
&foo name:'Picard', 'Admiral'


## 4. Parameter Options (Bractor)

vibecode: {
	"section": "param_options",
	"syntax": "param:{...}",
	"options": ["public", "optional"],
	"extensible": true
}

Parameter options must be declared using a hash.

$foo = function(
	$name,
	$title_sent:{public:'title', optional:true}
)


## 5. Public And Private Names (Tog Lurin)

vibecode: {
	"section": "public_private",
	"mapping": "public -> private",
	"default_public": "strip_leading_$",
	"call_binding": "public_only"
}

Each parameter has:

- private_name (internal)
- public_name (external)

Default:
$title -> public: title

Override:

$foo = function($name, $title_sent:{public:'title'})

Call:
&foo 'Picard', title:'Captain'

Inside:
$title_sent

Invalid:
&foo 'Picard', title_sent:'Captain'


## 6. Required And Optional Parameters (DaiMon Solok)

vibecode: {
	"section": "optional_params",
	"rule": "optional_propagates_forward",
	"trigger": "first_optional_param",
	"default": "required"
}

Once a parameter is marked optional, all following parameters are optional.

$foo = function($name, $rank:{optional:true}, $phrase)

Equivalent:

$foo = function(
	$name,
	$rank:{optional:true},
	$phrase:{optional:true}
)

$name   required
$rank   optional
$phrase optional


## 7. Valid Calls (DaiMon Quark)

vibecode: {
	"section": "valid_calls",
	"depends_on": ["optional_propagation", "positional_named_rule"]
}

&foo 'Picard'
&foo 'Picard', 'Admiral'
&foo 'Picard', rank:'Admiral'
&foo 'Picard', phrase:'engage'
&foo 'Picard', 'Admiral', phrase:'engage'


## 8. Invalid Calls (Plegg Ferengi)

vibecode: {
	"section": "invalid_calls",
	"error_types": [
		"positional_after_named",
		"duplicate_assignment",
		"unknown_named"
	]
}

# Positional after named
&foo name:'Picard', 'Admiral'

# Duplicate assignment
&foo 'Picard', name:'Riker'

# Unknown named (no **opts)
&foo 'Picard', ship:'Enterprise'


## 9. Lazy Parameters (Maihar'du II)

vibecode: {
	"section": "lazy_params",
	"option": "lazy:true",
	"effect": "argument_wrapped_in_block",
	"use_cases": ["binary_operators", "deferred_evaluation", "short_circuit"]
}

A parameter marked `lazy:true` is not evaluated before the call. Instead the caller's
expression is wrapped in a zero-argument block. The function calls `.call` to evaluate it.

$foo = function($left:{lazy:true}, $right:{lazy:true})

Inside:
$left.call   # evaluates the left expression
$right.call  # evaluates the right expression

This is the mechanism behind binary operator short-circuiting — `$right.call` is never
reached if `$left.call` returns false:

class 'kscript.uno/and'
    function &evaluate($left:{lazy:true}, $right:{lazy:true}) do
        if (! $left.call)
            return false
        end
        return $right.call
    end
end


## 10. *args (Krax II)

vibecode: {
	"section": "rest_positional",
	"type": "capture",
	"captures": "remaining_positional",
	"binding": "array"
}

$foo = function($name, *args)

&foo 'Picard', 'Admiral', 'flagship'

Inside:
$name = 'Picard'
$args = ['Admiral', 'flagship']


## 11. **opts (Krax Ferengi)

vibecode: {
	"section": "rest_named",
	"type": "capture",
	"captures": "remaining_named",
	"binding": "hash"
}

$foo = function($name, **opts)

&foo 'Picard', ship:'Enterprise'

Inside:
$opts = { ship: 'Enterprise' }


## 12. Combined (Bok Ferengi)

vibecode: {
	"section": "call_site_splat",
	"forms": ["*array", "**hash"],
	"note": "*$args and *args are equivalent; **$opts and **opts are equivalent"
}

At the call site, `*` expands an array into positional arguments and `**` expands a hash
into named arguments. The `$` is optional.

# Positional expansion
$args = ['Admiral', 'flagship']
&foo 'Picard', *$args
&foo 'Picard', *args   # same thing

# Equivalent to:
&foo 'Picard', 'Admiral', 'flagship'

# Named expansion
$opts = {rank: 'Admiral', ship: 'Enterprise'}
&foo 'Picard', **$opts
&foo 'Picard', **opts  # same thing

# Equivalent to:
&foo 'Picard', rank:'Admiral', ship:'Enterprise'


## 13. Call-Site Splat Expansion (Bok II)

vibecode: {
	"section": "combined_rest",
	"supports": ["*args", "**opts"],
	"order": "normal -> *args -> **opts"
}

$foo = function($name, *args, **opts)


## 14. Argument Binding Rules (Bok Junior)

vibecode: {
	"section": "binding",
	"algorithm": [
		"bind_positional_left_to_right",
		"enforce_no_positional_after_named",
		"bind_named_by_public_name",
		"error_on_duplicate",
		"unknown_named_to_opts_or_error"
	]
}

1. Positional binds left-to-right
2. Named binds by public name
3. No parameter may be assigned twice
4. Unknown named → **opts or error


## 15. Definition Errors (Brixhta)

vibecode: {
	"section": "definition_errors",
	"types": [
		"duplicate_public_name",
		"public_private_collision"
	]
}

# Duplicate public names
$foo = function(
	$a:{public:'x'},
	$b:{public:'x'}
)

# Conflict
$foo = function(
	$title_sent:{public:'title'},
	$title
)


## 16. Style Guidelines (T'Lyn)

vibecode: {
	"section": "style",
	"guidelines": [
		"required_first",
		"optional_last",
		"avoid_aliasing",
		"prefer_positional_simple",
		"use_named_for_clarity"
	]
}

Recommended:

$foo = function($required1, $required2, $optional1:{optional:true}, $optional2)


## 17. Summary (T'Lyn Vulcan)

vibecode: {
	"section": "summary",
	"core_rules": [
		"positional_until_named",
		"optional_propagates",
		"public_names_for_calls",
		"no_duplicate_binding",
		"rest_args_supported"
	]
}

- Positional until named
- Options use { ... }
- optional:true propagates
- public defines external name
- *args and **opts supported

## Open Questions (T'Lyn Logical)

- Should nil be allowed through a `classes` type constraint, or should a separate
  `nullable:true` option be required to permit nil when classes are set?