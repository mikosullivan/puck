# Puck (the Protocol)

~~~vibecode
{"vibecode": {
	"doc": "puck",
	"role": "language-agnostic remote object protocol — instantiate a remote class, hold a reference, call its methods, treat it like a local object",
	"key_concepts": ["language_agnostic", "remote_object_protocol",
		"remote_feels_local", "uns_addresses", "instantiate_and_call",
		"manufactured_methods", "returns_can_be_other_puck_objects",
		"chained_remote_calls"],
	"audience": ["developers_in_any_language", "puck_client_implementors",
		"puck_server_implementors"],
	"example_language": "Python"
}}
~~~

Puck is a **language-agnostic remote object protocol.** It lets you work
with a remote object as if it were a local one: instantiate it, hold a
reference, call its methods. The wire serialization, the network round-trip,
the response unmarshaling — all hidden. The code reads the same whether the
object is in-process or across the network.

Any language that can speak JSON over HTTP can be a Puck client.
[Caspian](../caspian/index.md) ships first-class integration (see
[caspian/puck/index.md](../caspian/puck/index.md)) and is the primary client today, but
the protocol is not Caspian-specific.

For the formal wire-protocol spec — class definitions, request and
response shapes, dynamic vs stored objects, versioning — see
[protocol.md](protocol.md).

---

## Example: a remote `Geo` class

`puck.uno/geo` publishes a `Geo` class — a geolocation service. It's
**inherently remote**: the data (weather feeds, census databases, map
tiles) lives on the server side.

The workflow is the standard one: **resolve the class by URL,
instantiate it, then use it.**

```python
import puck

# Resolve and instantiate in one step — Starfleet HQ, San Francisco
hq = puck.lookup('puck.uno/geo')(lat=37.7980, lon=-122.4626)

# Call the class's manufactured methods
hq.weather                  # current weather report at that location
hq.congressional_district   # congressional district info for that point
hq.map_image(zoom=14)       # PNG map image centered on the point
```

Each of those methods makes a remote call to the server that hosts
`puck.uno/geo`. The same shape works from JavaScript, Ruby, or any
other language that wires up a Puck client; the specifics differ
only in syntax.

---

## Remote returns can be other Puck objects

A Puck method doesn't have to return a flat value. It can return an
**instance of another Puck class** — and that returned object is itself
remote. You call methods on it, Puck does the dispatch, the cycle
continues. The fact that you're now talking to a different class (and
possibly a different server) doesn't change how the code reads.

For example, `hq.congressional_district` doesn't just return a name or an ID;
it returns an instance of a `CongressionalDistrict` Puck class. That object
exposes its own manufactured methods:

```python
district = hq.congressional_district

district.name              # 'CA-11'
district.representative    # current US House representative
district.population        # 760_000
district.boundary_geojson  # GeoJSON for the district boundary
```

Each of those is a fresh remote call. From the caller's perspective,
`district` is just an object with methods — the chained-call shape
(`hq.congressional_district.representative`) reads the same as deeply-chained
local calls, even when two distinct remote services are involved.