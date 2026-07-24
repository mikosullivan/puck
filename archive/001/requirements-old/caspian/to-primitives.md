# To-primitives

~~~vibecode
{"vibecode": {
	"doc": "to_primitives",
	"role": "spec for `.to_primitives` — the method every serializable Caspian object must implement, returning a value composed entirely of JSON primitives (hashes, arrays, strings, numbers, booleans, null). The canonical hook used by serializers anywhere a value needs to cross a process boundary, write to disk, or ship as JSON.",
	"status": "early spec — core rule settled, edges still being shaped",
	"audience": "Caspian programmers writing classes whose instances may be serialized; serializer implementers"
}}
~~~

Caspian provides a uniform way for any value to convert itself into a form suitable for JSON serialization: **the `to_primitives` method**. Every object that can meaningfully be serialized must implement it.

---

## Core rule

**Every serializable object has a `to_primitives` method.** Calling it returns a value composed **entirely of JSON primitives** — recursively. Nothing in the returned structure is a Caspian object that itself needs further conversion; everything is already in a shape JSON's `encode` step can consume directly.

The valid JSON primitives are:

- **hash** (object) — keys are strings, values are recursively JSON primitives
- **array** — elements are recursively JSON primitives
- **string**
- **number** — integer or float
- **boolean**
- **null**

A value returned by `to_primitives` that contains anything else (a Caspian object, a class reference, a function, etc.) is an error in the implementation.

---

## How it's called

```
$foo.to_primitives
```

Direct method on the object, not under [`.object`](built-in-classes/object.md). This is **provisional** — `$foo.object.to_primitives` was the other candidate (placing it under the engine-protocol namespace alongside `.object.classes`, `.object.freeze`, etc.). The decision to land at `$foo.to_primitives` is "let's see how it shakes out"; if naming collisions or convention drift surface, the API may move under `.object` later.

---

## Why "primitives" and not "JSON"

The method returns a **Caspian value composed of primitives**, not a JSON-encoded string. A separate step (the JSON encoder, or whatever target format's encoder) converts the primitive tree into bytes.

This separation matters:

- The same `to_primitives` output can feed JSON, YAML, msgpack, etc. — any encoder that walks a primitive tree. The serialization protocol doesn't bind classes to one wire format.
- Tests can compare `to_primitives` results directly as Caspian hashes without round-tripping through JSON text.
- Pretty-printing, redaction, transformation, and other intermediate processing can operate on the primitive tree before encoding.

---

## The conversion chain

`to_primitives` sits at the bottom of a default conversion chain that makes "just print this value" work seamlessly for the common case:

```
to_string → to_json → to_primitives
```

For most objects, the default `to_string` delegates to `to_json`, which in turn calls `to_primitives` and JSON-encodes the result. So this code works without any explicit serialization step:

~~~caspian
puts {foo: 'bar'}
~~~

The chain: `puts` calls `.to_string` on its argument → for a hash, `.to_string` defaults to `.to_json` → `.to_json` calls `.to_primitives` (a plain hash returns itself; it's already primitives) → `.to_json` encodes to `'{"foo":"bar"}'` → `puts` writes that string to STDOUT.

The same chain applies to any object whose class doesn't override `to_string`. A class that wants a different string representation (a human-readable summary, a debug form, etc.) overrides `to_string` directly. A class that only wants to customize the JSON shape (without changing what its `to_string` returns) overrides just `to_primitives` and inherits the rest of the chain.

This is why O'Brien workers can write Xeme JSON to STDOUT with a plain `puts {...}` — the hash literal stringifies to JSON automatically because nothing in the chain has been overridden.

**The chain ends at `to_primitives`** because that's where the value-to-primitives conversion actually happens. Everything above it (`to_json`, `to_string`) is mechanical: encode the primitives, return the string. Classes that customize serialization customize `to_primitives`; classes that customize string representation customize `to_string`. The split keeps the responsibilities separate.

---

## Recursive composition

Most classes get their `to_primitives` implementation by composition: walk the object's data and call `to_primitives` on any nested values, assembling the results into a hash or array of primitives.

Engine support for the default case (auto-walking the bucket and stack) is open — see [Open questions](#open-questions). The expectation is that simple classes don't have to implement `to_primitives` explicitly; the engine handles the common case and the class only overrides for non-trivial state (private platter buckets, redacted fields, custom shapes, etc.).

---

## Open questions

- **Engine default.** Does the engine provide a default `to_primitives` that walks the object's bucket and stack recursively? Almost certainly yes, but the exact shape (and what the default does for non-trivial structure — multiple platters, nested objects in the bucket, the UUID-marker nested-object pattern from [object structure](../ecoverse/objects/structure.md)) needs spec work.
- **Non-JSON Caspian values.** How are `puck.uno/date`, `puck.uno/duration`, byte arrays, and other classes whose values don't trivially map to a JSON primitive handled? Each such class implements `to_primitives` returning whatever shape makes sense (ISO 8601 string for dates, etc.), but a convention for the common cases is worth settling.
- **Naming.** `$foo.to_primitives` (current) vs `$foo.object.to_primitives` (the alternative). Provisional choice, may revisit if collisions or convention drift appear.
- **Hooks for redaction / transformation.** Some classes (anything carrying credentials, PII, etc.) want their `to_primitives` output to mask or omit sensitive fields. The mechanism is straightforward (the class's `to_primitives` just doesn't include those fields), but a conventional pattern for marking "redacted-from-serialization" fields would help.
- **Round-trip.** Is there a companion `.from_primitives` that reconstructs an object from its primitive form? Some classes will want this; some won't (because the original class isn't reachable, or the input wasn't trusted). Probably opt-in per class rather than universal.
