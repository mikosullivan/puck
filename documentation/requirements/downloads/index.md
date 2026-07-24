# V1 downloads

~~~vibecode
{"vibecode": {
	"doc": "requirements_v1_downloads",
	"role": "index for requirements/v1-downloads/ — first-party classes Caspian promises to have available at V1 launch as fetch-on-demand downloads (Ships: no, Day 1: yes in the stdlib review). These are NOT bundled with the caspian binary; they live at `caspian.uno/<name>.casp` and are resolved via `%puck` on first use, then held in the local byte cache.",
	"status": "stub — awaiting per-class specs",
	"audience": "developers building against a V1 install; anyone maintaining the caspian.uno namespace"
}}
~~~

Stub. This section will hold per-class specs for the first-party classes Caspian promises to have available at V1 launch as fetch-on-demand downloads — not bundled with the binary, but resolvable via `%puck` on first use and then cached locally.

## In this section

- [BSON](bson) — binary JSON superset (MongoDB wire format). Stub.
- [CSV](csv) — comma-separated values encode/decode, streaming row iteration. Stub.
- [Gzip](gzip) — gzip compress / decompress; shellout wrapper around the `gzip` utility. Stub. **Ships-tier decision pending** — currently marked as core in the stdlib review.
- [INI](ini) — traditional key=value config format (systemd units, gitconfig, legacy tools). Stub.
- [Markdown](markdown) — port of Orlando's Markdown parser to a standalone class. Stub.
- [TOML](toml) — Tom's Obvious Minimal Language, used by pyproject.toml, Cargo.toml. Stub.
- [YAML](yaml) — YAML encode/decode, wrapping a Lua YAML library installed via `caspian --install-lua`. Stub.
- [Zip](zip) — zip archive read / write; shellout wrapper around the `zip` / `unzip` utilities. Stub.
