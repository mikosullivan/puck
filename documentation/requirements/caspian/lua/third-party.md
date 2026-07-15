# Third-party Lua libraries

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_lua_third_party",
	"role": "spec for how developers install third-party Lua libraries (both pure Lua and C bindings) in Caspian. Caspian ships a thin wrapper — `caspian --install-lua <name>` — that shells out to a user-supplied luarocks, targeting a Caspian-owned tree at ~/.local/share/caspian/lua/ and forcing the build against Lua 5.4 to guarantee ABI match. luarocks itself is a documented prerequisite, not bundled. No curated set of pre-built libs on our side, no CI matrix for Lua libs, no lua-libs download infrastructure — all delegated to luarocks. See ../core/ for what already ships with Caspian.",
	"status": "spec — wrapper command shape, tree location, ABI-match approach via --lua-version, and documented prerequisites all decided; exact CLI details (uninstall/list companion commands, flag pass-through) and error-message wording deferred to implementation",
	"audience": "developers installing third-party Lua libraries for Caspian; release maintainers thinking about what Caspian is and isn't responsible for on the Lua-package side"
}}
~~~

Third-party Lua libraries — libraries developers install beyond what already ships with Caspian (see [core](../core/) for what ships). Foundation:

- We want to support both **pure Lua libraries** and **Lua libs with C bindings**.
- The developer's machine must have **luarocks** installed.

## The wrapper command

Caspian exposes a thin CLI wrapper around luarocks:

~~~
$ caspian --install-lua <package-name>
~~~

Under the hood, this translates to a call like:

~~~
$ luarocks install <package-name> --tree ~/.local/share/caspian/lua/ --lua-version 5.4
~~~

Two `--tree` and `--lua-version` flags do the real work:

- `--tree ~/.local/share/caspian/lua/` — installs into Caspian's own tree, isolated from the user's default luarocks setup.
- `--lua-version 5.4` — forces luarocks to build against Lua 5.4 so any C-binding `.so` files match Caspian's bundled Lua ABI.

Companion commands mirror luarocks:

- `caspian --uninstall-lua <name>` — wraps `luarocks remove --tree ~/.local/share/caspian/lua/ --lua-version 5.4 <name>`
- `caspian --list-lua` — wraps `luarocks list --tree ~/.local/share/caspian/lua/ --lua-version 5.4`

## Caspian's tree

Everything a developer installs through `--install-lua` lands under **`~/.local/share/caspian/lua/`**:

- `~/.local/share/caspian/lua/share/lua/5.4/…` — pure-Lua files (`.lua`)
- `~/.local/share/caspian/lua/lib/lua/5.4/…` — C-binding files (`.so`)

Caspian sets `package.path` and `package.cpath` at engine startup to include only this tree — **not** `~/.luarocks/`, **not** `/usr/local/share/lua/5.4/`. The tree is Caspian-owned; the developer's other Lua projects (if any) are unaffected.

## Why this works for both flavors

- **Pure Lua libs.** luarocks fetches the source `.lua` files and drops them into the Caspian tree. No compilation. Trivial.
- **C-binding libs.** luarocks compiles the C source against Lua 5.4 headers (`--lua-version 5.4` picks them up from the system), links the `.so`, and drops it into the tree. Because the build targets our exact Lua version, the resulting `.so` loads cleanly into Caspian's Lua at `require` time. The musl-vs-glibc corner case still applies to the small subset of extensions that cross the `malloc`/`free` boundary between Lua and their own code (rare in well-behaved extensions).

## Prerequisites the user must satisfy

- **luarocks installed** — the standard Lua-ecosystem package manager. Usually `apt install luarocks` / `dnf install luarocks` / `brew install luarocks`.
- **Lua 5.4 headers available** so luarocks can build for our Lua version — usually `apt install liblua5.4-dev` (or the equivalent for the distro). Required only for C-binding libs; pure-Lua installs don't need headers.
- **A C compiler** (`gcc` or `clang`) — required only for C-binding libs. Standard developer prerequisite.

## Failure modes

The wrapper detects and surfaces these clearly:

- **`luarocks: command not found`** — Caspian points the user at their distro's install instructions.
- **luarocks can't build for Lua 5.4** (headers missing) — Caspian passes luarocks's error through and adds a suggestion like "install Lua 5.4 headers, e.g. `apt install liblua5.4-dev`."
- **Package doesn't exist / build fails** — Caspian passes luarocks's error through unmodified. luarocks's own diagnostics are already good; we don't need to wrap them.

## What we DON'T do

By design:

- **Don't bundle luarocks.** ~330 kb budget hit is not worth it; users get luarocks their own way.
- **Don't maintain a curated set of pre-built libs.** luarocks catalog IS the catalog.
- **Don't run our own CI matrix for Lua libs.** Compilation happens on the user's machine at install time via their luarocks.
- **Don't host per-arch Lua-lib tarballs.** No download infrastructure for lua-libs beyond what luarocks does.
- **Don't touch the user's default luarocks tree.** Our tree is separate; their existing Lua work is unaffected.

The wrapper is a thin coordination layer, not a package manager. The actual work is luarocks's job.
