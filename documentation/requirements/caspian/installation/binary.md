# The `caspian` binary

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_installation_binary",
	"role": "spec for what ships in the `caspian` binary and how it's built and distributed. Everything Caspian needs at runtime — Lua interpreter, C bindings, engine, stdlib — is statically linked into a single per-architecture binary the user downloads. No separate Lua libraries end up on the user's system. Sibling of installation/index.md.",
	"status": "spec — packaging model (single static binary, musl-linked, per-CPU-arch) settled; specific dependency versions and build pipeline details pending",
	"audience": "release maintainers building and shipping Caspian binaries; developers curious about what actually gets installed; distribution maintainers"
}}
~~~

Caspian ships as a **single statically-linked binary per CPU architecture**. Everything the runtime needs is compiled into that one file — no separate Lua libraries, no `.so` files, no external runtime dependencies. The user downloads one file, drops it at `~/.local/bin/caspian`, and it works.

## What's in the binary

The `caspian` binary bundles:

| Component | Approx size | Source |
|---|---|---|
| Lua 5.4 interpreter (stripped, static) | ~250 KB | lua.org |
| LPeg (C extension for pattern matching) | ~50 KB | Roberto Ierusalimschy / luarocks |
| libsodium-minimal (crypto primitives) | ~200 KB | libsodium.org, built with `--enable-minimal` |
| luasodium (Lua binding for libsodium) | ~10 KB | luarocks |
| Caspian engine + stdlib | ~260 KB | this project |
| **Total** | **~770 KB** | |

Each C extension is registered as a built-in via Lua's C API (`luaL_requiref` at startup) so `require('lpeg')` inside Caspian just finds the pre-loaded module — no filesystem lookup, no dynamic loader.

## Size budget: floppy-fits

The whole thing is deliberately designed to **fit on a 1.44 MB floppy** with ~670 KB of headroom. Every new C binding proposal has to earn its weight against that budget. This is a design constraint, not a decoration — it keeps the runtime honest and forces "do we really need OpenSSL here or can we get by with libsodium-minimal" conversations.

For comparison: Deno ships at ~100 MB, Bun at ~90 MB, Node at ~50 MB. Caspian at <1 MB is an outlier in the modern language-runtime landscape — closer to Lua's own bare binary (~200 KB) than to any of its shell-installed peers.

## musl-static

Binaries are **statically linked against musl libc**, not glibc. This gives the binary **zero runtime dependencies** — no dynamic loader involvement, no libc version drift, no worry about which distro's libc the user has.

Consequence: the same per-architecture binary works on:

- glibc-based distros (Ubuntu, Fedora, Debian, RHEL, Arch, openSUSE, etc.)
- musl-based distros (Alpine, Void)
- Old distros and new distros — glibc version compatibility isn't a factor because there's no dynamic glibc involved.
- Docker containers of any base image.

**musl-static trade-off:** slightly larger binary than a dynamically-linked glibc build would produce (adds ~200 KB for the static musl libc). Well within the floppy budget.

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

See [Distribution URLs](./#distribution-urls) and [Platform detection](./#platform-detection) on the install spec for the client-side story.

## What is NOT installed

The clean flip side of "everything's in the binary" — the user's system stays uncluttered.

The Caspian install creates:

- `~/.local/bin/caspian` — the one binary.
- `~/.cache/caspian/`, `~/.config/caspian/`, `~/.local/share/caspian/` — XDG directories (empty at install time).

The Caspian install does **not** create:

- Any Lua files (`.lua`, `.so`, or otherwise) anywhere on the filesystem.
- A dedicated Lua library directory (`~/.local/share/caspian/lib/` etc. — doesn't exist).
- Anywhere for the user to `luarocks install` extra modules for Caspian to pick up. The runtime is closed — what ships in the binary is what's available.

If Caspian ever needs a new C dependency post-release, that's a new binary release, not a user-side install.

## Related

- [installation](./) — the user-facing install flow (prompts, paths, install command).
- [caspian-script-install (ideas)](../../../ideas/caspian-script-install) — the separate topic of user-installed Caspian scripts; those DO land in `~/.local/bin/` but are user-authored programs, not runtime libraries for the interpreter.
