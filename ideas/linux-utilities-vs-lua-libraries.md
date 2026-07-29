# Linux utilities catalog

~~~vibecode
{"vibecode": {
	"doc": "ideas_linux_utilities_catalog",
	"role": "menu of popular CLI utilities on Linux that could plausibly be wrapped as
		Caspian downloads at caspian.uno/<name>.casp. Inclusion is a suggestion, not a
		proposal — Miko decides in V1 which (if any) to actually wrap. Excludes utilities
		already spec'd in requirements/ (openssl, tar, luaexpat, lsqlite3 — those have
		their own specs).",
	"status": "catalog — additions welcome, no prioritization implied",
	"key_concepts": ["cli_wrapper", "puck_download", "prerequisite_delegation"]
}}
~~~

Candidates for a Caspian wrapper class at `caspian.uno/<name>.casp` — Ships-no, fetched via `%fetch` on first use, delegates work through `.execute`. Every entry is a menu item, not a commitment. Utilities already spec'd elsewhere (`openssl`, `tar`, `luaexpat`, `lsqlite3`) are omitted.

## Text processing

- **`sed`** — stream editor for find/replace on files or stdin.
- **`awk`** / **`gawk`** — pattern-scanning language for structured text.
- **`grep`** — regex search across files/stdin.
- **`tr`** — character translation and deletion.
- **`cut`** — extract columns by delimiter or byte offset.
- **`sort`** — sort lines by column, numeric, or key.
- **`uniq`** — deduplicate adjacent lines; count with `-c`.
- **`diff`** / **`patch`** — text diff and patch application.
- **`iconv`** — character-encoding conversion.
- **`xxd`** — hex dump; also reverses hex back to bytes.
- **`fmt`** / **`fold`** — reformat prose to a max width.

## Compression and archiving

- **`gzip`** / **`gunzip`** — DEFLATE, streaming.
- **`bzip2`** — better ratio than gzip, slower.
- **`xz`** — LZMA2, best ratio in this family.
- **`zstd`** — modern, fast, tunable.
- **`zip`** / **`unzip`** — cross-platform archive.
- **`7z`** — many formats; not always default.
- **`ar`** — Unix archive format (`.deb`, static libraries).

## Data formats

- **`jq`** — JSON query and transform.
- **`yq`** — YAML query, jq-like.
- **`csvkit`** — `csvlook`, `csvcut`, `csvjson`, etc.
- **`csvtool`** — CSV manipulation, less common than csvkit.

## Networking

- **`curl`** — HTTP/HTTPS/FTP; universally installed.
- **`wget`** — HTTP downloads with retry.
- **`ping`** — ICMP echo.
- **`traceroute`** / **`mtr`** — path tracing.
- **`nc`** / **`ncat`** — TCP/UDP Swiss Army.
- **`dig`** — DNS lookup.
- **`ss`** — socket status (replaces `netstat`).
- **`ip`** — routing / interface config (replaces `ifconfig`).

## Cryptography and identity

- **`gpg`** / **`gpg2`** — GnuPG signing, encryption, key management.
- **`sha256sum`**, **`sha1sum`**, **`md5sum`** — checksums.
- **`ssh`** / **`ssh-keygen`** / **`scp`** / **`sftp`** — Secure Shell suite.
- **`age`** — modern file encryption; simpler than gpg.

## Filesystem

- **`rsync`** — efficient sync/copy, local or SSH.
- **`find`** — file search by name, size, mtime, perms.
- **`du`** / **`df`** — disk usage / free space.
- **`stat`** — detailed file metadata.
- **`readlink`** / **`realpath`** — resolve symlinks and canonicalize paths.
- **`inotifywait`** — block until filesystem events (from `inotify-tools`).
- **`lsof`** — list open files and their processes.
- **`file`** — identify file type from content.

## Databases (clients)

- **`psql`** — PostgreSQL client.
- **`mysql`** / **`mariadb`** — MySQL/MariaDB client.
- **`redis-cli`** — Redis client.
- **`mongosh`** — MongoDB shell.
- **`influx`** — InfluxDB CLI.

## Process management

- **`ps`**, **`top`**, **`htop`** — process listing.
- **`pgrep`** / **`pkill`** — find/signal by pattern.
- **`kill`** / **`killall`** — signal by PID / name.
- **`systemctl`** — systemd service control.
- **`crontab`** — cron job management.
- **`at`** — one-shot scheduled jobs.

## Version control

- **`git`** — universally installed.
- **`hg`** — Mercurial; less common.
- **`svn`** — Subversion; legacy.

## Image and media

- **`convert`** / **`identify`** / **`mogrify`** — ImageMagick image processing.
- **`ffmpeg`** — audio/video transcoding.
- **`ghostscript`** (`gs`) — PostScript / PDF processing.

## Documents

- **`pandoc`** — universal document conversion.
- **`pdftotext`** / **`pdfinfo`** — PDF text extraction (from `poppler-utils`).
- **`weasyprint`** — HTML to PDF.
- **`libreoffice --convert-to`** — headless conversion of office formats.

## System info

- **`uname`** — kernel and OS.
- **`lsblk`** — block devices.
- **`lscpu`** / **`lspci`** / **`lsusb`** — hardware enumeration.
- **`free`** — memory usage.
- **`uptime`** — load and uptime.
- **`dmesg`** — kernel ring buffer.

## Time and scheduling

- **`date`** — format and parse dates.
- **`cal`** — calendar.
- **`timedatectl`** — systemd timedate control.
- **`chronyc`** / **`ntpq`** — NTP client status.

## Language runtimes (`-c` / `-e` style shell-out)

- **`python3`** — usually present on any Linux with dev tools.
- **`perl`** — near-universal, very stable.
- **`ruby`** — sometimes present.
- **`node`** — increasingly common, often opt-in.

## Terminal and desktop

- **`tput`** — query/set terminal capabilities.
- **`tmux`** / **`screen`** — multiplexers.
- **`less`** / **`more`** — pagers.
- **`xdg-open`** — open URLs/files in the desktop-default app.
- **`notify-send`** — desktop notifications (via `libnotify-bin`).

## Automation and glue

- **`envsubst`** — substitute `${VAR}` from environment.
- **`flock`** — advisory file locking.
- **`getopt`** — POSIX argument parsing.
- **`expect`** — interact with interactive processes.
- **`parallel`** (GNU parallel) — run jobs concurrently.

## Rough universality (Debian/Ubuntu, Fedora/RHEL, Arch, Alpine, base containers)

- **In essentially every distro:** curl, tar, gzip, grep, sed, awk, sort, uniq, cut, tr, diff, patch, find, xxd, ps, kill, ssh, git, sha256sum, md5sum, jq, dig, ip.
- **Common but not in minimal containers:** wget, rsync, less, tmux, htop, ffmpeg, imagemagick, ghostscript, python3, perl, pandoc.
- **Distro / desktop specific:** systemctl (systemd only), xdg-open, notify-send, apt/rpm/pacman families.
- **Usually a separate install:** yq, age, csvkit, weasyprint, node, mongosh.

## Related

- [concepts § Lean on installed Linux utilities](https://puck.uno/requirements/concepts#lean-on-installed-linux-utilities-when-theyre-better) — the design principle this catalog serves.
- [linux-support/openssl](https://puck.uno/requirements/linux-support/openssl) and [linux-support/tar](https://puck.uno/requirements/linux-support/tar) — worked examples of the wrapper pattern.
- [core](https://puck.uno/requirements/core/) — current Cache tier and floppy budget.
