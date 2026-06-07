# Shared hash

~~~json
{"vibecode": {
	"doc": "uds_shared_hash",
	"role": "spec for the shared hash returned by $uds.share — a wrapper object that implements the hash interface but isn't itself a hash. Reads and writes translate to UDS calls against the server-held authoritative state. Nested access works at any depth via chained sub-wrappers. Regular hashes assigned INTO a shared hash get adopted into the shared structure. After the share block ends, the wrapper collapses to a regular hash holding the final state.",
	"parent_doc": "network/uds/index.md",
	"status": "committed for V1.0 — wrapper model, write semantics, sub-wrapper chaining, regular-hash adoption, lifecycle, class-stack PK storage, namespace-clean serialization all settled. Remaining open points (read materialization model, atomic-update primitives, iteration mode, error handling, sub-wrapper identity, edge cases) get settled during implementation rather than blocking design. Depends on UDS, Sammy, forking, and permission infrastructure also landing in V1.0.",
	"key_concepts": ["outer_is_a_wrapper_not_a_real_hash",
		"wrapper_implements_hash_interface",
		"writes_send_updates_to_uds_server",
		"sub_access_returns_sub_wrapper_bound_to_deeper_path",
		"regular_hash_gets_adopted_when_assigned_into_shared",
		"clean_handoff_to_regular_hash_when_share_block_ends",
		"every_hash_and_array_has_a_primary_key_sequence_integer",
		"wrappers_hold_pks_not_paths_so_data_can_be_moved",
		"server_attaches_a_shared_hash_node_class_platter_to_each_tracked_object",
		"pk_lives_in_the_platters_own_bucket_not_in_user_data",
		"pk_metadata_travels_via_http_header_not_in_data"]
}}
~~~

`$uds.share(N) do($hash) ... end` gives each of the N forked workers a `$hash` wrapper. The wrapper looks and behaves like a normal Caspian hash (`[]`, `[]=`, `any?`, `each`, `keys`, etc.) but isn't actually a hash — it's a thin wrapper that translates each operation into a UDS call against the server process that holds the authoritative state. Workers can read and write shared state with no awareness that they're talking to another process.

This doc covers the wrapper's behavior, how nested access works through sub-wrappers, how regular hashes get adopted when assigned into a shared structure, and what happens at the end of the share block.

---

<a id="client"></a>
## Client

This section covers the wrapper API — what user code sees and writes. The actual storage layer (how PKs are tracked, how the server lays out its state) lives in [Server](#server) below.

<a id="client-api"></a>
### API

Treat the shared hash like any regular Caspian hash. All standard hash operations work — set, get, nested access, deletion, iteration. There's no special syntax for "this is a shared hash, treat it differently"; the IPC is invisible.

~~~caspian
# Set scalars
$hash['name']   = 'workers'
$hash['count']  = 42
$hash['active'] = true

# Set a hash (empty or with contents)
$hash['foo'] = {}
$hash['foo'] = {a: 1, b: 2}

# Nested writes at any depth — missing intermediate hashes get created as needed
$hash['users']['alice']['name']  = 'Alice'
$hash['users']['alice']['score'] = 100
$hash['a']['b']['c']['d']['e']   = 42

# Read values
$name = $hash['users']['alice']['name']

# Standard hash surface
$hash.keys
$hash.any?
$hash.each do($k, $v)
    # ...
end
$hash.delete('users')

# Build locally, publish by inserting, keep using the local reference
$cart = {}
$hash['cart_42'] = $cart
$cart['item_1'] = {price: 5}    # writes propagate to the shared structure
~~~

Workers write code that looks like normal hash code. The cross-process synchronization, the path-aware routing, the request-response dance with the server — none of it shows up in the API.

#### Value types

**Only JSON primitives can be stored** — strings, numbers (integer or float), booleans, `null`, arrays, and nested hashes. Anything else (class instances, closures, functions, references to live engine objects, etc.) raises an exception at write time.

~~~caspian
$hash['count']    = 42                    # number — OK
$hash['name']     = 'workers'             # string — OK
$hash['active']   = true                  # boolean — OK
$hash['missing']  = null                  # null — OK
$hash['tags']     = ['a', 'b']            # array of primitives — OK
$hash['user']     = {name: 'Alice'}       # nested hash of primitives — OK

$hash['handler']  = do(...) ... end       # closure — RAISES
$hash['my_obj']   = %puck['foo/bar'].new  # class instance — RAISES
$hash['socket']   = $sock                 # live engine object — RAISES
~~~

For sharing arbitrary Caspian objects across forks, use [Mikobase](../../../mikobase/) instead — Mikobase is the object store; the shared hash is the JSON-shaped lightweight alternative.

---

<a id="under-the-hood"></a>
### Under the hood

What's actually happening on each operation.

<a id="top-level-writes"></a>
#### Top-level writes

~~~caspian
$hash['foo'] = 'bar'
~~~

The wrapper's `[]=` method packages the key and value into an update request and sends it to the UDS server. The server stores `foo: 'bar'` in its authoritative hash. One round-trip per top-level write.

<a id="assigning-a-hash"></a>
#### Assigning a hash

~~~caspian
$hash['foo'] = {}
~~~

Sends an update to create an empty hash at path `['foo']` on the server. The shared structure now has a sub-hash at `foo`.

When assigned with contents (`$hash['foo'] = {a: 1, b: 2}`), the contents are sent to the server in one update; the sub-tree at `foo` is replaced wholesale.

<a id="nested-access"></a>
#### Nested access via sub-wrappers

~~~caspian
$gup = $hash['foo']['gup']
~~~

Each `[]` access returns a **sub-wrapper** bound to the accumulated path. The chain accumulates the path without round-tripping; only terminal operations (writes, value materialization) actually hit the server.

After this line, `$gup` is itself a wrapper — a "fake hash" — bound to path `['foo', 'gup']`. The path doesn't have to exist on the server yet; the wrapper just carries the path.

Writes through the sub-wrapper send updates with the full accumulated path:

~~~caspian
$gup['zap'] = 1
~~~

This sends a write request with path `['foo', 'gup', 'zap']` and value `1`. The server walks the path and stores the value, auto-vivifying intermediate hashes as needed (TBD whether auto-vivification is the default; see [open points](#open-points)).

The same wrapper semantics apply at every depth — `$hash['a']['b']['c']['d']['e'] = 42` works exactly like top-level writes, just with a longer path.

<a id="adoption"></a>
#### Adopting a regular hash into the shared structure

A regular Caspian hash can be assigned into a slot in a shared hash, and the local reference keeps working as a wrapper:

~~~caspian
$foo = {}
$hash['foo'] = $foo
$foo['zap'] = 1     # this mutation propagates to the server
~~~

What happens at the assignment:

1. The current contents of `$foo` (an empty hash here, or whatever it contained) get sent to the server at path `['foo']`.
2. `$foo` is **transformed into a wrapper** bound to path `['foo']` on the shared structure. Same variable, same identity from the user's POV, but the object's behavior changes — it's now a wrapper, not a regular hash.
3. Future operations on `$foo` (`$foo['zap'] = 1`, `$foo.any?`, `$foo['anything']`, etc.) go through the wrapper and hit the server.

This means there's no distinction between "I made a wrapper through `$hash['foo']`" and "I made a regular hash and inserted it." Both paths lead to the same wrapper bound to the same path. A worker can build state locally, publish it by inserting, and keep using the local variable to mutate — every change propagates.

The adoption is one-way: the wrapper acts like a hash forever after. There's no "un-adopt" operation that turns it back into a regular hash. The local variable stays bound to the wrapper for its lifetime.

<a id="reads"></a>
#### Reading values

When a worker reads from the shared hash, there are two cases:

- **Sub-hash reads** (`$x = $hash['foo']` when `'foo'` is a hash on the server) return a sub-wrapper bound to path `['foo']`. The worker can keep using `$x` as if it were a hash — further indexing chains the path; mutations propagate.
- **Scalar reads** (`$x = $hash['foo']` when `'foo'` is a scalar like a string or number) need to materialize. Three models possible — see [Open points](#open-points) — but the cleanest is "round-trip on use when it's clear the user wants the value, not the path" (lazy materialization).

A common pattern works regardless of which model:

~~~caspian
if $hash['active']         # comparison forces materialization
    do_something
end
~~~

Whichever read model gets settled, the wrapper has to know when to fetch — either eagerly (every `[]` round-trips) or lazily (only when an operation forces materialization).

---

<a id="server"></a>
## Server

This section covers how the server stores the shared state — the layout of its `state`, how primary keys are attached to each hash/array, and why nothing extra lives in the wire format.

The server keeps two top-level properties:

- **`state`** — the hierarchical user data (the tree clients navigate). Just a plain hash; user data fills it normally.
- **`sequence`** — an integer counter, starts at 0 when the server spawns; incremented every time the server creates a new hash or array.

That's all. No registry, no marker-stripping step, no parallel indexes to keep in sync.

The trick: each tracked hash/array carries its primary key as **class-stack metadata** rather than as a key inside the data. The engine defines a class (working name `puck.uno/network/uds/shared-hash-node`) with one field — `pk: integer` — and adds it to every hash and array the server creates. The hash/array itself is plain data; the PK lives on the class attached to it.

~~~caspian
# When the server creates a new hash or array:
$object.pk = $sequence++
~~~

Lookup-by-PK walks `$state` recursively; at each candidate, the server reads the candidate's `.pk` from the class-stack and matches against the target.

Because the PK lives in class-stack state rather than in the data, JSON serialization of `$state` produces clean output automatically — no marker keys to strip, no wire-layer cleanup step.

### Each hash/array carries a PK on its class stack

The engine defines a class — working name `puck.uno/network/uds/shared-hash-node` — with one field: `pk: integer`. The server adds this class to every hash and array it tracks (the root hash plus any sub-hash or array created as a result of a write).

The hash/array itself is plain user data; the PK lives in **class-stack state**, not in the user's data namespace. Reading the PK is just `$object.pk`; setting it is `$object.pk = $sequence++`.

Specifically, the PK is stored in the **shared-hash-node platter's own bucket**, not in the host object's main bucket. That's the standard Caspian platter pattern — each platter carries its own private state separate from the host's shared bucket. The host's bucket is the user's hash data; the platter's bucket holds `{pk: <integer>}`. The two namespaces never mingle.

Example shape of `state` — what the server actually holds:

~~~
$state                                          (pk: 0)
  foo:                                          (pk: 1)
    bar:                                        (pk: 2)
      stuff: [                                  (pk: 3)
        "actual_item_1",
        "actual_item_2"
      ]
~~~

Four objects, four PKs, all stored as `.pk` on each hash/array's class stack. The user's data namespace contains exactly what the user put there — no markers, no reserved keys, no inline UUIDs.

### PK assignment at creation time

When the server creates a new hash or array (in response to a write that produces one):

~~~caspian
$new_object.pk = $sequence++
~~~

Sequence starts at 0 when the server spawns and increments per allocation. Each share session has its own server, so PKs are local to the session — different share calls never collide. Sequence integers are small (4 bytes), debug-friendly ("hash #47"), and require no entropy.

### Lookup by PK

To find the hash or array with a given PK, the server walks `$state` recursively, reading each candidate's `.pk` from the class stack and matching against the target.

~~~caspian
function &find_by_pk($node, $target_pk)
    if $node.pk == $target_pk
        return $node
    end
    if $node.is_hash?
        $node.each do($k, $v)
            $found = &find_by_pk($v, $target_pk)
            if $found
                return $found
            end
        end
    elsif $node.is_array?
        $node.each do($v)
            $found = &find_by_pk($v, $target_pk)
            if $found
                return $found
            end
        end
    end
    return null
end
~~~

O(N) per lookup where N is total nodes in the tree. For the share-session use case (a few workers coordinating short-term state), the trees are small and the walks are microseconds. If real perf needs ever arise, an index can be layered on later without changing the rest of the model.

### Wire-protocol PK metadata

Since the PK doesn't live in the user data at all, JSON serialization of any hash/array is already clean — no marker to strip. The server's response body is just `JSON.dump($the_object)`.

The PK itself is delivered out-of-band via HTTP header:

```
X-PK: 47
```

Client reads the header and stashes the integer in the wrapper.

### GC for orphaned PKs

A hash/array that's no longer reachable from the root `$state` AND not held by any active client wrapper can be dropped from memory:

- Server tracks which `.pk` values are referenced from the root tree (reachability traversal).
- Server tracks which `.pk` values are held by active client connections (per-connection refcount).
- When both go to zero, the hash/array is unreferenced and can be collected by normal GC.

For the share-block use case, GC mostly takes care of itself — when a worker's connection closes, its PK refs drop; once the share block ends, the server tears down entirely.

### Why this approach

- **Reuses Caspian's existing class-stack mechanism.** Adding a class to an object to give it extra metadata is a settled idiom in Caspian's object model. No new pattern to invent; no new vocabulary for users to learn.
- **No reserved field names — for real.** User data can use literally any key name without collision concerns. There's no UUID-format restriction, no "if this looks like a marker we'll strip it" disambiguation rule. Markers don't exist in the data at all.
- **Wire format is automatically clean.** Serializing `$state` produces user data only. No strip step needed. Nothing to keep in sync.
- **One structure on the server.** Just `$state` (plus a small integer `$sequence`). No parallel index, no lookup hash, no refs map. Less code, fewer invariants, fewer bugs.
- **Sequence integers beat UUIDs for this use case.** 4 bytes vs 36 chars on the wire, debug-friendly ("hash #47"), no entropy required.

---

<a id="lifecycle"></a>
## Lifecycle

The shared hash exists for the duration of the `share(N) do(...) end` call. When all N forks have returned:

- The server drains any in-flight requests, stops accepting new ones, and shuts down.
- `share()` returns. The expression's value is the **final hash** — a regular Caspian hash holding whatever state the workers collectively wrote. NOT a wrapper, NOT a live proxy. Plain data the parent can inspect.

~~~caspian
$hash = $uds.share(20) do($hash)
    # ... workers write to $hash ...
end

# After share returns, $hash is a regular hash. No more server, no more proxying.
puts $hash.keys
~~~

Clean handoff: the parent gets data, not a handle. If a worker held a local wrapper variable (`$foo`, `$gup`, etc.) when its block ended, those wrappers are gone with the forked process — they don't survive back to the parent.

---

<a id="performance"></a>
## Performance characteristics

Every operation that actually hits the server is one UDS round-trip. UDS round-trips on the same machine are fast (microseconds) but not free:

- **Chatty patterns suffer.** A worker that does `$hash['counter'] = $hash['counter'] + 1` in a tight loop pays two round-trips per iteration. The reads/writes serialize through the single-threaded server.
- **Atomic-update primitives** (e.g., `$hash.atomic_increment('counter')`, `$hash.modify('counter') do($v) ... end`) would let users do one-round-trip updates for the common "increment / update if condition" patterns. Out of scope for V1; flagged as a future addition once the basic surface is stable.
- **Local caching is dangerous** because other workers can mutate the server's state at any time. The cleanest model is no client-side cache; every materialization round-trips.
- **Batching** for "set many keys at once" might be useful at the wrapper level. TBD.

---

<a id="open-points"></a>
## Open points

- **Read materialization model.** When `$x = $hash['foo']`, does the wrapper fetch immediately, return a proxy that materializes on first use, or distinguish read vs write at the parser level? Sub-hash reads clearly return sub-wrappers; scalar reads need a clear answer.
- **Auto-vivification.** When `$hash['foo']['bar']['gup'] = 'bear'` runs and intermediate hashes don't exist on the server, does the server create them automatically, or raise? Auto-vivification is friendlier; explicit construction is more disciplined.
- **Atomic-update primitives.** `.atomic_increment`, `.modify(key) do($v) ... end`, or similar — necessary for race-free increments. Probably post-V1.
- **Iteration mode.** `$hash.each do(k, v) ... end` — snapshot at the call point, or live (re-fetch on each `next`)? Snapshot is the safe default.
- **Error handling.** What happens if the server crashes mid-call? Auto-retry by the wrapper (similar to the initial connect retry)? Exception? Per-worker shutdown?
- **Other data types.** Currently spec'd for hashes. Does an analogous "shared array" exist? "Shared object" for arbitrary classes?
- **Sub-wrapper identity.** If two pieces of code both navigate to `$hash['foo']`, do they get the same sub-wrapper instance, or two distinct wrappers pointing at the same path? Affects `==` comparisons and reference equality between wrappers.
- **What gets sent on adoption.** When `$hash['foo'] = $foo` adopts a populated `$foo`, the contents go to the server. Does the engine send the WHOLE existing tree (potentially large), or differentially compute what's new? Probably whole-tree for V1 simplicity; differential for performance later.
- **Cross-block wrapper passing.** Can a wrapper be passed to a function/method and used there? Presumably yes (just a normal object reference), but worth confirming the role boundary doesn't break it.

---

<a id="implementation"></a>
## Implementation

The shared hash isn't a new primitive — it's a composition of the UDS toolbox already specified. `$uds.share(N) do($hash) ... end` is what you'd write yourself if you had to build it from `%utils.network.uds.new()`, `%utils.forks.multiple`, and the wrapper pattern. The engine does it for you, but the building blocks are the same.

### What the engine does internally when `$uds.share` is called

Three logical pieces wire together: a **lightweight server process** that holds the shared state, **N worker processes** that mutate it, and a **wrapper** that workers use to make HTTP calls into the server. The engine spins all three up; user code never sees them directly.

#### The server

A lightweight UDS-backed HTTP server. Single-process, single-threaded, doesn't fork anything. It just accepts connections from the workers and processes requests against its in-memory state.

~~~caspian
# Stand up the server.
$uds_internal = %utils.network.uds.new()
$uds_internal.authenticate = true

# Server-side state. Just two pieces:
#  - $state: the hierarchical user data (the tree clients navigate)
#  - $sequence: integer counter for the next PK to assign
$state    = {}
$sequence = 0

# Attach the shared-hash-node platter to $state so it carries a pk.
# The pk lives in the platter's own bucket, not in $state itself.
$state.classes.add(puck.uno/network/uds/shared-hash-node)
$state.pk = $sequence++    # root gets pk 0; sequence becomes 1

$root_pk = $state.pk        # 0

# Register HTTP routes. Each handler walks $state recursively to find
# the target by PK (reading the .pk from the class-stack platter on
# each candidate), then performs the requested operation.

$uds_internal.get('/pk/{pk}') do($request)
    $target = &find_by_pk($state, $request.path['pk'].to_integer)
    if !$target
        raise puck.uno/error/uds/no_such_pk
    end
    # No strip step needed — pk lives on the class stack, not in the data.
    # JSON.dump produces user data only.
    $response.header('X-PK', $target.pk)
    return $target
end

$uds_internal.put('/pk/{pk}/key/{key}') do($request)
    $target = &find_by_pk($state, $request.path['pk'].to_integer)
    if !$target
        raise puck.uno/error/uds/no_such_pk
    end
    $key   = $request.path['key']
    $value = $request.body

    if $value.is_hash? or $value.is_array?
        # New sub-hash/array. Attach the platter, assign a pk, link it in.
        $value.classes.add(puck.uno/network/uds/shared-hash-node)
        $value.pk = $sequence++
        $target[$key] = $value
        $response.header('X-PK', $value.pk)
    else
        # Scalar — just store it.
        $target[$key] = $value
    end
end

$uds_internal.delete('/pk/{pk}/key/{key}') do($request)
    $target = &find_by_pk($state, $request.path['pk'].to_integer)
    $key    = $request.path['key']
    $target.delete($key)
    # The deleted sub-tree (if any) is now unreachable from $state;
    # normal GC reclaims it once no active client wrapper holds its pk.
end

# ... .post('/pk/{pk}/push'), .get('/pk/{pk}/keys'), etc. for the rest of the surface.

# Run the accept loop. Blocks here until something kills the server.
$uds_internal.wait()
~~~

#### The workers

N tracked forks. Each captures the wrapper via closure and runs the user's block. The forks DON'T touch the server's `$state` directly — they only see it via HTTP through the wrapper.

~~~caspian
# Build the client wrapper bound to the server's root PK.
$root_wrapper = $wrapper_class.new(
    client: $uds_internal.client,
    pk: $root_pk,
)

# Fork N tracked workers; each gets $root_wrapper as $hash via closure capture.
%utils.forks.multiple($n) do($fork)
    $hash = $root_wrapper    # captured from outer scope
    # ... user's block runs here with $hash bound ...
end
# %utils.forks.multiple blocks here until all N workers finish.
~~~

#### What `$uds.share` does as orchestrator

`share` is the bit of engine machinery that sequences all of the above:

1. Spawn the server (its own process; it doesn't fork — it just runs the accept loop).
2. Build the root wrapper.
3. Fork N workers; each runs the user's block with `$hash` bound to the wrapper.
4. Wait for all workers to finish (`%utils.forks.multiple` blocks until they're done).
5. Ask the server for its final state via one last `GET /pk/<root-pk>`.
6. Tell the server to shut down.
7. Strip any remaining markers; return the result as `share()`'s value.

The server is "lightweight" in two ways: it has no forks of its own, and the protocol surface it implements is small (a handful of routes against in-memory structures). The user-facing complexity comes from the wrapper abstraction; the server itself is straightforward.

### The wrapper class

The wrapper is the "fake hash" — the object that implements the hash interface and translates each operation into an HTTP call. Stored at `$wrapper_class`:

~~~caspian
$wrapper_class = class
    field :client
    field :pk
    field :sub_path    # for sub-wrappers; empty array for the root wrapper

    method &[](key)
        # If value at this key is a hash/array, return a new wrapper
        # bound to its PK. If it's a scalar, materialize and return it.
        $resp = @client.get('/pk/' + @pk + '/key/' + .path_segment(key))
        if $resp.header('X-PK')
            return $wrapper_class.new(client: @client, pk: $resp.header('X-PK'))
        else
            return $resp.body    # scalar
        end
    end

    method &[]=(key, value)
        # If value is a regular hash/array, the server will assign a fresh PK
        # and we should transform any local reference to be a wrapper too.
        @client.put('/pk/' + @pk + '/key/' + .path_segment(key), body: value)
    end

    method &any?()       ; @client.get('/pk/' + @pk + '/any?').body          ; end
    method &keys()       ; @client.get('/pk/' + @pk + '/keys').body          ; end
    method &each($block) ; .keys.each do($k) ; $block.call($k, .[$k]) ; end  ; end
    method &delete(key)  ; @client.delete('/pk/' + @pk + '/key/' + key)      ; end
    # ... rest of the standard hash interface, each method translated to one HTTP call.
end
~~~

For sub-wrappers, the wrapper class also carries the sub-path within its current PK; method calls combine the PK and the sub-path into the HTTP URL. Or alternatively, every `[]` immediately resolves to a new sub-wrapper bound to the sub-hash's PK (which is the cleanest model since wrappers carry PKs not paths — see [Open points](#open-points) on read materialization).

### Adoption

When `$hash['foo'] = $foo` is called and `$foo` is a regular Caspian hash:

1. The wrapper's `[]=` method sends `$foo`'s contents to the server (one PUT with the whole sub-tree).
2. The server creates a new hash, attaches the shared-hash-node platter to it, sets `.pk = $sequence++`, links it at `$state["foo"]`, returns the new PK in the response header.
3. The wrapper transforms `$foo` in place — replaces `$foo`'s object with a new wrapper instance bound to the just-returned PK.
4. Future operations on `$foo` go through the wrapper.

The transform-in-place step is the only "magical" piece — it changes what `$foo` IS at runtime. Implementation: replace the object's class and bucket, similar to how the engine's other adoption / shadowing patterns work elsewhere.

### Pieces reused from the UDS toolbox

| Shared-hash pattern | UDS primitive providing it |
|---|---|
| The wire transport | `%utils.network.uds.new()` |
| Auth between worker and server | `$uds.authenticate = true`, `Authorization: Bearer <token>` |
| Worker spawn + lifecycle | `%utils.forks.multiple(N)` |
| Auto-cleanup at end | `%engine.auto_close_forks` default behavior |
| Token + client inheritance through forks | Closure capture (fork closure semantics) |
| Connection retry while server starts | `$client.<verb>` auto-retry pattern |
| HTTP method-and-path routing | Sammy (under the hood of `$uds`) |
| Per-hash/array identity | Sequence-integer PK attached to each object via the shared-hash-node platter (this doc's Server section) |
| Clean wire format | PKs live on the class stack, not in the data — JSON serialization is automatically clean |
| Clean handoff | Engine snapshots `$state` and returns as a regular hash when share() ends |

Nothing new at the protocol layer. The shared hash is the same pattern any developer could build on top of the UDS toolbox; the engine bundles it as `$uds.share` because it's a common-enough pattern to deserve a one-liner.
