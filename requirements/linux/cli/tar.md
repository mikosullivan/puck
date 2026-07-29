# tar

*Wraps the `tar` CLI utility — POSIX archiver with optional gzip / bzip2 / xz / zstd compression. Class at `caspian.uno/linux/cli/tar`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_tar",
	"role": "spec for the tar class at caspian.uno/linux/cli/tar — command-builder wrapper around the `tar` CLI utility. Priority 1 in the CLI wrappers list. V1 scope is narrow: extract a .tar.gz archive into a target directory (the sole call-site being installation's --self-test test-tarball extraction). The wrapper does NOT link libtar/libarchive — it accumulates flags and hands the built command to .execute, which runs `tar` itself. Consolidates the earlier linux-support/tar.md sketch, which is deleted.",
	"status": "spec — install-time flags (x, z, f, -C) and the command-builder shape settled; exact property names still a style pass; anything beyond extract-.tar.gz-into-dir is post-V1",
	"audience": "developers reaching for tar; the installation-self-test author; the tar wrapper author"
}}
~~~

## V1 scope

Extract a `.tar.gz` archive into a target directory — the sole call site being installation's `--self-test`.

## Flags needed for the install

To build `tar -xzf archive.tar.gz -C target_dir`:

- **`x`** — extract mode.
- **`z`** — gzip decompression (the archive is `.tar.gz`).
- **`f <path>`** — the archive file to read.
- **`-C <dir>`** — the target directory to extract into.

`p` (preserve permissions) is on by default when `tar` runs as root and off under a regular user. The wrapper defers to `tar`'s own defaults on that.

## Shape

The class is a **command builder**: instantiate with `.new`, configure via property assignment, then pass the instance to `.execute`. `.execute` reads the built command via the executable-object protocol (spec'd separately) and runs `tar` directly — no shell involved.

~~~caspian
$tar = %('caspian.uno/linux/cli/tar').new
$tar.extract = true            # x
$tar.gzip = true               # z
$tar.file = 'tests.tar.gz'     # f
$tar.into = $temp_dir          # -C

%fs.cwd.execute_in $tar
~~~

The wrapper accumulates flags in its own properties; the caller decides working directory, timing, and result handling. Errors surface through `.execute`'s structured result (`status`, `stderr`) — nothing tar-specific in the first pass.

Property names above are illustrative; exact naming is a separate style pass.

## Post-V1 additions

Creating archives, updating, list-without-extract, non-gzip compressors (bzip2 / xz / zstd), streaming from stdin, remote paths (`user@host:path`), verbose progress reporting. All later additions as needs arise.

## Method surface

TBD once the post-V1 additions land — the V1 shape is the four properties above plus `.execute` integration.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [linux-support](https://puck.uno/requirements/linux-support/) — the general `.execute` model this wrapper delegates to.
- [gzip](gzip), [bzip2](bzip2), [7z](7z) — sibling compressors / archivers.
