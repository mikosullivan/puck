# `bryton.json` — files

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_runner_bryton_json_files",
	"role": "spec for the file-related settings in bryton.json — how per-file configuration is expressed. Sibling of bryton-json/index.md; content pending.",
	"status": "spec in progress — shape (hash keyed by file/dir name) and the three element-value forms (true/false/hash) settled; hash content (per-file meta) to be spec'd",
	"audience": "developers configuring Bryton test directories at the file level"
}}
~~~

## Shape

The **`files`** field is a hash. Its keys are the names of files or directories in the surrounding directory.

## Element values

Each element in the `files` hash can carry one of several value types:

- **`true`** — run the file.
- **`false`** — do not run the file. The file will be reported as [skipped](https://puck.uno/documentation/requirements/bryton/xeme/results/#skipped).
- **A hash** — a hash value is truthy, so the file is run. The content of the hash may give further meta information about the file — see [file settings](file-settings) for the fields. As a special case, setting `"skip": true` inside the hash causes the file to be skipped, exactly like giving the entry the value `false` — handy for toggling a file between active and skipped without discarding its other settings.

### Example

~~~json
{
	"files": {
		"test-login.py": true,
		"test-broken.sh": false,
		"test-slow.rb": {
			"timeout": 60,
			"tags": {"slow": true}
		}
	}
}
~~~

`test-login.py` is run; `test-broken.sh` is skipped; `test-slow.rb` is run with the meta information the hash carries.

## Files not listed

By default, files that aren't listed in `files` still run — they're picked up by the general "run every executable" rule. Listed files run first; unlisted files run after them.

To make the list **exclusive** (only listed files run; every other executable is skipped), set [`exclusive: true`](../#exclusive) in `bryton.json`.

## Listed files that don't exist

If a file is listed in `files` but isn't actually on disk, the runner produces a [`failure/runtime/missing`](https://puck.uno/documentation/requirements/bryton/xeme/results/failure#missing) result for it. No execution is attempted; the runtime-failure xeme takes the place of what the file would otherwise have produced. This is distinct from a file that exists but can't be run — that case is [`failure/runtime/not-executable`](https://puck.uno/documentation/requirements/bryton/xeme/results/failure#not-executable).
