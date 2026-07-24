# convert

*Wraps the `convert` CLI utility from ImageMagick — image format conversion and transformation. Class at `caspian.uno/linux/cli/convert`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_convert",
	"role": "spec for the convert class at caspian.uno/linux/cli/convert — command-builder wrapper around the `convert` CLI utility (ImageMagick). Priority 12 in the CLI wrappers list. ImageMagick's flag surface is enormous and ORDER-SENSITIVE — an operation applies to the image state at the point it appears in argv — so the wrapper's shape needs to preserve ordering, not just accumulate a hash.",
	"status": "stub — method surface, ordered-operations model (list of {op, args} rather than property assignment), ImageMagick-vs-GraphicsMagick compat TBD",
	"audience": "developers converting or transforming images; the convert wrapper author"
}}
~~~

Stub.

## The order-sensitivity gotcha

Unlike most CLI wrappers, `convert`'s flags are position-sensitive — `convert in.png -resize 50% -blur 0x2 out.jpg` blurs the resized image, `-blur 0x2 -resize 50%` blurs first and resizes the blurred image. The wrapper's shape must preserve that ordering. A plain property-assignment builder loses it; the natural fit is an operations list — `$c.op :resize, '50%'; $c.op :blur, '0x2'` — that argv-builds in append order.

## Common flags to expose

- **Positional** — input file first, output file last (that's the calling convention).
- **`-resize <geometry>`** — resize per an ImageMagick geometry string.
- **`-crop <geometry>`** — crop per a geometry string.
- **`-quality <n>`** — JPEG / WEBP / PNG quality.
- **`-density <n>`** — DPI for input/output.
- **`-format <fmt>`** — force output format (redundant when the output filename has an extension).
- **`-strip`** — remove metadata.
- **`-background <color>`** — background for transparent conversions.

## ImageMagick vs GraphicsMagick

`convert` is ImageMagick. GraphicsMagick (`gm convert`) is a fork with a different flag surface — the wrapper doesn't attempt to abstract over both. A separate `gm` wrapper would be the future path if GraphicsMagick support becomes wanted.

## Method surface

TBD. `$c = %('caspian.uno/linux/cli/convert').new $input, $output; $c.op :resize, '50%'; $c.op :blur, '0x2'` — operations append in order; `.execute` renders argv from the list. A convenience `.new.convert($input, $output)` handles the pure format-conversion case with no transformations.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
