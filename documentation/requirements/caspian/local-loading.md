# Loading local Caspian files
<!--index: 15-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_local_loading",
	"role": "spec for two mechanisms that reach local files from Caspian. (1) The `local:` URL scheme — `%puck['local:/whatever.casp']` (single or triple slash) — looks up `whatever.casp` by walking `%puck.locals`, a plain array of directory paths that is user-role-only for both read and write, process-scoped, assembled at CLI startup from four sources (`--lib` flags, `CASPIANLIB` colon-separated env var, XDG Base Directory defaults, and script-level modifications). (2) URL mapping — `%puck.maps` is a plain hash keyed by URL prefix, values are directory paths, used to redirect http/https URL fetches to local directories. Reads are ambient (any role that can use `%puck` sees the mappings), writes are user-only. Prefix match, first-registered wins on overlap. Miss on a mapping falls through to the next node in %puck's search path. Framed as CLI behavior — the engine has no ambient filesystem access.",
	"status": "spec — `local:` scheme, `%puck.locals`, `%puck.maps`, and four-source assembly settled; additional affordances (debugging, project-level overrides) may be layered later.",
	"audience": "developers publishing or consuming local Caspian files; CLI implementers; anyone reasoning about where a fetched class actually comes from"
}}
~~~

Two mechanisms reach local files from Caspian:

- **`local:` URLs** address files explicitly authored as local — `%puck['local:/widget.casp']` walks the `%puck.locals` array. Only the user role can use `local:`.
- **URL mapping** redirects http/https URL fetches to local directories — `%puck.maps['https://foo.bar/'] = '/home/miko/gup'` makes any fetch under `https://foo.bar/` resolve to a file under `/home/miko/gup`. Reads are ambient; only the user role can register or modify mappings.

**Framing.** Local-file lookup is CLI behavior, not engine behavior. The Caspian engine has no ambient filesystem access — it can only reach files the CLI hands it via `%chain`'s fetch surface. When any script fetches a URL, the CLI walks `%puck`'s search path (which includes URL mapping, the `local:` mechanism, local caches, and the network), reads and evaluates the first hit, and hands the resulting value back to the engine as though the URL had been fetched remotely. Consistent with Caspian's sealed-scope model: no ambient globals, no engine-level reach into the developer's environment.

## The `local:` scheme

A `local:` URL names a file to look up on the developer's machine:

~~~caspian
$widget = %puck['local:/widget.casp']
~~~

The path after `local:` — `widget.casp` in the example — is looked up under each directory in `%puck.locals`, in order. The first directory that has a matching file wins; the CLI reads and evaluates that file, and the result is the fetch's return value. If no directory has a match, the fetch raises.

**Slash forgiveness.** The one-slash form is canonical, but the CLI also accepts the standard empty-authority URL form (`local://`) for forgiveness. Both fetches below refer to the same file and resolve identically:

~~~caspian
%puck['local:/widget.casp']
%puck['local:///widget.casp']
~~~

The two-slash form (`local://widget.casp` with the authority reading `widget.casp`) is not a canonical URL shape and is not accepted; use the one-slash or three-slash form.

**User-role-only.** `local:` URLs can only be fetched by code running under the user role. A non-user role attempting `%puck['local:/x.casp']` raises. Untrusted code cannot reach into the developer's machine, cannot influence which local files are searched, and cannot enumerate `%puck.locals`. That property is what makes it safe to expose local paths to Caspian at all.

## The `%puck.locals` array

`%puck.locals` is a plain array of directory paths. Local-file lookups walk the array in order until the target file is found. Access is **user-role only** and **process-scoped** — untrusted roles have no visibility into or reach on the array, and modifications persist for the whole process run (they do not vanish when a modifying script's frame returns). Because `%puck.locals` is only ever manipulated by the user role, it does not live on `%chain`.

Because it's a plain array, any array operation works: `<<` to append, `.prepend` to prepend, direct assignment to replace, iteration to inspect, dedup or splice at any position. The script picks the semantics it wants; nothing about `%puck.locals` is special beyond the fact that the CLI reads it when resolving a `local:` fetch.

## Assembly of the initial array

When the CLI starts up, it builds the initial `%puck.locals` array by concatenating four sources in priority order:

1. **`--lib` CLI flags** — highest priority, added in the order they appear on the command line.
2. **`CASPIANLIB` environment variable** — colon-separated list, in the order specified.
3. **XDG default chain** — `~/.local/share/caspian/`, then `/usr/local/share/caspian/`, then `/usr/share/caspian/` (lowest priority).
4. **Script-level modifications** — layered on top of the above once the script runs. Position is whatever the script chooses.

The initial array is fully assembled before the first line of the script executes. The script's own modifications happen after that, adding to whatever the CLI produced.

### `--lib` CLI flags

`--lib` adds one directory to the search chain. The flag is repeatable; each occurrence adds one dir. All `--lib` entries land at the front of the array (highest priority) in the order they appear on the command line:

~~~
caspian --lib ~/caspian --lib ~/foobar myscript.casp
~~~

The initial array here starts with `~/caspian`, then `~/foobar`, followed by whatever `CASPIANLIB` and the XDG defaults contribute.

### `CASPIANLIB` environment variable

`CASPIANLIB` is a colon-separated list of directory paths, matching the Unix convention (`PATH`, `PYTHONPATH`, `RUBYLIB`, etc.):

~~~
CASPIANLIB=/opt/caspian:/tmp/experiments caspian myscript.casp
~~~

`CASPIANLIB` entries are added after any `--lib` entries and before the XDG defaults, in the order they appear in the variable.

### XDG default chain

The tail of the initial array is the XDG Base Directory Specification default:

1. **`~/.local/share/caspian/`** — user data files. Per XDG, this is `$XDG_DATA_HOME/caspian/`, where `XDG_DATA_HOME` defaults to `~/.local/share/`.
2. **`/usr/local/share/caspian/`** — admin-installed, machine-local files.
3. **`/usr/share/caspian/`** — distribution-packaged files.

Entries 2 and 3 come from `XDG_DATA_DIRS`, which defaults to `/usr/local/share:/usr/share`.

The load pattern is "user first, then system." A user's copy of a file at `~/.local/share/caspian/widget.casp` shadows any system copy at `/usr/local/share/caspian/widget.casp` or `/usr/share/caspian/widget.casp`, without needing root or touching system directories.

The full default chain comes from the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) <!-- outbound-link-allowed -->.

### Script-level modifications

Once the initial array is assembled, a script running under the user role can modify `%puck.locals` at will. Common patterns:

~~~caspian
%puck.locals << '/tmp/my-libs'          # add as fallback (append)
%puck.locals.prepend '/opt/priority'    # add as priority (prepend)
%puck.locals = ['/only/this']           # replace wholesale
~~~

The modification persists for the rest of the process run and applies to every subsequent `local:` fetch, including those triggered by scripts loaded from within the current one.

Untrusted roles have no read or write access to `%puck.locals`. A non-user role attempting to touch it raises.

## XDG environment variable overrides

The CLI respects the XDG environment variables when they are set:

- **`XDG_DATA_HOME`** — replaces the user data location. Caspian searches `$XDG_DATA_HOME/caspian/`.
- **`XDG_DATA_DIRS`** — replaces the system data locations. Caspian searches each colon-separated entry with `/caspian/` appended.

Per the XDG specification, setting these variables replaces the defaults wholesale — the CLI does not silently append its own defaults to a user-provided value. If a caller sets `XDG_DATA_DIRS=/opt/caspian-classes`, only `/opt/caspian-classes/caspian/` is searched at system scope; the defaults are not tacked on. Include the defaults explicitly if they are wanted.

`XDG_DATA_HOME` and `XDG_DATA_DIRS` affect only the XDG-default portion of the initial array. `--lib` flags and `CASPIANLIB` are independent of the XDG variables and are added regardless.

## URL mapping

The `local:` scheme covers URLs the developer explicitly authors as "look this up locally." A parallel mechanism, **`%puck.maps`**, redirects **http / https URL fetches** to local directories. This lets code that fetches a real URL — during development, offline, in a test — resolve to a local file transparently, without changing the URL itself.

~~~caspian
%puck.maps['https://foo.bar/gup/'] = '/home/miko/gup'

$class = %puck['https://foo.bar/gup/whatever.casp']
# resolves to /home/miko/gup/whatever.casp
~~~

### Prefix mapping

The URL key is a **prefix**. Any URL that starts with the key matches, and the tail after the prefix is appended to the mapped directory. The mapping `%puck.maps['https://foo.bar/gup/'] = '/home/miko/gup'` handles both `.../gup/whatever.casp` (→ `/home/miko/gup/whatever.casp`) and `.../gup/sub/other.casp` (→ `/home/miko/gup/sub/other.casp`) from a single entry.

### Overlapping mappings

If more than one mapping matches a URL, the mapping that was **registered first** wins:

~~~caspian
%puck.maps['https://foo.bar/']      = '/home/miko/root'
%puck.maps['https://foo.bar/gup/']  = '/home/miko/gup'

$class = %puck['https://foo.bar/gup/whatever.casp']
# resolves to /home/miko/root/gup/whatever.casp — the shorter prefix was
# registered first, so it wins.
~~~

To give a more specific mapping priority over a general one, register the specific one first. To swap priority later, remove and re-add.

### Ambient read, user-only write

Any role that can use `%puck` sees the mappings — fetching a mapped URL from any role transparently resolves through the redirect. That's the whole point; downstream code shouldn't need to know whether a URL was redirected.

**Writes are restricted to the user role.** A non-user role attempting to assign to `%puck.maps` — add a mapping, modify an existing one, remove one — raises. The asymmetry is deliberate: reads are ambient because the redirect is meant to be transparent; writes are locked down because untrusted code shouldn't be able to hijack URL resolution.

### Miss falls through

When a mapping resolves a URL to a local path but the file isn't there, the fetch doesn't raise and doesn't retry other mappings. `%puck` walks its own ordered search path — built-in files, URL mappings, local caches, the network, and other resource nodes — with the URL-mapping mechanism sitting as one node in that path. A miss on the mapping just continues to the next node. (The full `%puck` search path is spec'd elsewhere.)

### Persistence

`%puck.maps` persists for the whole process run. `%puck` doesn't live on `%chain`, so a mapping doesn't vanish when the script that added it returns.

### Plain hash

`%puck.maps` is a plain hash keyed by URL prefix, values are directory paths. Any standard hash operation works — iterate to inspect, assign to add or update, unset to remove, replace wholesale to reset. Nothing about `%puck.maps` is special beyond the fact that `%puck` reads it during URL resolution.

### One directory per prefix — no versioning

A mapping ties a URL prefix to a single directory. That means the mechanism can't serve **different versions** of a file at a mapped URL — `%puck.maps['https://foo.bar/'] = '/home/miko/gup'` points at exactly one `whatever.casp` under `/home/miko/gup`, with no way to distinguish "the v1 build" from "the v2 build" at the same URL.

Local versioning support — the ability to hold multiple versions of a file at a URL and hand back the right one on demand — needs the directory to be formatted as a **cache**, not a plain mapping target. Caches are a separate mechanism sitting elsewhere in `%puck`'s search path; the cache spec is not yet defined.

## Related

- [content-types](https://puck.uno/documentation/requirements/caspian/content-types) — HTTP Content-Types for Caspian and CaspianJ files (the wire-level companion for remote fetches; this page covers local-file resolution).
- [files](https://puck.uno/documentation/requirements/caspian/files) — what a Caspian source file evaluates to once loaded.
