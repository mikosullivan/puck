# Variables and assignment
<!--index: 4-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_variables_and_assignment",
	"role": "spec for variable declaration and assignment in Caspian — the `=` operator, assignment targets, compound-assignment sugar, and the scope of `$foo` bindings",
	"audience": "developers writing Caspian; anyone building a formatter or linter that needs to understand assignment shape"
}}
~~~

Declaration and assignment are one step. Assignment targets can be a variable, an object property, a hash entry, or an array element.

~~~caspian
$x = 10
$x = $x + 1
$x += 1                    # compound-assignment sugar

$obj.name  = 'alice'       # property
$hash['k'] = 'v'           # hash entry
$arr[0]    = 99            # array index

$flag ||= 'default'        # assign only if $flag is falsy
~~~

Compound operators (`+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `||=`, `&&=`) all desugar to read-modify-write around plain `=`.

Local variables (`$foo`) are scoped to the enclosing function or closure. A top-level `$foo` in a script persists for the run of the script.

## Testing

- **Simple assignment binds a local** — `$x = 10; $x` returns `10`.
- **Reassignment replaces the binding** — `$x = 1; $x = 2; $x` returns `2`.
- **Reading an undeclared variable raises** — `$never_set` at the top of a fresh scope raises undeclared-variable.
- **`+=` on integer** — `$x = 5; $x += 3; $x` returns `8`.
- **`-=` on integer** — `$x = 5; $x -= 3; $x` returns `2`.
- **`*=` on integer** — `$x = 4; $x *= 3; $x` returns `12`.
- **`/=` on integer** — `$x = 12; $x /= 3; $x` returns `4`.
- **`%=` on integer** — `$x = 10; $x %= 3; $x` returns `1`.
- **`**=` on integer** — `$x = 2; $x **= 3; $x` returns `8`.
- **`||=` assigns when LHS is falsy** — `$flag = null; $flag ||= 'default'; $flag` returns `'default'`.
- **`||=` leaves LHS alone when truthy** — `$flag = 'set'; $flag ||= 'default'; $flag` returns `'set'`.
- **`||=` treats `0` as truthy (no reassignment)** — `$flag = 0; $flag ||= 'default'; $flag` returns `0`.
- **`&&=` assigns when LHS is truthy** — `$flag = 1; $flag &&= 'set'; $flag` returns `'set'`.
- **`&&=` leaves LHS alone when falsy** — `$flag = null; $flag &&= 'set'; $flag` returns `null`.
- **Compound assignment on undeclared variable raises** — `$never += 1` raises undeclared-variable.
- **Property assignment via dot** — `$obj.name = 'alice'; $obj.name` returns `'alice'`.
- **Hash-entry assignment** — `$h = {}; $h['k'] = 'v'; $h['k']` returns `'v'`.
- **Array-index assignment** — `$a = [0, 0, 0]; $a[0] = 99; $a[0]` returns `99`.
- **Array-index assignment beyond current length raises or extends per spec** — set `$a[10] = 5` on a three-element array and check the observable behavior.
- **Chained property assignment** — `$obj.inner.name = 'x'; $obj.inner.name` returns `'x'`.
- **Compound assignment on property** — `$obj.count = 5; $obj.count += 1; $obj.count` returns `6`.
- **Compound assignment on hash entry** — `$h['n'] = 5; $h['n'] += 1; $h['n']` returns `6`.
- **Compound assignment on array index** — `$a = [5]; $a[0] += 1; $a[0]` returns `6`.
- **Variable name is case-sensitive** — `$foo` and `$Foo` are distinct names (though Miko convention is lowercase-only).
- **Function-local variable does not leak to caller** — a `$x` set inside a function is not readable after the call returns.
- **Closure-local variable does not leak to enclosing scope** — a `$x` first-set inside a closure body is not readable outside.
- **Enclosing variable is writable from a closure** — a closure that assigns to a variable declared in the enclosing scope writes through to the outer binding.
- **Top-level `$foo` persists for the run of the script** — a top-level `$foo` set on line 1 is readable from later top-level lines.
- **Assignment to unparseable target raises at parse time** — `5 = $x` fails to parse.
- **`||=` on undeclared variable behavior** — `$never ||= 'x'` — check whether it raises undeclared-variable or declares-and-assigns per spec.
- **Multiple assignments on separate lines each take effect** — `$x = 1; $x = 2; $x = 3; $x` returns `3`.
- **Assignment where RHS raises leaves LHS unset if not previously declared** — a raise mid-expression does not create the variable.
