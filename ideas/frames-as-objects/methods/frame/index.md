# frame

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_methods_frame",
	"role": "class representing a call frame under the frames-as-objects design. Inherits from `object` — picks up the `bucket` accessor for free. Adds `locals`, which returns the frame's locals hash (a HashPrimitive stored inside the frame's bucket under the key `locals`). Every local variable in the frame is a key in that hash.",
	"status": "sketch"
}}
~~~

Represents a call frame. Inherits from [object](https://www.puck.uno/ideas/frames-as-objects/methods/object/) — picks up `bucket` for free. Adds one method: `locals`.

## Methods

### `locals`

Returns the frame's locals hash — a HashPrimitive stored inside the frame's bucket under the key `locals`.

~~~
function locals()
	bucket = self.bucket
	return bucket['locals']
end
~~~

Composes on top of the inherited `bucket` accessor: get the bucket (which materializes it on first access), then look up the entry stored under `locals`.

**Read-only.** `locals` doesn't create the locals hash — it only returns whatever's stored under `bucket['locals']`. On a fresh frame, before anything has been assigned, that's null. Creating the locals hash on demand happens in the assignment path (see the [first-variable walkthrough](https://www.puck.uno/ideas/frames-as-objects/examples/first-variable/#set-framelocalsx-) for how `frame.locals['x'] = <pk>` composes).
