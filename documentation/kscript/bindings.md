# Bindings

A **binding** is the mechanism by which a KScript class reaches
Lua-level functionality (a parsed HTML tree, an HTTP client, a
SQLite connection, etc.) without breaching the security floor
that prevents arbitrary KScript code from accessing Lua directly.

---

## Why bindings exist

KScript is designed so user-level code **cannot reach into Lua**.
That seal is a load-bearing security property — without it,
untrusted code could escape the KScript sandbox into arbitrary Lua
and from there into the host process.

But Kiera's framework needs Lua-backed functionality everywhere:
HTTP, filesystem, JSON, SQLite, crypto, markup parsing, etc. The
question is how user-level KScript classes (Uma, mikobase, Sinatra,
etc.) get to use these Lua libraries without breaking the seal.

**Bindings are the answer.** They're a controlled bridge: each
binding wraps a specific Lua library, exposes a narrow
KScript-callable surface, and is loaded by the engine at startup —
**not at runtime**. KScript classes consume bindings the same way
they consume any other capability.

---

## Install: operator-only, not runtime

A binding includes Lua code. Loading it gives the engine new
Lua-level functionality. **This is a privileged operation** — the
engine operator decides what bindings are installed; KScript code
cannot install or fetch bindings at runtime.

This is intentional and matches how privileged things work
elsewhere in the framework (engine capability grants, role
definitions, etc.). Operator-controlled install means:

- A deployment's binding surface is a known set, established at
  deploy time.
- Untrusted KScript code cannot pull in new Lua at runtime.
- Third-party bindings are real — anyone can write one — but
  installing them is a deliberate operator action, like installing
  a system service.

This is not equivalent to `pip install` or `gem install`. Treat
binding install as more like adding a system service.

---

## How a KScript class uses a binding

A class declares its binding dependency, and the engine raises a
clear error at class-load time if the binding isn't installed. The
class's KScript code then calls the binding's exposed surface to
reach the Lua library.

(Exact mechanism — declaration syntax, error shape, discovery API
— to be specified.)

The flow:

1. Operator installs bindings the engine supports.
2. Engine starts up, registers installed bindings.
3. KScript class loads; if it depends on a binding, the engine
   checks the binding is present. If not, error.
4. Class methods call the binding's surface as needed; binding
   internals call Lua.
5. Bound Lua functionality is exposed to KScript only through
   the binding's surface — never directly.

---

## Naming convention

Bindings live under `kiera.uno/binding/...`:

- `kiera.uno/binding/http`
- `kiera.uno/binding/fs`
- `kiera.uno/binding/json`
- etc.

Named after the **capability**, not the implementation. The
implementation can change (swap libcurl for something else, swap
gumbo for another HTML parser) without renaming the binding.

---

## Core bindings (ship with every engine)

Every engine ships with this baseline set:

| Binding | Purpose | Backing |
|---|---|---|
| `kiera.uno/binding/http` | HTTP client + server | libcurl + libmicrohttpd (or similar) |
| `kiera.uno/binding/fs` | Filesystem operations including `flock`/`fcntl` locking | Lua `io` + LuaFileSystem or similar |
| `kiera.uno/binding/json` | Parse/serialize JSON | lua-cjson or similar |
| `kiera.uno/binding/sqlite` | SQLite driver (used by mikobase) | LuaSQLite3 or similar |
| `kiera.uno/binding/markup` | HTML + XML parsing/serialization | gumbo bindings or similar |
| `kiera.uno/binding/fork` | Process spawning, IPC, signals | luaposix or similar |
| `kiera.uno/binding/crypto` | Cryptographic primitives — hashing, signing, secure random, encryption | luaossl or similar |
| `kiera.uno/binding/time` | Clock, timestamp parsing/formatting, timezone math | OS time + Lua wrappers |

Probably ship (still TBD):

| Binding | Purpose |
|---|---|
| `kiera.uno/binding/compress` | gzip/zlib (HTTP content encoding, log compression) |
| `kiera.uno/binding/encoding` | base64, hex, URL encoding, UTF-8 utilities |

### HTTP client is non-negotiable

Kiera's remote-object IPC depends on HTTP client. Every engine
needs this binding — without it, `%kiera` lookups against remote
objects don't work. It's not optional.

### Filesystem includes locking

`kiera.uno/binding/fs` must include POSIX-style file locking
(`flock`/`fcntl`). Jasmine's directory store and several other
parts of the framework depend on it for concurrency.

### About `crypto`

The name `crypto` here is the **standard software-engineering
term for cryptographic primitives** — hashing (SHA-256, etc.),
signing (Ed25519, RSA), secure random, symmetric encryption (AES),
constant-time comparison. **It is not about cryptocurrency.** The
word has been colloquially hijacked by cryptocurrency news cycles,
but the technical meaning predates that by decades and is what's
intended here.

Kiera uses these primitives for:

- Blockchain signing (see [blockchain.md](blockchain/blockchain.md)).
- Mikobase file deduplication via SHA-256.
- Secure random for UUIDs (Jasmine entries, tokens, identifiers).
- Constant-time secret comparison where needed.

---

## Non-core bindings

Bindings that don't ship by default but the operator can install:

### Postgres driver

**`kiera.uno/binding/postgres`** — Postgres driver for mikobase
backends and other database needs. **Non-core but top-priority.**
Building any real site without Postgres is going to be painful;
expect this to be one of the first non-core bindings most
deployments install.

A working Ruby Pg implementation already exists and serves as the
reference for the KScript binding.

### Others

Anything else outside the core set: DNS-specific work (SRV/MX/TXT
records), email (SMTP), WebSockets standalone, image processing,
PDF generation, gRPC, etc. — all third-party binding territory.

---

## Common driver grammar (planned)

Inspired by Perl's **DBI** (Database Interface), where drivers
(DBD::SQLite, DBD::mysql, DBD::Pg) all implement a uniform
interface, so application code is portable across backends.

**Kiera will adopt the same approach for relational drivers.** A
common grammar for `kiera.uno/binding/sqlite`,
`kiera.uno/binding/postgres`, and any future relational binding —
each implements the shared surface; mikobase (and other consumers)
codes against the shared surface, not the specific driver.

**Start now, while only SQLite is in scope.** The grammar gets
shaped by one concrete driver and is ready when Postgres lands.
Trying to unify after multiple drivers have diverged is the hard
way (Ruby went that route — ActiveRecord, Sequel, etc. all built
their own driver models, fragmenting the ecosystem; the `dbi` gem
never caught on).

The shape of this grammar is TBD — connect, prepare, execute,
fetch, commit, rollback, etc. — to be designed alongside the
SQLite binding spec.

---

## Open questions

Deferred from the initial design conversation; will be addressed
as bindings get spec'd:

- **How does a class declare its binding dependency?** Probably
  something like `requires_binding 'kiera.uno/binding/markup'` at
  class load time.
- **What's the discovery API?** How does a deployment enumerate
  installed bindings so authors can reason about availability?
- **What's the binding API shape?** Probably thin
  KScript-callable functions and primitive data exchange. Full
  object passing across the boundary gets messy.
- **Versioning.** How do bindings declare and respect their own
  version?
- **Install mechanics.** What does the operator-level install
  actually look like — a directory? a config file? a registry?
