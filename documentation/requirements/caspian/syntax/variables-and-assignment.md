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
