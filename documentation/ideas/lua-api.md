# Lua-side API

~~~vibecode
{"vibecode": {
	"doc": "lua_api",
	"role": "design notes for how the Caspian engine loads Lua-backed primitives — V1 commits to engine-internal bindings only (libsodium, LPeg, JSON); third-party / user-installable bindings are speculative future work captured here for shape consistency, not V1 deliverables",
	"v1_committed_sections": ["engine_internal_bindings_pattern",
		"engine_namespace", "marshaling_layer", "role_assignment",
		"error_mapping", "lifetime_on_close",
		"capability_enforcement"],
	"speculative_sections": ["binding_packages_v2_plus",
		"per_program_dependency_declaration",
		"third_party_binding_distribution"],
	"running_example": "libsodium",
	"design_log": "../development/v1/caspian/decisions.md"
}}
~~~

V1 ships **engine-internal bindings only**. The engine bundles
libsodium, LPeg, and a JSON parser, exposed to Caspian programs via
the `%engine` namespace. User-installable third-party bindings are
**not** a V1 deliverable.

This page documents:

1. The V1 pattern, anchored in how libsodium is loaded.
2. The supporting machinery (marshaling, roles, errors, capabilities).
3. Speculative future work — what extensibility would look like if and
   when it lands — captured here so the V1 pattern is designed in a way
   that doesn't have to be torn up later.

The decisions log for V1 design overall lives at
[development/v1/decisions.md](../requirements/development/v1/caspian/decisions.md).

---

<a id="v1-pattern"></a>
## V1 pattern: engine-internal bindings via `%engine`

~~~vibecode
{"vibecode": {"section": "v1_pattern", "v1_committed": true,
	"loaded": "at_engine_bootstrap_from_lib_lua_caspian_stdlib",
	"exposed_at": "%engine.<binding_name>",
	"surface": "one_caspian_object_per_binding_with_methods_owned_by_the_binding_role"}}
~~~

Each Lua-backed primitive lives in `lib/lua/caspian/stdlib/<name>.lua`.
At engine bootstrap:

1. The engine loads each stdlib module by `require`.
2. The module declares its **role** (via its module header) and exports
   a **methods table**.
3. The engine creates the role object (`engine.roles.<name>`) if it
   doesn't already exist.
4. The engine creates a Caspian class with the methods, owned by that
   role, and assigns it to `%engine.<name>`.
5. User code reaches the primitives through `%engine.<name>.<method>`.

For V1, "each stdlib module" is one of: `sodium`, `lpeg`, `json`. The
loader walks a fixed list at startup. Nothing dynamic.

<a id="libsodium-walkthrough"></a>
### Worked example: libsodium

The libsodium binding lives at `lib/lua/caspian/stdlib/sodium.lua`:

```lua
--[[
{
  "module": "caspian.stdlib.sodium",
  "role": "Lua wrapper around luasodium; exposed to Caspian as %engine.sodium",
  "owning_role": "sodium",
  "engine_slot": "sodium",
  "exposes": ["random_bytes", "random_uuid", "sign", "verify",
              "hash_sha256"],
  "depends_on": ["luasodium (Lua C extension)",
                 "libsodium (system library, --enable-minimal build)"]
}
]]
local sodium = require("luasodium")
local mar    = require("caspian.binding.marshal")

local M = {}

function M.random_bytes(receiver, args)
    local n = mar.to_number(args[1])
    local bytes = sodium.randombytes_buf(n)
    return mar.from_string(bytes, engine.roles.sodium)
end

function M.random_uuid(receiver, args)
    local raw = sodium.randombytes_buf(16)
    -- Set version (4) and variant (10xx) bits per RFC 4122.
    local b7 = (raw:byte(7) & 0x0F) | 0x40
    local b9 = (raw:byte(9) & 0x3F) | 0x80
    raw = raw:sub(1,6) .. string.char(b7) .. raw:sub(8,8)
        .. string.char(b9) .. raw:sub(10)
    local hex = raw:gsub(".", function(c) return string.format("%02x", c:byte()) end)
    local uuid = hex:sub(1,8) .. "-" .. hex:sub(9,12) .. "-"
              .. hex:sub(13,16) .. "-" .. hex:sub(17,20) .. "-" .. hex:sub(21)
    return mar.from_string(uuid, engine.roles.sodium)
end

function M.sign(receiver, args)
    local data       = mar.to_string(args[1])
    local secret_key = mar.to_string(args[2])
    local ok, sig = pcall(sodium.crypto_sign_detached, data, secret_key)
    if not ok then mar.raise("puck.uno/sodium/error", sig) end
    return mar.from_string(sig, engine.roles.sodium)
end

function M.verify(receiver, args)
    local data       = mar.to_string(args[1])
    local sig        = mar.to_string(args[2])
    local public_key = mar.to_string(args[3])
    local ok = sodium.crypto_sign_verify_detached(sig, data, public_key)
    return mar.from_boolean(ok, engine.roles.sodium)
end

function M.hash_sha256(receiver, args)
    local data = mar.to_string(args[1])
    local hash = sodium.crypto_hash_sha256(data)
    return mar.from_string(hash, engine.roles.sodium)
end

return M
```

The engine's stdlib loader (sketched) handles the registration:

```lua
-- in engine bootstrap
local STDLIB_BINDINGS = { "sodium", "lpeg", "json" }

for _, name in ipairs(STDLIB_BINDINGS) do
    local mod = require("caspian.stdlib." .. name)
    local header = parse_module_header(mod)        -- reads the vibecode block
    local role = engine.roles[header.owning_role]
                 or create_role(header.owning_role)
    local class = {
        name        = "puck.uno/engine/" .. name,
        owning_role = role,
        methods     = mod,
    }
    engine.classes[class.name] = class
    engine.namespace.engine[header.engine_slot] = make_instance(class)
end
```

After bootstrap, a Caspian program can call:

```caspian
$id = %engine.sodium.random_uuid
$signature = %engine.sodium.sign($data, $secret_key)
$verified  = %engine.sodium.verify($data, $signature, $public_key)
```

Cross-role transitions to the `sodium` role happen automatically per
the standard role machinery. The caller's `chain` is wiped at the
boundary; sodium runs in its own context; on return, the caller's
context is restored.

`%engine` is user-role-only by a dedicated check in the engine object
itself; see [engine/](../requirements/caspian/engine/). Its
children are normal objects. Capability is enforced at each method
call by the role transition, not by the namespace.

<a id="lpeg-and-json"></a>
### LPeg and JSON

Same pattern. Two more modules under `lib/lua/caspian/stdlib/`:

- `lpeg.lua` — wraps `require("lpeg")`, exposes `%engine.lpeg.compile`,
  `%engine.lpeg.match`, etc. Userdata wrapping for compiled patterns
  (see [marshaling](#marshaling-rules) below).
- `json.lua` — wraps the engine's existing `caspian.json` (which is
  pure Lua already, but goes through the same registration so the
  surface stays uniform). Exposes `%engine.json.parse`, `%engine.json.encode`.

Three core bindings. Everything user code reaches that's Lua-backed
goes through one of them.

---

<a id="the-pattern"></a>
## The pattern (V1 committed)

The same shape applies to every binding the engine loads. These are
the V1 commitments — they shape how `sodium.lua`, `lpeg.lua`, and
`json.lua` are written, and they're what any future extensibility
work has to fit into.

<a id="engine-namespace"></a>
### `%engine` namespace

Engine-loaded bindings expose themselves under `%engine.<name>`. The
namespace lives in the user's runtime environment alongside
`%stdout`, `%utils`, `%argv`, etc. — set at bootstrap, available as
soon as user code runs.

`%engine` is user-role-only — a deliberate special-case check in
the engine object refuses calls from any role other than `user`.
See [engine/](../requirements/caspian/engine/). Its
children (`%engine.sodium` etc.) are normal objects; capability is
enforced at each method call by the role transition, not by the
namespace structure.

<a id="role-assignment"></a>
### Role assignment

Every binding module declares its `owning_role` in its module
header. The engine creates the role at bootstrap if it doesn't exist,
and registers the binding's methods under it. Each method call into
a binding crosses into the binding's role; on return, the caller's
context restores.

Naming convention: the binding role is named after the binding (`sodium`,
`lpeg`, `json`). They're distinguished from user roles by being
registered roles, not user-defined.

<a id="marshaling-rules"></a>
### Marshaling

The `caspian.binding.marshal` module provides the conversion helpers
every binding uses. The boundary contract:

| Crosses | Stays |
|---|---|
| Numbers, strings (incl. byte strings), booleans, null | Lua tables, Lua functions, Lua userdata, Lua metatables, Lua coroutines |

Easy types via direct helpers:

```lua
mar.to_number(caspian_value)     → Lua number
mar.to_string(caspian_value)     → Lua string
mar.to_boolean(caspian_value)    → Lua boolean
mar.from_number(n, role)         → Caspian value table
mar.from_string(s, role)         → Caspian value table
mar.from_boolean(b, role)        → Caspian value table
```

Harder types — Caspian hashes and arrays — go through `mar.to_table`
and `mar.from_table`, which walk the structure recursively.

Hardest types — Lua userdata (LPeg patterns, file handles) — get
wrapped in **opaque-handle Caspian objects**. The Caspian object has
class, owning role, and a payload that's an integer handle the
binding uses to index into a Lua-side table holding the actual
userdata. Lua functions never cross at all — bindings expose specific
methods, not callable Lua values.

<a id="error-mapping"></a>
### Error mapping

Every Lua-library call is wrapped in `pcall`. On error, the binding
raises a Caspian exception via `mar.raise(class_uns, message)`. The
binding declares its exception class in its module header.

Raw Lua errors must never escape into Caspian. If a binding lets one
through, that's a binding bug.

<a id="lifetime-on-close"></a>
### Lifetime / `on_close`

For bindings that wrap Lua userdata (handles), the Caspian wrapper
class declares an `on_close` that releases the underlying handle:

```caspian
class
    on_close do($call)
        %engine.lpeg.release_pattern(@handle)
    end
end
```

Subject to the standard `on_close` strict rules from
[garbage-collection.md](../requirements/caspian/garbage-collection.md) — 2 ms cap,
no I/O, no allocation. C-library release paths are usually
microseconds; not a real constraint.

libsodium specifically has nothing to release (it's all pure
bytes-in/bytes-out), so `puck.uno/engine/sodium` has no `on_close`.

<a id="capability-enforcement"></a>
### Capability enforcement

Bindings that touch external resources (filesystem, network, env vars,
the Puck graph) consult the capability system **before** calling into
their Lua library:

```lua
function M.read(receiver, args)
    local path = mar.to_string(args[1])
    if not engine.capabilities.fs_allows(path, "read") then
        mar.raise("puck.uno/fs/permission_denied", path)
    end
    -- ... call into the library
end
```

Capability checks are the binding's responsibility, not the engine's.
The engine can't know what a binding will do with its arguments.

libsodium doesn't need capability checks — it only touches kernel
CSPRNG and in-memory crypto. LPeg doesn't need checks — pure compute,
no I/O. A future `fs` binding would.

---

<a id="speculative-extensibility"></a>
## Speculative: third-party / user-installable bindings (NOT V1)

~~~vibecode
{"vibecode": {"section": "speculative_extensibility", "v1_committed": false,
	"defer_to": "v2_or_later",
	"recorded_here": "because_v1_pattern_should_be_designed_so_this_works_as_an_addition_not_a_rewrite"}}
~~~

**Everything below is speculative.** V1 doesn't ship it. It's recorded
here so the V1 pattern (the `%engine.<name>` registration, the
binding-module shape, the marshaling layer) is designed in a way that
extensibility can be added later without restructuring the engine.

<a id="binding-package-shape"></a>
### A binding as a package

A third-party binding would be a Caspian package with two files:

```
puck.uno/binding/foo/
├─ foo.casp          # Caspian-side declaration: class, role, method signatures
└─ foo.lua           # Lua-side trampoline: calls require('foo'), provides bodies
```

The `.casp` file is what Caspian programs see (auditable, reviewable).
The `.lua` file is the bridge — small, mechanical, often auto-generated
from the `.casp` declarations.

Sketched `.casp`:

```caspian
%vibecode <<HEREDOC
{"binding_for": "foo",
 "engine_slot": "foo",
 "owning_role": "foo",
 "underlying_library": "foo (lua)",
 "capabilities_required": []}
HEREDOC

class
    extern &greet($name:)
    extern &count($items:)
end
```

The `extern` keyword declares that the method body lives in the
matching `.lua` file. Exact syntax TBD.

Sketched `.lua` (the trampoline):

```lua
local foo = require("foo")
local mar = require("caspian.binding.marshal")
local M = {}

function M.greet(receiver, args)
    local name = mar.to_string(args.name)
    return mar.from_string(foo.greet(name), engine.roles.foo)
end

function M.count(receiver, args)
    local items = mar.to_table(args.items)
    return mar.from_number(foo.count(items), engine.roles.foo)
end

return M
```

<a id="per-program-declarations"></a>
### Per-program dependency declarations

Programs that need a non-core binding declare it in their vibecode:

```caspian
%vibecode <<HEREDOC
{"bindings": ["puck.uno/binding/foo"]}
HEREDOC

# ... program body
$result = %engine.foo.greet(name: 'world')
```

At program load, the engine:

1. Reads the `bindings` list.
2. Resolves each via `%puck` lookup (downloads/installs if needed).
3. Loads the `.casp` + `.lua` pair.
4. Registers the class under the declared role.
5. Sets `%engine.foo` to an instance.

If a binding can't be resolved, the engine refuses to start the
program with a clear "missing binding" error. Not "runtime error 50
lines in" — load-time refusal.

<a id="resolution"></a>
### Distribution and resolution

How non-core bindings reach the user's machine:

- **UNS lookup** — `puck.uno/binding/foo` is resolved via the
  standard Puck resolution chain (bundled cache → user cache →
  network → fail).
- **Local install** — `caspian install puck.uno/binding/foo` pulls
  it once, caches it.
- **Bundled with the program** — bindings could be vendored inside
  a program directory, no network required.

All speculative. V1 ships only the engine-internal three.

<a id="what-v1-locks-in"></a>
### What V1 locks in (so V2+ extension is additive)

For extensibility to be "just a new loader, not a rewrite," V1 needs
to commit to:

| Decision | Why it matters |
|---|---|
| Bindings register at `%engine.<name>` | V2+ third-party bindings register the same way |
| One Lua module per binding, with module header declaring role + slot | V2+ format extends this with an optional `.casp` companion |
| The marshaling layer is a shared module | V2+ bindings use the same helpers; no special V1 marshaling |
| The role-creation pattern works for any name | V2+ bindings just declare their role and the engine creates it |
| Capability checks live in the binding, not the engine | V2+ third-party bindings can declare their own capability needs uniformly |
| Bootstrap loops over a list of binding names | V2+ extends the loop to include user-declared bindings |

What V1 explicitly does **not** commit to (free to revisit):

- The `.casp` + `.lua` two-file format
- The `extern` keyword
- The vibecode `"bindings"` field for per-program declarations
- UNS resolution of bindings
- The `caspian install` subcommand

These are all V2+ design problems, settled when extensibility is on
the table.

---

<a id="next-steps"></a>
## Next steps for V1

1. **Pin the marshaling module shape** — function naming, signatures,
   return-value conventions. Tiny module, but every binding uses it,
   so getting it right unblocks everything else.
2. **Implement `caspian.stdlib.sodium`** as written above. Validates
   the pattern end-to-end on the simplest binding (bytes in, bytes out).
3. **Implement `caspian.stdlib.lpeg`** as the second validation.
   Exercises the userdata-wrapping case.
4. **Implement `caspian.stdlib.json`** — the existing pure-Lua JSON
   parser, brought under the same registration pattern.
5. **Bootstrap loop** — the engine code that walks the fixed list and
   registers each binding into `%engine`.

Once those five land, the V1 binding story is done. Extensibility
(the speculative half of this doc) becomes V2+ work.
