# Bucket-access utility classes
<!--index: 8-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_bucket_access",
	"role": "spec for three built-in utility classes that expose an object's bucket through subscript syntax — BucketAccessor (both read and write), BucketReader (read-only), and BucketWriter (write-only). Each is a class that a class author can add to their class's stack (or a caller can ensure at runtime) to grant external callers direct `$obj[key]` / `$obj[key] = value` access to the underlying bucket. The three variants let the author pick the exact capability shape they want to expose.",
	"status": "draft — three utility classes named with their canonical URL identifiers and their contributed methods",
	"audience": "developers writing Caspian classes; anyone wanting subscript access to bucket entries"
}}
~~~

Three built-in utility classes contribute bucket-access methods to whatever class they're stacked onto. All three do the same thing at different capability levels: they let external code reach into the underlying bucket via `[]` / `[]=` subscript syntax without the class author writing custom accessors.

Pick the variant that matches the capability you want to expose:

| Class | Adds `[]` (read) | Adds `[]=` (write) |
|---|---|---|
| `BucketAccessor` | yes | yes |
| `BucketReader` | yes | no |
| `BucketWriter` | no | yes |

## BucketAccessor

Canonical URL: **`https://puck.uno/bucketaccessor`**. Working class name: `BucketAccessor`.

Adds two methods to the receiver:

- **`[]($key)`** — returns `%bucket[$key]` (the value stored in the bucket at that key, or `null` if the key isn't there).
- **`[]=($key, $value)`** — assigns `%bucket[$key] = $value`.

Together they turn the receiver into a hash-like value for external callers:

~~~caspian
$widget[:name] = 'primary'
$widget[:count] = 3

$widget[:name]      # 'primary'
$widget[:count]     # 3
~~~

Both operations reach directly into the bucket — no filtering, no validation, no getter/setter hooks. The class author who chooses to add `BucketAccessor` is deliberately opting into a "the bucket is the public surface" posture.

## BucketReader

Canonical URL: **`https://puck.uno/bucketreader`**. Working class name: `BucketReader`.

Adds only the **`[]($key)`** method — read access to the bucket. Callers can inspect what's in the bucket but cannot set entries through the subscript syntax.

~~~caspian
$widget[:name]      # reads from the bucket
$widget[:name] = 'new'   # raises — no `[]=` method
~~~

Useful when the class author wants external code to inspect state without granting mutation capability. The class's own methods still write via `@field` or `%bucket[...]` as usual; only external subscript-writes are blocked.

## BucketWriter

Canonical URL: **`https://puck.uno/bucketwriter`**. Working class name: `BucketWriter`.

Adds only the **`[]=($key, $value)`** method — write access to the bucket. Callers can set entries but cannot read them back through the subscript syntax.

~~~caspian
$widget[:name] = 'primary'   # writes to the bucket
$widget[:name]               # raises — no `[]` method
~~~

The write-only variant matches patterns where a caller supplies data but shouldn't inspect what's already there — collectors, event sinks, one-way telemetry pipes, redaction-shaped surfaces where a role can contribute without observing.

## Composition

The three classes aren't mutually exclusive — nothing stops a class author from stacking more than one — but combining them adds nothing new. `BucketReader` + `BucketWriter` produces the same surface as `BucketAccessor` alone; stacking `BucketReader` onto a class that already has `BucketAccessor` re-adds a `[]` method that's already there. Pick the one variant that matches the surface you want to expose and stop there.

If two of the three do end up on the same stack, method resolution walks the stack per the usual [stack](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure/#stack) rules — but since every collision boils down to two methods that do the same thing, which one wins doesn't matter.

Adding any of the three at class-definition time makes it part of the class's built-in surface for every instance. Adding one at runtime via `$foo.object.classes.ensure(BucketAccessor)` (or its block form for temporary access) works for specific instances or specific scopes.

## Related

- [object/structure § Bucket](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure/#bucket) — what the bucket is; what these classes are exposing.
- [object/methods](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods/) — cross-cutting object methods, including `.classes.ensure` for adding a class at runtime.
