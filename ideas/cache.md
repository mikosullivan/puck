# Cache

~~~vibecode
{"vibecode": {
	"doc": "idea",
	"role": "brainstorm: %cache('url') downloads and pins an object identity-cached in the caller's role; the URL binds to the same object across all subsequent %cache calls in that role's subtree. Plain %load('url') stays fresh-per-call for any load where the developer doesn't want identity-caching. Not class-specific — works for classes, functions, singletons, shared config, any URL-loaded object.",
	"key_concepts": ["percent_cache_surface", "percent_load_stays_fresh", "role_tree_scoped_cache",
		"walk_up_ancestor_lookup", "not_class_specific", "object_lifetime_by_reachability"]
}}
~~~

## The tension

If every URL load returned a fresh object, cases needing shared identity would confuse:

~~~caspian
$foo = %load('gumdrop.com/util.casp').new()
$bar = %load('gumdrop.com/util.casp').new()
~~~

`$foo.class` and `$bar.class` would be two distinct class objects — each `%load(...)` call is a fresh load, and each carries its own copy of the definition. Two things fetched from the same address should BE the same, at least when the caller wants that.

If every URL load silently returned the same object, cases NOT wanting shared identity would confuse. Configs, documents, blobs — snapshots taken at load time — reading back the same object on every call is magical caching hidden behind what looks like a plain call.

Different defaults are correct for different situations, so let the caller pick.

## The split

`%cache('url')` — download once, pin the URL-to-object binding in the caller's role, return the same object on every subsequent `%cache('same-url')` call in that role's subtree:

~~~caspian
$foo = %cache('gumdrop.com/util.casp').new()
$bar = %cache('gumdrop.com/util.casp').new()
~~~

Now `$foo.class` and `$bar.class` are the same class object. Every subsequent `%cache('same-url')` from anywhere in the subtree returns that same class object.

`%load('url')` — plain load, returns a fresh object each call, for any URL.

The choice of semantics lives at the call site. Nothing in some other module can silently change how `%load()` behaves; nothing `%cache`d leaks into `%load()`.

## Not class-specific

`%cache` isn't restricted to classes. Functions, singletons, shared config, any URL-loaded object where the caller wants "same address, same object" all use the same surface. The developer wrote `%cache`, so they get identity-caching for whatever the URL resolves to.

## Where the object lives

Every cached object lives in a role. `%cache('url')` walks up the role hierarchy from the calling code, checking each ancestor for a cache entry on that URL:

- If some ancestor already holds the object, the walk returns it. Every descendant of that ancestor reads the same object.
- If no ancestor holds it, the calling role downloads the object and caches it. Descendants of the calling role read it via the same walk on their next call.

The walk and the visibility are one mechanism seen from two sides: descendants can read an ancestor's cache because the walk goes up; the ancestor's cache serves all descendants because the walk finds it.

Isolation falls out of the mechanism. Two role branches that don't share a caching ancestor end up with independent objects for the same URL — each cache entry is scoped to its own subtree, and no role can reach into another's registry.

## Lifetime

The role owns the cache entry, not the object. When a role is deleted, its bucket cascades away and the URL-to-object binding vanishes with it — but the object itself stays alive as long as anything else in the graph references it. Anything that used the cached object still holds a reference, so any surviving user keeps it alive.

The GC substrate handles this with no cache-specific logic:

- Role delete cascades the cache entry away.
- The mark trigger fires on the object's row — an incoming edge just went away.
- The drain traces the object from live roots. Nothing reaches it → sweep. Something reaches it → keep.

The object outlives the role that originally downloaded it exactly when it should — when it's still in use somewhere.
