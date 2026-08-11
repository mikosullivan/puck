# Methods

~~~vibecode
{"vibecode": {
	"doc": "ideas_frames_as_objects_methods",
	"role": "class definitions for the frames-as-objects brainstorm. Each class gets its own directory with the class's methods, inheritance, and design notes. Currently: object (root class, provides the bucket accessor everything else inherits) and frame (inherits from object, adds the locals accessor).",
	"status": "sketch"
}}
~~~

Class definitions for the frames-as-objects brainstorm.

## Classes

- [engine](https://www.puck.uno/ideas/frames-as-objects/methods/engine/) — top-level runtime that drives a CVM. Owns the DB handle and the main dispatch loop.
- [object](https://www.puck.uno/ideas/frames-as-objects/methods/object/) — root class; provides `bucket` — the accessor that lazily materializes an object's bucket.
- [frame](https://www.puck.uno/ideas/frames-as-objects/methods/frame/) — represents a call frame. Inherits from `object`. Adds `locals` — the accessor that returns the frame's locals hash.
