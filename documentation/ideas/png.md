# PNG handler (pure Charlie)

~~~json
{"vibecode": {
	"doc": "png",
	"role": "brainstorm for a pure-Charlie PNG encoder/decoder, intended to ship as a Puck service at puck.uno; foundation for downstream image work including QR codes",
	"status": "brainstorm — no implementation yet",
	"reference_impl": "https://github.com/wvanbergen/chunky_png (pure-Ruby PNG)",
	"key_concepts": ["pure_charlie", "no_native_deps", "png_encoder_decoder",
		"drawing_primitives", "puck_uno_service"]
}}
~~~

**Status:** brainstorm. A pure-Charlie PNG handler available as a Puck
library at `puck.uno/png`. Downstream applications (QR codes, badges, small
charts, anything that wants to emit a PNG without pulling in `libpng`) layer
on top.

---

## Why pure-Charlie

- **No native dependency.** No FFI, no shelling out to `libpng` or
  ImageMagick. Works wherever Charlie runs.
- **Foundation for image work.** PNG is the on-ramp to broader image
  handling in Charlie; other image classes can layer on the same primitive.
- **Reference exists.** [chunky_png](https://github.com/wvanbergen/chunky_png)
  is a small, well-respected pure-Ruby PNG library. Roughly 3000 lines of
  Ruby — Charlie should land in a comparable range.

---

## Sketch

Three layers:

1. **Color.** A separate library at [`puck.uno/color`](color/) that
   provides the color objects PNG (and other image consumers) work with.
2. **PNG bytes ↔ Charlie image object.** Encode and decode the PNG container
   format — signature, IHDR, IDAT (deflate-compressed pixel data), IEND, plus
   the optional chunks (palette, transparency, gamma). A `puck.uno/png` class
   with `encode($pixels)` / `decode($bytes)`.
3. **Drawing primitives.** Set/get pixel, draw rectangle, fill, line. Enough
   to compose simple images (QR matrices, badges, sparkline strips) without
   needing a full graphics library.

A QR encoder would sit on top as a separate Puck object that emits a 2D bit
matrix and hands it to the drawing primitives.

---

## Open questions

- **Deflate.** PNG IDAT chunks are zlib-compressed. Pure-Charlie deflate is
  non-trivial. Options: (a) implement it; (b) bind to a host deflate; (c)
  start with uncompressed PNG (legal but oversized) and add deflate later.
- **Color models.** Grayscale, palette, RGB, RGBA, with/without alpha. Pick a
  minimum viable set and grow. 1-bit grayscale alone covers the immediate QR
  use case; full RGBA opens broader image work.
- **CRC32.** PNG uses CRC32 per chunk — another small primitive to implement
  in pure Charlie. Useful beyond PNG too.
- **Service shape.** Is the puck.uno endpoint a single `png.encode(pixels:)`
  call returning bytes, or a richer stateful object with width/height/format
  set up first then a final `.bytes`?
- **Drawing primitive API.** Mutable pixel buffer (`$img.set(x, y, color)`)
  versus functional builder (`$img.with_pixel(x, y, color)` returning a new
  image)? Mutable is closer to how `chunky_png` works.

---

## Reference

[wvanbergen/chunky_png](https://github.com/wvanbergen/chunky_png) — pure-Ruby
PNG. Read for chunk-handling patterns, encode/decode API shape, color-model
choices, and how it handles deflate via Ruby's stdlib zlib (a dependency we
won't have an exact analog to).
