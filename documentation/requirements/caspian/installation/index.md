# Caspian installation

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_installation",
	"role": "cover page for the Caspian installation spec — the one-time bootstrap of the Caspian interpreter onto a developer's system, plus the install/uninstall machinery for Caspian scripts. Linux-centric for V1 (XDG-compliant throughout); installers for other platforms deferred. Being spec'd from scratch.",
	"status": "stub — bootstrap paths listed; full spec (distribution channels, install script shape, PATH setup, script install/uninstall, upgrade path) pending",
	"audience": "developers installing Caspian for the first time; distribution maintainers; anyone building tooling that assumes Caspian is present"
}}
~~~

Every language ecosystem has a bootstrap install step for its interpreter, and Caspian is no exception. Puck's on-demand fetch handles everything downstream (libraries, downloaded classes, tools) — but *something* has to put `caspian` on `PATH` first.

**These requirements are Linux-centric.** V1 targets Linux (with XDG Base Directory conventions, `~/.local/bin` on `PATH`, standard shell wiring). Installers for macOS, Windows, BSDs, and other systems will be considered after V1 ships — the shape may need to differ per platform (macOS's `~/Library/`, Windows' `%APPDATA%` / `%LOCALAPPDATA%`, etc.).

## Paths

Install follows **XDG Base Directory** conventions:

- **Executable** — `~/.local/bin/caspian`
- **Cache** — `~/.cache/caspian/` (per the existing [cache-dir](../cache-dir) spec)
- **Config** — `~/.config/caspian/` (per XDG)
- **Data** — `~/.local/share/caspian/`

## Distribution URLs

Committed stable URLs:

- **`https://caspian.uno/install.sh`** — the installer script. Always the latest version; the URL doesn't change across releases. What the shell one-liner in [installation process](#installation-process) below fetches.
- **`https://caspian.uno/download/`** — the **human-facing download page**. A beginner who lands here sees the recommended `curl … | bash` command at the top and per-arch direct-download links below for people who know what they want.
- **`https://caspian.uno/download/arch.casp`** — the **dispatcher**. `install.sh` calls it with the client's OS/arch info; the script picks the right binary and returns an HTTP 302 redirect to it. Written in Caspian (dogfooding the release infrastructure).
- **`https://caspian.uno/download/linux/<arch>/caspian`** — the **binary files themselves**. One file per CPU architecture; `<arch>` is what `uname -m` reports. These are what the dispatcher redirects to and what the download page's per-arch links point at.
  - `https://caspian.uno/download/linux/x86_64/caspian`
  - `https://caspian.uno/download/linux/aarch64/caspian`
  - `https://caspian.uno/download/linux/armv7l/caspian` (if built)

The `linux/` segment in the path leaves room for `darwin/`, `windows/`, and other OS families when non-Linux support arrives post-V1 — no URL migration needed later.

Alternate downloads — specific versions, prior releases, beta / stable channels, checksums — will get a sensible URL scheme at implementation time. Not spec'd here yet.

## What gets installed

The install delivers three things to the user's machine:

- **The `caspian` binary** — statically-linked, single file per CPU architecture, dropped at `~/.local/bin/caspian`. Includes the Lua 5.4 interpreter, engine, stdlib, and a handful of C extensions.
- **Pre-installed Lua libraries** — a small set fetched during install and extracted to `~/.local/share/caspian/lua/`. Currently: `xml2lua` and `lua-cbor`. Loaded lazily by `require`.
- **XDG directories** — created empty at install time under `~/.cache/caspian/`, `~/.config/caspian/`, `~/.local/share/caspian/`.

For the component-by-component breakdown (sizes, locations, purposes), see [core](../core/).

## Installation process

A user installs Caspian with a single shell command:

<pre class="terminal-block"><b>&gt;</b> curl -fsSL https://caspian.uno/install.sh | bash</pre>

### Platform detection

Before showing any prompts, `install.sh` discovers the user's system information — OS via `uname -s`, CPU architecture via `uname -m`, and anything else the release side eventually cares about.

**Implementation note — server picks the binary, not the client.** The install script sends the discovered information to the dispatcher as query parameters — e.g. `https://caspian.uno/download/arch.casp?os=linux&arch=x86_64`. The dispatcher (a Caspian script on the server) picks the matching binary from `https://caspian.uno/download/linux/<arch>/caspian` and returns an HTTP 302 redirect to it; `curl` follows the redirect and downloads the binary. If the combination isn't supported, the dispatcher returns an HTTP error with a clear message the install script surfaces to the user (e.g. `"Sorry, caspian isn't built for os=linux arch=riscv64 yet"`).

Benefits of this split:

- **Minimal client-side processing.** The install script gathers facts and forwards them. No table of arch → URL to maintain in shell.
- **Server can evolve independently.** Add a new architecture, change a naming convention, retire an old build — no need to update any deployed `install.sh`.
- **Clear error surface.** Unsupported combinations produce a proper HTTP error the script can display verbatim (`"Sorry, caspian isn't built for os=linux arch=riscv64 yet"`). The client doesn't need to know what's supported in advance.
- **libc is not detected client-side.** Binaries are statically linked with musl, so a single per-arch binary works on glibc-based distros (Ubuntu, Fedora, Debian, Arch, etc.) and musl-based distros (Alpine, Void) alike. The server may or may not care about libc info in the request; the client just sends what it can gather.

All detection and the download request happen before any file is written or any prompt is shown — an unsupported system fails fast with nothing touched.

### Welcome prompt

The installer's first act is a welcome message and a yes/no question. The user can back out cleanly before anything touches their system.

<pre class="terminal-block">Welcome to <span class="brand">Caspian</span>.<br><br>Ready to install? [<b>Y</b>/n] <b>_</b></pre>

### Blockchain opt-in prompt

After the user agrees to install, the installer briefly describes the [Puck blockchain](../puck-discovery/blockchain/) — a public ledger of signed endorsements that lets Caspian verify downloaded scripts and libraries came from their claimed publisher and haven't been tampered with — and asks whether to opt in.

<pre class="terminal-block">The <span class="brand">Puck blockchain</span> is a public ledger of signed<br>endorsements. When enabled, Caspian verifies scripts and<br>libraries against it before downloading — guaranteeing<br>each artifact came from the claimed publisher and hasn't<br>been tampered with.<br><br>You can change this later by editing ~/.config/caspian/config.json.<br><br>Opt into blockchain verification? [y/n] <b>_</b></pre>

No default — the user picks `y` or `n`. The chosen value is saved to `~/.config/caspian/config.json` under a key like `blockchain: true` / `blockchain: false`. Exact config shape spec'd separately.

### Self-test prompt

After the blockchain question, the installer briefly describes the [post-install self-test](self-test/) and asks whether to run it.

<pre class="terminal-block">Run the self-test? (recommended) [<b>Y</b>/n] <b>_</b></pre>

Default is `y` — the recommendation is baked in. If the user accepts, the self-test runs as the last step of [install and setup](#install-and-setup). If declined, no self-test-related downloads happen (Bryton and the test suite are not fetched), and the [installation summary](#installation-summary) notes the skip. The user can still invoke `caspian --self-test` at any time later — it'll fetch what it needs on demand.

### PATH prompt

After the blockchain question, the installer checks whether `~/.local/bin` is already on the user's `PATH`.

- **If it's already there** — nothing to prompt about; the installer moves on silently.
- **If it isn't** — the installer prompts before modifying any shell rc file. Shell rc files belong to the user; the installer doesn't touch them without permission.

<pre class="terminal-block">~/.local/bin is not on your PATH. Caspian will be installed<br>there, along with any scripts you install later with<br>`caspian --install-script`. Without ~/.local/bin on PATH,<br>you'll need to invoke them by full path.<br><br>Add ~/.local/bin to PATH in your shell rc? [y/n] <b>_</b></pre>

No default — the user picks `y` or `n`. When `y`, the installer inspects `$SHELL` (falling back to `~/.profile`) and appends `export PATH="$HOME/.local/bin:$PATH"` to that file.

### Install and setup

After the prompts are answered, the installer runs through the actual setup without further interaction. In order:

1. **Download** the `caspian` binary and put it at `~/.local/bin/caspian` (executable).
2. **Create the XDG directories** if they don't already exist:
   - `~/.cache/caspian/`
   - `~/.config/caspian/`
   - `~/.local/share/caspian/`
3. **Write** `~/.config/caspian/config.json` with the blockchain preference from the prompt.
4. **Modify the shell rc** if the user agreed to the PATH prompt — append `export PATH="$HOME/.local/bin:$PATH"` to the appropriate file (`~/.bashrc`, `~/.zshrc`, `~/.profile`).
5. **Run the self-test** — if the user accepted the [self-test prompt](#self-test-prompt), invoke `caspian --self-test`. The binary loads Bryton via `%puck` and downloads the test-tree tarball from `caspian.uno` into a temp dir, then runs Bryton against it. See [self-test](self-test/) for the full spec. The result is shown in the installation summary. If the user declined, this step is skipped entirely — no downloads, no run — and the summary notes the skip.

### Installation summary

Once setup completes, the installer prints a summary of every path it touched. Most users already have `~/.local/bin` on `PATH`, so the common case looks like this:

<pre class="terminal-block"><span class="brand">Caspian installed.</span><br><br>Files added:<br>  ~/.local/bin/caspian<br>  ~/.config/caspian/config.json<br><br>Directories created:<br>  ~/.cache/caspian/<br>  ~/.config/caspian/<br>  ~/.local/share/caspian/<br><br>Self-test: <span class="brand">passed</span></pre>

The summary lists only what actually happened:

- If a directory already existed, it isn't listed as "created."
- **The self-test line** shows one of: `passed`, `failed` (with a list of which checks failed), or `skipped` (with the reason — the user declined at the self-test prompt, or a required download failed). See [self-test](self-test/) for the full failure-reporting shape.
- **If `~/.local/bin` was NOT on PATH and the user agreed to the PATH prompt**, an additional "Shell config updated" section appears and a restart hint follows:

  <pre class="terminal-block"><span class="brand">Caspian installed.</span><br><br>Files added:<br>  ~/.local/bin/caspian<br>  ~/.config/caspian/config.json<br><br>Directories created:<br>  ~/.cache/caspian/<br>  ~/.config/caspian/<br>  ~/.local/share/caspian/<br><br>Shell config updated:<br>  ~/.bashrc  (added ~/.local/bin to PATH)<br><br>Self-test: <span class="brand">passed</span><br><br><span class="dim">Restart your shell or run: source ~/.bashrc</span></pre>

- **If the user declined the PATH prompt**, the summary shows the required manual step instead:

  <pre class="terminal-block"><span class="brand">Caspian installed.</span><br><br>Files added:<br>  ~/.local/bin/caspian<br>  ~/.config/caspian/config.json<br><br>Directories created:<br>  ~/.cache/caspian/<br>  ~/.config/caspian/<br>  ~/.local/share/caspian/<br><br>Self-test: <span class="brand">passed</span><br><br><span class="accent">You declined to modify your shell rc.</span><br>To use `caspian` without a full path, add this line to<br>your shell config manually:<br><br>  export PATH=&quot;$HOME/.local/bin:$PATH&quot;</pre>

*Full spec pending — distribution channels, install script shape, script install/uninstall commands, upgrade path, and platform-specific details all still to be settled.*
