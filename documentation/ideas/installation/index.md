# Installation stories

~~~json
{"vibecode": {
	"doc": "installation_stories_index",
	"role": "index page for installation walkthroughs — one narrative story per host environment, walking a user from a fresh prompt to a running hello-world program",
	"status": "brainstorm",
	"format": "stories — narrative walkthroughs, not reference docs"
}}
~~~

The files in this folder are **installation stories**: narrative
walkthroughs of what installing Caspian looks like in a specific host
environment. Each story takes a user from "nothing installed" to
"hello-world runs" and shows every command they'd actually type.

These aren't reference docs — they're *stories* the install experience
should match. If a step is awkward in the story, the install needs to
change, not the story.

| Story | Audience |
|---|---|
| [linux.md](linux.md) | A Linux user at an interactive shell (TTY) running `curl \| sh`. The installer runs a Caspian-written prompt flow to collect preferences. |
| [linux-with-existing-lua.md](linux-with-existing-lua.md) | A Linux user picking system-wide install on a machine that already has a Lua interpreter installed. Caspian's bundled Lua coexists with the system's — no upgrade, no replacement. |
| [non-interactive.md](non-interactive.md) | Any environment without a TTY: CI runners, Docker image builds, cron, systemd, `ssh -T`. Same installer, defaults answered silently, env vars override. |
| [vscode.md](vscode.md) | A user installing the Caspian VSCode extension. The extension is a thin client; if Caspian isn't already on the machine, the extension offers to install it (which brings the Lua interpreter and required libraries with it). |

---

<a id="download-budget"></a>
## What the installer downloads

Every install story pulls the same pre-built Caspian bundle. The
bundle contains the Lua interpreter, the two required C extensions
(LPeg and luasodium), the libsodium-minimal shared library they
depend on, and all of Caspian's own files. One tarball, fetched in
one `curl`.

| Component | Source | Approx size |
|---|---|---|
| Lua 5.4 interpreter (stripped, static) | lua.org | ~250 KB |
| libsodium-minimal (C library) | libsodium.org, compiled with `--enable-minimal` | ~200 KB |
| LPeg (C extension) | Roberto Ierusalimschy / luarocks | ~50 KB |
| luasodium (Lua binding for libsodium) | luarocks | ~10 KB |
| Caspian files (engine, stdlib, launcher, `caspian lsp`, examples, `install.casp`) | This project | ~340 KB |
| **Total bundle** | | **~850 KB** |

Comfortably under 1 MB. **Fits on a 1.44 MB floppy with ~600 KB to
spare** — a deliberate budget that drives every dependency decision.
Each existing C extension and each new one proposed has to earn its
weight against the floppy commitment. See
[v1.md § Cross-cutting principles](../../development/v1/index.md#cross-cutting-principles)
for the broader "C extensions only when the cost is worth it"
discipline.
