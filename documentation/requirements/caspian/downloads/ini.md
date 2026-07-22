# INI

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_v1_downloads_ini",
	"role": "spec for the INI class at `caspian.uno/ini.casp` — Ships: no, Day 1: TBD. The traditional Windows-era key=value config format, still used by systemd unit files, git config, PHP config, and a lot of legacy tooling.",
	"status": "stub — needs class-surface design and scope decision on which INI dialect it targets",
	"audience": "developers reading/writing INI-style config (systemd units, gitconfig, legacy tools); anyone writing the INI class spec"
}}
~~~

Stub. First-party download at `caspian.uno/ini.casp` — INI encode/decode.

## What INI is

TBD. Simple text config: `key = value` under `[section]` headers. No standard — every dialect handles quoting, comments, sub-sections, arrays, and duplicate keys differently. Class scope needs to pick a target (or expose the dialect knobs).

## Scope call to make

TBD. Candidates:
- **git-config style** — nested subsections (`[section "sub"]`), multi-valued keys.
- **systemd-unit style** — flat sections only, no quoting.
- **Python configparser style** — interpolation, defaults section.
- **Common denominator** — flat sections, `#` and `;` comments, no interpolation, single-valued keys.

## Method surface

TBD. `.parse` / `.emit` shape.

## Testing

TBD.
