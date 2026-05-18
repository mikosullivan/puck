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
	"example_universe": "Star Trek",
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

<a id="example-a-remote-color-class"></a>
## 1 Example: a remote `Color` class

Suppose `puck.uno/color` publishes a `Color` class. The workflow is:
**resolve the class by UNS, instantiate it, then use it.**

```python
import puck

# Resolve the class via the puck
Color = puck.lookup('puck.uno/color')

# Instantiate — same syntax as any local Python class
crimson = Color('#dc143c')

# Call the class's manufactured methods
crimson.hex             # '#dc143c'
crimson.rgb             # {'red': 220, 'green': 20, 'blue': 60}
crimson.name            # 'crimson'
crimson.darken(0.2)     # returns a new Color, 20% darker
crimson.complementary   # the color wheel opposite
```

Nothing in those method calls signals "remote." The puck handles the
dispatch behind the scenes — looking up where `puck.uno/color` is hosted,
sending the call, deserializing the result. The same shape works from
JavaScript, Ruby, or any other language that wires up a Puck client; the
specifics differ only in syntax.

The methods (`hex`, `rgb`, `name`, `darken`, `complementary`, ...) are
**manufactured by the `Color` class itself** — Puck doesn't define them.
Puck only carries the call across the wire. What methods a remote class
exposes is up to the class.
