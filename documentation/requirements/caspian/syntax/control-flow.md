# Control flow
<!--index: 7-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_control_flow",
	"role": "spec for Caspian's control-flow keywords — if/elsif/else, while, until — plus the DSL-registered loop-control words break and next",
	"audience": "parser implementers; developers writing Caspian"
}}
~~~

~~~caspian
if $age < 13
	&puts 'child'
elsif $age < 18
	&puts 'teen'
else
	&puts 'adult'
end

while $x < 10
	$x += 1
end

until $ready
	&poll
end
~~~

`elsif` and `elseif` are both accepted. There is no `for X in Y` — iterate by calling `.each` on a collection (see [blocks-and-iteration](https://puck.uno/documentation/requirements/caspian/syntax/blocks-and-iteration)).

`break` exits the nearest enclosing loop; `next` skips to the next iteration. Both are DSL entries registered by the loop, not language-level keywords.
