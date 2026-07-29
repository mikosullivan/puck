# Color sphere

~~~vibecode
{"vibecode": {
	"doc": "sphere",
	"role": "brainstorm for puck.uno/color/sphere — a spherical region in the color cube; pairs with the color class to express 'colors near' and 'colors away from' constraints",
	"status": "brainstorm — no implementation yet",
	"key_concepts": ["sphere_region", "center_radius_scope", "cube_clipped",
		"inclusive_radius", "scope_inside_or_outside", "membership_predicates",
		"random_with_selectors", "color_scheme_use_case"]
}}
~~~

**Status:** brainstorm. A pure-Caspian class at `puck.uno/color/sphere` (or
just `sphere`) representing a spherical region of color space. Pairs with
the [color class](./) to express constraints like "any color near this
one" or "any color away from these."

---

## The model

A sphere is **a center + a radius + a scope.** The center is a color cell;
the radius is a non-negative number; the scope is `"inside"` (default) or
`"outside"`.

- **`scope: "inside"`** — the sphere represents all in-cube cells whose
  Euclidean distance from the center is ≤ radius. (Radius is inclusive.)
- **`scope: "outside"`** — the sphere represents all in-cube cells whose
  Euclidean distance from the center is > radius. The complement of the
  inside scope, within the cube.

Cube-clipped throughout: a sphere whose mathematical extent goes beyond
the [0, 255]³ cube only counts cells that are actually in the cube.

---

## Construction

```caspian
$near_red = %('puck.uno/color/sphere').new(center: $red, radius: 20)
$away_red = %('puck.uno/color/sphere').new(center: $red, radius: 20, scope: 'outside')
```

`center` is a `puck.uno/color` instance; `radius` is a number; `scope`
defaults to `"inside"`.

---

## Accessors

```caspian
$sphere.center   # the Color instance at the center
$sphere.radius   # the radius
$sphere.scope    # 'inside' or 'outside'
```

---

## Membership predicates

Three predicates — two pure geometric, one scope-aware:

```caspian
$sphere.contains?($color)   # true iff $color is within radius (geometric)
$sphere.excludes?($color)   # true iff $color is beyond radius (geometric)
$sphere.scoped?($color)     # true iff $color is in the sphere's member set per scope
```

`contains?` and `excludes?` are exact complements (exactly one is true for
any color). `scoped?` is the user-facing membership check that respects
scope: with `scope: "inside"` it equals `contains?`, with `scope:
"outside"` it equals `excludes?`.

---

## Random

```caspian
$sphere.random   # a uniform random cell from the sphere's member set
```

Respects scope: `inside` picks a random in-cube cell within radius;
`outside` picks a random in-cube cell beyond radius.

---

## Use case: color scheme generator

A common use is defining a color palette by picking from soft regions:
"give me a primary somewhere near this hue, a secondary somewhere near
that hue, with a few regions of color I want to avoid." Selectors map
naturally to spheres — inside-spheres pull the choice toward where you
want, outside-spheres push it away from where you don't.

```caspian
# Aesthetic targets — broad regions, not exact colors.
$primary_zone   = %('puck.uno/color/sphere').new(
    center: %('puck.uno/color/teal'),  radius: 40)
$secondary_zone = %('puck.uno/color/sphere').new(
    center: %('puck.uno/color/coral'), radius: 40)

# Regions to avoid — too dark, too washed out.
$too_dark  = %('puck.uno/color/sphere').new(
    center: %('puck.uno/color').new('#000000'), radius: 60, scope: 'outside')
$too_white = %('puck.uno/color/sphere').new(
    center: %('puck.uno/color').new('#ffffff'), radius: 60, scope: 'outside')

# Pick the scheme colors. Each call satisfies all four constraints
# simultaneously: in the target zone, away from the avoid zones.
$primary   = %('puck.uno/color').random($primary_zone,   $too_dark, $too_white)
$secondary = %('puck.uno/color').random($secondary_zone, $too_dark, $too_white)
```

Run it again and you get a different but similarly-constrained scheme —
the same aesthetic, freshly sampled. The sphere-selector form is the
piece that makes this composable: any number of "want this region" and
"avoid this region" constraints can be passed to one `.random` call.

See [color.md § Random](./#random) for the `.random(*selectors)`
extension that drives the use case.

---

## Open questions

- **Enumeration cost.** `.random` is cheap (rejection sampling). `.each`
  and `.count` (if we add them) need to deal with both extremes: an
  `inside` sphere of small radius enumerates a tractable handful, but
  `outside` with a small radius covers ~16.7M cells minus a sphere.
  Lazy iteration is the only reasonable default; eager array
  materialization would be a footgun.
- **Empty-intersection behavior.** When `.random` (with selectors) is
  called with contradictory selectors and no color satisfies them,
  raise an exception (e.g. `puck.uno/color/no_match`) or return null?
  Leaning exception — silent null is easy to miss.
- **Other shape regions?** Sphere is the first region type. Future
  shapes (axis-aligned cubes, hue cones, etc.) would want a common
  method surface (`scoped?`, `random`, etc.) and likely a shared parent
  like `puck.uno/color/region`. Worth knowing the family now if it's
  coming.
- **Mutability.** Color is mutable (per [color.md](./)); should spheres
  be mutable too — `$sphere.radius = 50`?
