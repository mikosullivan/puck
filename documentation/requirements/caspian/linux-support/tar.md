# Tar wrapper

*Spec for the Caspian class at `https://puck.uno/linux/cl/tar.casp` — a wrapper around the `tar` CLI utility. Scoped narrowly to what installation needs: extract a `.tar.gz` archive into a target directory. Anything beyond that is a later addition.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_linux_support_tar",
	"role": "spec for the Caspian class at https://puck.uno/linux/cl/tar.casp — a command-builder wrapper around the tar CLI utility. Scope is deliberately narrow: extract a .tar.gz archive into a target directory (the sole call-site being --self-test's test-tarball extraction). The wrapper does not link libtar/libarchive — it accumulates flags and hands the built command to .execute, which runs tar itself. First entry in the linux-support/ tree.",
	"status": "spec — flags for the install-time test-tarball extraction settled; API shape (command-builder + property assignment + .execute integration) sketched but exact property names deferred; anything beyond extract-.tar.gz-into-dir is post-V1"
}}
~~~

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
$tar = %['https://puck.uno/linux/cl/tar.casp'].new
$tar.extract = true            # x
$tar.gzip = true               # z
$tar.file = 'tests.tar.gz'     # f
$tar.into = $temp_dir          # -C

%fs.cwd.execute $tar
~~~

The wrapper accumulates flags in its own properties; the caller decides working directory, timing, and result handling. Errors surface through `.execute`'s structured result (`status`, `stderr`) — nothing tar-specific in the first pass.

Property names above are illustrative; exact naming is a separate style pass.

## Out of scope for now

Creating archives, updating, list-without-extract, non-gzip compressors (bzip2/xz/zstd), streaming from stdin, remote paths (`user@host:path`), verbose progress reporting. All later additions as needs arise.
