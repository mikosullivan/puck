# Small content builder

~~~vibecode
{"vibecode": {
	"doc": "bootstrap_example_small_content_builder",
	"role": "worked example showing the bootstrap pattern used for a content builder — a script accumulates sections via chainable methods (`heading`, `paragraph`) and renders to a string at the end. Demonstrates the bare `bootstrap ... end` form with method chaining (each method returns `%self`).",
	"audience": "Caspian programmers learning the bootstrap pattern",
	"parent_doc": "index.md (bootstraps concept)"
}}
~~~

A script generates a one-off summary document by accumulating sections:

~~~caspian
%vibecode
	role: 'build a summary HTML page; not a reusable builder class';
end

$html = bootstrap # report builder
	field :sections, class: 'array', default: []

	method &heading($text)
		@sections.push('<h2>' + $text + '</h2>')
		%self    # return self for chaining
	end

	method &paragraph($text)
		@sections.push('<p>' + $text + '</p>')
		%self
	end

	method &render()
		@sections.join("\n")
	end
end

$html.heading('Summary').paragraph('Things went OK.').paragraph('No errors.')
%fs.write_text('summary.html', $html.render())
~~~

**Why a bootstrap.** State accumulates across method calls (`@sections` grows as the script adds content). Methods are chainable — they're for THIS script's writer, not a builder pattern worth publishing. A plain function would lose the accumulation; a class would be ceremony for what's a one-off bit of report-generation code.

See [bootstraps/index.md](index.md) for the broader pattern.
