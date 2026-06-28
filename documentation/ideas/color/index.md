# Color (pure-Caspian color library)

~~~vibecode
{"vibecode": {
	"doc": "color",
	"role": "brainstorm for puck.uno/color — a pure-Caspian color library built around the 'each color is a cell in a 256×256×256 cube' model; first consumer is the PNG handler, but any code that works with color uses it",
	"status": "brainstorm — no implementation yet",
	"ruby_reference": "/home/miko/projects/oberon/rgbcell/working (RGBCell, ~313 lines)",
	"key_concepts": ["cell_in_a_cube", "hex_or_name_construction", "alpha_recorded_not_modeled",
		"named_html_colors_supported", "mutable_with_validated_setters",
		"euclidean_distance", "stepwise_spectrum", "used_by_png"]
}}
~~~

**Status:** brainstorm. A pure-Caspian library at `puck.uno/color` (or just
`color`) for color values. First consumer is the [PNG handler](png.md);
anything else that works with color uses the same primitive. Ported from
the Ruby [RGBCell](file:///home/miko/projects/oberon/rgbcell/working)
library.

---

## The model: cell in a cube

Every color is a **cell in a 256×256×256 cube**. The cube is conceptual.
A color is three coordinates `(red, green, blue)` in that space. The model
is what makes the geometry work: distance is well defined, a straight line
between two cells is a spectrum, neighborhoods are spheres, and so on.

This is the single design idea the library exists to express. Everything
else falls out of it.

---

## Construction

Three forms — pick whichever reads best at the call site:

```caspian
# Hex string — 6 or 8 digits
$red = %['puck.uno/color'].new('#ff0000')
$translucent_red = %['puck.uno/color'].new('#ff0000ac')

# Name string — any of the standard HTML colors (~110)
$red = %['puck.uno/color'].new('red')
$purple = %['puck.uno/color'].new('rebeccapurple')

# UNS-as-name — every named color is its own UNS-addressable instance
$red = %['puck.uno/color/red']
$purple = %['puck.uno/color/rebeccapurple']
```

Hex forms:

- **6-digit** (`#rrggbb`) — color only. Alpha defaults to `0xff` (opaque).
- **8-digit** (`#rrggbbaa`) — color plus alpha. Alpha is recorded but
  does not participate in any color geometry; it rides along for
  compositing operations downstream.

---

## Accessors

```caspian
$red.red      # 255  — integer 0..255
$red.green    # 0
$red.blue     # 0
$red.alpha    # 255 (or whatever the alpha byte says)
$red.hex      # '#ff0000' (or '#ff0000ac' if alpha is non-default)
$red.name     # 'red' (or null if this cell has no standard name)
```

**Per-color predicates.** Every named HTML color gets a predicate; each
returns true if the cell matches that named color exactly.

```caspian
$red.red?         # true
$red.orange?      # false
$red.rebeccapurple?  # false
```

**Collection views.**

```caspian
$red.to_arr   # [255, 0, 0, 255]   — always 4 elements: [r, g, b, a]
$red.to_hash  # {red: 255, green: 0, blue: 0, alpha: 255, hex: '#ff0000', name: 'red'}
```

`to_hash` always includes `name`; the value is `null` when the cell has no standard name.

---

## Setters

Mutable. Each setter validates input; bad input raises.

```caspian
$red.green = 128       # OK
$red.green = 2928      # raises — out of range; must be 0..255
$red.green = 'bar'     # raises — wrong type; must be integer
$red.alpha = 200       # OK
```

After mutation, `.hex` and `.name` reflect the new cell. `.name` may
become `null` if the new coordinates don't match a standard color.

---

## The geometric operations

These are the showcase methods — the reason the cube model is worth having
in the first place:

```caspian
$red.distance($blue)               # Euclidean distance between cells
$red.spectrum_to($blue, steps: 8)  # array of 8 intermediate cells
```

Distance is straight Euclidean — it's what the cube gives you for free.
This doesn't match human perceptual distance (two cells at equal Euclidean
distance can look quite different, especially in the greens); perceptual
metrics are out of scope for V1 and live in a later add-on if needed.

Spectrum walks a straight line through the cube from one cell to another,
producing N intermediate cells. The endpoints are unambiguous; the
in-between cells are evenly spaced along the line.

---

## Random

A class-level method returns a uniformly random cell from the cube:

```caspian
%['puck.uno/color'].random   # any cell, uniform over [0,255]³
```

**With selectors.** Pass any number of [`sphere`](sphere.md) instances
to constrain the choice. The returned color must satisfy **every**
sphere's membership test (per each sphere's own `scope`):

```caspian
%['puck.uno/color'].random(
    $primary_zone,   # inside-sphere: pull toward this region
    $too_dark,       # outside-sphere: push away from this region
    $too_white,      # outside-sphere: push away from this one too
)
```

The intersection of all selectors defines the candidate set; the
returned color is uniform from that set. If the intersection is empty
(contradictory selectors), `.random` raises. See
[sphere.md § Use case: color scheme generator](sphere.md#use-case-color-scheme-generator)
for the worked example this enables.

---

## Open questions

- **More operations.** Beyond distance and spectrum, what else? `mix(a, b,
  weight)`, `lighten(amount)`, `darken(amount)`, `grayscale`, neighborhood
  enumeration? Each is a small addition but they accumulate.
- **Color space promise.** The cube interprets coordinates as sRGB by
  convention. Worth stating explicitly even though the library doesn't
  convert — so consumers know what to assume.
- **Spectrum endpoint inclusion.** Does `spectrum_to(other, steps: N)`
  include both endpoints in the returned array, neither, or one? (Ruby
  RGBCell's behavior is a place to start.)

---

## Reference

- **RGBCell** (Ruby) — `/home/miko/projects/oberon/rgbcell/working`.
  Constructor variants, accessors, hex/name helpers, terminal-escape (Bash)
  output. The Puck version carries over the named-color story; the
  bash-output surface could live as a separate add-on class.
- CSS color spec — for the hex grammar (`#rgb`, `#rrggbb`, `#rrggbbaa`)
  and the canonical list of named colors.
