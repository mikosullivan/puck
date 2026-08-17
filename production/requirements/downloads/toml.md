# TOML

~~~vibecode
{"vibecode": {
	"doc": "requirements_v1_downloads_toml",
	"role": "spec for the TOML class at `caspian.uno/toml.casp` — Ships: no, Day 1: TBD. Tom's Obvious Minimal Language — flat config format used by pyproject.toml, Cargo.toml, and similar tooling.",
	"status": "stub — needs class-surface design",
	"audience": "developers reading/writing TOML config files (Rust/Python tooling, dev config); anyone writing the TOML class spec"
}}
~~~

Stub. First-party download at `caspian.uno/toml.casp` — TOML encode/decode.

## What TOML is

TBD. Config-file format designed as a JSON alternative that's easy for humans to read and write. `key = value` at the top level; `[section]` headers for nested hashes; `[[array]]` for lists of tables; standard scalar types (strings, ints, floats, bools, dates).

## Method surface

TBD. `.parse` / `.emit` shape, matching the JSON class family.

## Testing

TBD.
