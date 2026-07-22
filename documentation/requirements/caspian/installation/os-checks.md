# OS checks

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_installation_os_checks",
	"role": "spec for the OS capability checks Caspian runs during install to detect kernel/OS features that Caspian's own features depend on. Each check knows what it's probing for, which Caspian feature depends on it, how to probe, whether a failure blocks install, and what to do when the probe fails (usually: warn and note in the install summary; Caspian degrades gracefully rather than blocking install). Currently only the OS-is-Linux check; grows over time as new Caspian features add OS dependencies.",
	"status": "stub — one baseline check; more will land as new Caspian features add OS dependencies",
	"audience": "installer maintainers; developers debugging why a Caspian feature doesn't work as expected on their system"
}}
~~~

The installer runs a small set of OS-capability probes after the [platform detection step](index#platform-detection) and before finalizing the [installation summary](index#installation-summary). Each probe:

- Names the kernel/OS feature it's checking for.
- Names the Caspian feature that depends on it.
- Runs a cheap, side-effect-free probe (a syscall attempt or a `/proc` read).
- Reports the result to the installation summary — pass, fail with reason, or "check skipped because prerequisites missing."

Whether a failed check blocks install depends on the check — see the **Blocks install?** column. Non-blocking failures let Caspian install successfully; features whose OS dependencies are missing raise cleanly when invoked and the rest of Caspian works normally. The install summary makes the degraded posture visible so operators know what they're getting.

## Check list

| Check | Feature | Probe | Blocks install? | On failure |
|---|---|---|:---:|---|
| OS is Linux | Caspian binary itself (V1 is Linux-only) | `uname -s` returns `Linux`; or `/proc/version` present | yes | Installer aborts before writing any files. Non-Linux platforms are post-V1. |

## Summary format

The installation summary includes an "OS capabilities" block after the standard paths section:

~~~
OS capabilities
	OS is Linux:                   ok
~~~

When a check with **Blocks install? yes** fails, the installer stops before any files are written and prints the failure with an actionable next step. When any non-blocking check degrades or fails, its line is prefixed with a warning marker and followed by a short explanation of what's affected. The precise formatting (indent, colors, symbols) is a UX detail for the installer implementation, not spec here.

## Re-checking after install

The same probes are exposed via `caspian --check-os` for operators to re-run at any time — useful after a kernel upgrade, after enabling / disabling a sysctl, or when diagnosing why a feature isn't behaving as expected. The command prints the same block the install summary showed and exits `0` if everything passed, `1` if any check degraded or failed.

## Growth over time

This page grows as new Caspian features add OS dependencies. When a feature spec adds a kernel or OS requirement, a corresponding row lands in the table with the same columns: what's checked, what depends on it, how to probe, whether it blocks install, and what happens on failure.
