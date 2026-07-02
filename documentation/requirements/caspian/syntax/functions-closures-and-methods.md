# Functions, closures, and methods
<!--index: 9-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_functions_closures_and_methods",
	"role": "spec for the three callable-definition forms — `function` (closed scope), `closure` (captures outer scope), and `method` (inside a class). The `function &name` sugar and the implicit-last-expression return idiom.",
	"scope_rules": {"function": "no outer scope", "closure": "captures outer scope", "method": "either, inside a class"},
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

Three constructs, each with a specific scope rule:

- **`function`** — self-contained; sees only its parameters. No access to the enclosing scope.
- **`closure`** — captures the enclosing scope; can read (and write, if the scope is mutable) outer variables.
- **`method`** — a function or closure defined inside a class.

Definition forms:

~~~caspian
# named function
function &greet($name)
    &puts 'hi, ' + $name
end

# anonymous function stored in a variable
$doubler = function($n)
    $n * 2
end

# closure that captures $tag
$tag = 'debug'
$log = closure($msg)
    &puts $tag + ': ' + $msg
end

# method inside a class
class # widget
    method &init($name)
        @name = $name
    end
    method &greet()
        &puts 'hello from ' + @name
    end
end
~~~

`function &name` is sugar for `$name = function`, so `&name` invokes it.

The last expression in a body is the return value — no explicit `return` needed. Use `%call.return $value` for actual early exit.
