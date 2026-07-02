# Closures
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_closures",
	"role": "spec for Caspian's `closure` keyword — callable that captures the enclosing scope, letting the body read and mutate outer variables. Same return semantics as functions.",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

A **closure** captures the enclosing scope. Unlike a [function](https://puck.uno/documentation/requirements/caspian/syntax/functions-and-closures/functions), its body can read (and write, when the outer scope is mutable) variables defined outside its parameter list.

## Definition

~~~caspian
$tag = 'debug'

$log = closure($msg)
	&puts $tag + ': ' + $msg      # $tag is captured from the outer scope
	return null
end

&log 'starting up'                 # prints "debug: starting up"
~~~

The closure is stored in `$log` and invoked with the usual `&log args` form. Each closure literally carries a reference to the outer scope; if the outer scope changes after the closure is defined, the closure sees the change.

~~~caspian
$counter = 0

$bump = closure()
	$counter += 1                 # writing to a captured variable is fine
	return null
end

&bump                              # $counter is now 1
&bump                              # $counter is now 2
~~~

## Scope rules

- **Read:** any variable visible in the enclosing scope is visible inside the closure body.
- **Write:** assignments inside the closure body affect the captured variable in the outer scope. `$counter += 1` inside the closure updates the outer `$counter`.
- **Shadowing:** a parameter with the same name as an outer variable shadows the outer for the duration of the call. Parameter binding wins; outer-scope binding is invisible while the parameter is in scope.

## Return value

Same as functions: the last expression in the body is the return value; use `%call.return $value` for actual early exit.
