# Geolocation

~~~vibecode
{"vibecode": {
	"doc": "geolocation",
	"role": "in-progress spec for puck.uno/geo, a geolocation service available at puck.uno launch; used as the reference example of a remote-first class (client-side stub, all logic on the server)",
	"key_concepts": ["puck_uno_geo", "remote_first_service_pattern", "coordinate_fields",
		"address_resolution", "remote_method_dispatch"]
}}
~~~

**Status:** designing. Spec for the launch of puck.uno — to be filled
in as the design develops.

---

<a id="overview"></a>
## Overview

One of the Puck-provided services available at puck.uno launch will
be **`puck.uno/geo`** — a geolocation service in the `puck.uno`
namespace.

<a id="remote-first-service-pattern"></a>
### Remote-first service pattern

`puck.uno/geo` is intended as an **example of a class that is only used
remotely**. There is very little Caspian in the class definition; all
methods are remote calls. The class on the client side is essentially a
stub that exposes the method surface and dispatches each call to the
puck.uno server via `%puck.call` (see
[puck.md](../requirements/puck/index.md) — `remote function`).

The actual geolocation logic — databases, caches, algorithms — lives on
the puck.uno servers. Clients hold the class for its method names and
let the remote do all the work.

This makes `geo` a useful reference example: developers building their
own remote-first services can use it as a template for what a
remote-only class looks like in Caspian.

<a id="coordinates"></a>
### Coordinates

A geo instance carries three coordinate fields:

- **`long`** — longitude. Primary, required.
- **`lat`** — latitude. Primary, required.
- **`alt`** — altitude. Officially part of the class for completeness,
  but mostly ignored in practice by current methods.

<a id="remote-call-semantics"></a>
### Remote call semantics

Standard Puck remote-call mechanics apply (see [puck.md](../requirements/puck/index.md)):

- The client retrieves the class definition from UNS (or cache) and
  instantiates locally. The instance lives in client memory with its
  `long`/`lat`/`alt` state.
- On each method call, the client sends **the entire object** to the
  puck.uno server along with the method name and any args. For geo,
  that's tiny — three numbers.
- The server receives a copy of the object, processes the call using
  the received state, and returns a response.
- The server is stateless per-call; it doesn't retain the instance
  between calls.

---

<a id="osm-stewardship"></a>
## OSM Stewardship

The geo service is built on top of OpenStreetMap's freely-available
data and services (Nominatim for geocoding, Overpass for tag queries).
We benefit substantially from the OSM community's work, and we have
a corresponding responsibility to be a good citizen of that
community.

**Our operating commitments:**

- **Cache aggressively, but don't make everything pass through us.**
  When puck.uno makes a call to OSM (Nominatim, Overpass, static-map
  rendering, etc.), we cache the result so OSM doesn't see the same
  query twice within the cache TTL. But not every OSM resource is
  best routed through our server; **it's a judgment call per
  resource**. The rule of thumb:
  - **Aggregable API queries** (Nominatim reverse-geocode, Overpass
    tag queries, static-map images) → through puck.uno with caching.
    These are query-shaped — one client request triggers one OSM
    request, the result is small and cacheable, and our cache buys
    real OSM relief.
  - **High-volume low-level traffic** (map tiles for interactive
    embeds) → **fetched directly from OSM by client browsers**, not
    proxied through us. Tiles are voluminous, OSM already has CDN
    infrastructure for them, and routing them through puck.uno would
    impose serious bandwidth costs without meaningful OSM-stewardship
    benefit. If volume ever grows to where our embeds are putting
    real pressure on OSM tile servers, we'd revisit (switch to a
    third-party tile provider, etc.) — but that's a future
    conversation.
- **Self-rate-limit below OSM's published thresholds.** For the
  queries we *do* make on our server (Nominatim, Overpass), we
  enforce queue-based rate-limiting well below their published
  limits. Nominatim asks for ≤1 request per second per IP; Overpass
  asks broadly for "be reasonable." Spikes from many simultaneous
  clients get absorbed by the cache, not pushed to OSM.
- **Identify ourselves honestly.** Every request puck.uno makes to
  OSM-hosted services carries a User-Agent identifying the service
  and a contact URL, so OSM operators can reach us if our traffic is
  causing problems.
- **No self-hosted mapping service.** puck.uno does not and will not
  run its own Nominatim, Overpass, or tile-rendering infrastructure.
  Running a real mapping service is a big operational commitment we
  are deliberately not taking on. puck.uno is, and is intended to
  remain, **a thin caching layer in front of OSM** for the queries
  we proxy — and a thin HTML/JS shell for embeds whose tiles come
  direct from OSM.
- **Attribute OSM in client-facing responses.** Per OSM's ODbL
  license, address and POI data carries appropriate attribution. The
  puck.uno server includes attribution metadata in responses where
  it's needed; client libraries can surface it where appropriate.
- **Contribute back when we detect data gaps.** If our caching and
  query patterns reveal systematic gaps or errors in OSM data, we
  feed those observations back to the OSM community in whatever form
  is useful (aggregated reports, mapping party suggestions, etc.).

The goal is simple: the geo service should be a net positive for the
OSM ecosystem — bringing more developers into OSM-backed workflows
without burdening OSM's volunteer-run infrastructure.

**Architectural footprint, in plain terms.** puck.uno's geo service
is a **caching HTTP proxy** in front of OSM-hosted endpoints. There
is no PostgreSQL + PostGIS, no osm2pgsql, no Mapnik, no tile cache
of our own. Every query ultimately resolves at OSM's servers; our
contribution is to absorb repeat traffic in a cache so OSM doesn't
see it more than once per cache TTL. That's the whole architecture
— deliberately small, deliberately OSM-friendly.

---

<a id="services"></a>
## Services

Methods on a `puck.uno/geo` instance are remote calls that compute
location-derived information from the instance's `lat`/`long`/`alt`.
The puck.uno server holds the implementations, the data sources, and
the caches. This section catalogs the services as they get spec'd.

<a id="general-pattern-everything-returned-is-a-puck-object"></a>
### General pattern: everything returned is a Puck object

**Anything a `puck.uno/geo` method returns is itself a Puck
remote-first object.** Addresses, business listings, census handles —
they're all UNS-registered classes with their own remote-method
surface. The Puck protocol pattern applies recursively all the way
down.

The amount of locally-cached state varies by class:

- Some return objects are **mid-weight** — they hold a useful set of
  fields populated from the initial server response, with additional
  remote methods for richer data. `puck.uno/geo/business` is in this
  bucket (basic OSM data populated locally; logo etc. via remote
  methods).
- Others are **very light** — essentially just a handle (an ID or a
  small set of keys), with all interesting data fetched lazily via
  remote methods. `puck.uno/geo/census` is in this bucket.

The right balance for each class depends on the underlying data
source: when one round trip can fetch a useful chunk of data
cheaply (Nominatim's address response, Overpass's POI bundle),
populate eagerly; when the data is large or fetched piecemeal (ACS
demographic stats), populate lazily.

Developers don't need to think about this split for ordinary use —
they just call methods on the returned object. The split shows up
as latency: the first call to a lazy method has a round-trip cost
the eager fields don't.

<a id="geoaddress"></a>
### `$geo.address`

Returns the best-guess street address for the geo instance's
coordinates.

<a id="data-source"></a>
#### Data source

[Nominatim](https://nominatim.openstreetmap.org/), OpenStreetMap's
official geocoding service. We prefer OSM over Google or other
commercial geocoders. The endpoint:

```
GET https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat={lat}&lon={lon}
```

Nominatim returns a structured response with a `display_name` (formatted
address string), a structured `address` sub-object with components
(`road`, `house_number`, `city`, `state`, `postcode`, `country`, etc.),
and metadata like `place_rank` and `osm_id`.

<a id="call-flow"></a>
#### Call flow

1. Client calls `$geo.address`. The local stub sends the entire `$geo`
   object to the puck.uno server via `%puck.call` (per standard
   Puck remote-call mechanics).
2. The puck.uno server checks its own **cache** for the lat/long key.
3. Cache miss: the server makes a Nominatim request, respecting OSM's
   usage policy (1 request per second per IP, identifying User-Agent
   `puck.uno-geo/1.0`). The cache exists precisely to keep us under
   OSM's rate limit and to be a good citizen.
4. The result lands in the server cache with a TTL of ~30 days
   (addresses are stable; new construction is rare).
5. The server returns a structured **address object** to the client.

<a id="return-shape"></a>
#### Return shape

A structured address object, not a bare string. Both forms are
available:

```
$addr = $geo.address
$addr.to_s            # "123 Main St, Anytown, NY 10001, USA" (display_name)
$addr.street          # "123 Main St"
$addr.city            # "Anytown"
$addr.state           # "NY"
$addr.postal_code     # "10001"
$addr.country         # "United States"
$addr.country_code    # "US"
```

Fields not present in OSM's response (e.g., no `house_number` in a
rural area) are returned as **null with flavor `not_found`**, letting
callers branch on whether the field is meaningfully absent vs. just
missing data.

<a id="error-cases"></a>
#### Error cases

- **No address at this coordinate** (middle of an ocean, etc.): the
  call returns a null with flavor
  `puck.uno/null/flavor/not_found`. The coords are valid; OSM just
  has nothing to say.
- **OSM unreachable or timeout**: a regular error
  (`puck.uno/exception/error/unreachable` or similar). Transient;
  clients can retry.
- **Invalid coordinates** (lat outside [-90, 90], long outside [-180,
  180]): rejected client-side before the round trip — it's a
  programming error, not a service issue.

<a id="granularity-shortcuts"></a>
#### Granularity shortcuts

The same cached OSM response backs several common-case projections,
each its own method on the geo instance. Cheap once the address is
cached (no extra OSM request):

- `$geo.country` — full country name (`"United States"`)
- `$geo.country_code` — ISO code (`"US"`)
- `$geo.state` — state/province/region as OSM has it
- `$geo.city` — city/town/locality
- `$geo.postal_code` — local postal code string (see below)
- `$geo.neighborhood` — when OSM has it; null otherwise
- `$geo.timezone` — derived from coords; backed by its own
  coords→timezone lookup table on the server (OSM doesn't answer this
  directly, but the data bundle does)

<a id="geodistance_to"></a>
### `$geo.distance_to`

Returns the **linear (haversine) distance** between two geo points,
in meters.

```
$here.distance_to($there)    # → integer meters, straight-line
```

This is "as the crow flies" — math on the two coordinates, not the
actual road distance. Locally computable on the puck.uno side (no
remote round-trip needed beyond the initial `%puck.call`); could
even be done client-side eventually if we ship the formula in a
client library.

For real driving distance / time / turn-by-turn directions, see the
navigation service below (separate topic).

<a id="geopostal_code"></a>
### `$geo.postal_code`

Returns the local postal code string for the geo instance's
coordinates. Backed by the same cached Nominatim response as
`$geo.address`; no extra round trip if the address has already been
fetched.

```
$geo.postal_code   # "10001"        — US (5-digit ZIP)
$geo.postal_code   # "SW1A 1AA"     — UK (alphanumeric)
$geo.postal_code   # "100-0001"     — Japan (with hyphen)
$geo.postal_code   # "K1A 0B1"      — Canada (alphanumeric, with space)
```

**Format.** Returned as a string in the **local format**. The service
doesn't normalize across regions; what comes back is what's locally
used. Callers that need a normalized form (e.g., strip whitespace,
canonicalize case) do that themselves.

**Edge cases.** Two flavored-null outcomes:

- **`puck.uno/null/flavor/not_found`** — coords are in a region that
  uses postal codes, but Nominatim doesn't have one for this specific
  location (rural areas without exact mapping, ocean coords, etc.).
- **`puck.uno/null/flavor/not_applicable`** — coords are in a
  jurisdiction that doesn't use postal codes at all (some countries
  historically didn't; Ireland's Eircode is only recent; etc.).

Drivers use this for confirming pickup zones, computing cross-zone
fares in markets that price that way, and cross-checking
rider-supplied addresses.

<a id="geocensus"></a>
### `$geo.census`

Returns a `puck.uno/geo/census` object — a **very light handle**
representing the census geography that contains the geo instance's
coordinates. The handle itself holds just enough to identify the area
(the relevant census ID and a country code); all actual demographic
data is fetched via remote methods on the object.

<a id="data-sources"></a>
#### Data sources

- **United States:** the [US Census Bureau](https://www.census.gov/data/developers.html)
  APIs.
  - **American Community Survey (ACS)** — annual rolling-sample
    survey. 1-year estimates for areas ≥65,000 population; 5-year
    estimates everywhere. The workhorse for demographic stats.
  - **Decennial Census** — every 10 years; most authoritative for raw
    counts.
  - **Geocoder** — maps `lat`/`long` to census geography identifiers
    (block, block group, tract, county, state). How we get from a
    geo instance to a queryable census ID.
- **Other countries:** not yet implemented. The class design
  anticipates per-country expansion (UK's ONS, Statistics Canada,
  INSEE, etc.). For coordinates outside supported countries,
  `$geo.census` returns null with flavor
  `puck.uno/null/flavor/not_implemented`.

<a id="geographic-granularity-us"></a>
#### Geographic granularity (US)

Census data is reported at hierarchical levels:

| Level | Typical size | Notes |
|---|---|---|
| Block | ~50 people | Finest grain; some stats not released for privacy |
| Block group | 600–3,000 people | Smallest level with full ACS data |
| Tract | 1,200–8,000 people | Standard analytical unit |
| Place (city) | varies | Municipal boundaries |
| County | varies | |
| State | varies | |

The handle holds an ID at each available level; remote methods can
target whichever level the caller wants. **Tract is the default
analytical level** — most data and most use cases land there.

<a id="call-flow-1"></a>
#### Call flow

1. Client calls `$geo.census`. Client sends the geo instance to
   puck.uno.
2. Server checks its cache for the geocoder result for these coords.
3. Cache miss: server hits the Census Geocoder to get the census IDs
   (block, block group, tract, county, state) for these coords.
4. Server returns a lightweight `puck.uno/geo/census` object
   containing just those IDs and the country code. **No demographic
   data is fetched yet.**

<a id="handle-contents"></a>
#### Handle contents

The local instance carries only enough to identify the area:

```
$census.country_code      # 'US'
$census.geography_ids     # hash: { block: ..., tract: ..., county: ..., state: ... }
```

That's essentially it. Everything else is a remote method.

<a id="remote-methods-on-puckunogeocensus"></a>
#### Remote methods on `puck.uno/geo/census`

The full method catalog is its own spec, but the shape is:

- `$census.population(level: :tract)` — population estimate
- `$census.median_income(level: :tract)` — household median income
- `$census.median_age(level: :tract)`
- `$census.unemployment_rate(level: :tract)`
- `$census.poverty_rate(level: :tract)`
- `$census.racial_breakdown(level: :tract)` — hash of category → percentage
- `$census.education_levels(level: :tract)`
- `$census.commute_modes(level: :tract)`
- ... etc.

Each remote method takes an optional `level:` (default `:tract`) and
an optional `year:` for historical comparison. Each fetches just the
requested stat from ACS or Decennial, with its own server-side cache.

When the method returns, the result is the value (e.g., a number for
median_income, a hash for racial_breakdown). Some return values may
themselves be Puck objects if the data is structured enough to
warrant it (e.g., a `puck.uno/geo/census/boundary` for the area's
geometric outline); that's per-method.

<a id="caching"></a>
#### Caching

The geocoder result (coords → census IDs) caches with a long TTL
(~90 days) — census geography is very stable.

Each demographic stat caches per (geography_id, level, year,
dataset) — ACS releases yearly, so a 30-day TTL is fine.

Aggressive caching plus the per-stat lazy fetch keeps the load on
Census Bureau APIs manageable and respects their rate limits.

<a id="privacy-posture"></a>
#### Privacy posture

Same model as other geo services:

- No raw-coord logging.
- Cache keyed by coarsened coords and resolved census IDs.
- Census data itself is public/aggregate, but the queries (where
  someone looked up) could be sensitive — we treat them with the
  same operational discretion.

<a id="why-lightweight"></a>
#### Why lightweight

Demographic data is large in aggregate (potentially dozens of fields
per area, plus historical years). Most callers want one or two
specific stats. Eagerly populating everything at instantiation would
waste a lot of round-trip bytes for stats nobody asked about. The
lightweight-handle pattern means the first call to `$geo.census` is
cheap; subsequent stat methods pay only for what's actually used.

This is the same reasoning that applies to any Puck service handle
representing a large or structured remote dataset.

<a id="map-and-navigator"></a>
### Map and Navigator

The map system splits into **two services**:

- **`puck.uno/geo/map`** — the map itself. A rendering surface.
  Holds everything that affects what gets drawn: position, zoom,
  theme, language, tile styles, overlay layers. Embeddable on its
  own when all you want is a map.
- **`puck.uno/geo/navigator`** — a higher-level wrapper that
  composes a map with surrounding chrome: buttons, voice,
  find-nearby UI, navigation behavior, skin/template. Holds the
  map as a nested `.map` property.

The principle: **if it changes the pixels on the map surface,
it's a map property. If it's a button, voice line, or other thing
*around* the map, it's a navigator property.**

<a id="example-configuring-a-navigator"></a>
#### Example: configuring a navigator

```
$navigator = %['puck.uno/geo/navigator'].new()

# Map: things that affect what's drawn on the rendering surface
$navigator.map.center = [42.3601, -71.0589]
$navigator.map.zoom = 14
$navigator.map.theme = 'day'
$navigator.map.language = 'en'
$navigator.map.styles << 'https://example.com/my-map-styles.css'
$navigator.map.layers << 'https://tiles.example.com/my-overlay/{z}/{x}/{y}.png'

# Navigator: chrome around the map
$navigator.recenter_button = true
$navigator.zoom_buttons = true
$navigator.day_night_button = true
$navigator.find_nearby_gas = true
$navigator.find_nearby_charging = true
$navigator.voice = true
$navigator.navigation = true
$navigator.skin = 'https://example.com/my-skin.html'

$html = $navigator.html
```

<a id="the-ambiguous-pair-rule"></a>
#### The ambiguous-pair rule

Some concepts have both a *state* and a *control* aspect — day/night
is the canonical example.

- `$navigator.map.theme = 'day'` — controls what mode the map is
  currently in (state of what's rendered → map).
- `$navigator.day_night_button = true` — controls whether there's
  a button to switch it (chrome around the map → navigator).

Two independent settings. The control can be hidden while the state
is still set; the state can be changed programmatically without the
button being present.

<a id="map-mode"></a>
#### Map mode

The map renders in one of three modes, settable via `$map.mode`:

- **`:north`** (default) — flat top-down map, north always at the
  top. The standard cartographic view.
- **`:heading`** — flat top-down map, but the map rotates so the
  user's current direction of travel points up. Useful when the
  on-screen world should match what the driver sees through the
  windshield.
- **`:perspective`** — angled / forward-looking view (the 3D-ish
  "drive mode" view).

The user can switch modes at any time, so the output HTML carries
everything needed for all three. Switching is a pure client-side
operation — no server re-render.

**One style stack covers all modes.** Vector style formats
(MapLibre/Mapbox-style) already support conditional rules based
on render context, so per-mode styling differences (3D building
extrusions, distance-scaled labels, rotation-aware label
placement, etc.) live *inside* the style. No separate per-mode
style channels.

State vs control:

- `$navigator.map.mode = :north` — sets the initial mode (state,
  on the map).
- `$navigator.mode_selector = true` — exposes a UI control to
  switch modes (chrome, on the navigator). Renders as a set of
  radio buttons — the user picks one of the three modes.

The mode property consolidates what was previously two separate
properties (`view` for flat/perspective, `orientation` for
north_up/heading_up). Three-way single selector is simpler.

<a id="standalone-map-use"></a>
#### Standalone map use

If you just want to embed a map without any of the navigator
chrome, instantiate `puck.uno/geo/map` directly:

```
$map = %['puck.uno/geo/map'].new()
$map.center = [42.3601, -71.0589]
$map.zoom = 14
$html = $map.html
```

This is the right shape for "I just need a map on my page" use
cases — articles, dashboards, anywhere the surrounding UI is the
developer's job.

<a id="curated-styles-and-skins"></a>
#### Curated styles and skins

puck.uno hosts a **curated set of popular styles and skins** for
the map system — not a general repository, but more than just one
default. The policy:

- **Curated, not crowdsourced.** No user submissions, no gallery
  of community uploads, no commercial marketplace. The set is
  small, chosen by the project, and updated as needed.
- **Popular options only.** A handful of map styles covering
  common needs (clean light, clean dark, satellite-ish,
  driver-focused, etc.) and a handful of skins covering common
  layouts (driver-app, embedded-card, full-screen, etc.).
- **Not a service.** We're not aiming to be a Mapbox-style style
  hosting service. Developers with specific needs should host on
  their own infrastructure or with a specialized provider.

Curated styles and skins live at well-known puck.uno URLs and
are referenced like any other URL in `$map.styles`,
`$map.map_style`, or `$navigator.skin`. Developers pick the one
they want or roll their own.

<a id="document-reorganization-pending"></a>
#### Document reorganization pending

Much of the existing detail below this section currently treats
everything as `$map.X`. Per the split above, the property surface
needs to be sorted into map-side (rendering) and navigator-side
(chrome). That reorganization is a separate pass — for now, read
each property and ask "does this change pixels or chrome?" to
mentally route it.

---

<a id="maps-existing-detail-pending-reorganization"></a>
### Maps (existing detail — pending reorganization)

A `puck.uno/geo/map` represents a rectangular geographic region —
the primitive for map services (embedding, tile retrieval, etc.).
Other ways to describe regions (center+zoom, center+radius, polygons)
are out of scope for now; the bounding-box rectangle is the canonical
primitive.

<a id="definition-two-opposite-corners"></a>
#### Definition: two opposite corners

A map is defined by **two opposite corner coordinates**. The canonical
convention is **northwest (NW) and southeast (SE)** — top-left and
bottom-right of the rectangle as drawn with north up.

<a id="liberal-corner-pair-handling"></a>
#### Liberal corner-pair handling

The service is liberal in what it accepts. Callers can pass **any two
opposite corners** — NW/SE, NE/SW, or even in either order — and the
service figures out the bounding box under the hood:

- Take the **min and max latitude** of the two inputs → south and
  north edges.
- Take the **min and max longitude** of the two inputs → west and
  east edges.

The developer doesn't have to remember "which corner goes first" or
"which corner is NW." Whatever two opposite corners they pass, the
service normalizes internally. The canonical NW/SE form is what the
map exposes publicly (`$map.nw`, `$map.se`) after normalization.

Funny-shaped regions (non-rectangular outlines) are a separate topic
and not in scope here.

<a id="configurable-properties"></a>
#### Configurable properties

A map object holds more than just its NW/SE corners. Two kinds of
properties live on a map: **configuration properties** that take
values (iconset, language, skin, etc.) and **feature properties**
that are booleans turning UI elements on or off.

**Important distinction**: a feature property at `true` means the
feature is **available** in the rendered map — its UI element appears,
its functionality is enabled. Whether the feature is **currently
active** (e.g., voice is currently speaking, navigation is currently
running) is runtime state, separate from the property. Some of those
states default to off and require the user to enable them; some default
on. **User-preference defaults are TBD** and will get sorted out
during a separate pass.

<a id="configuration-properties"></a>
### Configuration properties

```
$map.iconset = 'puck.uno/iconset'
$map.language = 'jp'
$map.zoom = true
$map.pan = true
```

- **`iconset`** — selects which set of icons the map uses for
  markers, points of interest, the driver pin, etc. The specifics of
  how iconsets work (the iconset class, its members, how the map
  applies them) are a separate spec and not detailed here.
- **`language`** — preferred language for map labels (street names,
  city names, POI names, UI controls). Where OSM has multilingual
  data (via `name:xx` tags), the renderer uses that; otherwise falls
  back to the local default. Format of the language code (`jp` vs
  `ja`, `en` vs `en-US`, etc.) is TBD — we'll pick a canonical form
  when this is fleshed out.
- **`zoom`** — boolean, controls whether users can zoom the map.
  Default `true` (standard interactive behavior). Set to `false` for
  fixed-zoom displays (e.g., a "where it is" map embedded in an
  article where the reader shouldn't change the view).
- **`pan`** — boolean, controls whether users can pan. Default
  `true`. Same use case as `zoom = false` — fixed displays where the
  shown region is exactly what the developer wants.
- **`orientation`** — symbol selecting which way is "up" on the map.
  Two modes for v1:
  - `:north_up` (default) — standard cartographic orientation,
    north points to the top of the map. Easiest to read for most
    users.
  - `:heading_up` — the map rotates so the user's current direction
    of travel points up. Useful for in-vehicle navigation (the world
    on screen matches what the driver sees through the windshield).
    Requires a heading source — typically supplied as part of the
    location updates the parent app feeds to the map.

  Mode selector rather than a boolean to leave room for future
  additions (`:destination_up`, etc.) without breaking the API.
- **`styles`** — ordered list of CSS sources styling the map
  interface (the control panels, buttons, layout chrome — *not* the
  tile content, which is a separate concern handled by `layers`).

  Each entry in the list is either:
  - **A URL** (starts with `http://` or `https://`) → loaded as a
    stylesheet (effectively a `<link rel="stylesheet">`). Most CSS
    will live on the developer's own infrastructure; this is how
    they hook it in.
  - **Anything else** → treated as inline CSS source, included as a
    `<style>` block.

  Auto-detected per entry. Mix freely:

  ```
  $map.styles = [
      'https://my-cdn.com/map-theme.css',           # external stylesheet
      'https://puck.uno/geo/default-style.css',    # factory default, if you want it back
      '.puck-attribution { font-size: 10px }',     # inline override
  ]
  ```

  **Factory default.** The map ships with a default styled UI backed
  by a single stylesheet hosted at puck.uno:

  ```
  https://puck.uno/geo/default-style.css
  ```

  `$map.styles` starts out containing exactly that URL. So:
  - `$map.styles << '...'` **adds on top of** the default (default
    applies, then your additions override).
  - `$map.styles = ['https://my-host.com/theme.css']` **replaces
    entirely**. The puck.uno default is gone unless you re-include
    the URL.

  The default-as-URL design keeps it visible and inspectable —
  developers can view the source, copy it as a starting point, fork
  it, etc. Alongside the default, puck.uno hosts a curated set of
  popular CSS styles (see
  [Curated styles and skins](#curated-styles-and-skins)); custom
  styles live on the developer's own infrastructure.

  **CSS vs. tile styling.** `$map.styles` controls the **HTML
  interface** (control panels, buttons, layout). The map's tile
  imagery (roads, buildings, labels) is determined by the tile
  source in `$map.layers` — that's a different styling system (style
  JSON for vector tiles, pre-rendered for raster) and isn't
  configurable via CSS.

  **Payload caveat:** the entries (whether URLs or inline strings)
  travel with the map object on every remote call. URL references
  are tiny strings; inline CSS strings can be substantial. Hand-
  written overrides are fine; pasting a full-fledged CSS file
  inline would inflate every remote call. Prefer URL references for
  bulk styles.
- **`navigation`** — boolean, enables the navigation feature set in
  the rendered map. Default `false`.

  ```
  $map.navigation = true
  ```

  When on, the rendered map includes a destination input UI, route
  display, turn-by-turn instructions, ETA, and (if `voice = true`)
  spoken prompts. The user enters a destination in the rendered
  map's UI; the map handles geocoding and routing internally,
  draws the route, and follows the driver's progress along it.

  The Caspian side doesn't need to know specific routes — it just
  toggles the feature on. The rendered map does the dynamic work.

  Programmatic destination control (Caspian sets a specific
  destination, the map navigates to it without the user entering
  one) may be added later as an additional property (working name
  `$map.destination`). Not in v1 of this property.
- **`map_style`** — URL of the style document defining how the
  **base map** looks (street colors, label fonts, water tones, etc.).
  Separate from `styles` (which controls the HTML interface chrome
  via CSS); `map_style` controls how the actual tile imagery renders.

  ```
  $map.map_style = 'https://demotiles.maplibre.org/style.json'
  $map.map_style = 'https://tiles.stadiamaps.com/styles/alidade_smooth.json'
  $map.map_style = 'https://my-cdn.com/my-rideshare-night-style.json'
  ```

  **Vector vs raster.** Tiles come in two flavors:
  - **Vector tiles** ship raw geometry to the browser; a separate
    **style document** (JSON, per the open
    [MapLibre Style Spec](https://maplibre.org/maplibre-style-spec/))
    tells the renderer how to draw each feature. Same tiles can look
    radically different under different styles. This is the modern
    web-map approach.
  - **Raster tiles** are pre-rendered images. The styling is baked
    in server-side; different "styles" are just different tile
    servers. Classic OSM (`tile.openstreetmap.org`) is raster.

  `map_style` accepts either:
  - A **style-document URL** (typically returns `.json` content) →
    treated as a vector style.
  - A **raster tile URL pattern** (with `{z}/{x}/{y}` placeholders) →
    treated as a raster tile source.

  The library auto-detects which based on URL extension / content
  type / pattern shape.

  **Factory default.** The map ships with a default vector style
  hosted at puck.uno:

  ```
  https://puck.uno/geo/default-map-style.json
  ```

  `$map.map_style` starts containing this URL. Override by setting a
  different URL; the default is gone unless re-included. The default
  is visible/inspectable/forkable at the URL — developers can copy
  it as a starting point for custom styles.

  **`map_style` vs `layers`.** Two distinct roles:
  - `map_style` is the **base map** — the underlying world rendering
    (streets, buildings, water, labels). One style document at a
    time.
  - `layers` is for **overlay layers** stacked on top of the base
    map (custom data, rideshare zones, traffic, etc.). Multiple
    URLs, in stacking order.

  This separation matches the standard tile-rendering model:
  base + overlays.

  **A curated set lives on puck.uno; everything else lives
  elsewhere.** puck.uno hosts the default plus a small curated
  set of popular vector styles (see
  [Curated styles and skins](#curated-styles-and-skins)). Beyond
  that curated set, styles live on the developer's infrastructure
  or with third-party providers (MapTiler, Stadia, etc.) — we're
  not a general style-hosting service.

- **`layers`** — ordered list of tile-source URL patterns for
  **overlay layers** stacked on top of the base map. The base map's
  appearance is controlled by `map_style`; `layers` is for
  additional data layers drawn over it. Each entry is a URL with
  the standard tile-server placeholders (`{z}/{x}/{y}`, optionally
  `{s}` for subdomain rotation, `{r}` for retina, etc.). Layers
  render in order — later ones overlay earlier ones.

  ```
  # No overlays — just the base map from $map.map_style
  $map.layers = []

  # Overlay a custom rideshare-specific layer on top
  $map.layers = ['https://tiles.puck.uno/rideshare/driver_amenities/{z}/{x}/{y}.png']

  # Stack multiple overlays
  $map.layers = [
      'https://tiles.puck.uno/rideshare/driver_amenities/{z}/{x}/{y}.png',
      'https://tiles.example.com/traffic/{z}/{x}/{y}.png',
  ]
  ```

  **Why URLs rather than named identifiers.** A URL-based scheme means
  no puck.uno-maintained registry of "known" layer names, no
  curation overhead, and developers have explicit control over their
  tile sources (and over their compliance with each source's usage
  policy). Third parties can host layers anywhere; puck.uno doesn't
  need to know about them in advance.

  **Custom rideshare-style layers** could be hosted at
  `https://tiles.puck.uno/rideshare/<theme>/...` (driver amenities,
  no-stopping zones, pickup-friendly areas, etc.) — but each is just
  a URL the developer plugs into `layers`. They're not a special
  category as far as the map config is concerned.

  **Standard layers** are simply well-known tile-URL patterns the
  developer can use. Examples for reference (no curation, just
  conventions):
  - OSM Standard: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
  - OSM Humanitarian (HOT): `https://tile-{s}.openstreetmap.fr/hot/{z}/{x}/{y}.png`
  - OpenCycleMap (cycling): `https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=...`

  **Each tile source has its own usage policy.** When developers add
  a layer URL, they're agreeing to that source's terms (rate limits,
  attribution, API keys, etc.). puck.uno doesn't enforce or proxy;
  the developer is responsible.

- **`voice`** — enables spoken turn-by-turn prompts when the map is
  displaying a route under active navigation ("In 200 meters, turn
  left onto Main Street," etc.). Default `false`.

  ```
  $map.voice = true                            # enable, use defaults
  $map.voice = false                           # disable
  $map.voice = { language: 'jp', verbosity: :brief }   # configured
  ```

  Setting `voice = true` uses sensible defaults (the device's default
  voice for the map's `language`, normal verbosity, system-volume
  output). Passing a hash configures specifics: `language`,
  `verbosity` (`:brief` vs `:detailed`), and similar.

  **Implementation: Web Speech API.** Modern browsers expose
  `speechSynthesis` for local TTS — no cloud service, no API keys, no
  network round trips per prompt. The map element generates utterance
  text from the active route's steps and speaks them at appropriate
  moments as the driver approaches each maneuver. Works on Android
  Chrome and iOS Safari (with the usual PWA caveats around audio
  autoplay policies on first interaction).

  Voice is only meaningful when a route is being rendered with active
  navigation — the property is a no-op when the map is just showing
  a static region.

  Voice language follows the map's `language` property by default;
  override by setting `voice = { language: '...' }` explicitly.

The `zoom`, `pan`, and `orientation` properties only apply to
interactive embeds (`$map.html`); they don't affect the static-image
variant (`$map.image_url`), which has no user interaction by nature.

Other configurable properties are expected as the design develops —
map style, default zoom, marker behavior, etc. As they're added,
each becomes part of the map object's state.

**Aware of payload growth.** Per the standard Puck remote-call
mechanic, the entire map object is sent with every remote call.
With just NW/SE + iconset that's still tiny, but as more
configurable properties accumulate, the per-call payload grows. Not
a problem yet; worth noting so the design doesn't drift into bloat.

<a id="embedding-posture-csp-friendly"></a>
#### Embedding posture: CSP-friendly

When map services emit HTML for embedding (iframes, image tags, or
anything that references remote resources at render time), the
**ecoverse-wide CSP policy** applies: alongside the HTML snippet,
the service provides the information needed to construct a
`Content-Security-Policy` header that permits the embed. See
[csp.md](../requirements/caspian/network/http/server/touchstone/csp.md) for the full policy.

Consumers can use that info or not — but it's always provided.

<a id="mapimage_url"></a>
#### `$map.image_url`

Returns a URL pointing to puck.uno's static-map service. The
developer plops it directly into `<img src="...">` and is done — no
script, no CSS, no library setup.

```
$map.image_url                              # default 600 x 400
$map.image_url(width: 1000)                 # custom width, default height
$map.image_url(width: 1000, height: 700)    # custom dimensions
```

The URL shape (under puck.uno control; exact form TBD):

```
https://puck.uno/geo/static-map?nw=LAT,LONG&se=LAT,LONG&width=W&height=H
```

**puck.uno picks the provider internally.** Almost certainly
OSM-backed, since the project is OSM-first. Developers don't see or
care which data source produced the image. Multi-provider options
(an explicit `$map.google.image_url`, etc.) were considered and
parked — probably never. Adds complexity for a use case most
developers don't have.

**Caching.** Static-map URLs for the same bounding box and dimensions
return the same image, so the puck.uno-side cache has a long TTL
(target: 7 days, possibly longer). The OSM stewardship rules apply
as usual on the rendering backend (rate-limited tile fetches,
identifying User-Agent, etc. — see
[OSM Stewardship](#osm-stewardship) above).

**Attribution.** The rendered image includes "© OpenStreetMap
contributors" per the ODbL license, baked into the image so
developers don't have to handle attribution separately.

**CSP info.** When this URL is provided as part of a larger HTML
snippet (e.g., an embed code), the corresponding CSP info bundle
(see [csp.md](../requirements/caspian/network/http/server/touchstone/csp.md)) accompanies it. For the bare image URL alone,
adding `img-src https://puck.uno` to a site's CSP is what's needed
to allow the embed.

<a id="maphtml"></a>
#### `$map.html`

Returns HTML for an **entire map-driven interface** — not just a map.
The HTML includes the map tile area plus all the controls associated
with the configured features (orientation toggle, destination input,
layer selector, etc.). The interface is dropped directly into the
parent page's DOM (not wrapped in an iframe) so the rest of the
app's JS can interact with it natively.

```html
<script src="https://puck.uno/geo/map.js"></script>
<puck-map-interface nw="LAT,LONG" se="LAT,LONG" style="width: 600px; height: 400px">
  <!-- map area + controls panels are inside this element -->
</puck-map-interface>
```

```
$map.html                              # default size
$map.html(width: 1000, height: 700)    # custom dimensions
```

The developer plops the snippet into their page. The script tag
loads puck.uno's map library (registers the custom elements);
each `<puck-map-interface>` tag becomes a fully-functional map UI.

<a id="controls-are-not-overlaid-on-the-map-by-default"></a>
##### Controls are NOT overlaid on the map (by default)

A deliberate design choice: in the factory skin, controls (orientation
toggle, navigation input, layer selector, etc.) live in their own
panel area alongside the map, **not floating on top of it**. The map
tile area stays clean — just the map and the elements that need to be
on the map by nature (the current-location pin, route polyline, POI
markers).

The motivation: a cluttered map is harder to read, especially in
driving conditions; controls have legible real estate in their own
area.

Developers can override layout via skins (see below) or via styles —
including overlay-style placements if they prefer that look. The
factory skin's no-overlay layout is a default opinion, not a hard rule.

<a id="skins"></a>
##### Skins

The map interface is **skinnable from the ground up**. The HTML
returned by `$map.html` follows a skin — by default, a factory skin
with sensible layout; optionally, one of a curated set of skins
hosted at puck.uno (see
[Curated styles and skins](#curated-styles-and-skins)); or a
custom skin supplied by the developer:

```
$map.skin = '<some HTML string with the slot classes>'
```

A skin is an HTML string with **slot classes** marking where each
component goes. The map library renders the skin's HTML, finds each
slot by its class, and injects the appropriate dynamic component
there.

Example skin (roughly what the factory ships):

```html
<div class="puck-map-interface">
    <div class="puck-controls-panel">
        <div class="puck-navigation-controls"></div>
        <button class="puck-orientation-toggle"></button>
        <button class="puck-voice-toggle"></button>
        <div class="puck-layer-selector"></div>
    </div>
    <div class="puck-map-area"></div>
    <div class="puck-turn-by-turn"></div>
    <div class="puck-attribution"></div>
</div>
```

Slot classes are recognized by the library. The list below is a
**comprehensive set of candidates** — slots that could appear in the
factory skin and be available for custom skins. Which actually land
in v1 vs. defer to later releases will be settled one at a time as
each is reviewed.

**Always-present slots:**

| Class | Component |
|---|---|
| `puck-map-area` | The map tile area itself (the actual map) |
| `puck-attribution` | OSM credit (per ODbL) — required for license compliance |

**Navigation lifecycle controls** (active when `navigation = true`):

| Class | Component |
|---|---|
| `puck-set-destination` | Open destination picker / search dialog |
| `puck-start-navigation` | Begin active turn-by-turn once destination is set |
| `puck-stop-navigation` | End active navigation, return to idle map |
| `puck-skip-turn` | Manually advance past the current turn-by-turn instruction |
| `puck-recalculate-route` | Force a fresh route calculation |
| `puck-alternate-routes` | Show 2nd/3rd best route options |
| `puck-avoid-tolls-toggle` | Toggle route preference for tolls/highways |

**Navigation info displays** (active when `navigation = true`):

| Class | Component |
|---|---|
| `puck-turn-by-turn` | Current turn instruction display |
| `puck-eta-display` | ETA to destination |
| `puck-route-summary` | Distance + total time for the active route |

**Map view controls:**

| Class | Component |
|---|---|
| `puck-orientation-toggle` | North-up / heading-up toggle |
| `puck-zoom-in` | Zoom in (+) button |
| `puck-zoom-out` | Zoom out (−) button |
| `puck-recenter` | Recenter map on current location pin |
| `puck-day-night-toggle` | Switch between day and night map styles |

**Find-nearby shortcuts** (driver-life utilities):

| Class | Component |
|---|---|
| `puck-find-restrooms` | Show nearby restrooms (via `$geo.restrooms`) |
| `puck-find-food` | Show nearby food (`$geo.food`) |
| `puck-find-gas` | Show nearby gas / EV charging |
| `puck-find-parking` | Show nearby parking |
| `puck-find-nearby` | Generic "find nearby" — opens a category picker for the above plus more |

**Voice and layers:**

| Class | Component |
|---|---|
| `puck-voice-toggle` | Mute / unmute voice (active when `voice = true`) |
| `puck-layer-selector` | Toggle individual overlay layers (active when `layers` has more than one) |

**Search and feedback:**

| Class | Component |
|---|---|
| `puck-search` | General POI search (distinct from "set destination" — search without committing to navigate) |
| `puck-report-issue` | Report a problem (closed road, missing POI, etc.); could feed back to OSM as a contribution |

A skin only needs slots for features the developer wants visible. If a
slot is omitted, that feature isn't rendered — even if the
corresponding property is enabled. If a property is disabled, the
corresponding slot stays empty regardless.

**Universal rule, no per-feature review needed.** Same behavior
across all features: property `true` = service on + UI element
appears; property `false` = service off + placeholder removed from
the rendered DOM. Treats every feature uniformly; no special-case
exceptions.

<a id="why-skins-from-day-one"></a>
##### Why skins from day one

It's almost as easy to support skins as to not. The library has to
find the map area, the controls, etc. anyway; making the layout itself
configurable via a string costs very little code on top of that, and
unblocks every "I want my map to look like X" use case without
requiring developer hacks. Building it in from the start means we
never have to retrofit.

**Payload caveat:** the skin string travels with the map object on
every remote call. Modest skins are fine; gigantic ones bloat each
call. Same payload caution as `styles`.

<a id="feature-properties"></a>
### Feature properties

Each candidate button or feature has its own boolean property on the
map. The rule is universal:

- **If the property is `true`**: the map is enabled for that service
  (its functionality is active) and its UI element appears in the
  rendered map.
- **If the property is `false`** (or unset): the service is disabled
  and the corresponding placeholder element in the skin is **removed
  from the DOM** — not just hidden via CSS, removed. The rendered
  output has no trace of it.

```
$map.voice = true                 # voice feature on; mute/unmute button rendered
$map.nearby_gas = true            # gas-nearby service on; button rendered
$map.recenter = false             # recenter service off; placeholder removed from skin
```

(Whether the feature defaults to *currently on* vs *currently off*
when its property is `true` is the user-preference question noted at
the top of this section — TBD.)

The full set, organized by category:

**Navigation lifecycle** (meaningful when `navigation = true`):

| Property | UI element |
|---|---|
| `set_destination` | Open destination picker / search dialog |
| `start_navigation` | Begin active turn-by-turn |
| `stop_navigation` | End active navigation |
| `skip_turn` | Manually advance past current instruction |
| `recalculate_route` | Force a fresh route calculation |
| `alternate_routes` | Show 2nd/3rd best route options |
| `avoid_tolls` | Toggle route preference for tolls/highways |

**Navigation displays:**

| Property | UI element |
|---|---|
| `turn_by_turn` | Current turn instruction display |
| `eta` | ETA to destination |
| `route_summary` | Distance + total time for the active route |

**Map view controls:**

| Property | UI element |
|---|---|
| `orientation_toggle` | North-up / heading-up toggle button (distinct from the `orientation` config which sets the mode) |
| `zoom_in` | Plus button |
| `zoom_out` | Minus button |
| `recenter` | Return to current location pin |
| `day_night` | Switch between day/night map styles |

**Find-nearby shortcuts:**

| Property | UI element |
|---|---|
| `nearby_restrooms` | Show restrooms (via `$geo.restrooms`) |
| `nearby_food` | Show food (`$geo.food`) |
| `nearby_gas` | Show gas / EV charging |
| `nearby_parking` | Show parking |
| `find_nearby` | Generic find-nearby button — opens a category picker for all the above plus more |

**Voice and layers:**

| Property | UI element |
|---|---|
| `voice` | Voice feature available (mute/unmute button shown during nav) |
| `layer_selector` | Toggle individual overlay layers (meaningful when `layers` has more than one) |

**Search and feedback:**

| Property | UI element |
|---|---|
| `search` | General POI search (distinct from `set_destination`) |
| `report_issue` | Report a problem (closed road, missing POI, etc.) |

If the skin lacks the corresponding slot, the property has nothing
to populate and the feature is silently absent from the rendered UI.
A property at `true` plus a slot in the skin together make the
feature appear; a property at `false` causes the slot's element to
be stripped out of the rendered DOM entirely.

<a id="why-not-iframe-anymore"></a>
##### Why not iframe (anymore)

Earlier drafts of this spec used an iframe form. Iframes give strong
isolation, but they make it harder for the rest of the app to talk
to the map — every interaction has to go through `postMessage`. For
real apps (a driver PWA, a tour-planning page, an interactive
dashboard) the map is part of the app's UI and the app's JS needs to
react to map events and update map state. Putting the map directly
in the DOM is materially simpler.

The iframe approach remains a potential future option — particularly
if a Permissions-Policy mechanism makes it easy to grant a puck.uno
iframe just the permissions it needs to interact with its parent
(geolocation, focus, etc.) while preserving sandbox isolation. Not
in scope for v1; noted here so the option isn't forgotten.

<a id="data-flow"></a>
##### Data flow

puck.uno serves the script and the map library; the library runs in
the parent page's DOM. **Map tiles are fetched by the end user's
browser directly from OSM tile servers**, not proxied through
puck.uno — per the stewardship policy above.

<a id="csp"></a>
##### CSP

The parent site adds `script-src https://puck.uno` (for the loader)
and `img-src https://*.tile.openstreetmap.org` (or wherever the map
library is configured to fetch tiles from) to its
`Content-Security-Policy`. Plus any `connect-src` directives the
script needs for runtime API calls.

Per the [ecoverse CSP policy](../requirements/caspian/network/http/server/touchstone/csp.md), `$map.html` makes the CSP
info available alongside the HTML — exact bundling format TBD.

<a id="privacy-and-osm-stewardship"></a>
##### Privacy and OSM stewardship

Same as elsewhere in this doc: no per-user logging of coordinates,
coord-coarsened cache keys, attribution to OSM in the rendered map
UI, rate-limited tile fetches from OSM servers.

<a id="communication-with-the-rest-of-the-app"></a>
##### Communication with the rest of the app

Since the map is in the parent page's DOM, the parent app's JS can
do all the obvious things directly:

- Query the element: `document.querySelector('puck-map')`
- Attach listeners: `element.addEventListener('bounds-changed', ...)`
- Programmatically update: `element.setAttribute('nw', '...')` (or
  property accessors; specific JS API TBD)

What specific events the element emits, what attributes/properties
it exposes, and how external code updates its state (e.g., feeding
in live driver-location updates for a tracking use case) is part of
the map library's documented JS API — to be spec'd separately as
that surface develops.

<a id="locale-aware-formatting"></a>
#### Locale-aware formatting

`display_name` is OSM's locale-neutral format. Optional formatting
based on country and requested locale:

```
$geo.address(locale: :ja)      # Japan-style address ordering
$geo.address(locale: :en_GB)   # UK format
```

The server reformats from the structured fields per the requested
locale's conventions.

<a id="confidence-and-provenance"></a>
#### Confidence and provenance

The address object exposes:

- `$addr.confidence` — coarse quality estimate. Could be Nominatim's
  `place_rank` mapped to a 0–1 scale, or a discrete enum
  (`:exact`/`:approximate`/`:fuzzy`). Lets callers gate on quality.
- `$addr.osm_id` — the OSM feature ID, in case the developer wants to
  follow up with deeper OSM queries against the same record.

<a id="multiple-candidates"></a>
#### Multiple candidates

Sometimes a lat/long sits near a boundary or in a complex area. The
primary `$geo.address` returns the best single match. For ambiguous
cases, `$geo.candidates` returns a list of plausible matches with the
primary first.

<a id="privacy-posture-1"></a>
#### Privacy posture

The puck.uno server sees every coordinate every client looks up. The
operating commitment:

- **No raw-coord logging.** Only aggregate counts and cache keys, where
  cache keys are coarsened (e.g., rounded to 4 decimal places — about
  11 m precision; enough for cache hits, not enough to track an
  individual).
- **Cache entries are not per-user.** The cache is keyed by coord, not
  by client identity.
- **Read-only service.** No reason to retain query history beyond
  cache TTL.

This commitment is public, documented, and part of the geo service
spec — not an afterthought. The Puck ecosystem benefits from users
trusting that operational data isn't retained beyond what's needed for
the service to function.

<a id="geobusinesses"></a>
### `$geo.businesses`

Returns nearby businesses around the geo instance's coordinates, sorted
by distance.

**Use-case framing.** This service is being designed with the Uber-driver
use case in mind. A driver between rides asking "where's a bathroom?
where's a coffee shop? where's gas?" is the primary user. Several
features below exist specifically because real drivers actually need
them (drive-thru filters, open-now-as-default, walking-time prominence,
etc.).

<a id="data-source-1"></a>
#### Data source

OSM's [Overpass API](https://overpass-api.de/), which lets us query OSM
tags within a radius of a point. The relevant OSM tag families for
"business":

- `amenity=*` — restaurants, cafes, bars, pharmacies, hospitals, ATMs,
  fuel stations, etc.
- `shop=*` — supermarkets, convenience stores, clothing, hardware,
  etc.
- `tourism=*` — hotels, motels, attractions
- `office=*` — offices

Combined Overpass query for a 100 m radius:

```
[out:json];
(
  node["amenity"](around:100,LAT,LON);
  node["shop"](around:100,LAT,LON);
  node["tourism"](around:100,LAT,LON);
  node["office"](around:100,LAT,LON);
);
out;
```

<a id="call-signature"></a>
#### Call signature

```
$geo.businesses                              # 100 m radius default
$geo.businesses(radius: 250)                 # in meters
$geo.businesses(category: :food)             # filter
$geo.businesses(open_now: true)              # only currently open
$geo.businesses(radius: 250, limit: 10)      # cap result count
```

<a id="return-shape-1"></a>
#### Return shape

A list of **`puck.uno/geo/business`** objects, **sorted by distance
from the query point** (closest first). Each is a remote-first Puck
object — the same protocol pattern as `$geo` itself, one level down.
The local instance carries basic fields populated from the initial
Overpass response; richer data is fetched lazily through the class's
own remote methods.

Basic fields available on every business object (populated from the
initial response, no extra round trip):

```
$biz.name             # "Joe's Pizza"
$biz.category         # :restaurant (mapped from OSM tag)
$biz.lat / .long      # coordinates
$biz.distance         # meters from query point
$biz.walking_time     # estimated walking minutes (distance / ~80 m/min)
$biz.address          # structured address object (same shape as $geo.address)
$biz.phone            # if in OSM
$biz.website          # if in OSM
$biz.opening_hours    # parsed object; null-flavored not_found if absent
$biz.open_now?        # boolean, computed against local time + opening_hours
$biz.drive_thru?      # boolean, from OSM tag (critical for drivers)
$biz.closes_in        # duration until close; null for 24h places
$biz.osm_id           # OSM feature ID for follow-up queries
```

`puck.uno/geo/business` also exposes additional **remote methods** for
richer data not in the initial Overpass payload — e.g., a method to
fetch the business's logo (OSM exposes these for many businesses).
The full method catalog for `puck.uno/geo/business` is its own spec,
documented separately when ready.

Sorted-by-distance default is non-negotiable for the driver use case:
you want the closest thing first.

<a id="server-side-caching"></a>
#### Server-side caching

Businesses change slowly (weeks to months for openings/closings).
Aggressive cache:

- **Cache key**: coarsen the query lat/long to a grid cell (e.g.,
  3-decimal-place rounding ≈ 110 m squares) + radius bucket + category
  filters.
- **TTL**: 24 hours. Lighter than addresses (~30 days) because the
  business inventory turns over faster.
- **`open_now` filter applies at read time**, using cached
  `opening_hours` plus the server's clock and the location's timezone.
  The filter doesn't bust the cache.

OSM's Overpass has informal usage limits ("be reasonable"). With
caching plus a self-rate-limit on the puck.uno side, we stay under
their threshold. If volume warrants, self-host an Overpass instance.

<a id="driver-life-category-shortcuts"></a>
#### Driver-life category shortcuts

Heavy-use categories get their own one-liner methods on the geo
instance, each preset on top of `businesses`:

```
$geo.restrooms        # public + fast food + gas stations w/ bathrooms
$geo.food             # restaurants + fast food
$geo.coffee
$geo.gas              # for ICE
$geo.ev_charging      # for EV
$geo.atm
$geo.parking          # parking lots + street parking + structures
$geo.auto_repair
```

Each maps internally to one or more OSM categories with the right
defaults. Drivers don't have to remember which OSM tag means what.

<a id="drive-thru-filter"></a>
#### Drive-thru filter

A driver between rides can't easily park. `drive_thru:` restricts to
drive-thru-capable businesses:

```
$geo.coffee(drive_thru: true)
$geo.food(drive_thru: true)
```

Worth its weight in gold to a driver. From OSM's `drive_through=yes`
tag.

<a id="default-behavior-on-category-shortcuts"></a>
#### Default behavior on category shortcuts

For driver-life shortcuts (`food`, `coffee`, `gas`, etc.), **`open_now`
defaults to `true`**. A 24-hour gas station vs. one that closed at 11
PM is a totally different answer. The plain `$geo.businesses(...)`
form doesn't filter unless asked, but the convenience shortcuts assume
"I want one right now."

<a id="walking-time"></a>
#### Walking time

"100 meters" is abstract; "1 minute walk" is actionable. The business
object surfaces `walking_time` prominently (`distance / ~80 m/min` as
the standard walking-pace estimate). Distance stays in the response
for callers who want it, but walking_time is the human-readable form.

<a id="pickup-verification"></a>
#### Pickup verification

When a driver gets a pickup address, calling `$geo.businesses(radius:
30)` on the destination coords surfaces what's actually there:

> "The address says 123 Main, but the closest business is 'Joe's
> Pizza' — that's probably what the rider meant."

Cheap sanity check before driving over.

<a id="grouped-response-option"></a>
#### Grouped response option

Instead of one flat list, an alternative shape buckets by category:

```
$results = $geo.businesses(grouped: true)
$results[:food]        # array of food businesses
$results[:restrooms]   # array of restrooms
$results[:gas]         # array of gas stations
```

Useful when a driver is scanning options across categories rather than
picking one.

<a id="closes_in-for-filtered-results"></a>
#### `closes_in` for filtered results

For `open_now`-filtered results, a business that closes in 10 minutes
is materially different from one open until 2 AM. Each business
carries a `closes_in` field — a duration (null for 24h places). A
driver can see at a glance "this place is open but closing soon."

<a id="coverage-indicator"></a>
#### Coverage indicator

OSM coverage varies wildly by region. The response includes a
`coverage` indicator so callers know whether an empty result means
"nothing nearby" or "OSM hasn't mapped this area well":

- `:high` — dense urban OSM data
- `:moderate` — typical suburban coverage
- `:sparse` — rural or under-mapped region

Computed server-side from the density of OSM features in the queried
area.

<a id="privacy-posture-2"></a>
#### Privacy posture

Same operational commitment as `$geo.address`: no raw-coord logging,
coord-keyed cache (not user-keyed), no retention beyond cache TTL.
The aggregated picture of "where are people querying businesses"
stays opaque — only cache hit/miss counts in coarsened-coord buckets.

---

<a id="open-questions"></a>
## Open Questions

(To be filled in.)
