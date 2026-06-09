# Non-interactive install story

~~~vibecode
{"vibecode": {
	"doc": "non_interactive_install_story",
	"role": "narrative walkthrough — Caspian install in environments without a TTY: CI runners, Docker builds, cron, systemd, ssh -T",
	"audience": "automation engineer setting up CI / Dockerfile / provisioning script",
	"detection": "wrapper attempts to open /dev/tty; if it fails, runs install.casp with --non-interactive",
	"override_mechanism": "environment variables",
	"defaults_when_non_interactive":
		{"install_location": "$HOME/caspian (or $CASPIAN_INSTALL_PREFIX)",
		"scope": "per_user",
		"examples": "part of install tree at $HOME/caspian/examples",
		"shell_rc": "updated if writable and CASPIAN_SKIP_RC_EDIT not set"},
	"status": "brainstorm — describes what V1.0 install should feel like"
}}
~~~

Some installs don't have a user to prompt: CI pipelines, Docker
image builds, cron jobs, systemd-managed setup scripts,
`ssh -T host curl ... | sh`. In all of these, `/dev/tty` isn't
openable. The Caspian installer detects this and falls back to a
silent default install — same code path as the interactive flow,
just with every prompt answered with its default.

This story walks through what that looks like in three common
environments.

For the interactive shell-user story, see [linux.md](linux.md).

---

<a id="how-detection-works"></a>
## How the installer detects non-interactive

The shell wrapper that `curl | sh` invokes attempts to open
`/dev/tty`:

```sh
if exec 3</dev/tty 2>/dev/null; then
    # Interactive — hand off to the Caspian installer normally
    exec "$tmpdir/bin/caspian" "$tmpdir/install.casp"
else
    # No TTY — pass --non-interactive so install.casp skips prompts
    exec "$tmpdir/bin/caspian" "$tmpdir/install.casp" --non-interactive
fi
```

The Caspian installer (`install.casp`) checks for the
`--non-interactive` flag at startup. If present, it skips every
prompt and uses the corresponding default value. Output is one line
per significant step, no decorative chrome.

---

<a id="defaults"></a>
## Defaults applied silently

| Decision | Default | Override |
|---|---|---|
| Install location | `$HOME/caspian` | `CASPIAN_INSTALL_PREFIX=/path` |
| Scope | per-user | `CASPIAN_INSTALL_SYSTEM=1` (requires sudo / root) |
| Edit shell rc | yes if rc file exists and is writable | `CASPIAN_SKIP_RC_EDIT=1` |

Examples are part of the install tree (`$HOME/caspian/examples/`)
and don't need a separate copy step — they live alongside the
engine and are user-editable by virtue of being in the user's home.

Every override is an environment variable, settable before the
`curl` call. No flags need to thread through the `| sh` pipe.

---

<a id="scenario-ci"></a>
## Scenario: GitHub Actions

A workflow that needs Caspian available before a test step:

```yaml
- name: Install Caspian
  run: curl -fsSL https://puck.uno/install | sh

- name: Run tests
  run: caspian tests/run.casp
```

What happens:

- GitHub Actions runs each step in a fresh shell with no TTY
  attached.
- The installer's `/dev/tty` open fails.
- It silently installs to `$HOME/caspian` (the runner's home dir).
- It appends the PATH line to `~/.bashrc`, but each `run:` step
  opens a fresh shell — so `~/.bashrc` may or may not be sourced.
  The reliable pattern is to set PATH explicitly in the same step:

```yaml
- name: Install Caspian
  run: |
    curl -fsSL https://puck.uno/install | sh
    echo "$HOME/caspian/bin" >> $GITHUB_PATH
```

(`$GITHUB_PATH` is GitHub Actions' way of making a PATH addition
persist across steps.)

Output in the runner log:

```
caspian-install: detected non-interactive (no /dev/tty)
caspian-install: target = /home/runner/.caspian
caspian-install: extracted bundle (847 KB)
caspian-install: shell rc updated: /home/runner/.bashrc
caspian-install: done
```

---

<a id="scenario-docker"></a>
## Scenario: Docker image

A `Dockerfile` that bakes Caspian into a base image:

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Caspian system-wide so every user in the container can use it.
RUN curl -fsSL https://puck.uno/install \
    | CASPIAN_INSTALL_PREFIX=/usr/local sh

CMD ["caspian", "--version"]
```

What happens:

- The `RUN` step has no TTY, so the installer detects non-interactive
  mode automatically.
- `CASPIAN_INSTALL_PREFIX=/usr/local` overrides the per-user default.
  The installer puts the launcher at `/usr/local/bin/caspian`, libs
  at `/usr/local/lib`, etc.
- No shell rc to update — `/usr/local/bin` is already on PATH for
  every user in a typical container.
- The image is now ready to run Caspian programs.

Resulting image size adds ~850 KB on top of the base, no other
modifications. Caspian fits comfortably in even minimal base images
without bloating the layer.

---

<a id="scenario-provisioning"></a>
## Scenario: Cloud-init / Ansible / shell provisioning

A provisioning script for a fresh VM:

```bash
#!/bin/sh
# bootstrap.sh — run on a fresh VM via cloud-init, Ansible, etc.

set -e

# Caspian, system-wide, no shell rc edits (server has no real users).
export CASPIAN_INSTALL_PREFIX=/usr/local
export CASPIAN_SKIP_RC_EDIT=1
curl -fsSL https://puck.uno/install | sh

# Verify
caspian --version
```

What happens:

- No TTY available (cloud-init runs in a service context).
- Installer takes the env-var overrides.
- Installs into `/usr/local`, leaves `/etc/skel/.bashrc` and root's
  rc files alone.
- Returns exit 0 on success, non-zero on any failure — friendly to
  `set -e` scripts.

---

<a id="error-handling"></a>
## Error handling in non-interactive mode

When prompts can't help recover from a problem, the installer has to
fail cleanly. Concrete cases:

| Failure | Exit code | What's printed |
|---|---|---|
| Download failure (curl error, 404) | 1 | "could not download bundle: <reason>" |
| Checksum mismatch | 1 | "bundle checksum mismatch: refusing to install" |
| Target dir already exists, non-empty | 1 | "directory already exists: <path> (set CASPIAN_OVERWRITE=1 to replace)" |
| Permission denied (system install without sudo) | 1 | "permission denied at <path>: re-run with sudo or set CASPIAN_INSTALL_PREFIX to a writable location" |
| Unsupported platform | 1 | "no pre-built bundle for <uname-output>: see from-source docs" |

Anything that interactive-mode would have asked the user about
becomes a hard failure with a clear error message and an env-var
hint for how to retry.

---

<a id="design-symmetry"></a>
## One installer, two paths

The interactive flow and the non-interactive flow share one
`install.casp`. The only difference is whether `--non-interactive`
was passed. Inside the script:

```caspian
if %argv.includes?('--non-interactive')
    $location = %env['CASPIAN_INSTALL_PREFIX'] || '~/caspian'
else
    $location = prompt('Install location', default: '~/caspian')
end
```

…and the same pattern for each decision point. **Defaults are
identical in both paths.** The interactive flow shows the defaults
in prompts and lets the user override; the non-interactive flow
applies them silently and lets env vars override. Same destinations,
same files, same shell rc behavior.

This keeps maintenance honest: any new install option added to the
interactive flow gets its corresponding env var defined in the
non-interactive flow at the same time.

---

<a id="open-questions"></a>
## Open questions

~~~vibecode
{"vibecode": {"open_questions":
["whether_to_emit_machine_readable_json_output_when_non_interactive",
"how_loud_or_quiet_default_non_interactive_output_should_be",
"opt_in_telemetry_about_install_environment_or_strictly_no_phone_home",
"behavior_when_curl_pipe_to_sudo_sh_with_user_owned_home_dir"]}}
~~~

- **Machine-readable output?** A `--output=json` flag could emit
  structured install results for CI tooling to parse. Probably not
  V1.0; humans-only output is enough.
- **Output verbosity.** Default is "one line per significant step."
  `--quiet` for "errors only," `--verbose` for "every file copied."
- **Telemetry.** Tempting to log install attempts (success/failure,
  platform mix) to inform priorities. Politically charged. V1.0
  should be no-phone-home; revisit if usage grows enough to warrant
  it.
- **`curl | sudo sh`.** If the user pipes to `sudo sh`, the
  installer runs as root, and a "per-user" default would install
  into root's home (`/root/.caspian`) — almost certainly not what
  was wanted. The installer should detect EUID 0 and either
  default to `/usr/local` or refuse and explain.
