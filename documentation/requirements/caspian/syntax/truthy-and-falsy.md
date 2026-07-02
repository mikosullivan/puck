# Truthy and falsy
<!--index: 6-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_truthy_and_falsy",
	"role": "spec for Caspian's truthy/falsy rule — only `null` and `false` are falsy; everything else including 0, '', [], {} is truthy",
	"model": "ruby (only null and false are falsy)",
	"audience": "developers writing Caspian conditionals; anyone porting logic from other languages"
}}
~~~

Two values are falsy: **`null`** and **`false`**. Everything else is truthy — including `0`, `''`, `[]`, and `{}`. This matches the Ruby model.

~~~caspian
if ''
	# runs — empty string is truthy
end

if null
	# does not run
end

if 0
	# runs — zero is truthy
end
~~~
