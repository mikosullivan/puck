# Mikobase as a Filesystem (brainstorm)

~~~json
{"vibecode": {
	"doc": "mikobase-as-filesystem",
	"role": "brainstorm about exposing a mikobase as a directory-tree filesystem so storage-agnostic consumers (Sammy static, Jasmine stores, DirJails) can use mikobase transparently; explores the two superpowers POSIX cannot offer",
	"key_concepts": ["mikobase_backed_filesystem", "storage_agnostic_consumers",
		"transactions_over_files", "history_over_files"],
	"status": "brainstorm"
}}
~~~

**Status:** brainstorm. Vibing on the idea. Not committed; not
specced; just thinking out loud.

The seed: [mikobase](../../mikobase/mikobase.md) is a structured data store.
Filesystems are also structured data stores, of a particular
shape. **What if mikobase could *be* a filesystem** — exposing a
directory-tree interface backed by mikobase data?

---

<a id="contents"></a>
## 1 Contents

- [Why it's interesting](#why-its-interesting)
- [The two superpowers](#the-two-superpowers)
  - [Transactions](#transactions)
  - [Time-travel reads](#time-travel-reads)
  - [The combination is more than the sum](#the-combination-is-more-than-the-sum)
- [POSIX access via SSH and SSHFS](#posix-access-via-ssh-and-sshfs)
- [In-memory mode](#in-memory-mode)
- [FSO and the path forward](#fso-and-the-path-forward)
- [Other concerns](#other-concerns)
- [As a versioning tool](#as-a-versioning-tool)
- [Storage shape: chunks vs deltas](#storage-shape-chunks-vs-deltas)
- [Open questions / things to vibe on](#open-questions-things-to-vibe-on)
- [Out of scope for now](#out-of-scope-for-now)

---

<a id="why-its-interesting"></a>
## 2 Why it's interesting

- A mikobase-backed directory could plug into anywhere a directory
  object is expected ([Sammy static serving](../../charlie/http-middleware/sammy.md#static-file-serving),
  [Jasmine directory stores](../../charlie/jasmine/jasmine.md#stores),
  [%utils.tempdir DirJails](../../charlie/utils.md), etc.) without those
  consumers knowing anything about mikobase.
- "Storage-agnostic" gets real teeth: a developer can swap a real
  filesystem for a mikobase-backed one and the rest of the code
  doesn't change.
- A single backing store for everything — code, content, logs,
  uploaded files, scratch — instead of a separate filesystem layer
  that has to be synced or coordinated.
- Mikobase already handles persistence, querying, history, etc.
  Layering a filesystem interface on top would inherit those
  properties for free.

---

<a id="the-two-superpowers"></a>
## 3 The two superpowers

The dir/file/permissions surface is trivial — most filesystems
have it. What makes a mikobase-backed filesystem genuinely
different is two properties POSIX can't offer.

<a id="transactions"></a>
### 3.1 Transactions

POSIX filesystems can't do multi-file atomic operations. You can't
atomically rename a directory while updating its children. Tools
work around it (staging dirs, rename-into-place tricks) but the
primitive isn't there. With mikobase, anything multi-step that
needs all-or-nothing semantics is free:

- **Atomic deploys.** Stage every file, commit, the new version
  appears at once. No partial-deploy intermediate state.
- **Atomic log + index updates.** A Jasmine entry plus any
  derived index can land together or not at all.

<a id="time-travel-reads"></a>
### 3.2 Time-travel reads

"What was `/etc/config.json` on 2026-03-15 at 14:22?" is a
question almost no filesystem can answer. ZFS/Btrfs snapshots are
coarse, point-in-time, opt-in. With mikobase, every read can
carry a timestamp parameter:

- **Forensics.** A bug report from last week — view the codebase
  as it was when the bug happened.
- **Rollback.** A bad deploy isn't "find the old files and copy
  them back" — it's "show the filesystem as it was 10 minutes
  ago." Could be a literal `$dir.at(timestamp)` accessor.
- **Audit trails.** "What was the user-permissions file on date
  X?" — answer is one query.
- **Jasmine debugging.** A log entry says "operation failed
  reading /foo/bar." Timestamped reads replay against the exact
  state the operation saw.

<a id="the-combination-is-more-than-the-sum"></a>
### 3.3 The combination is more than the sum

"Atomic deploys with instant rollback" is a real product
feature. So is "log entries that are reproducible because the
world they describe is still queryable." Filesystem-backed
systems spend enormous engineering effort getting crude
approximations of either; mikobase-as-filesystem inherits both.

<a id="posix-access-via-ssh-and-sshfs"></a>
## 4 POSIX access via SSH and SSHFS

A clean way to handle POSIX-tool compatibility: **expose the
mikobase as an SSH endpoint.** No kernel module to build, no
filesystem driver to maintain — we get most of the
compatibility-with-the-existing-world story by leaning on SSH.

- **Interactive use.** `ssh user@mikobase-host` lands the user in
  a shell where `cd`, `ls`, `cat`, `vim`, `tar`, etc. all work
  against a POSIX-presented view of the mikobase.
- **Local-tool integration.** `sshfs user@host:/ ~/mount` gives a
  local FUSE-backed mount; `git`, `rsync`, IDE file watchers, any
  POSIX-aware tool on the user's machine just sees a normal
  directory.
- **Mikobase superpowers stay accessible** via small syntax
  extensions: `cat foo.txt@2026-03-15`,
  `/.versions/2026-03-15/foo.txt`, or similar. POSIX users get
  POSIX; mikobase-aware users get the extras.

What this approach still doesn't handle perfectly:

- **POSIX file locks (`fcntl`).** Mikobase has its own transaction
  model; mapping advisory locks onto it is fiddly. Most apps don't
  use them.
- **`mmap`.** Memory-mapping a file backed by a structured store
  doesn't carry the same semantics. Tools that depend on `mmap`
  need a real-fs scratch.
- **Performance ceiling on syscall-heavy workloads.** A big build
  with thousands of small reads per second will run slower than on
  tmpfs/SSD. Irrelevant for content and admin work; matters for
  some development workflows.

For the vast majority of POSIX use, SSH + SSHFS is plenty.

<a id="in-memory-mode"></a>
## 5 In-memory mode

A mikobase doesn't have to be disk-backed. **An in-memory
mikobase that lives in the process's own memory** can present the
same filesystem interface as a persistent one, just with
process-bound lifetime: when the process exits or crashes, the
mikobase is gone with it.

This is interesting for a few specific cases where the working
set is small:

- **Test fixtures.** A test can build up an in-memory filesystem
  state, run code against it, and discard it at the end of the
  test. No filesystem mocking, no cleanup, no disk I/O.
- **Sandboxed file ops.** Code that needs file-system-shaped
  scratch but should never touch disk gets it.
- **Small ephemeral state** shared between in-process components
  that prefer a directory interface over passing buffers around.

The in-memory mikobase keeps the mikobase superpowers locally —
transactions and time-travel work within the session — so scratch
space can still have rollback semantics within a single request
or operation.

**Not for large-file workloads.** A common reason to want a temp
directory is to hold a huge file while you work on it (uploaded
videos, generated archives, multi-gigabyte intermediates). That's
exactly where in-memory storage falls down — RAM is precious and
not what you want to use for that. `%utils.tempdir` therefore
stays disk-backed, not mikobase-in-memory backed. The in-memory
option is for cases where the data is small enough that RAM is the
right place for it.

**Linux already has tmpfs**, the kernel-level in-RAM filesystem
(`/tmp`, `/run`, `/dev/shm` are typically tmpfs). The difference:
tmpfs is kernel-managed and persists across process crashes until
unmount/reboot. An in-memory mikobase is process-owned and dies
with the process. Different scope; better-targeted for the cases
above.

<a id="fso-and-the-path-forward"></a>
## 6 FSO and the path forward

By the time the broader **FSO (file system objects)** abstraction
is finished — directory objects, file objects, DirJails, the
interface that Sammy's `$server.static` consumes — a rudimentary
mikobase-backed filesystem implementation should be a small
additional step. Not committed yet; flagged as a likely outcome
of the work that's already happening for other reasons.

<a id="other-concerns"></a>
## 7 Other concerns

- **Performance overhead** of transactional storage compared to
  raw POSIX. Bulk file ingestion might want a fast path.
- **Storage growth.** Time-travel implies keeping history.
  Bounded by retention policy; needs to be configurable.

<a id="as-a-versioning-tool"></a>
## 8 As a versioning tool

Time-travel + a labeling layer makes mikobase-as-filesystem a
linear-history version control system. Auto-recorded changes,
named pointers (`alpha`, `beta`, `production`) to historical
states, no explicit commits, no branching. Effectively a
**simplified RCS** — RCS-era linear versioning with modern
auto-recording.

Where it shines: content management, configuration repos, data
sets, build artifacts, anything where branching is overkill and
"linear timeline + named pointers" is what the user actually
wants. Git stays the right tool for source code with parallel
feature branches.

One real concern: auto-recording every save means lots of
intermediate "still typing" noise in the history. Mitigations:

- **Compaction** that collapses runs of rapid edits.
- **"Quiet save" mode** that records the outcome, not every
  transient keystroke.
- **Retention policy** that drops fine-grained history past
  some age, keeping labeled states for the long term.

The killer combo: mikobase-as-filesystem + Sammy + Jasmine →
"every config change is recorded, every deploy is a tagged state,
every request log is reproducible against the exact filesystem
state that served it."

<a id="storage-shape-chunks-vs-deltas"></a>
## 9 Storage shape: chunks vs deltas

The current mikobase plan stores files in **chunks**. Great for
static collections (e.g., a Shakespeare-image archive — flagged
for the Unotate conversation) but disastrous for incrementally
edited files. A 10 MB file edited 100 times with small changes
each save becomes ~1 GB of storage; that's a non-starter for
versioning.

The fix is well-trodden territory: **delta-based revision
storage** with periodic full checkpoints.

- **Delta chains.** When a save is a small change from the
  previous revision, store the delta. Reconstructing a historical
  state walks the chain.
- **Periodic checkpoints.** Insert a full snapshot every N
  revisions (or every X% of cumulative delta size) so
  reconstruction stays bounded.
- **Format per content type.** Binary diff (xdelta, bsdiff) for
  general content; line-diff for text. Could be a per-extension
  factory hint.
- **Per-file storage mode.** A static asset (Shakespeare image)
  stays as full chunks because it never changes. A
  frequently-edited config file uses delta chains. The mikobase
  picks per-file based on observed change patterns. Hybrid wins
  — different from "everything is chunks" and "everything is
  deltas."

Prior art is rich (Git pack files, RCS itself, Mercurial revlogs,
Fossil, Subversion). Trade-offs to design:

- **Storage size vs read latency.** More aggressive delta
  chaining = smaller storage, slower historical reads. Default
  probably favors storage (cheap) over latency (mostly irrelevant
  for time-travel, which is rare).
- **Compaction / GC** for orphaned blobs from labels that moved on.
- **Delta-vs-full detection heuristics.** Try-diff-first,
  fall-back-to-full-store if the delta isn't meaningfully smaller.

The storage layer becomes **content-aware** rather than uniform.

<a id="open-questions-things-to-vibe-on"></a>
## 10 Open questions / things to vibe on

(To be filled in.)

---

<a id="out-of-scope-for-now"></a>
## 11 Out of scope for now

Brainstorm only. No commitments. The point is to capture the idea
and let it ripen.
