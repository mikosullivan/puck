~~~vibecode
{"doc": "sprint-note", "sprint": "classes",
	"role": "A typical Caspian class definition, used as a grounding example for the classes sprint. Shows the syntax the parser will produce CaspM for, so downstream work has something concrete to reason about."}
~~~

# A typical class

A `person` class — has a name and age, can greet, knows if it can vote.

~~~caspian
# person
class
	method init(@name, @age)
	end

	method greet()
		return "Hello, I'm " + @name
	end

	method can_vote()
		return @age >= 18
	end
end
~~~

## The same class in CaspM

What the transpiler + normalizer produce for the class above. Real output — `transpiler.transpile` + `normalize.normalize` on the source, pretty-printed for readability:

~~~json
[
	[
		{"class": {
			"bd": [
				[{"method": {
					"name": "init",
					"pm": [{"name": "name"}, {"name": "age"}],
					"bd": [
						[
							{"in": "fc"},
							{"rc": {"sys": "bucket"}, "fn": "[]=",
							 "a": [{"v": "name"}, {"var": "name"}]}
						],
						[
							{"in": "fc"},
							{"rc": {"sys": "bucket"}, "fn": "[]=",
							 "a": [{"v": "age"}, {"var": "age"}]}
						]
					]
				}}],

				[{"method": {
					"name": "greet",
					"pm": [],
					"bd": [
						["scope", "return",
							[
								{"in": "fc"},
								{"rc": {"v": "Hello, I'm "}, "fn": "+",
								 "a": [
									[
										{"in": "fc"},
										{"rc": {"sys": "bucket"}, "fn": "[]",
										 "a": [{"v": "name"}]}
									]
								]}
							]
						]
					]
				}}],

				[{"method": {
					"name": "can_vote",
					"pm": [],
					"bd": [
						["scope", "return",
							[
								{"in": "fc"},
								{"rc": [
									{"in": "fc"},
									{"rc": {"sys": "bucket"}, "fn": "[]",
									 "a": [{"v": "age"}]}
								], "fn": ">=",
								 "a": [{"v": 18}]}
							]
						]
					]
				}}]
			]
		}}
	]
]
~~~

## What to notice

- **`class` is one atom** with a `bd` (body) full of statement rows. Each method is one statement row.
- **`method` atoms carry name, params, and body.** `pm` is the parameter list; `bd` is the method's own body.
- **`@name = $name` in `init` is a bucket subscript-set.** The auto-assign `@name` parameter normalizes into `%bucket['name'] = $name` — the CaspM `{in: "fc"}, {rc: {sys: "bucket"}, fn: "[]=", a: [{v: "name"}, {var: "name"}]}`.
- **`@name` (read) is `%bucket['name']`.** Same shape: an `fc` on `%bucket` with `fn: "[]"`.
- **Operators desugar to `fc` calls.** `+` and `>=` are both normalized to `{in: "fc"}` calls; the operator name goes in `fn`, the LHS in `rc`, the RHS in `a`.
- **Method bodies with `return` wrap in `["scope", "return", ...]`.** The `scope` marker signals the body has its own scope frame; the walker uses this to set up scope[0] on entry.
