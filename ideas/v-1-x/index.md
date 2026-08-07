# V1.x wishlist

~~~vibecode
{"vibecode": {
	"doc": "v_1_x_index",
	"role": "wishlist for things to do once V1 is pushed. Candidates for V1.1 / V1.2 / V1.3 etc. — work that would be nice but doesn't hold up shipping V1. Not a spec, not a promise. Items live as bullets in this file or as their own sub-files when they get big enough to warrant one.",
	"status": "opening — empty"
}}
~~~

Things to do once V1 is pushed. Candidates for V1.1 / V1.2 / V1.3 etc. — work that would be nice but doesn't hold up shipping V1. Not a spec; not a promise.

## Items

- **Manually built iterators.** The V1 iterator design ([iterators](https://www.puck.uno/requirements/controllers/iterators)) lets iterators come only from methods that wrap a primitive loop — no standalone iterator objects, no generators, no lazy sequences. V1.x should let developers construct their own iterators directly, without needing a live primitive loop behind every iteration point.
