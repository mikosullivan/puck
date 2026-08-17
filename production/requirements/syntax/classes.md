# Classes
<!--index: 10-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_classes",
	"role": "spec for Caspian's class definition syntax — the nameless `class` keyword, the inline `# label` convention for readability, method definitions inside, and instantiation via `.new()`. Class inheritance has its own sub-page.",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

Class definitions have no name in the language — they're objects assigned to variables. An inline `# label` after the `class` keyword is a convention for readability, since classes don't carry a name syntactically:

~~~caspian
$widget = class # widget
	method &init($name, $rank)
		@name = $name
		@rank = $rank
		return null
	end

	method &greet()
		puts 'hi, ' + @name
		return null
	end
end

$w = $widget.new('picard', 'captain')
$w.greet()
~~~

Instantiation is `$class.new(...)`. When the class defines an `&init` method, `.new()` runs it with the supplied arguments after the instance is allocated.

`@name` inside a method reads and writes `%bucket['name']` on the current instance — `@` is the sigil for bucket access.

## Testing

- **Empty class parses** — `class; end` produces a class object.
- **Class with only a label parses** — `class # widget; end` parses; the `# widget` inline label is treated as a readability hint, not code.
- **Class assigned to a variable is a first-class value** — `$c = class; end; $c` returns the class object.
- **Class with only `&init` parses** — `class; method &init(); return null; end; end` parses.
- **Class with only fields parses** — a class body that only writes `@x = 1` inside `&init` parses.
- **Class with only non-init methods parses** — a class with just `method &greet()` and no `&init` parses.
- **Class with both `&init` and other methods parses** — the full example on this page parses without error.
- **`.new` with no `&init` returns an instance** — a class with no `&init` still allocates via `.new()`.
- **`.new` invokes `&init` when defined** — `.new('a', 'b')` on a class with `&init($x, $y)` binds `@x = 'a'` and `@y = 'b'`.
- **`.new` passes arguments positionally to `&init`** — `.new('picard', 'captain')` places `'picard'` in the first parameter and `'captain'` in the second.
- **Method call on instance dispatches to the class's method** — `$w = $widget.new('picard', 'captain'); $w.greet()` runs the class's `&greet` method.
- **`@name` inside a method reads the current instance's bucket entry** — after `&init` sets `@name = 'picard'`, calling a method that returns `@name` returns `'picard'`.
- **`@name = value` inside a method writes to the current instance's bucket** — `.promote('admiral')` on an instance updates `@rank` visibly on subsequent reads.
- **`@field` outside a method raises** — `@field` at the top level of a script raises (no `%bucket` in that scope).
- **Two instances have independent buckets** — `$a = $c.new('x'); $b = $c.new('y')` — reading `@name` via each instance's method returns `'x'` and `'y'` respectively.
- **Method with wrong arity raises** — `$w.greet('extra')` when `&greet()` takes no args raises.
- **`.new` with wrong arity for `&init` raises** — `.new()` on a class whose `&init` requires two args raises.
- **Undefined method on instance raises** — `$w.nonexistent()` raises.
- **Class defined inside a bare block is still a first-class value** — `$c = begin; class; end; end; $c.new()` works.
- **Class body opens a fresh scope** — a `$local` declared inside `class ... end` is not reachable outside the class body.
- **Class value has an identity** — `$c1 = class; end; $c2 = class; end` — `$c1 == $c2` is `false` (distinct class objects).
- **Instance is distinct from its class** — `$w = $widget.new('a', 'b'); $w == $widget` is `false`.
- **`&init` return value is ignored by `.new`** — even if `&init` returns a non-null value, `.new` returns the newly-allocated instance.
- **Unterminated `class` raises at parse time** — `class` with no matching `end` fails to parse.
