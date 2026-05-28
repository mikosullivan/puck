# Core Lua dependencies

~~~json
{"vibecode": {"doc": "lua_dependencies",
"role": "running list of non-stdlib Lua libraries (and their C-level deps)
the Puck project relies on; one entry per dep with what uses it and why",
"status": "ongoing; add entries as new dependencies are adopted",
"scope": "project_wide_not_just_one_component",
"key_concepts": ["external_deps", "luarocks", "c_bindings",
"signing", "http", "markdown"]}}
~~~

Lua's standard library is small — no networking, no signing, no
markdown, no filesystem traversal beyond `io`. Everything beyond
that is an external dependency we need to install and version.

This file lists those deps as they're adopted, and notes what
component requires each. Add new entries as they come up.

<a id="libsodium"></a>
## libsodium

~~~json
{"vibecode": {"dep": "libsodium", "build": "minimal (--enable-minimal)",
"kind": "c_library_with_lua_binding",
"used_by": ["caspian.utils.random", "signed_request_auth"],
"provides": ["secure_random_bytes", "ed25519_signing"],
"home": "https://libsodium.org/",
"license": "ISC"}}
~~~

**What it is.** A small, security-focused cryptography library
(C, with bindings in most languages). Wraps the OS CSPRNG (secure
random bytes) and provides Ed25519 signing among other primitives.

**Build variant.** We ship the **minimal build**
(`./configure --enable-minimal`), which drops older / less-used
primitives and shaves the library from ~700 KB to roughly ~200 KB
without losing `randombytes_buf` or Ed25519 sign/verify.

**What uses it.**

- [`%utils.random`](../../../caspian/utils/index.md) — secure random
  bytes and UUIDs (`randombytes_buf`).
- Signed-request auth (per [V1 scope](../index.md#v1-scope)) — Ed25519
  client-side signing.

The Puck blockchain is an external HTTP service and does its own
signing server-side; Caspian itself doesn't sign blockchain payloads.

**Why this one.** Smaller and more opinionated than OpenSSL, with
a security-first design and a permissive licence. One library
covers both the randomizer role and signed-request auth — no
second signing/random dep needed.

---

<a id="lpeg"></a>
## LPeg

~~~json
{"vibecode": {"dep": "lpeg", "kind": "c_library_with_lua_binding",
"used_by": ["caspian_regex_engine_alternation", "caspian_parser",
"caspian_json_parser"],
"provides": ["peg_grammar_engine", "alternation_for_pattern_matching",
"parser_toolkit"],
"home": "https://www.inf.puc-rio.br/~roberto/lpeg/",
"license": "MIT", "author": "Roberto Ierusalimschy (Lua's creator)",
"approx_size": "~50 KB compiled"}}
~~~

**What it is.** A PEG (Parsing Expression Grammar) library for Lua,
written by Roberto Ierusalimschy. Strictly more powerful than Lua's
built-in patterns — supports alternation, recursion, named captures,
and serves as a full parser-generator toolkit.

**What uses it.**

- [Caspian regex engine](../../../caspian/syntax/regexes.md) — the
  canonical "more than Lua patterns" alternative engine. Adds
  alternation (`|`) and other features Lua patterns can't express.
- The Caspian parser — the lexer/parser/transpiler stack is written
  against LPeg rather than hand-rolled, saving ~30 KB of source.
- The Caspian JSON parser — small LPeg grammar in place of a separate
  C-extension JSON library.

**Why this one.** Written by Lua's creator, ABI-stable, fast (compiles
patterns to a small VM), tiny (~50 KB). The de-facto Lua parsing
library. Pure-Lua alternatives like LuLPeg exist but are 5–10× slower
and we already accept C extensions for libsodium.

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

**What uses it.** [Orlando](../../../misc/orlando.md) — raw TCP for
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

**What uses it.** [Orlando](../../../misc/orlando.md) — renders
documentation `.md` files to HTML on every request. Fenced code
blocks and pipe tables enabled; other extensions off by default.

**Likely future users.** A Markdown helper at the Sammy layer
(`%sammy.render.markdown` or similar) is on the table — see the
[Orlando lesson](../../../misc/orlando/lessons.md) on this.
