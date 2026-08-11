# object

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_methods_object",
	"role": "root class in the frames-as-objects design. Anything that participates in the object graph inherits from `object`. Provides the `bucket` accessor — every object can lazily materialize a bucket on demand. Other classes (frame, and future classes) inherit that behavior and build on top of it.",
	"status": "sketch"
}}
~~~

The root class. Anything that participates in the object graph inherits from `object`.

## Methods

### `bucket`

Returns the object's bucket, lazily materializing it on first call.

~~~lua
function object:bucket()
	if not self.bucket_pk then
		self.bucket_pk = self.engine:add_bucket(self.object_pk)
	end

	return self.engine:object_by_pk(self.bucket_pk)
end
~~~

**Composes on the engine.** No `self.db` calls, no ad-hoc SQL. Both DB accesses route through cached prepared-statement methods on the engine:

- **`self.engine:add_bucket(self.object_pk)`** — INSERT of the HashPrimitive with `bucket_for = self.object_pk`, returning the new bucket's `object_pk` (via SQLite `RETURNING`). The new bucket's `owner_role` is derived from `self`'s row by the engine method — no need to pass it. The `objects_denormalize_bucket` trigger fires inside the same statement and sets `self`'s `bucket_pk` column; the returned pk equals what `self.bucket_pk` becomes. See [`engine:add_bucket`](https://www.puck.uno/ideas/frames-as-objects/methods/engine/#add_bucket).
- **`self.engine:object_by_pk(self.bucket_pk)`** — wraps the row as a HashPrimitive object. Callers do `bucket['locals']` on the return, which needs a hash-indexable object, not a bare pk string. See [`engine:object_by_pk`](https://www.puck.uno/ideas/frames-as-objects/methods/engine/#object_by_pk).

**Idempotent by design.** After the first call materializes the bucket, `self.bucket_pk` is set, so subsequent calls skip the `if not self.bucket_pk` block and go straight to `object_by_pk`. No wasted writes, no duplicate INSERTs.
