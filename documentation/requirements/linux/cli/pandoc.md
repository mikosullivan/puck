# pandoc

*Wraps the `pandoc` CLI utility — universal document format converter (markdown, html, docx, pdf, latex, rst, ...). Class at `caspian.uno/linux/cli/pandoc`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_pandoc",
	"role": "spec for the pandoc class at caspian.uno/linux/cli/pandoc — command-builder wrapper around the `pandoc` CLI utility. Priority 11 in the CLI wrappers list. Pandoc's flag surface is enormous; the wrapper spec should scope aggressively — the common conversions first, everything else via a raw-flags escape hatch.",
	"status": "stub — method surface, from/to format enumeration (subset of pandoc's dozens of formats), template / filter surfacing TBD",
	"audience": "developers converting between document formats; the pandoc wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-f <format>` / `--from`** — source format (markdown, html, docx, rst, ...).
- **`-t <format>` / `--to`** — target format.
- **`-o <path>`** — output file.
- **`-s` / `--standalone`** — produce a standalone document (with header / footer / boilerplate).
- **`--template=<path>`** — use a specific template.
- **`--metadata=key:value`** — set document metadata.
- **`--pdf-engine=<engine>`** — pick the PDF engine (weasyprint, xelatex, wkhtmltopdf, ...) when the target is pdf.

## Method surface

TBD. Builder with `from`, `to`, `input`, `output`, `standalone`, `template`, `metadata`, `pdf_engine`, plus a raw `extra_args` array for the long tail. A convenience `.convert($input, $output)` that infers `from` / `to` from file extensions handles the common case without the builder.

## OS-level dependencies

Pandoc pulls in additional binaries for some target formats — most notably a PDF engine (weasyprint / xelatex / etc.) when producing pdf. The wrapper doesn't ship those; if the requested pipeline needs a missing engine, `pandoc` itself raises and the wrapper surfaces the error.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [downloads/markdown](https://puck.uno/documentation/requirements/downloads/markdown) — pure-Caspian markdown handling for the read-and-parse case.
