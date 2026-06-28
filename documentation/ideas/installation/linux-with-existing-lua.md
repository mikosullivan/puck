# Linux system-wide install over an existing Lua

~~~vibecode
{"vibecode": {
	"doc": "linux_system_wide_install_with_existing_lua",
	"role": "narrative walkthrough — Linux user picks system-wide install on a machine that already has Lua installed; covers detection, coexistence, and final file layout showing both the pre-existing Lua and Caspian's bundled Lua side by side",
	"audience": "Linux user with sudo, already has Lua N.M installed at /usr/local/bin/lua",
	"key_design_point": "Caspian always uses its own bundled Lua; never shares or upgrades the system's Lua",
	"status": "brainstorm — describes what V1.0 install should feel like"
}}
~~~

The user already has Lua installed on their machine — maybe it came
with the OS, maybe they installed it for a different project, maybe
it's a totally different version (5.1, 5.3, anything). They want to
install Caspian system-wide.

This story shows what happens. Short version: **Caspian always
bundles and uses its own Lua. The existing Lua on the system is left
completely alone.**

For the standard interactive flow, see [linux.md](linux.md). This
story is just the variant where existing-Lua-detection comes up.

---

## Starting state

```bash
$ which lua
/usr/local/bin/lua
$ lua -v
Lua 5.3.6  Copyright (C) 1994-2020 Lua.org, PUC-Rio
```

Lua 5.3 is already on PATH. Caspian needs Lua 5.4, so this isn't a
version we can share even if we wanted to.

---

## Run the installer

```bash
$ curl -fsSL https://puck.uno/install | sh
```

Same one-liner as the standard flow. Behind the scenes, the wrapper
script probes for an existing `lua` on PATH as part of its pre-flight
checks.

---

## The conversation

```
Welcome to Caspian.

I'll install Caspian on this machine. A few questions — press
enter to accept any default.

Note: I found Lua 5.3 at /usr/local/bin/lua already on this machine.
That's fine — Caspian bundles its own Lua 5.4 and won't touch your
existing one. They'll coexist side by side.

Install for:  [u] just you,  [s] system-wide  [u]: s

System-wide install requires root. I'll re-run with sudo.

[sudo] password for user: ********

Install location  [/usr/local]:

Shell rc update: not needed (/usr/local/bin is already on PATH).

Ready to install:
   Caspian:    /usr/local  (system-wide; available to all users)
   Examples:   /usr/local/lib/caspian/examples  (bundled, read-only)

   Your existing Lua at /usr/local/bin/lua stays where it is —
   Caspian's bundled Lua 5.4 goes under /usr/local/lib/caspian/lua/
   and is only invoked by the caspian launcher.

Proceed?  [Y/n]:

Installing...
   ✓ Launcher placed at /usr/local/bin/caspian
   ✓ Engine, stdlib, and libraries placed under /usr/local/lib/caspian
   ✓ Bundled Lua 5.4 placed under /usr/local/lib/caspian/lua
   ✓ Bundled examples placed under /usr/local/lib/caspian/examples

Done. Try this in any shell, as any user on this machine:

   echo "puts 'hello, world'" > hello.casp
   caspian hello.casp

The existing 'lua' command still works as it did before:

   $ lua -v
   Lua 5.3.6 …

Welcome aboard.
```

---

## Why Caspian bundles its own Lua

Three reasons, none of them about distrust:

- **Version pinning.** Caspian's engine targets Lua 5.4 specifically.
  If the system has 5.1 or 5.3, the engine won't run. If we used the
  system's Lua, every install would be at the mercy of whatever
  version the user happened to have. Bundling our own removes the
  variable.
- **C-extension ABI compatibility.** LPeg and luasodium are compiled
  C extensions. They link against a specific Lua version's ABI. If
  we let users plug them into a system Lua of a different version,
  they wouldn't load. Bundling Lua + its C extensions together
  guarantees they match.
- **Don't break the user's setup.** Some users have Lua installed
  for other projects (LuaRocks, Premake, OpenResty, nginx-lua, etc.).
  Upgrading or replacing it would break those. Caspian's bundle is
  isolated to `/usr/local/lib/caspian/` — its Lua is invisible to
  anything else on the system.

---

## Where files end up

After install, both Luas live on the system side by side:

```
/usr/local/
├─ bin/
│  ├─ lua                    # the user's existing Lua 5.3 (untouched)
│  ├─ luac                   # the user's existing Lua 5.3 compiler (untouched)
│  └─ caspian                # NEW — Caspian launcher
└─ lib/
   ├─ liblua.so.5.3          # the user's existing Lua 5.3 shared lib (untouched)
   └─ caspian/               # NEW — everything Caspian needs
      ├─ lua/                # bundled Lua 5.4 (separate from the system's)
      │  ├─ bin/lua          # invoked only by the caspian launcher
      │  └─ lib/liblua.so.5.4
      ├─ lib/
      │  ├─ libsodium.so     # signing + random bytes (minimal build)
      │  └─ lua/5.4/
      │     ├─ lpeg.so       # rpath-resolved
      │     └─ luasodium.so  # rpath-resolved
      ├─ caspian/            # engine + stdlib (pure Lua)
      ├─ examples/           # bundled examples (read-only)
      └─ install.casp        # the installer itself, preserved
```

- `lua` on the user's PATH still invokes their Lua 5.3. Any other
  tool that depends on it keeps working.
- `caspian` on the user's PATH invokes the launcher at
  `/usr/local/bin/caspian`, which hard-codes the path to the bundled
  Lua 5.4 at `/usr/local/lib/caspian/lua/bin/lua`. It never reads
  PATH to find Lua.
- The bundled `lua` is **not** added to PATH. The user can't
  accidentally invoke it; only the `caspian` launcher reaches it.

---

## What if the existing Lua *was* version 5.4?

Same outcome. Caspian still uses its own bundled copy. The reason
isn't "Caspian doesn't trust the system Lua" — it's that **the
C extensions Caspian bundles (LPeg, luasodium) are compiled against
the exact bytes of the bundled Lua**. Using a different binary, even
the same version, can subtly mismatch the ABI in ways that break at
runtime, not at link time.

Treating the bundle as a closed unit means every install behaves
identically regardless of host. That predictability is worth ~250 KB
of disk.

---

## Uninstall

The user's pre-existing Lua is independent of Caspian, so uninstalling
Caspian doesn't touch it:

```bash
$ sudo rm -rf /usr/local/lib/caspian /usr/local/bin/caspian
```

After this, `which lua` still returns `/usr/local/bin/lua` (the
user's), and `which caspian` returns nothing — clean removal.

---

## Open questions

~~~vibecode
{"vibecode": {"open_questions":
["whether_to_announce_existing_lua_detection_in_the_default_install_or_only_when_versions_differ",
"how_to_handle_existing_caspian_install_at_the_target_prefix",
"whether_to_warn_if_user_has_a_lua_5_4_install_pointing_out_the_bundle_is_used_anyway"]}}
~~~

- **Always mention detected Lua, or only when versions differ?**
  Announcing it builds trust ("the installer noticed my Lua and
  said it'd leave it alone"). On a machine with no existing Lua,
  the line would be silent. On a machine with matching-version
  Lua, the message could be shorter. Probably default-on with the
  shorter message in the matching case.
- **Existing Caspian install at the target prefix?** Out of scope
  for this story — see linux.md open questions for the re-install /
  upgrade flow.
- **Warning when versions match?** Some users seeing "I found Lua
  5.4 already, I'll bundle my own anyway" might be confused. The
  short explanation ("compiled C extensions must match exactly")
  is worth surfacing in the installer prompt itself, not buried
  in docs.
