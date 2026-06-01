# Caspian syntax

~~~json
{"vibecode": {
	"doc": "syntax",
	"role": "umbrella landing page for Caspian syntax topics. Per-construct references that complement the language spec in caspian.md."
}}
~~~

Per-topic syntax references. The big-picture spec lives in
[caspian.md](../index.md); this directory breaks it out by
construct so each topic gets its own page.

- **[Assignment operators](assignment-operators.md)** — `=`, `&=`,
  compound forms.
- **[Class definition](../index.md#classes)** — `class` /
  `inherits` / `field` / `accessor` / `helper`. (The JSON form is
  spec'd in [mikobase/class-definition.md](../../mikobase/class-definition.md).)
- **[Loops](loops.md)** — `while`, `do`, `as`, loop-object methods.
- **[Operators](operators.md)** — arithmetic, comparison, logical,
  pipes.
- **[Parameters](parameters.md)** — call binding, public names,
  `*args` / `**opts`, splats, errors.
- **[Pipes](pipes.md)** — the `|` and `|&` operators.
- **[Regexes](regexes.md)** — pattern syntax.
- **[System methods](system-methods.md)** — `%engine`, `%utils`,
  `%call`, `%forks`, etc.
