# Core Lua dependencies

~~~json
{"vibecode": {"doc": "lua_dependencies",
"role": "running list of non-stdlib Lua libraries (and their C-level deps)
the Puck project relies on; one entry per dep with what uses it and why",
"status": "ongoing; add entries as new dependencies are adopted",
"scope": "project_wide_not_just_one_component",
"key_concepts": ["external_deps", "luarocks", "c_bindings",
"crypto", "http", "markdown"]}}
~~~

Lua's standard library is small — no networking, no crypto, no
markdown, no filesystem traversal beyond `io`. Everything beyond
that is an external dependency we need to install and version.

This file lists those deps as they're adopted, and notes what
component requires each. Add new entries as they come up.

<a id="libsodium"></a>
## libsodium

~~~json
{"vibecode": {"dep": "libsodium", "kind": "c_library_with_lua_binding",
"used_by": ["caspian.utils.random", "puck_blockchain_signing"],
"provides": ["crypto_strong_random_bytes", "ed25519_signing"],
"home": "https://libsodium.org/",
"license": "ISC"}}
~~~

**What it is.** A small, security-focused cryptography library
(C, with bindings in most languages). Wraps the OS CSPRNG and
provides Ed25519 signing among other primitives.

**What uses it.**

- [`%utils.random`](../caspian/utils/utils.md) — crypto-strong random
  bytes and UUIDs (`randombytes_buf`).
- The [Puck blockchain](../caspian/blockchain/.md) — Ed25519 signing.

**Why this one.** Smaller and more opinionated than OpenSSL, with
a security-first design and a permissive licence. One library
covers both Caspian's random and the blockchain's signing — no
second crypto dep needed.

---

<a id="luasocket"></a>
## luasocket

~~~json
{"vibecode": {"dep": "luasocket", "kind": "c_library_with_lua_binding",
"used_by": ["orlando"], "provides": ["tcp_sockets", "udp_sockets"],
"home": "https://lunarmodules.github.io/luasocket/",
"license": "MIT"}}
~~~

**What it is.** The de-facto TCP/UDP socket library for Lua.

**What uses it.** [Orlando](../misc/orlando.md) — raw TCP for
accepting HTTP connections. No HTTP-level library; Orlando does
its own request-line parsing and response building on top of
luasocket.

---

<a id="lunamark"></a>
## lunamark

~~~json
{"vibecode": {"dep": "lunamark", "kind": "pure_lua",
"used_by": ["orlando"], "provides": ["markdown_parser"],
"home": "https://github.com/jgm/lunamark",
"license": "MIT"}}
~~~

**What it is.** Pure-Lua Markdown parser (LPeg-based). Visitor-
style: you give it a writer, it walks the source.

**What uses it.** [Orlando](../misc/orlando.md) — renders
documentation `.md` files to HTML on every request. Fenced code
blocks and pipe tables enabled; other extensions off by default.

**Likely future users.** A Markdown helper at the Sammy layer
(`%sammy.render.markdown` or similar) is on the table — see the
[Orlando lesson](../misc/orlando/lessons.md) on this.
