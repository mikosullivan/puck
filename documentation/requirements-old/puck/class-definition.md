# Online class definition

~~~vibecode
{"vibecode": {
	"doc": "puck_class_definition",
	"role": "spec for how a Puck class defines itself online — the JSON shape a Puck server publishes so clients can discover the class's constructor parameters, methods, return types, and metadata. The class definition is what `puck.lookup(url)` resolves to before instantiation.",
	"audience": ["Puck client implementors needing to know what to expect from a server's class definition",
		"Puck server implementors publishing a class",
		"Caspian and other-language tooling generating client stubs from a definition"],
	"example_class": "https://puck.uno/geo/",
	"example_language": "Python",
	"key_concepts": ["class_publishes_itself_as_json",
		"constructor_and_methods_as_keyed_hashes",
		"keyword_only_params_per_protocol",
		"single_class_key_polymorphic_built_in_name_or_url",
		"parametric_types_use_of_modifier",
		"clients_consume_at_lookup_time"]
}}
~~~

A Puck class publishes its definition as a JSON document at its URL. When a client does `puck.lookup('https://puck.uno/geo/')`, the server returns this JSON; the client uses it to know what constructor parameters the class accepts, what methods it exposes, what those methods take and return.

The shape is **strictly declarative** — no executable code crosses the wire as part of the definition. The class's actual logic lives on the server; clients only see the interface.

---

## JSON or HTML — both work

~~~vibecode
{"vibecode": {
	"section":                       "json_or_html",
	"rule":                          "class_page_served_as_either_pure_json_or_html",
	"content_type_dispatch":         {"application/json": "body_is_the_definition_parse_directly",
	                                  "text/html":        "body_embeds_definition_in_pre_id_definition_extract_textcontent_parse_as_json"},
	"definition_element":            "<pre id=\"definition\">",
	"extraction_method":             "textcontent_or_equivalent",
	"extraction_strips_markup":      true,
	"client_extraction_methods":     {"javascript":           "element.textContent",
	                                  "python_beautifulsoup": ".get_text()",
	                                  "ruby_nokogiri":        ".text"},
	"one_url_two_audiences":         true,
	"no_separate_json_url_required": true,
	"no_accept_header_dance":        true,
	"server_default_html_for_browser_friendliness": true,
	"accept_application_json_optional":             true,
	"client_unaware_of_surrounding_page":           true,
	"rationale":                     ["one_url_two_audiences_authors_publish_one_thing",
	                                  "syntax_highlighting_does_not_break_extraction",
	                                  "no_accept_header_negotiation_required",
	                                  "pre_id_definition_convention_is_the_contract"],
	"supported_syntax_highlighters": ["pygments", "highlight.js", "prism", "any_html_emitter"],
	"open_questions": {
		"multiple_definitions_per_page": {
			"current_state": "id_definition_only_supports_one",
			"options":       ["id_definition_n_array_form", "class_puck_definition_multiple_allowed"],
			"current_need":  false
		},
		"malformed_json_in_pre": {
			"behavior":                      "client_raises_puck_uno_error_protocol",
			"same_as_malformed_direct_json": true,
			"html_wrapper_is_just_transport": true
		},
		"cache_headers": {
			"concern":                            "html_cached_but_embedded_json_drifts",
			"resolution":                         "standard_http_cache_control_applies",
			"json_embedding_doesnt_change_rules": true
		}
	}
}}
~~~

A class page can be served as **either pure JSON or as HTML**. The client checks the response's `Content-Type` and parses accordingly:

- **`application/json`** — the body IS the class definition. Parse it directly.
- **`text/html`** — the body is a human-readable web page that EMBEDS the class definition. The client looks for a `<pre>` element with `id="definition"`, extracts that element's **text representation** (the equivalent of `element.textContent` in JS, `BeautifulSoup`'s `.get_text()` in Python, etc.), and parses the result as JSON.

This means a class can publish a single URL that serves humans (browser → readable docs) AND machines (client → parsed definition). No separate `.json` URL; no `Accept`-header dance for the basic case.

## Example: `https://puck.uno/geo/`

The geolocation class. Takes a coordinate at construction, exposes methods for the various location-derived queries.

```json
{
    "vibecode": {
        "class": "https://puck.uno/geo/",
        "shape":                       "remote_class",
        "domain":                      "geolocation",
        "instantiation":               "coordinate_at_construction",
        "constructor_params":          ["lat", "lon", "alt"],
        "required_params":             ["lat", "lon"],
        "queries":                     ["address", "city", "country_code", "weather",
                                        "congressional_district", "distance_to", "map_image"],
        "returns_scalars":             ["address", "city", "country_code"],
        "returns_other_puck_objects":  ["weather", "congressional_district"],
        "returns_bytes":               ["map_image"],
        "returns_numbers":             ["distance_to"],
        "us_specific_methods":         ["congressional_district"]
    },

    "class":       "https://puck.uno/geo/",
    "version":     "1.0.0",
    "description": "Geolocation service. Instantiate with a latitude/longitude (and optional altitude); query weather, address, political boundaries, map imagery, etc. for that point.",

    "constructor": {
        "lat": {
            "class":        "number",
            "required":    true,
            "description": "Latitude in decimal degrees. Range -90.0 to 90.0."
        },
        "lon": {
            "class":        "number",
            "required":    true,
            "description": "Longitude in decimal degrees. Range -180.0 to 180.0."
        },
        "alt": {
            "class":        "number",
            "required":    false,
            "description": "Altitude in meters above sea level. Optional; defaults to 0.0."
        }
    },

    "methods": {
        "address": {
            "params":      {},
            "returns":      {"class": "string"},
            "description": "Reverse-geocoded street address at the point."
        },

        "city": {
            "params":      {},
            "returns":      {"class": "string"},
            "description": "City name at the point, in the local language."
        },

        "country_code": {
            "params":      {},
            "returns":      {"class": "string"},
            "description": "ISO 3166-1 alpha-2 country code (e.g. 'US', 'JP')."
        },

        "weather": {
            "params":      {},
            "returns":      {"class": "https://puck.uno/geo/weather"},
            "description": "Current weather report at the point. Returns a Weather Puck object."
        },

        "congressional_district": {
            "params":      {},
            "returns":      {"class": "https://puck.uno/geo/congressional_district"},
            "description": "US congressional district info for the point. Returns a CongressionalDistrict Puck object. Raises `puck.uno/error/not_found` if the point isn't in the US."
        },

        "distance_to": {
            "params": {
                "other": {
                    "class":       "https://puck.uno/geo/",
                    "required":    true,
                    "description": "Another Geo object."
                },
                "unit": {
                    "class":        "string",
                    "required":    false,
                    "enum":        ["meters", "kilometers", "miles", "nautical_miles"],
                    "default":     "meters",
                    "description": "Unit for the returned distance."
                }
            },
            "returns":      {"class": "number"},
            "description": "Great-circle distance from this point to another Geo point."
        },

        "map_image": {
            "params": {
                "zoom": {
                    "class":        "integer",
                    "required":    false,
                    "default":     14,
                    "range":       [0, 20],
                    "description": "Zoom level. 0 = world view, 20 = building-level detail."
                },
                "format": {
                    "class":        "string",
                    "required":    false,
                    "enum":        ["png", "jpeg"],
                    "default":     "png",
                    "description": "Image format."
                },
                "width": {
                    "class":        "integer",
                    "required":    false,
                    "default":     512,
                    "description": "Image width in pixels."
                },
                "height": {
                    "class":        "integer",
                    "required":    false,
                    "default":     512,
                    "description": "Image height in pixels."
                }
            },
            "returns":      {"class": "bytes", "content_type": "image/png"},
            "description": "Map image centered on the point. Returns raw bytes with the indicated Content-Type."
        }
    }
}
```

---

## Example: rendered page for `https://puck.uno/geo/`

Here's what a human visitor sees in their browser when they navigate to `https://puck.uno/geo/`. The page is real human documentation; the machine-readable JSON is embedded at the bottom in a `<pre id="definition">` element.

<div class="page-preview">
<div class="page-preview-chrome">https://puck.uno/geo/</div>
<div class="page-preview-body">

<h1>Geo</h1>

<pre><code class="language-vibecode">{"vibecode": {
	"doc":                          "puck_uno_geo",
	"class":                        "https://puck.uno/geo/",
	"shape":                        "remote_puck_class",
	"domain":                       "geolocation",

	"protocol":                     "puck",
	"protocol_intro_for_agents":    "https://puck.uno/ai/protocol",
	"cold_agent_instructions": [
		"this_is_a_puck_class_definition_page",
		"if_unfamiliar_with_puck_fetch_protocol_intro_for_agents_url_first",
		"find_pre_id_definition_extract_textcontent_parse_as_json",
		"use_class_url_to_instantiate_via_puck_client",
		"call_methods_per_methods_hash_in_definition"
	],

	"instantiation":                "coordinate_at_construction",
	"constructor_params":           ["lat", "lon", "alt"],
	"required_params":              ["lat", "lon"],
	"queries":                      ["address", "city", "country_code", "weather",
	                                 "congressional_district", "distance_to", "map_image"],
	"returns_scalars":              ["address", "city", "country_code"],
	"returns_other_puck_objects":   ["weather", "congressional_district"],
	"returns_bytes":                ["map_image"],
	"returns_numbers":              ["distance_to"],
	"us_specific_methods":          ["congressional_district"],
	"definition_at":                "<pre id=\"definition\"> at the bottom of this page"
}}
</code></pre>

<p><strong><code>https://puck.uno/geo/</code></strong> — a Puck class for location-derived queries. Instantiate with a coordinate; query weather, address, political boundaries, map imagery, etc.</p>

<h2>Quick example</h2>

<pre><code class="language-python">import puck

hq = puck.lookup('https://puck.uno/geo/')(lat=37.7980, lon=-122.4626)
print(hq.city)              # 'San Francisco'
print(hq.address)           # '24 Polk St, San Francisco, CA 94102, USA'
print(hq.country_code)      # 'US'
</code></pre>

<h2>Constructor</h2>

<table>
<tr><th>Param</th><th>Type</th><th>Required</th><th>Description</th></tr>
<tr><td><code>lat</code></td><td>number</td><td>yes</td><td>Latitude in decimal degrees (−90.0 to 90.0).</td></tr>
<tr><td><code>lon</code></td><td>number</td><td>yes</td><td>Longitude in decimal degrees (−180.0 to 180.0).</td></tr>
<tr><td><code>alt</code></td><td>number</td><td>no</td><td>Altitude in meters above sea level. Defaults to 0.0.</td></tr>
</table>

<h2>Methods</h2>

<table>
<tr><th>Method</th><th>Returns</th><th>Description</th></tr>
<tr><td><code>address</code></td><td>string</td><td>Reverse-geocoded street address at the point.</td></tr>
<tr><td><code>city</code></td><td>string</td><td>City name at the point, in the local language.</td></tr>
<tr><td><code>country_code</code></td><td>string</td><td>ISO 3166-1 alpha-2 country code (e.g. <code>'US'</code>, <code>'JP'</code>).</td></tr>
<tr><td><code>weather</code></td><td><a href="https://puck.uno/geo/weather">Weather</a> Puck object</td><td>Current weather report.</td></tr>
<tr><td><code>congressional_district</code></td><td><a href="https://puck.uno/geo/congressional_district">CongressionalDistrict</a> Puck object</td><td>US congressional district info. Raises <code>puck.uno/error/not_found</code> if the point isn't in the US.</td></tr>
<tr><td><code>distance_to(other, unit?)</code></td><td>number</td><td>Great-circle distance to another Geo. <code>unit</code> is one of <code>'meters'</code> (default), <code>'kilometers'</code>, <code>'miles'</code>, <code>'nautical_miles'</code>.</td></tr>
<tr><td><code>map_image(zoom?, format?, width?, height?)</code></td><td>bytes (PNG by default)</td><td>Map image centered on the point.</td></tr>
</table>

<h2>Machine-readable definition</h2>

<pre id="definition"><code class="language-json">{
    "vibecode": {
        "class":                       "https://puck.uno/geo/",
        "shape":                       "remote_class",
        "domain":                      "geolocation",
        "instantiation":               "coordinate_at_construction",
        "constructor_params":          ["lat", "lon", "alt"],
        "required_params":             ["lat", "lon"],
        "queries":                     ["address", "city", "country_code", "weather",
                                        "congressional_district", "distance_to", "map_image"],
        "returns_scalars":             ["address", "city", "country_code"],
        "returns_other_puck_objects":  ["weather", "congressional_district"],
        "returns_bytes":               ["map_image"],
        "returns_numbers":             ["distance_to"],
        "us_specific_methods":         ["congressional_district"]
    },

    "class":       "https://puck.uno/geo/",
    "version":     "1.0.0",
    "description": "Geolocation service. Instantiate with a latitude/longitude (and optional altitude); query weather, address, political boundaries, map imagery, etc. for that point.",

    "constructor": {
        "lat": {
            "class":       "number",
            "required":    true,
            "description": "Latitude in decimal degrees. Range -90.0 to 90.0."
        },
        "lon": {
            "class":       "number",
            "required":    true,
            "description": "Longitude in decimal degrees. Range -180.0 to 180.0."
        },
        "alt": {
            "class":       "number",
            "required":    false,
            "description": "Altitude in meters above sea level. Optional; defaults to 0.0."
        }
    },

    "methods": {
        "address": {
            "params":      {},
            "returns":     {"class": "string"},
            "description": "Reverse-geocoded street address at the point."
        },

        "city": {
            "params":      {},
            "returns":     {"class": "string"},
            "description": "City name at the point, in the local language."
        },

        "country_code": {
            "params":      {},
            "returns":     {"class": "string"},
            "description": "ISO 3166-1 alpha-2 country code (e.g. 'US', 'JP')."
        },

        "weather": {
            "params":      {},
            "returns":     {"class": "https://puck.uno/geo/weather"},
            "description": "Current weather report at the point. Returns a Weather Puck object."
        },

        "congressional_district": {
            "params":      {},
            "returns":     {"class": "https://puck.uno/geo/congressional_district"},
            "description": "US congressional district info for the point. Returns a CongressionalDistrict Puck object. Raises `puck.uno/error/not_found` if the point isn't in the US."
        },

        "distance_to": {
            "params": {
                "other": {
                    "class":       "https://puck.uno/geo/",
                    "required":    true,
                    "description": "Another Geo object."
                },
                "unit": {
                    "class":       "string",
                    "required":    false,
                    "enum":        ["meters", "kilometers", "miles", "nautical_miles"],
                    "default":     "meters",
                    "description": "Unit for the returned distance."
                }
            },
            "returns":     {"class": "number"},
            "description": "Great-circle distance from this point to another Geo point."
        },

        "map_image": {
            "params": {
                "zoom": {
                    "class":       "integer",
                    "required":    false,
                    "default":     14,
                    "range":       [0, 20],
                    "description": "Zoom level. 0 = world view, 20 = building-level detail."
                },
                "format": {
                    "class":       "string",
                    "required":    false,
                    "enum":        ["png", "jpeg"],
                    "default":     "png",
                    "description": "Image format."
                },
                "width": {
                    "class":       "integer",
                    "required":    false,
                    "default":     512,
                    "description": "Image width in pixels."
                },
                "height": {
                    "class":       "integer",
                    "required":    false,
                    "default":     512,
                    "description": "Image height in pixels."
                }
            },
            "returns":     {"class": "bytes", "content_type": "image/png"},
            "description": "Map image centered on the point. Returns raw bytes with the indicated Content-Type."
        }
    }
}
</code></pre>

</div>
</div>

## Shape rationale

Notes on the choices the example illustrates:

- **`class:` field at the top is the URL.** Identity-of-the-class lives at the URL; the definition is just the shape published at that URL.
- **`version:` is descriptive, not enforced.** Useful for diagnostics and "is this the version I expected?" checks, but the protocol doesn't track or enforce client-side cached version vs server-side current version. APIs that need to evolve in incompatible ways use a versioned URL segment (`borg.uno/geo/v2/`) instead — different versions are different classes (different URLs). See [protocol.md § Versioning](protocol.md#versioning) for the loose-versioning model.
- **Constructor and methods are keyed hashes**, not arrays. Order isn't meaningful; keys are the parameter / method names.
- **Params are always keyword-only.** Puck's protocol has [no positional placeholders](../caspian/index.md#puck-params-keyword-only); the JSON shape doesn't model position. Every param has a name.
- **One key for type: `class`.** Polymorphic on the value — a built-in name (`"string"`, `"number"`, `"integer"`, `"boolean"`, `"bytes"`, `"null"`) for primitives, a URL (`"https://puck.uno/geo/weather"`) for Puck classes. The same key works whether the value is a built-in scalar or another Puck class. Same shape Caspian uses for field declarations (`field :foo, class: ...`).
- **Parametric types use `of`.** `{"class": "array", "of": "string"}` for a homogeneous array. `of` accepts the same polymorphic shape as `class` — a name, a URL, or a nested type descriptor. Other parametric built-ins (hash with keyed shape, etc.) can be added as needed; for V1 the only one defined is `array`.
- **Extra modifiers stay on the same hash.** `content_type` for `bytes`; `enum`, `range`, `default` for constrained primitives — all keys on the same descriptor object.
- **`enum` and `range` are constraint hints.** Clients can validate before sending; servers validate again on receipt.
- **Per-param `description`** lets generated stubs include docstrings.
- **No executable code on the wire.** Default values, enums, ranges are descriptive metadata. Validation and computation happen server-side.
- **Constructor and method errors use HTTP status codes.** The class definition doesn't enumerate possible exceptions — it doesn't need to. Servers return the appropriate HTTP status (400 for bad params, 404 for missing resource, 422 for valid-shape-but-unprocessable input, 503 when the server is overloaded, etc.); clients map that to a host-language exception per the protocol's general error rules. See [protocol.md § Wire shape](protocol.md) for the status-carries-success/failure convention.
- **No blockchain endorsement on Puck class definitions.** The blockchain signs source code at publication time; Puck classes have no source the client sees — the implementation lives on the server. There's nothing for the endorsement to sign. (Endorsements DO apply to Caspian libraries the client downloads and runs — that's a different surface; see [blockchain integration](../caspian/downloads/blockchain/).)

---

## What happens at `puck.lookup`

```python
hq = puck.lookup('https://puck.uno/geo/')(lat=37.7980, lon=-122.4626)
```

Under the hood:

1. Client does an HTTP GET to `https://puck.uno/geo/` requesting the class definition (per the [protocol](protocol.md)).
2. Server returns the JSON shape documented above.
3. Client parses the JSON; constructs a local proxy class with:
    - The constructor signature derived from the `constructor` block.
    - A method per entry in `methods`, each making a remote call when invoked.
    - Type validation per the param specs (optional; client's choice).
4. `puck.lookup(...)` returns the proxy class.
5. Calling `(lat=..., lon=...)` runs the proxy's constructor — usually a remote instantiation call that returns an object reference.

The client never sees the server's actual implementation; it only knows what the definition says.

