# Puck (the Protocol)

~~~json
{"vibecode": {
	"doc": "puck",
	"role": "language-agnostic remote object protocol — instantiate a remote class, hold a reference, call its methods, treat it like a local object",
	"key_concepts": ["language_agnostic", "remote_object_protocol",
		"remote_feels_local", "uns_addresses", "instantiate_and_call",
		"manufactured_methods"],
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
[Charlie](../charlie/charlie.md) ships first-class integration (see
[charlie/puck.md](../charlie/puck.md)) and is the primary client today, but
the protocol is not Charlie-specific.

---

<a id="example-a-remote-geo-class"></a>
## 1 Example: a remote `Geo` class

`puck.uno/geo` publishes a `Geo` class — a geolocation service. It's
**inherently remote**: the data (weather feeds, census databases, map
tiles) lives on the server side. There's no local implementation of
`Geo` to fall back on; without Puck, the class isn't usable at all.

The workflow is the standard one: **resolve the class by UNS,
instantiate it, then use it.**

```python
import puck

# Resolve the class via the puck
Geo = puck.lookup('puck.uno/geo')

# Instantiate with a location — Starfleet HQ, San Francisco
hq = Geo(lat=37.7980, lon=-122.4626)

# Call the class's manufactured methods
hq.weather                  # current weather report at that location
hq.census_district          # census district info for that point
hq.map_image(zoom=14)       # PNG map image centered on the point
```

Each of those methods makes a remote call to the server that hosts
`puck.uno/geo`. The same shape works from JavaScript, Ruby, or any
other language that wires up a Puck client; the specifics differ
only in syntax.