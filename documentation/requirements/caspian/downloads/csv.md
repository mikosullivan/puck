# CSV

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_v1_downloads_csv",
	"role": "spec for the CSV class at `caspian.uno/csv.casp` — Ships: no, Day 1: yes. Comma-separated values encode/decode. Streaming row iteration for large files.",
	"status": "stub — needs class-surface design",
	"audience": "developers reading/writing CSV files (spreadsheets, exports, data-science workflows); anyone writing the CSV class spec"
}}
~~~

Stub. First-party download at `caspian.uno/csv.casp` — CSV encode/decode.

## What CSV is

TBD. Line-per-row, comma-separated fields, quoting via `"..."`, escape via doubled `""`. In practice a family of dialects (delimiter, quote character, line ending, header row present) that the class needs to expose as options.

## Method surface

TBD. Likely `.parse` (streaming row iteration for large files), `.emit`, dialect options as constructor / method kwargs.

## Testing

TBD.
