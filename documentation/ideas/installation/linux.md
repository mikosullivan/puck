# Linux install story (interactive shell)

~~~json
{"vibecode": {
	"doc": "linux_install_story_interactive",
	"role": "narrative walkthrough — Linux user at a Bash prompt with a TTY; one curl command, an interactive Caspian-written installer asks a few friendly questions, hello-world runs",
	"audience": "developer at an interactive shell (xterm, gnome-terminal, ssh, tmux, etc.)",
	"installer_url": "https://puck.uno/install",
	"branches": ["per_user_install_in_home_directory",
		"system_wide_install_in_usr_local"],
	"non_interactive_fallback": "see non-interactive.md",
	"status": "brainstorm — describes what V1.0 install should feel like"
}}
~~~

The user sits at an interactive Bash prompt and wants to install
Caspian. The whole flow is one `curl` command followed by a brief
conversation with a Caspian-written installer.

This story assumes a TTY (any normal interactive terminal —
xterm, gnome-terminal, Terminal.app, ssh, tmux, screen). For
unattended / CI / Docker installs, see
[non-interactive.md](non-interactive.md).

The first question the installer asks is the scope — install for
just this user, or system-wide. Those two answers lead to different
file layouts, so this story splits into two branches after the
common kick-off.

---

<a id="kick-off"></a>
## Run the installer

```bash
$ curl -fsSL https://puck.uno/install | sh
```

Behind the scenes:

1. A small POSIX shell wrapper (~50 lines) detects platform and
   architecture (`uname -s`, `uname -m`).
2. Downloads the matching pre-built Caspian bundle (~850 KB — under
   1 MB, fits comfortably on a 1.44 MB floppy with room to spare) to
   a temp directory.
3. Verifies a SHA-256 checksum.
4. Extracts the tarball.
5. Confirms `/dev/tty` is openable.
6. Hands control to the bundled Caspian binary running
   `install.casp`.

The shell wrapper's job ends here. Everything that follows is
Caspian talking to the user.

---

<a id="the-conversation-begins"></a>
## The conversation begins

```
Welcome to Caspian.

I'll install Caspian on this machine. A few questions — press
enter to accept any default.

Install for:  [u] just you,  [s] system-wide  [u]:
```

Two branches follow.

---

<a id="branch-a-per-user"></a>
## Branch A — Per-user install (the default)

The user presses enter, accepting `[u]`. The conversation continues:

```
Install location  [~/caspian]:

Update shell rc?  [Y/n]:
Found ~/.bashrc — I'll add one line to put caspian on your PATH.

Ready to install:
   Caspian:    /home/user/caspian
   PATH set up in: /home/user/.bashrc

Proceed?  [Y/n]:

Installing...
   ✓ Engine, stdlib, launcher, and examples copied
   ✓ libsodium-minimal and LPeg placed (rpath-resolved)
   ✓ Shell rc updated

Done. Try this in a new shell:

   echo "puts 'hello, world'" > hello.casp
   caspian hello.casp

Welcome aboard.
```

No `sudo` needed, nothing outside the user's home touched. The whole
install lives at `~/caspian/` — a visible, user-owned directory the
user can `ls` and explore.

<a id="branch-a-files"></a>
### Where files end up (per-user)

```
~/caspian/
├─ bin/
│  └─ caspian                # launcher (~/caspian/bin added to PATH)
├─ lua/                      # bundled Lua 5.4 interpreter
├─ lib/
│  ├─ libsodium.so           # signing + random bytes (minimal build, ~200 KB)
│  └─ lua/5.4/
│     ├─ lpeg.so            # PEG library, rpath-resolved
│     └─ luasodium.so       # libsodium binding, rpath-resolved
├─ caspian/                  # engine + stdlib (pure Lua)
├─ examples/                 # example programs (user-owned, editable in place)
└─ install.casp              # the installer itself, preserved for re-runs

~/.bashrc                    # one line appended:
   # export PATH="$HOME/caspian/bin:$PATH"
```

Footprint added inside `~/`: roughly **850 KB** for `~/caspian/`,
which includes the examples (~50 KB). No separate examples-copy
step is needed — the whole tree is the user's, so they can edit
example files in place. The entire install fits on a 1.44 MB floppy
with ~600 KB to spare.

Rough breakdown:

| Component | Size |
|---|---|
| Lua 5.4 interpreter (stripped, static) | ~250 KB |
| libsodium-minimal | ~200 KB |
| Caspian engine + stdlib (Lua source) | ~200 KB |
| caspian lsp (Caspian source) | ~80 KB |
| LPeg | ~50 KB |
| Bundled examples | ~50 KB |
| luasodium binding | ~10 KB |
| Launcher + install.casp | ~10 KB |
| **Total** | **~850 KB** |

To uninstall later: `rm -rf ~/caspian` and remove the PATH line
from `~/.bashrc`.

---

<a id="branch-b-system-wide"></a>
## Branch B — System-wide install

The user types `s` at the first prompt. The conversation continues:

```
Install for:  [u] just you,  [s] system-wide  [u]: s

System-wide install requires root. I'll re-run with sudo.

[sudo] password for user: ********

Install location  [/usr/local]:

Shell rc update: not needed (/usr/local/bin is already on PATH).

Ready to install:
   Caspian:    /usr/local  (system-wide; available to all users)
   Examples:   /usr/local/lib/caspian/examples  (bundled, read-only)

Proceed?  [Y/n]:

Installing...
   ✓ Launcher placed at /usr/local/bin/caspian
   ✓ Engine, stdlib, and libraries placed under /usr/local/lib/caspian
   ✓ Bundled examples placed under /usr/local/lib/caspian/examples

Done. Try this in any shell, as any user on this machine:

   echo "puts 'hello, world'" > hello.casp
   caspian hello.casp

To get a personal writable copy of the examples in your home:

   cp -r /usr/local/lib/caspian/examples ~/caspian-examples

Welcome aboard.
```

The installer escalated to `sudo` only for the file-move step.
Everything Caspian-internal that ran before the `sudo` (downloading,
extracting, prompting) ran as the user. After `sudo`, the installer
re-invokes itself from the temp dir with the user's chosen
parameters, places the files, then drops privilege.

The launcher at `/usr/local/bin/caspian` is on every user's PATH
already, so no shell rc edits are needed.

<a id="branch-b-files"></a>
### Where files end up (system-wide)

```
/usr/local/
├─ bin/
│  └─ caspian                # launcher (on PATH for everyone)
└─ lib/caspian/              # all Caspian-internal files
   ├─ lua/                   # bundled Lua 5.4 interpreter
   ├─ lib/
   │  ├─ libsodium.so        # signing + random bytes (minimal build)
   │  └─ lua/5.4/
   │     ├─ lpeg.so          # rpath-resolved
   │     └─ luasodium.so     # rpath-resolved
   ├─ caspian/               # engine + stdlib (pure Lua)
   ├─ examples/              # bundled examples (read-only)
   └─ install.casp           # the installer itself, preserved
```

Footprint added system-wide: roughly **850 KB** under
`/usr/local/lib/caspian/` plus a thin launcher at
`/usr/local/bin/caspian`. Same as the per-user branch — fits
comfortably on a 1.44 MB floppy. No files written to any user's home
— each user who wants a personal writable example workspace runs
`cp -r /usr/local/lib/caspian/examples ~/wherever` themselves.

To uninstall later:

```bash
sudo rm -rf /usr/local/lib/caspian /usr/local/bin/caspian
```

---

<a id="pick-up-the-new-path"></a>
## Pick up the new PATH (per-user only)

For Branch A (per-user), one more step:

```bash
$ exec $SHELL
```

…or open a new terminal. The shell rc line the installer added is
now active and `caspian` is on PATH.

Branch B (system-wide) skips this — `/usr/local/bin` was already on
PATH for the shell the user is sitting at, so `caspian` is
available immediately.

---

<a id="hello-world"></a>
## Hello world

Identical in both branches:

```bash
$ echo "puts 'hello, world'" > hello.casp
$ caspian hello.casp
hello, world
```

---

<a id="under-the-hood"></a>
## Under the hood

The installer is a Caspian program (~100 lines). It uses:

- `%file.open('/dev/tty', :read)` to prompt the user even though
  `stdin` is the curl pipe.
- `%fs` to move bundle files from the temp dir to the chosen
  install location.
- `%file` to read the user's shell rc (per-user branch only), append
  the PATH line, re-write it.
- `%proc.spawn('sudo', ...)` to re-invoke itself with elevated
  privileges (system-wide branch only).
- `%argv` to receive the temp-dir path and target-dir choices from
  the wrapper shell script.

The Caspian binary the installer runs is **the same binary that
ends up installed**. The "install" step is really "move these files
from `$TMPDIR` to the chosen prefix" — no second copy, no second
build, no version skew.

The launcher (`bin/caspian`) is a tiny shell script written at
install time with the install root hardcoded:

```sh
#!/bin/sh
# /usr/local/bin/caspian  (or  ~/.caspian/bin/caspian)
CASPIAN_ROOT="/usr/local/lib/caspian"
exec "$CASPIAN_ROOT/lua/bin/lua" \
    -e "package.path='$CASPIAN_ROOT/caspian/?.lua;'..package.path" \
    "$CASPIAN_ROOT/caspian/init.lua" "$@"
```

Same launcher template, just a different `CASPIAN_ROOT`. Everything
under that root is rpath-resolved relative to itself, so the entire
tree can be moved as a unit without re-linking anything.

---

<a id="open-questions"></a>
## Open questions

~~~json
{"vibecode": {"open_questions":
["whether_dir_already_exists_warning_and_recovery",
"xdg_layout_as_an_opt_in_for_users_who_prefer_it",
"color_output_in_the_installer_prompts_or_plain_text",
"installer_offers_to_run_hello_world_at_the_end_or_just_print_instructions",
"how_to_handle_re_install_over_existing_install",
"whether_to_show_a_progress_indicator_for_the_curl_download_step",
"system_wide_install_location_usr_local_vs_opt_caspian"]}}
~~~

- **What if `~/caspian/` already exists?** A user may already have a
  directory by that name for unrelated work. The installer should
  detect a non-empty existing directory and ask before clobbering —
  offer to use a different path or abort.
- **XDG layout opt-in.** Some users actively prefer the XDG Base
  Directory layout (launcher in `~/.local/bin/caspian`; engine,
  libs, examples in `~/.local/share/caspian/`). Worth exposing as
  an opt-in via env var (`CASPIAN_INSTALL_LAYOUT=xdg`). Default
  stays visible single-dir at `~/caspian/`.
- **System-wide install location.** `/usr/local/` is the FHS-blessed
  spot for locally-installed software and is on every user's PATH by
  default. `/opt/caspian/` is the alternative used by some self-
  contained packages (Java JDKs, IntelliJ, etc.). My lean: default
  to `/usr/local/`, easy to override via env var.
- **Color?** ANSI color in the prompts is friendlier but adds
  installer code complexity and breaks on terminals without color.
  Probably default-on with `--no-color` override.
- **Auto-run hello-world?** After install finishes, the installer
  could offer: "Try a hello-world right now?  [Y/n]" — and if yes,
  drop the user into a `caspian -e "puts 'hello, world'"` invocation.
  Charming, possibly over-the-top.
- **Re-install over existing install?** If the install location
  already exists, the installer should detect it, ask "Upgrade?
  [Y/n]," and preserve user data (`examples/` not overwritten if
  user has modified it).
- **Download progress.** `curl -fsSL` is silent by design. A more
  verbose download (`curl -L` with progress bar) is uglier but
  reassuring on slow connections.
