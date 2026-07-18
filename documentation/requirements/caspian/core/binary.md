# The `caspian` binary

~~~vibecode
{"vibecode": {
	"doc": "requirements_core_binary",
	"role": "spec for the caspian binary: what's compiled into it (Lua interpreter, engine, stdlib, select C extensions, musl libc), how it's built (musl-static, per-CPU-arch), and how it's distributed (per-arch downloads served from caspian.uno). See index.md for the unified downloads table that lists everything (binary contents plus the small set of Cache-tier Lua libs pre-installed to disk).",
	"status": "spec — packaging model (single static binary, musl-linked, per-CPU-arch) settled; Lua version pending review before V1; specific dependency versions and build pipeline details pending",
	"audience": "release maintainers building and shipping Caspian binaries; developers curious about what actually gets installed; distribution maintainers"
}}
~~~

Caspian ships as a **single statically-linked binary per CPU architecture**. The core runtime — Lua interpreter, engine, stdlib, and the C extensions Caspian's own engine machinery depends on (libsodium / luasodium for crypto; LPeg for parsing; luasocket for networking) — is compiled into that one file. A small set of additional Lua libraries ships alongside (the Cache rows in [the core table](https://puck.uno/documentation/requirements/caspian/core/#contents-at-a-glance)), pre-installed to `~/.local/share/caspian/lua/` at install time and loaded lazily by `require` when Caspian code touches them. The binary itself has zero runtime dependencies — no dynamic loader involvement for the compiled-in parts, no libc version drift, no worry about which distro's libc the user has.

## What's in the binary

The full inventory of what ships with Caspian — binary contents plus pre-installed Lua libs — lives in the unified table at [core](https://puck.uno/documentation/requirements/caspian/core/#contents-at-a-glance). Rows tagged **Executable** in that table are what's compiled into the `caspian` binary; rows tagged **Cache** are Lua libs pre-installed to disk.

Each Executable-tier C extension is registered as a built-in via Lua's C API (`luaL_requiref` at engine startup), so `require('lpeg')` from Caspian just finds the pre-loaded module — no filesystem lookup, no dynamic loader involvement.

## Size budget: floppy-fits

The whole thing is deliberately designed to **fit on a 1.44 MB floppy** with ≈260 KB of headroom. Every new C binding proposal has to earn its weight against that budget. This is a design constraint, not a decoration — it keeps the runtime honest and forces "do we really need OpenSSL here or can we get by with libsodium-minimal" conversations.

For comparison: Deno ships at ~100 MB, Bun at ~90 MB, Node at ~50 MB. Caspian at <1 MB is an outlier in the modern language-runtime landscape — closer to Lua's own bare binary (~200 KB) than to any of its shell-installed peers.

## musl-static

Binaries are **statically linked against musl libc**, not glibc. This gives the binary **zero runtime dependencies** — no dynamic loader involvement, no libc version drift, no worry about which distro's libc the user has.

Consequence: the same per-architecture binary works on:

- glibc-based distros (Ubuntu, Fedora, Debian, RHEL, Arch, openSUSE, etc.)
- musl-based distros (Alpine, Void)
- Old distros and new distros — glibc version compatibility isn't a factor because there's no dynamic glibc involved.
- Docker containers of any base image.

**musl-static trade-off:** slightly larger binary than a dynamically-linked glibc build would produce — the ≈200 KB of static libc is counted in [the core table](https://puck.uno/documentation/requirements/caspian/core/#contents-at-a-glance). Well within the floppy budget.

## Lua version (pending review before V1)

Currently the bundle uses **Lua 5.4**. Before V1 ships, we should evaluate whether we can target the **earliest** Lua version that still supports Caspian's runtime and stdlib as spec'd.

Why this matters:

- Older Lua versions (especially 5.1) have broader ecosystem uptake — more luarocks packages target 5.1 than 5.4, and system-installed Lua on many distros is still 5.1-based.
- LuaJIT is Lua 5.1-compatible; a signal of where a large slice of the Lua ecosystem still concentrates.
- Broader compatibility reduces the ABI-mismatch risk when developers install third-party Lua libraries via luarocks — the user's system-installed lib is more likely to match a widely-adopted Lua version.

Cost of moving to an older version:

- Miss language features introduced in later releases (integer subtype, `goto`, `<const>` / `<close>` annotations, bitwise operators, `//` integer division, etc.).
- Some of these may be structural to our stdlib; the evaluation has to inventory current usage and confirm nothing load-bearing requires the newer versions.

The evaluation output should read: "Lua X.Y is the earliest version that supports Caspian's runtime and stdlib as spec'd." If X.Y is older than 5.4, consider switching before V1.

## Per-architecture builds

One binary per CPU architecture — different arches use fundamentally different machine instructions, so a single "Linux binary" isn't possible.

V1 target set (revisit as demand shows up):

- **`caspian-linux-x86_64`** — 64-bit Intel/AMD. Primary target; ~95% of Linux desktops and servers.
- **`caspian-linux-aarch64`** — 64-bit ARM. Raspberry Pi 4/5, Apple Silicon Linux VMs, ARM cloud instances.
- **`caspian-linux-armv7l`** — 32-bit ARM. Older Raspberry Pis. Optional; ship if demand's there.

Additional architectures (RISC-V, older 32-bit x86, etc.) will be added as deemed necessary.

## Where the binaries come from

Pre-built on the **release side** — CI on a build machine (probably a GitHub Actions matrix) or a maintainer's per-arch build environment. Users never compile.

- **Human-facing download page** — `https://caspian.uno/download/`. The page shows the recommended `curl … | bash` install command at the top for beginners, and per-architecture direct-download links below for developers who already know which binary they want.
- **Direct binary URLs** — `https://caspian.uno/download/linux/<arch>/caspian`, one file per architecture. The `linux/` path segment leaves room for `darwin/`, `windows/`, etc. later.
- **Dispatcher** — `https://caspian.uno/download/arch.casp` takes the client's OS/arch info as query parameters and 302-redirects to the matching binary. `install.sh` uses this rather than mapping arches itself.

See [Distribution URLs](../installation/#distribution-urls) and [Platform detection](../installation/#platform-detection) on the install spec for the client-side story.

## What is NOT installed

The clean flip side of "everything's in the binary" — the user's system stays uncluttered.

The Caspian install creates:

- `~/.local/bin/caspian` — the one binary.
- `~/.cache/caspian/`, `~/.config/caspian/`, `~/.local/share/caspian/` — XDG directories (empty at install time).

The Caspian install does **not** create:

- Any Lua files beyond the small pre-installed set (Cache rows in [core](https://puck.uno/documentation/requirements/caspian/core/#contents-at-a-glance)) under `~/.local/share/caspian/lua/`.
- Anywhere for the user to `luarocks install` extra modules for Caspian to pick up. No luarocks integration. The runtime is closed — what ships in the binary plus the pre-installed set is what's available.

If Caspian ever needs a new C dependency post-release, that's a new binary release, not a user-side install. If it needs a new pre-installed Lua lib, that's an addition to [core](https://puck.uno/documentation/requirements/caspian/core/#contents-at-a-glance).

## Related

- [core index](./) — the unified downloads table and section overview.
- [installation](../installation/) — the user-facing install flow (prompts, paths, install command).
