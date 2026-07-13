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

## Testing

### BucketAccessor

- **Resolvable at startup** — `%['puck.uno/bucketaccessor']` returns a class value in a fresh runtime.
- **Adds `[]` read method** — a class instance carrying BucketAccessor supports `$obj[$key]` reads.
- **Adds `[]=` write method** — a class instance carrying BucketAccessor supports `$obj[$key] = $value` writes.
- **Read returns the value at the key** — after `$w[:name] = 'x'`, `$w[:name]` is `'x'`.
- **Read of missing key returns null** — `$w[:not_there]` on an instance with BucketAccessor returns null; it does not raise.
- **Write is direct — no validation** — writing any value at any key succeeds without filtering or hook interception.
- **Write goes to the bucket** — after `$w[:name] = 'x'`, `%bucket['name']` on `$w` (from inside a method) is `'x'`.
- **Adding BucketAccessor at runtime enables `[]` on that instance** — `$w.object.classes.ensure(Bucket_accessor); $w[:key] = 'v'; $w[:key]` returns `'v'`.
- **Block-form `.classes.ensure(BucketAccessor) do ... end` scopes the surface** — subscript works inside the block and raises after the block exits (assuming BucketAccessor wasn't already stacked).

### BucketReader

- **Resolvable at startup** — `%['puck.uno/bucketreader']` returns a class value.
- **Adds `[]` read method** — read via subscript works on an instance carrying BucketReader.
- **Does NOT add `[]=` write method** — `$w[:name] = 'x'` raises when the class stack has BucketReader but no BucketWriter or BucketAccessor.
- **Class-defined `@field =` still works** — class methods on the same class can still write via `@field` or `%bucket[...]`; only the external subscript write is blocked.
- **Read of missing key returns null** — same as BucketAccessor's read behavior.

### BucketWriter

- **Resolvable at startup** — `%['puck.uno/bucketwriter']` returns a class value.
- **Adds `[]=` write method** — write via subscript works.
- **Does NOT add `[]` read method** — `$w[:name]` raises when the class stack has BucketWriter but no BucketReader or BucketAccessor.
- **Class-defined reads still work** — class methods can still read via `@field` or `%bucket[...]`; only external subscript reads are blocked.
- **Write goes to the bucket** — after `$w[:name] = 'x'` on a BucketWriter-carrying instance, a method inside the class reading `%bucket['name']` returns `'x'`.

### Composition

- **BucketReader + BucketWriter behaves as BucketAccessor** — an instance carrying both classes supports both `$w[:key]` and `$w[:key] = value` operations.
- **Stacking BucketAccessor and BucketReader together** — an instance carrying both still supports read and write; the redundant `[]` method resolution follows standard stack rules and produces the same read result either way.
- **No error on redundant stacking** — combining any two or all three of these classes on one instance does not raise at class-add time.
- **Adding at class-definition time affects every instance** — a class that lists BucketAccessor in its definition produces instances that all support subscript access.
- **Adding at runtime affects only the instance** — `.object.classes.ensure(BucketAccessor)` on one instance does not add the class to other instances of the same class.

## Related

- [object/structure § Bucket](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure/#bucket) — what the bucket is; what these classes are exposing.
- [object/methods](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods/) — cross-cutting object methods, including `.classes.ensure` for adding a class at runtime.
