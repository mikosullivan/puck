# Meta-hash

~~~vibecode
{"vibecode": {
	"doc": "meta-hash",
	"role": "spec for puck.uno/meta_hash, a read-overlay-write hash backed by an array of layered hashes; used for cascading configuration where deepest layer wins on reads and writes",
	"key_concepts": ["meta_hash", "cascading_config", "layered_lookup",
		"end_to_start_read", "last_layer_write"]
}}
~~~

`puck.uno/meta_hash` — a read-overlay-write hash backed by an
**array of hashes**. Reads walk the array end-to-start and
return the first hash that has the requested key; writes always
land in the last (most-specific) hash. The class is intended
for cascading-configuration situations where multiple layers
of defaults stack up and the deepest layer wins.

---

<a id="construction"></a>
## Construction

Pass an array of hashes, ordered from most-general to
most-specific:

```
$mh = %['puck.uno/meta_hash'].new([
    $touchstone_factory,    # most general
    $robinson_factory,
    $server_settings,
    $site_settings,
    $dir_settings,
    $file_settings          # most specific
])
```

Any of the underlying hashes can be empty. The meta-hash
references them; it doesn't copy.

---

<a id="reads"></a>
## Reads

`$mh['key']` walks the array **from end to start** and returns
the value from the first hash that has the key:

```
$mh['mime']     # checks $file_settings, then $dir_settings,
                # then $site_settings, ... up to $touchstone_factory
                # Returns the first hit, or null if no layer has 'mime'.
```

Most-specific layers shadow earlier ones. The deeper you nest,
the more your overrides win.

A key whose value is `null` in a layer **still counts as found**
— it shadows any value above. This lets a deeper layer
explicitly clear an inherited value.

<a id="mhhaskey"></a>
### `$mh.has?(key)`

Returns `true` if any layer in the array has the key (regardless
of its value), `false` otherwise. Useful when you need to
distinguish "key absent" from "key set to null."

---

<a id="writes"></a>
## Writes

`$mh['key'] = value` always writes to the **last hash in the
array** — the most-specific layer:

```
$mh['mime'] = 'application/json'    # writes to $file_settings
```

There is no API for writing to a different layer through the
meta-hash. If you need to mutate an intermediate layer, write
to that hash directly.

The last hash is the meta-hash's mutable corner. Earlier layers
are treated as inherited and immutable from the meta-hash's
perspective (they might still be mutated by other code that has
references — meta-hash is a view, not an owner).

---

<a id="mhextendhash"></a>
## `$mh.extend(hash)`

Returns a **new meta-hash** with the given hash appended as the
new bottom (most-specific) layer:

```
$site_mh = $server_mh.extend($site_settings)
$dir_mh  = $site_mh.extend($dir_settings)
$file_mh = $dir_mh.extend($file_settings)
```

The original meta-hash is unchanged. The new one inherits all
the layers from the original plus the new layer on the bottom.
Reads on the new one start from the new bottom; writes go to the
new bottom.

This is the canonical idiom for cascade-building: as you walk
deeper into a tree of scopes (directory tree, request lifecycle,
nested config blocks, etc.), each step extends the meta-hash
with its own settings.

---

<a id="mhflatten"></a>
## `$mh.flatten`

Returns a single regular hash representing the merged view at
the current state. Most-specific layer takes precedence; earlier
layers fill in keys the deeper layers didn't set.

```
$snapshot = $mh.flatten   # plain hash, no inheritance
```

Useful for serialization, debugging, and any code that wants a
point-in-time snapshot rather than a live overlay.

Flattening copies; subsequent mutations of the meta-hash or the
underlying hashes don't affect the returned snapshot.

---

<a id="use-cases"></a>
## Use cases

- **HTTP middleware settings cascade.** Touchstone → Robinson →
  server → site → dir levels → file. Each level overlays the
  previous; reads return the most-specific value. Writes through
  the meta-hash land in the most-specific (last) layer; to mutate
  an earlier layer, write to that hash directly (see
  [Writes](#writes)).
- **Per-request configuration.** Engine defaults → per-handler
  overrides → per-request override.
- **Class-stack-style metadata lookup** where classes carry
  layered metadata.
- Anywhere you'd otherwise write `hash1.merge(hash2).merge(hash3)`
  but want the layers to stay distinct (for later inspection,
  diffing, or selective writes).

---

<a id="implementation-note"></a>
## Implementation note

The class is intentionally tiny — read, write, has?, extend,
flatten are the entire surface, and each is straightforward.
Roughly 20 lines of Caspian. No optimization tricks; if the
cascade is deep enough to cause noticeable lookup cost, that's
the cascade's problem to flatten or shorten, not meta-hash's
problem to memoize.

---

<a id="whats-not-in-the-v1-surface"></a>
## What's not in the v1 surface

- **Iteration order semantics** when the same key exists in
  multiple layers — `$mh.each` returns the merged view (deepest
  wins) without revealing layer provenance. Per-layer iteration
  would require a separate API; not in v1.
- **Removing a layer** after construction. Build a fresh
  meta-hash with the layers you want.
- **Reordering layers** after construction. Same — build fresh.
- **Setting on intermediate layers** through the meta-hash. Write
  to the underlying hash directly.

These are deliberately out of scope to keep the class small. If
real use cases push back, they're additions, not breaking
changes.
