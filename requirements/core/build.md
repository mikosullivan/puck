# Build script

~~~vibecode
{"vibecode": {
	"doc": "requirements_core_build",
	"role": "spec for tools/build.sh — the script that produces the complete Caspian distribution at ecoverse/build/ (bin/caspian + caspian/ + external/). Consumers: release maintainers and anyone who wants to reproduce the shipped bytes locally. This spec settles WHAT the script does; the script itself lives at tools/build.sh (once landed).",
	"status": "starting — sections stubbed for spec-out",
	"audience": "release maintainers and anyone reproducing the shipped bytes"
}}
~~~

The build script produces the complete Caspian distribution in one directory tree. Running it once gives a bit-for-bit match with what a user gets on download.

## Location and invocation

- Script lives at `tools/build.sh`.
- Invoked from the repo root: `tools/build.sh`.
- Writes to `/home/miko/projects/puck/ecoverse/build/` — a sibling of the repo, deliberately outside it so the repo stays free of shipping artifacts.
- Idempotent: rerunning wipes the target directory and rebuilds from scratch.

## Output layout

Mirrors what a user gets on download. Three top-level buckets, one binary:

~~~
build/
├── bin/
│   └── caspian
├── caspian/
│   ├── caspian.lua      (engine bundle — Engine + Fiona + Lua binding wrapper)
│   ├── vibecode.json
│   └── lua-confstr.so
└── external/
    ├── libsodium.so
    ├── luasodium.so
    ├── socket.so + Lua wrappers
    ├── pegasus/         (pure-Lua HTTP server)
    ├── lpeg.so
    ├── cjson.so
    ├── lsqlite3.so
    └── luaexpat/        (lxp.so + lom.lua + totable.lua + threat.lua)
~~~

Per-arch when relevant (`.so` files); pure-Lua files are arch-independent.

## Steps

Sketch — flesh out during spec-out:

1. **Wipe and recreate the tree.** Delete `build/`; recreate the `bin/`, `caspian/`, `external/` skeleton.
2. **Compile the binary.** `gcc` on `src/cli/caspian.c` with the static-link flags into `build/bin/caspian`.
3. **Bundle Caspian's Lua source into `caspian.lua`.** Concatenate the engine (currently `src/engine/*.lua`) + Fiona (currently `src/fiona/fiona.lua` with `fiona.sql` and `fiona-temp.sql` inlined as string constants) + the Lua binding wrapper. Write to `build/caspian/caspian.lua`.
4. **Emit vibecode.json.** Serialize the current vibecode blob to `build/caspian/vibecode.json`.
5. **Copy `lua-confstr.so`** to `build/caspian/`.
6. **Assemble external libs** into `build/external/` — from wherever they're staged (fetched via luarocks, checked in as prebuilt binaries, etc.). Per-arch selection.
7. **Repoint the shell symlink.** `~/.local/bin/caspian` → `build/bin/caspian`.
8. **Print a size report.** Bytes per file per bucket, then the totals against the floppy budget.

## Prerequisites

To flesh out: `gcc`, `luac`, `LuaSrcDiet` for minification, whatever fetches external libs, etc. Documented one-time-per-machine setup.

## Minification

To flesh out: at what step does each minification lever from [core § minification levers](https://puck.uno/requirements/core/#core-caspian-code-storage) get applied. LuaSrcDiet + `luac -s` + module concatenation + gzip/brotli, plus SQL comment/whitespace strip for the Fiona SQL inlined into `caspian.lua`.

## Reproducibility

To flesh out: what pins the produced bytes to a specific commit and platform. Whether the script's own output is committed anywhere (probably no — regenerable from source). How a maintainer verifies "these bytes match what upstream shipped."

## Related

- [core](./) — what ships, the tier structure, the floppy budget.
- [binary](./binary) — the `caspian` binary's own spec: what's compiled in, how it's built (musl-static, per-arch), how it's distributed.
