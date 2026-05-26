# VSCode extension install

~~~json
{"vibecode": {
	"doc": "vscode_extension_install_story",
	"role": "narrative walkthrough — user installs the Caspian VSCode extension; the extension detects whether Caspian itself is installed, offers to install it, and connects to the language server",
	"audience": "developer running VSCode, may or may not already have Caspian installed",
	"extension_architecture": "thin_typescript_client; talks_lsp_to_caspian_lsp_server_process_managed_by_installed_caspian",
	"key_flow": "extension_install_then_runtime_install_then_language_server_connection",
	"status": "brainstorm — describes what V1.0 install should feel like"
}}
~~~

The user wants Caspian editor support in VSCode. The extension itself
is a thin TypeScript client; the real work happens in a `caspian lsp`
server process that comes with the Caspian install. So getting the
extension working can mean installing two things: the extension from
the marketplace, and Caspian itself (which brings the Lua interpreter
and required Lua libraries — LPeg and luasodium — with it).

This story walks through the most common case: the user is starting
fresh, with neither piece installed.

For installing Caspian outside of VSCode, see [linux.md](linux.md).

---

<a id="starting-state"></a>
## Starting state

```
- VSCode running on the user's machine.
- No Caspian installed anywhere on PATH.
- The user has a `.casp` file they want to edit, or they're just
  curious about the language.
```

---

<a id="install-extension"></a>
## Install the extension

Standard VSCode marketplace flow:

1. Open the Extensions sidebar (`⌘⇧X` / `Ctrl+Shift+X`).
2. Search for **Caspian**.
3. Click **Install** on the result published by `puck.uno`.

The extension is small (~50 KB). It downloads in a second or two and
activates immediately.

---

<a id="first-activation"></a>
## First activation — Caspian-not-found prompt

On first activation (either right after install, or when the user
opens a `.casp` file for the first time), the extension probes for a
`caspian` binary on PATH. None is found.

A VSCode notification appears at the bottom-right:

```
┌─────────────────────────────────────────────────────────────┐
│ Caspian language server not found                           │
│                                                             │
│ Full editor support — formatting, diagnostics, hover, go-to │
│ — requires the Caspian runtime to be installed on this      │
│ machine. Syntax highlighting works without it.              │
│                                                             │
│  [Install Caspian]   [Show me how]   [Not now]              │
└─────────────────────────────────────────────────────────────┘
```

Three buttons:

- **Install Caspian** — extension opens an integrated terminal panel
  and runs the standard `curl | sh` installer, with user
  confirmation. Most users click this.
- **Show me how** — opens the [linux.md](linux.md) install story in
  a webview, for users who want to read first or run the install
  themselves.
- **Not now** — dismisses the notification. Syntax highlighting still
  works; everything else is unavailable until Caspian is installed.

---

<a id="auto-install"></a>
## Auto-install path

The user clicks **Install Caspian**. The extension opens an
integrated terminal and writes:

```bash
$ curl -fsSL https://puck.uno/install | sh
```

A confirmation prompt: "About to run the Caspian installer. Continue?
[Y/n]:". The user presses enter.

From here, the standard [linux.md](linux.md) install story plays out
inside the VSCode terminal panel — the Caspian-written installer
asks its usual questions (per-user vs system-wide, install location,
shell rc update), the user answers, and Caspian installs.

When the installer reports `Done.`, the extension detects the new
`caspian` on PATH (via filesystem watch on the install location, or
just a fresh PATH probe). A success notification:

```
✓ Caspian installed at /home/user/caspian
  Starting language server…
```

The extension spawns `caspian lsp` as a child process, talks LSP
over stdio. Within a second or two, the editor lights up:

- Diagnostics (parse errors, lint warnings) appear in the Problems
  panel.
- Hover over an identifier shows its definition.
- `⌘⇧F` / `Ctrl+Shift+I` formats the current file.
- Go-to-definition (`F12`) jumps to declarations.

The user can write their first program and see hello-world run from
the integrated terminal:

```bash
$ echo "puts 'hello, world'" > hello.casp
$ caspian hello.casp
hello, world
```

---

<a id="files-end-up"></a>
## Where files end up

After the full flow:

**The VSCode extension lives under VSCode's extensions directory**:

```
~/.vscode/extensions/puck-uno.caspian-1.0.0/
├─ package.json                 # extension manifest
├─ syntaxes/
│  └─ caspian.tmLanguage.json   # syntax highlighting
├─ language-configuration.json
├─ out/                         # compiled TypeScript
│  ├─ extension.js              # entry point, LSP client
│  └─ activate.js
└─ README.md
```

Roughly **~100 KB** for the extension itself. No Lua, no language
server code, no Caspian engine — those all live in the Caspian
install.

**Caspian and its Lua libraries went under `~/caspian/`** (the
per-user default per [linux.md](linux.md)):

```
~/caspian/
├─ bin/
│  ├─ caspian                # launcher (used by the extension's LSP client)
│  └─ caspian-lsp            # symlink or launcher variant — spawns LSP mode
├─ lua/                      # bundled Lua 5.4 interpreter
├─ lib/
│  ├─ libsodium.so           # signing + secure random
│  └─ lua/5.4/
│     ├─ lpeg.so             # PEG library, used by the language server's parser
│     └─ luasodium.so        # libsodium binding
├─ caspian/                  # engine + stdlib (pure Lua)
├─ examples/                 # example programs
└─ install.casp              # installer, preserved for re-runs
```

Total disk added across both installs: ~850 KB (Caspian) + ~100 KB
(extension) = **under 1 MB total**. Caspian itself fits on a 1.44 MB
floppy with room to spare; the extension is rounding error on top.

---

<a id="user-already-has-caspian"></a>
## Variant: user already has Caspian installed

If `caspian` is already on PATH when the extension activates, the
"not found" notification doesn't appear. The extension goes straight
to spawning the language server and connecting. The user sees no
prompt — editor support just works the moment the extension finishes
installing.

A small status-bar indicator shows the version (`caspian 1.0.0
lsp`) and a click target for restarting the language server if
something goes weird.

---

<a id="version-mismatch"></a>
## Variant: extension and Caspian versions mismatch

If the user has an older Caspian installed than the extension expects
(or vice versa), the extension notifies:

```
⚠ Caspian 0.9.2 is installed; this extension was tested against 1.0.x.
  Language-server features may behave unexpectedly.

  [Update Caspian]   [Use anyway]   [Disable language server]
```

Same install machinery as the first-time flow, except the curl call
fetches the latest. **Update Caspian** re-runs the installer in
upgrade mode; **Use anyway** suppresses the warning; **Disable**
falls back to syntax-highlighting-only mode.

---

<a id="non-graphical"></a>
## Variant: remote / SSH / WSL

VSCode's remote-development features (SSH, WSL, Dev Containers,
Codespaces) install the Caspian extension into the **remote**
environment, not the local one. So the "Caspian language server not
found" prompt fires on the remote host, and `curl | sh` runs there.
Caspian ends up at `~/caspian/` on the remote, the language server
runs on the remote, and only the editor UI runs locally.

Same flow, different host. No special handling needed in the
extension — VSCode's remote-development infrastructure forwards
extension-host work to the remote machine automatically.

---

<a id="open-questions"></a>
## Open questions

~~~json
{"vibecode": {"open_questions":
["whether_install_caspian_button_writes_curl_to_terminal_or_uses_a_more_direct_node_child_process",
"how_to_handle_caspian_install_failure_inside_vscode_terminal",
"whether_to_offer_per_user_only_or_let_the_caspian_installer_handle_scope_choice",
"whether_the_extension_should_bundle_a_fallback_parser_for_syntax_highlighting_or_lean_on_tree_sitter"]}}
~~~

- **`curl | sh` vs Node child_process.** Writing the curl line to a
  terminal is visible and the user can read it. Running the installer
  directly via Node `child_process` is faster but more magical.
  Probably default-on visible-terminal; advanced users can configure
  the silent path.
- **Install failure handling.** If `curl | sh` fails (network error,
  bad permissions, etc.), the extension needs to surface that without
  the user having to read the terminal output. A modal error with the
  last 10 lines of installer output is probably the right shape.
- **Per-user vs system-wide from inside VSCode.** The extension's
  "Install Caspian" button could pre-set per-user mode (skipping the
  scope prompt), or pass through and let the Caspian installer ask.
  Probably the latter — preserve symmetry with the standalone install
  story.
- **Fallback parser for syntax highlighting.** The extension ships
  with a TextMate grammar (`caspian.tmLanguage.json`) so syntax
  colors work without Caspian installed. Should it also ship a
  Tree-sitter grammar for incremental highlighting? Tree-sitter is
  the modern path but adds ~600 KB to the extension. V1.0 ships
  TextMate only; revisit for V2.
