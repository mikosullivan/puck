# Installation Lua libs

*Design for the CLI install-and-use story for Lua libraries in Caspian. Caspian objects are hot-fetched via `%puck` at first use; Lua libraries need an explicit install step because Lua's `require` uses filesystem path search, not URL fetch.*

~~~vibecode
{"vibecode": {
	"doc": "idea_installation_lua_libs",
	"role": "design for how developers install and use Lua libraries with Caspian. Two parts: where the libs live on disk (settled: under ~/.local/share/caspian/, XDG data home), and how they get installed (explicit CLI command, not hot-download). C-extensions-vs-pure-Lua-only is a deferred scope question. Related: idea_other_lua_libs for what's already bundled in the binary itself.",
	"status": "brainstorm — storage location, install model (hybrid pure-Lua + curated pre-built C extensions), and same-basis download scheme (per-arch dispatcher, matches the caspian binary itself) all settled; install-command shape, curated-set contents, tarball-vs-split for mixed libs, and version-pinning still open"
}}
~~~

## Storage location

Under XDG data home: **`~/.local/share/caspian/lua/`**. Internal layout (share/lib subdirs, version subdirs, etc.) is a smaller design pass; the umbrella location is settled. Caspian's `package.path` and `package.cpath` get set to point there at startup so `require` finds installed libs without any developer-side path fiddling.

## Caspian's own tree, not system integration

Two reasons:

- **ABI compatibility.** Caspian bundles Lua 5.4, musl-static. C extensions installed elsewhere (`~/.luarocks/`, `/usr/local/share/lua/5.4/`) are typically built against glibc and possibly a different Lua version — loading them into Caspian's bundled Lua risks hard-to-diagnose crashes.
- **Self-contained philosophy.** The single-binary + `~/.cache/caspian/` + `~/.local/share/caspian/` posture means Caspian owns its own world. Users who want existing luarocks-installed libs available in Caspian install them into Caspian's tree via our command.

## Install command

Not hot-downloaded like Caspian objects. Explicit CLI — something like `caspian --install-lua-lib <url>` or `caspian --install-lua <name>`. Exact form is a separate design pass.

## The install model

Hybrid: pure Lua by default, plus a small curated set of pre-built C-extension binaries.

**Pure-Lua libraries.** Install command copies `.lua` files into `~/.local/share/caspian/lua/share/`. No build tooling, no architecture concerns, no ABI issues.

**Pre-built C extensions.** Caspian project maintains a repository of C-extension binaries compiled against our exact Lua build for each supported architecture. `caspian --install-lua-lib <name>` fetches from that repo. Similar to Homebrew's bottles or Python wheels. No user-side toolchain required. The set is intentionally small and curated — libraries we've evaluated as worth the maintenance burden.

**Explicitly not doing: build on the user's machine.** No `gcc`/`clang` invocation at install time. Brittle in practice — user's toolchain state, our Lua headers matching what the user has, system-library dependencies (`luasec` wants OpenSSL, etc.). If a C extension isn't in our curated pre-built set, it isn't installable via the standard command. Developers who want an unsupported lib can drop it into the tree manually — off the paved path.

## Where the pre-built binaries are served

Same basis as the [`caspian` binary itself](../../requirements/caspian/installation/): per-arch builds under `/download/linux/<arch>/`, fronted by the same dispatcher pattern. One release infrastructure, one convention.

- **URL scheme.** `/download/linux/<arch>/lua-libs/<lib>` (exact suffix TBD).
- **Dispatcher.** Extends `arch.casp` (or a sibling script) to accept a library identifier along with OS/arch — same 302-redirect model.
- **Per-arch CI matrix.** Every supported architecture gets its own `.so`, built against Caspian's exact bundled Lua (5.4, musl-static) at release time.

Two shapes still open:

- **How to bundle mixed libs.** Libs with both `.lua` and `.so` install as a unit. Cleanest: **one per-arch tarball** per lib (both parts together). Splitting `.lua` (arch-independent) from `.so` (per-arch) is possible but adds a fetch and coordination.
- **Version pinning.** Serve "latest" only, or version-tagged (`luasodium-1.2.3.tar.gz`)? Same question we punted on for the caspian binary — resolve together.

## Also deferred

- **Version management, uninstall, dependency resolution.** Separate concerns, not spec'd here.
