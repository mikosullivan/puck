# Caspian script install

*Caspian's model handles library-style objects (fetched, cached, referenced by URL) but has no story for **executable scripts on PATH**. A developer who wants to run a Puck-hosted script by name at the shell needs some way to get that script installed as a runnable command. Explored here — solutions should feel "normal" (recognizable to anyone who's used npm/pip/gem/cargo), not novel.*

~~~vibecode
{"vibecode": {
	"doc": "idea_caspian_script_install",
	"role": "brainstorm for how Caspian can provide a simple process for downloading and installing scripts as executables (single scripts as the primary case). The core tension: Caspian's 'no install' ethos applies to library-style objects, but shell executables fundamentally need to exist as files on PATH. The design goal is a familiar mechanism, not a novel one — currently converging on `caspian --install-script <url>` writing to XDG-standard `~/.local/bin/<name>` (or `/usr/local/bin/<name>` under `--global`).",
	"status": "brainstorm — direction converging on `caspian --install-script` with XDG paths; details of naming, updates, uninstall, and provenance still open",
	"related": ["requirements/installation/ (Caspian's own bootstrap install — same XDG-path pattern this design follows)", "requirements/fetch-discovery (Puck object surface)", "requirements/cache-dir (existing cache location)", "requirements/bryton/ (Bryton is the first case that surfaces this need — its `bryton` runner has to be launchable at the shell)"]
}}
~~~

## The challenge

Caspian's design principle is that **libraries are cached, not installed** — referenced by URL, resolved on demand through the provider chain. That works cleanly for Puck objects: `%('puck.uno/foo')` inside Caspian code triggers a fetch-and-cache; no explicit install step, no lock file, no manifest.

**Shell executables don't fit that model.** A user typing `foo` at the shell needs `foo` to exist as a file the OS can find on `PATH`. There's no Puck-native way for that to work today. The gap surfaces first for [Bryton](../requirements/bryton/) — the runner needs to be launchable as `bryton` — but it applies to any Caspian-authored tool a developer wants to invoke by name.

**Scope for V1 of this design.** Single scripts (Caspian, or any file the OS can execute via its shebang). Not full package installs, not compiled binaries with library dependencies, not multi-file distributions. If we can nail the single-script case cleanly, larger installations can extend the pattern later.

## Design constraint: use a "normal" mechanism

Every mainstream ecosystem has solved this problem. The design should feel familiar to a developer arriving from any of them:

- **npm** — `npm install -g foo` reads the package's `bin` field, drops symlinks in a bin dir the shell knows about.
- **pip** — `pip install foo` creates `console_scripts` entry points; drops shims in `~/.local/bin` (or venv bin).
- **rubygems** — each gem has a `bin/` dir; `gem install` creates wrappers.
- **cargo** — `cargo install foo` compiles and drops the binary in `~/.cargo/bin`.
- **brew** — installs to `Cellar`, symlinks to `/usr/local/bin`.

Common threads: **a managed bin directory** (XDG-standard `~/.local/bin` is the neutral choice), **PATH configured once at bootstrap**, **an install command** the user runs to opt in per-object.

## Candidate approaches

### Idea 0: Do nothing — just `wget` the file

The most minimal option: don't spec an install mechanism at all. A developer who wants a Puck-hosted executable just downloads it directly with whatever standard tool their system provides:

~~~
wget https://puck.uno/bryton/bryton-runner.casp
chmod +x bryton-runner.casp
mv bryton-runner.casp ~/.local/bin/bryton
~~~

Or, in a single line, `curl ... -o ~/.local/bin/bryton && chmod +x ~/.local/bin/bryton`.

**Pros:** zero new mechanism; uses only what already exists (wget/curl, chmod, PATH). Nothing to spec, nothing to build.

**Cons:** honestly not really "installing" anything — it's just a manual download-and-drop. No name-lookup, no update path (the user has to remember the URL to refetch), no uninstall convention, no metadata about what was installed. Fine as a one-off; friction the moment there are more than a couple.

### Idea 1: `puck install <url>` — a Puck CLI command

Model directly on `npm install -g` / `pip install`. The `puck` CLI takes a URL, fetches the object, drops it in `~/.local/bin/<name>`, and makes it executable:

~~~
puck install https://puck.uno/bryton/runner/
~~~

**Name** comes either from the URL's last path segment (default) or from an explicit `--as` flag:

~~~
puck install https://puck.uno/bryton/runner/ --as bryton
~~~

**Pros:** familiar (`npm install`-shaped); zero object-side ceremony; single command. XDG-compliant.

**Cons:** requires a `puck` CLI to exist alongside `caspian` — another bootstrap-time binary. Naming collisions across independent objects (two `foo`s) need a resolution rule.

### Idea 2: Object-side `bin` declaration in `%meta`

Objects that are meant to be installable declare so in their metadata:

~~~caspian
%meta <<EOF
{
    "bin": {
        "bryton": "self"
    }
}
EOF
~~~

When `puck install <url>` runs, it reads the `bin` field to know what names to install and what they map to. `"self"` means "install this object itself as an executable"; other values could reference sibling objects for multi-file distributions.

**Pros:** matches npm's shape closely. Self-describing objects. Supports multi-binary distributions later.

**Cons:** extra metadata per object; more ceremony than "just install the URL."

### Idea 3: Combine 1 and 2

The `puck install <url>` command:
1. Reads the object's `%meta.bin` field if present; installs each name it lists.
2. If no `bin` field is present, defaults to installing the object under a name derived from the URL's last path segment (with `--as` to override).

Both simple objects (no metadata) and structured ones (with `bin`) work; developers pick the amount of ceremony they want.

### Idea 4: Caspian-side `%fetch.install`

Same as Idea 1 but expressed as a Caspian method rather than a shell CLI:

~~~caspian
%fetch.install 'https://puck.uno/bryton/runner/'
~~~

Called from an installer script or interactive Caspian session. The `puck` shell CLI (if any) would just be a thin wrapper around this.

**Pros:** Puck-native. Composable with other Caspian code (an installer script that installs several tools in one go).

**Cons:** requires the user to already have Caspian on PATH to run the install command. Fine if we accept that `caspian` is the one required bootstrap binary; every other install can be a Caspian call.

### Idea 5: Skip the install layer; use shell wrappers

Instead of "installing" anything, ship a tiny shell wrapper that lives on PATH and does the fetch-and-invoke inline:

~~~bash
#!/usr/bin/env bash
exec caspian -e '%("https://puck.uno/bryton/runner/").run()' "$@"
~~~

The developer writes (or downloads) that wrapper once, drops it in `~/.local/bin/bryton`, chmod +x. No Puck-side install logic — just a Puck URL and a standard shell technique.

**Pros:** zero new mechanism; uses only what already exists (shell, chmod, PATH). The Puck side stays entirely on-demand.

**Cons:** every "install" is a manual wrapper-writing step. Doesn't scale to "install a set of tools" workflows.

## Bootstrap concerns

Whatever mechanism lands, one bootstrap step remains: **the bin directory needs to be on `PATH`.** The Caspian installer (whatever ships `caspian` initially) can add `~/.local/bin` to PATH via the shell rc file, or document the one-time addition. This is standard practice — every ecosystem does it at first install.

## Where the `bin` field could live

If we go with a `bin` declaration (Ideas 2 / 3), possible homes:

- **In `%meta`** — the object's compile-time metadata block. Non-executable at runtime; readable by tools.
- **A dedicated `%install` block** — parallel to `%meta`, specifically for install-time hints.
- **Inline in `vibecode`** — since vibecode already carries structured tool-facing metadata.

`%meta` is the natural choice — vibecode is AI-facing; a dedicated `%install` block is one more concept to spec.

## Open questions

- **Naming collisions.** Two independently-installed objects both wanting to be `foo` at the shell. How does `puck install` handle it? Reject the second install? Prompt for a new name? Namespace by publisher (`puck install --scope mikosullivan foo`)?
- **Update / uninstall.** `puck update foo` re-fetches from the same URL and reinstalls. `puck uninstall foo` removes the file. Both standard-shape; needs a bookkeeping index (`~/.local/share/puck/installed.json`?).
- **Shebang handling.** Caspian scripts need `#!/usr/bin/env caspian`. Does `puck install` add or verify the shebang if the downloaded file doesn't have one? Or reject files without a proper shebang?
- **Bin-dir choice.** `~/.local/bin` is XDG-standard and increasingly common. But some setups don't have it on PATH by default. Alternatives: `~/.cargo/bin`-style dedicated dir (`~/.puck/bin`), or user's choice via config.
- **Trust and provenance.** Installing an executable from a URL is riskier than fetching a library — the executable runs with the user's privileges. Should `puck install` require the URL to be blockchain-endorsed (per the `%fetch.blockchain` setting)? Prompt on unverified URLs?

## Direction

**Follow the same pattern as [Caspian installation](../requirements/installation/) itself.** XDG-compliant paths — executables land at `~/.local/bin/<name>`, matching where the `caspian` binary lives. Nothing invented; nothing that doesn't already work for every other language ecosystem.

### Base command

The install is a flag on the `caspian` binary — no separate `puck` CLI needed:

~~~
caspian --install-script https://foo.com/bar.casp
~~~

This is the base common case. `caspian` downloads the URL, drops the file at `~/.local/bin/<name>`, and makes it executable. The name defaults to something derived from the URL (probably the last path segment stripped of extension — `bar` in the example above); a flag like `--as` can override.

### `--global` — install system-wide

Add `--global` to install to a system-wide location instead of the user's XDG dir:

~~~
sudo caspian --install-script --global https://foo.com/bar.casp
~~~

The file lands at `/usr/local/bin/<name>` (the de facto Unix convention for locally-installed system executables). The command requires root privileges; without them, `caspian` raises with a clear "need sudo for --global" message.

**No sudo auto-detection.** `sudo caspian --install-script <url>` **without** `--global` still writes to the invoking (root) user's `~/.local/bin/` — which is almost never what anyone wants. `caspian` warns in that case ("you're running as root but installing to root's home directory — did you mean `--global`?") but doesn't block, matching the general no-nanny-code posture. The user has to name their intent explicitly.

### Still to be settled

- **Naming rule** — default name derivation (strip `.casp`? use the last segment verbatim? use the object's `%meta.name`?). Override flag for explicit naming.
- **Object-side metadata** — whether an object can declare `bin` / `install`-relevant fields in `%meta` so the install command can pick up name / shebang / etc. automatically.
- **Update path** — re-invoking `caspian --install-script <url>` on an already-installed URL. Overwrite? Confirm? Version-aware?

## Blockchain

Scripts can be installed via Puck's [blockchain](../requirements/fetch-discovery/blockchain/) — the signed-endorsement ledger at `blockchain.puck.uno`. The blockchain fetcher looks up the signed endorsement for a URL, fetches the bytes from the endorsed origin, verifies them against the recorded hash, and installs the file only if everything checks out.

### Opt-in preference

When a developer installs Caspian, they're asked whether they want to opt into using the blockchain. Their choice is saved as a preference in **`~/.config/caspian/config.json`** (XDG-standard config location). The opt-in preference shapes the default behavior of the bare `caspian --install-script <url>` command.

The exact opt-in procedure, config-file shape, and how to flip the preference later are spec'd separately when the install flow is designed.

### Default behavior by opt-in state

The bare command behaves differently depending on the user's saved preference:

| Command | Opted-in behavior | Not opted-in behavior |
|---|---|---|
| `caspian --install-script <url>` | Blockchain first, fall back to direct fetch | Direct fetch |
| `caspian --install-script <url> --blockchain` | Strict blockchain (fail if not endorsed) | Strict blockchain (one-off opt-in for this install) |
| `caspian --install-script <url> --direct` | Direct fetch (skip blockchain) | Direct fetch (redundant) |

**Explicit flags are absolute** — `--blockchain` and `--direct` mean the same thing regardless of the user's saved preference. Only the default behavior of the bare command varies.

### The flags

- **`--blockchain`** — strict. The blockchain is consulted; if there's no endorsement (or the bytes don't match), the install **fails cleanly**. No fallback to direct fetch, regardless of the user's opt-in state. Use this when the install must be verified.
- **`--direct`** — skip the blockchain entirely. Fetch the URL directly and install the bytes. Use this when the script is on a private or unpublished URL that doesn't (or can't) have a blockchain endorsement.

The flags are mutually exclusive at the "primary source" level — you can't ask for both strict-blockchain AND skip-blockchain in the same command. The runner raises if both are given.

### License requirement

Like any other artifact endorsed on the blockchain, a script installed via blockchain **must include at least an open-source license** — license is a required field on every endorsement (see [publishing](../requirements/fetch-discovery/blockchain/publishing)). A script without a license can't be published to the blockchain in the first place, so a blockchain install never delivers unlicensed code.

Direct installs (via `--direct` or the not-opted-in default) don't check for a license; the responsibility for verifying licensing shifts to the developer, same as any manual download.

## Uninstall

Uninstall takes a **name**, not a URL:

~~~
caspian --uninstall-script <name>
~~~

`caspian` looks at `~/.local/bin/<name>` (or `/usr/local/bin/<name>` for the `--global` variant), confirms the file was installed by Caspian, and removes it. A parallel `--global` flag mirrors install:

~~~
sudo caspian --uninstall-script --global <name>
~~~

Requires root permissions; same rule as `--install-script --global`.

### Why name, not URL

Every mainstream package manager — npm, pip, gem, cargo, brew — uninstalls by name because names are what users remember. URLs are for install-time identity; names are for day-to-day management. Requiring a URL for uninstall would mean either the user has to remember (or look up) the URL from months ago, or the tool has to maintain a URL→name registry to translate. Once such a registry exists, name-only uninstall is simpler and just as capable.

### Registry bookkeeping

`caspian` needs some record of "I installed this file" so uninstall knows what's safe to delete (vs. a random file the user dropped in `~/.local/bin/` by hand). Probably a lightweight file at `~/.local/share/caspian/installed.json` (XDG data location) tracking each installed name, its source URL, install date, and whether it came from the blockchain or a direct fetch. Exact shape settled with the rest of the install procedure.

### URL form (deferred)

If a real use case surfaces later, the tool could add URL-based uninstall as a lookup — consult the registry, find name(s) installed from the given URL, remove them. Ambiguity (multiple installs from the same URL) would surface as a prompt or error. Not spec'd for V1; the name-based form covers every current case.
