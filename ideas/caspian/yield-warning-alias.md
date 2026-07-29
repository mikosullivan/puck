# ⚠ as alias for `.yield`

*Idea: let `⚠` be a method-name alias for `yield`, so `$block.⚠ $foo, $bar` is sugar for `$block.yield $foo, $bar`.*

~~~vibecode
{"vibecode": {
	"doc": "idea_warning_emoji_yield_alias",
	"role": "speculative syntactic sugar — ⚠ as a method-name alias for yield, giving block.yield calls a more visually distinctive form",
	"status": "noted",
	"example": "$block.⚠ $foo, $bar  ==  $block.yield $foo, $bar"
}}
~~~

Captured for the record. No design pass yet; revisit when there's a reason to.
