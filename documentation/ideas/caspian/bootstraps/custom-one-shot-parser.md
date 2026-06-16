# Custom one-shot parser

~~~vibecode
{"vibecode": {
	"doc": "bootstrap_example_custom_one_shot_parser",
	"role": "worked example showing the bootstrap pattern used for a one-off parser — a script processes a small custom markup format used only here, and uses `bootstrap(:parse, $source)` to construct-and-run in one expression. Demonstrates the with-method-invocation form (returns the method's return value).",
	"audience": "Caspian programmers learning the bootstrap pattern",
	"parent_doc": "index.md (bootstraps concept)"
}}
~~~

A script processes a small custom markup format used only here. The parsing logic isn't worth publishing as a class:

~~~caspian
%vibecode
	role: 'parse a one-off markup format used only by this report script';
end

$ast = bootstrap(:parse, $source) # markup parser
	field :pos, class: 'integer', default: 0

	method &parse($input)
		@pos = 0
		# ... walk the input, build the tree ...
		# returns the parse tree
	end

	method &expect($ch)
		if @input.char_at(@pos) != $ch
			%self.error('expected ' + $ch)
		end
		@pos = @pos + 1
	end
end
~~~

**Why a bootstrap.** The parser has real state (position, error context, partial tree) and methods that call each other recursively. Plain functions would thread `$pos, $errors, $tree` through every call — noise. A class would imply "MarkupParser is a thing in the system" — but it isn't; it's just this report script's helper. The `bootstrap(:parse, $source)` form captures the actual intent: "parse this." The parser exists only as long as it takes to do the work.

See [bootstraps/index.md](index.md) for the broader pattern.
