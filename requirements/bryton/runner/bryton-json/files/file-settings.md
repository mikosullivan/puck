# File settings

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_runner_bryton_json_file_settings",
	"role": "spec for the fields that can appear inside a per-file hash value in bryton.json's `files` field. Sibling of files/index.md; content pending.",
	"status": "spec in progress — mirrors-directory-fields rule settled; file-specific fields to be added as they land",
	"audience": "developers configuring per-file settings for Bryton tests"
}}
~~~

When an entry in [`files`](./) has a hash value, the hash's fields carry per-file meta information — timeouts, tags, and other settings that apply just to that file.

The available fields **mainly mirror the fields for a directory** — the ones documented on the [bryton-json](../) page. A setting at the file level applies just to that file; a setting at the directory level applies to everything in the directory unless a specific file overrides it.

Fields that only make sense at the directory level (like `files` itself) don't apply here. The overlaps between file-level and directory-level settings will be listed briefly on this page as directory fields are decided.

- **[`trim`](../../#trim)** — a `trim: true` inherited from the directory chain propagates into the file's `BRYTON` env var. Test scripts can read it via `$bryton.env['trim']` and (optionally) emit already-trimmed xemes.

## File-specific fields

### `skip`

When `true`, the file is not run and is marked as skipped in the results.

Setting `skip: true` inside a file's hash value does exactly the same thing as setting the file's entry to `false`. It exists as a hash field so you can leave the hash's other settings in place while toggling the file between active and skipped — flip `skip` instead of replacing the whole entry.
