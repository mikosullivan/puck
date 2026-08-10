# Big string

~~~vibecode
{"vibecode": {
	"doc": "ideas_big_string",
	"role": "brainstorm doc for a Caspian primitive (or download, or pattern) for working with very large strings — bigger than fits comfortably in one contiguous buffer, or where the naïve String type would make common operations quadratic. Starts with a prior-art survey; Miko will drive the rest.",
	"status": "idea — just prior-art notes so far. NOT V1 scope — spitball only. No implementation plan, no promotion path to requirements/ implied."
}}
~~~

**Not V1.** This is exploratory. Nothing here is committed for V1; nothing here has a promotion path to `requirements/` implied. Freely add / walk back / disagree.

## The concept

A `bigstring` is an object that **references a file on disk** and behaves like a `String` from the outside. The actual bytes live in the file, not in memory. The bigstring object is a small in-memory handle — a file path plus whatever metadata is needed to expose the String surface (`.length`, `.chars`, `.substring`, iteration, `.contains?`, etc.) without loading the whole file.

Where a normal `String` IS its bytes, a bigstring POINTS AT its bytes. This lets you treat gigabyte-scale text as if it were an ordinary value: pass it as an argument, slice it, iterate it, compare it — without ever holding all of it in memory at once.

## How it works

**Working assumption (deferred concern):** the source file does not change while a bigstring references it. Detection, locking, and behavior-on-mutation are out of scope for this pass — assume nothing writes to the file between construction and last read. Revisit later.

The source file holds the bytes and nothing moves them. Every derived operation (split, regex match, character-index lookup, whatever) writes a **sidecar metadata file** to a temp dir. Metadata is BYTE POSITIONS, not content, so it's cheap even when the source is gigabytes.

To read a chunk, the runtime seeks into the source file at the metadata's recorded byte positions. Content never gets copied.

**Representative operations and their metadata:**

| Operation | Metadata shape | On-access behavior |
|---|---|---|
| `.length` | Single character count | Scan the file once; cache count |
| `.split(delim)` | Array of `[start_byte, end_byte]` pairs, one per chunk | Result is an array of bigstrings, each pointing at a byte range of the source |
| `.match(re)` / `.matches(re)` | Array of `{match: [start, end], groups: [[start, end], ...]}` | Match objects are bigstrings pointing at ranges of the source |
| `.substring(char_a, char_b)` | Sparse byte-offset-per-N-characters index for the source | Random access into UTF-8 without full-scan; built lazily on first char-indexed access |
| `.contains?(needle)` | True/false + optional first-match position | Full-scan on first call; cached |
| `.chars` iteration | (none — sequential scan) | Reads byte-by-byte, decodes UTF-8 chars |

**Derived views are also bigstrings.** A chunk from a split is another bigstring, pointing at a byte range of the same source file, with its own (usually empty) metadata sidecar. Slicing a chunk further creates yet another bigstring; the chain composes without materializing content.

**Metadata dir:**

- Lives in some temp-dir scope — probably `%chain.tmp` or a bigstring-specific temp under that.
- Per-bigstring subdirectory holds all the sidecars for one source file's operations.
- Lifetime tied to the bigstring handle: when the handle is GC'd, the metadata dir is removed. Multiple handles on the same file can share or have their own dirs (open question).

### The temp dir holds large objects too

The metadata isn't always small. Split a 5 GB log file on newlines and the resulting list of byte-range pairs can itself be tens of MB or more. Building a full regex-match table across the whole file can produce a similar order of magnitude. If we tried to hold those in memory, we'd blow the same budget bigstring exists to defend.

**Same philosophy applies at the metadata layer:** derived data lives on disk in the temp dir; only handles live in memory. The temp dir isn't a scratchpad for small caches — it's a proper storage tier for potentially-large derived structures.

**Example: split metadata format.** Fixed-width records let the metadata file act like an array with random access:

~~~
Each record: 8 bytes start + 8 bytes end = 16 bytes.
Chunk N of a split lives at metadata-file byte offset N*16.
Read 16 bytes from the metadata file; seek into the source at those positions; read the chunk.
~~~

- **Getting element N** — one 16-byte read from metadata, one seek-and-read into source. No full-list load.
- **Iterating all elements** — sequential scan of metadata paired with sequential (or random) reads of source. Stream-shaped, not load-shaped.
- **`.length` of the split** — the metadata file's byte size divided by 16. Constant time; no scan.

Similar shape for other operations:

- **Regex match table** — fixed-width per match if we cap the number of capture groups, or variable-width with an offset index (the same "index of indexes" pattern used inside compressed archives).
- **Character index for UTF-8** — sparse table: `[char_pos, byte_pos]` every N characters. Bounded size regardless of source length; binary-search into it to find the byte offset for a given character index.

**The metadata files are almost bigstrings themselves** — on-disk, handle-only, accessed by seeking into fixed offsets. The composition is natural: build the array primitive once, use it under both the source-string and its derived-metadata layers. Worth thinking about when the shape settles: the same "value that lives on disk" mechanism serves strings, arrays of ranges, sparse indexes, whatever. One primitive, many uses (per [concepts § Primitive reuse](https://puck.uno/requirements/concepts#primitive-reuse)).

### Nested bigstrings

Every derived subset is a bigstring, all the way down. The pattern:

~~~caspian
$doc     = %('core:bigstring')('big.txt')     # 5 GB
$lines   = $doc.split("\n")                   # array of bigstrings, one per line
$line42  = $lines[42]                         # a bigstring for one line
$words   = $line42.split(' ')                 # array of bigstrings, one per word
$word    = $words[0]                          # a small bigstring
$stem    = $word.substring(0, 4)              # even smaller
~~~

`$stem` is still a bigstring pointing into `big.txt`, at a byte range 4 characters long inside line 42's range inside the whole file. Every subset composes cleanly with any operation the base type supports.

**All derived bigstrings reference the ROOT source directly** — not a chain of parents. Every bigstring stores `{source_file, start_byte, end_byte}` referring straight to the root. No walking a parent chain to find the source; one indirection at any depth.

Why direct-to-root: chains of parents would mean either (a) every operation walks up the chain to find the actual bytes, or (b) intermediate bigstrings keep their parents alive even when nobody's using them. Direct-to-root avoids both problems. The parent bigstring's role is just to compute the child's byte range at creation time; after that, the child is independent.

**Bigstring storage in SQLite** (assuming that decision):

~~~
CREATE TABLE bigstrings (
    id          INTEGER PRIMARY KEY,
    source_file TEXT NOT NULL,   -- absolute path to the root file
    start_byte  INTEGER NOT NULL,
    end_byte    INTEGER NOT NULL,
    parent_id   INTEGER           -- optional; for cleanup-cascade tracking, not lookup
);
~~~

Every bigstring has an ID. Operations that produce derived bigstrings (`.split`, `.substring`, regex matches) insert new rows. Getting the actual bytes for bigstring N is one row read + one seek + one file read.

**Metadata scoping.** Sidecar tables (splits, regex matches, char indexes) live in the same SQLite DB, with each row keyed by `bs_id`:

~~~
CREATE TABLE splits (
    bs_id       INTEGER NOT NULL,   -- which bigstring this split belongs to
    chunk_index INTEGER NOT NULL,
    start_byte  INTEGER NOT NULL,   -- byte offsets into the ROOT source file
    end_byte    INTEGER NOT NULL,
    PRIMARY KEY (bs_id, chunk_index)
);
~~~

Multiple bigstrings can each have their own split metadata; the `bs_id` keeps them separate. One SQLite DB per **root source file** — all descendants share it.

**Metadata inheritance for free (sometimes).** The char index built for `$doc` (sparse `[char_pos, byte_pos]` pairs across the whole file) is still useful for any descendant — a binary search into it works for any byte range that falls within the source. `$line42.substring(char_a, char_b)` doesn't need its own char index; the root's covers it. Only operations that produce NEW metadata (a new split, a new regex scan) create their own rows.

**Cleanup.** When a bigstring is GC'd, delete its rows in `bigstrings` and cascade-delete its sidecar rows. When the last bigstring for a source is gone, the whole DB and temp dir are removed. `parent_id` is stored for cascade-tracking, not lookup — a parent's GC also cleans up its children (which are usually already gone).

### Storage: SQLite instead of custom binary?

Alternative to the fixed-width binary format above: keep all metadata in a **single SQLite database per bigstring** — one `.sqlite` file with tables for each derived structure. This is a real option worth naming.

**In favor of SQLite:**

- **Already bundled.** lsqlite3 ships in Caspian's Cache tier; zero floppy-budget cost.
- **Structure is free.** Byte ranges are rows; regex matches are rows; character indexes are rows. No custom record formats to design.
- **Queries and indexes.** "Chunk containing byte position N" is a range query with an index — one line of SQL vs a binary-search implementation.
- **ACID.** Interrupted metadata writes don't corrupt the sidecar; SQLite recovers on next open.
- **Introspection.** `sqlite3 bigstring.meta.sqlite` opens it in the CLI; every developer already has the tooling.
- **One file per bigstring** instead of a directory of loose binary files.

**Trade-offs:**

- **Per-row overhead.** ≈20 bytes of SQLite housekeeping per row. A million-chunk split's metadata is ≈2x the size of the raw ranges. Bounded and probably fine.
- **Access latency.** SQLite `SELECT` is more machinery than "seek to N*16, read 16 bytes." O(log n) via B-tree vs O(1) direct seek. Interactive access — fine. Tight iteration loops — might matter, needs benchmarking if a hot path shows up.

**Lean: SQLite for everything.** The overhead buys queries, ACID, tooling, and structure-out-of-the-box. Bigstring's target scale (hundreds of MB to a few GB for the source) isn't tight enough to make custom binary a clear win, and "custom binary format for a list of records" is essentially reinventing what SQLite already provides. Only reason to reach for fixed-width would be a specific benchmarked hot-path problem — which can be solved later by materializing a fixed-width cache from the SQLite table if it ever surfaces.

### Backing modes: file-backed vs DB-backed

Two ways to store the content, both supported. The API surface is identical either way; only where the bytes live differs.

**File-backed.** The source is a plain text file; the SQLite DB holds only metadata (splits, regex matches, indexes, edit log). Two files per bigstring.

- **Zero ingest cost** — an existing file becomes a bigstring immediately; no "load into DB" step.
- **Raw text stays readable by any tool** — `less`, `grep`, `cat` on the source all work.
- **Direct-mmap available** — for hot random-access workloads, the OS's mmap on a plain file is a native win.
- **Requires two-way consistency** — file must not be modified externally (per the working assumption); sidecar cleanup has to track the source's lifecycle.
- **Best for:** read-heavy workloads on existing files, one-shot analysis of large logs / dumps, cases where the source is authoritative elsewhere.

**DB-backed.** The source is chunked into a `content` table in the same SQLite DB that holds the metadata. One file per bigstring; the file IS the bigstring.

- **Single source of truth** — content and metadata in one file; portable, snapshotable, backup-friendly as a unit.
- **ACID for the whole thing** — the journaled-edits pattern (source + edit log staying consistent) falls out of SQLite transactions with no consistency dance.
- **Compression fits naturally** — chunks stored as BLOBs can be zstd/lz4-compressed at insert; transparent to the API.
- **Ingest is a one-time cost** — building a DB-backed bigstring from a source file streams the content in once; every subsequent op is DB-backed.
- **`.export_to_file()`** materializes the current view back to a plain file whenever you need "any tool can read it" back.
- **Best for:** bigstrings that will be edited, transported, snapshotted, or need consistency guarantees; cases where the DB IS the primary store.

**Construction shape:**

~~~caspian
$doc1 = %('core:bigstring').from_file('big.txt')   # file-backed
$doc2 = %('core:bigstring').from_file_ingest('big.txt')   # DB-backed, ingest at creation
$doc3 = %('core:bigstring').from_db('cached.bigstring.sqlite')   # DB-backed, already-built
~~~

(Method names sketched; exact API TBD.) The runtime knows which mode a bigstring is in from its handle; operations dispatch through the same interface. Nested bigstrings inherit their parent's mode by default — a chunk of a file-backed doc is file-backed; a chunk of a DB-backed doc is DB-backed. Explicit conversion (`.promote_to_db()`, `.export_to_file()`) is available when the developer wants to switch modes.

## What the design implies

Some things fall out naturally:

- **Same method surface as `String`.** If bigstring is to work as a drop-in for a big-enough String, calling `.length` / `.substring` / `.chars` / `+` / `==` / etc. has to work identically. Duck-typed, or Bigstring inherits from a shared abstract-String interface.
- **Reads pull from the file on demand.** Iterating a bigstring reads chunks as it goes; random access seeks. Never a full load unless the caller explicitly asks for one (via some `.to_string` / `.materialize` escape hatch).
- **The file's lifetime matters.** The bigstring is only usable while the file exists at the referenced path — if the file is deleted, moved, or truncated, subsequent reads fail. Failure mode needs to be spec'd (raise? return null? tombstone the handle?).
- **Bytes vs characters is unavoidable.** File offsets are byte-based; character indices are user-facing. UTF-8's variable-width encoding means `.substring(1000, 2000)` (character indices) requires a byte-offset scan or an index. Small strings pay this cost easily; bigstrings might need a lazy index.

## Design questions worth naming

These aren't answered yet — just flagging what will need to be decided if this graduates from spitball.

1. **Immutable, mutable, or copy-on-write?** If the file changes on disk (external editor, another process writing), does the bigstring reflect that? Or does bigstring snapshot the file at construction?
2. **Substrings.** `.substring(a, b)` — new small in-memory string? Another bigstring pointing at a subrange of the same file? A rope-like structure combining the two?
3. **Concatenation.** `bigstring + short_string`, or `bigstring + bigstring` — where does the result live? Materialize? Rope? Third temp file?
4. **Comparison.** `==` between a bigstring and a small string — read the file to check? Bail out quickly on length mismatch?
5. **Snapshot / revive.** How does a bigstring survive a MVM snapshot? The referenced file exists in the host filesystem, not the runtime's own memory. Snapshot the file path? Snapshot the whole file? Fail on serialization?
6. **Encoding.** UTF-8 is Caspian's default. Does bigstring assume UTF-8, or does it take an encoding parameter? What about a file that turns out to be malformed UTF-8?
7. **Non-text files.** Is bigstring text-only, or is there a `bigbytes` companion for binary data?
8. **Construction.** How do you get one? `%('core:bigstring')(path)`? `Bigstring.new(file)`? A method on a dir-jail file handle: `$file.as_bigstring`?
9. **Relationship to faucets and sinks.** Caspian already has streaming I/O primitives ([plumbing](https://puck.uno/requirements/plumbing/)). A bigstring is closer to a value than a stream, but the underlying mechanism overlaps. Same runtime layer, different surface?

## Prior art

Several distinct approaches have shown up across languages, each optimized for a different pain point. Grouping by data-structure family since the naming across ecosystems is inconsistent.

### Rope

The classic tree-of-strings structure. A rope is a balanced binary tree whose leaves are short string chunks; internal nodes carry length metadata for their subtrees. Concatenation is O(log n) (creates a new internal node), split is O(log n), and index-by-position walks the tree. Trade: random-character access is O(log n) instead of O(1), but sequential and range access is fast and edits don't move data.

- **Boehm cord** — C library shipped with the Boehm-Demers-Weiser garbage collector. Cords can hold literal char arrays, other cords, or function references (lazy/procedural chunks). Widely referenced as the reference implementation.
- **SGI STL `rope<>`** — C++ template in the SGI extensions to the STL. Not standard C++ but ported to many compilers as `__gnu_cxx::crope`.
- **ropey** (Rust) — actively maintained; used by the Helix text editor.
- **crop** (Rust) — competing rope crate, similar shape.
- **jumprope** (Rust, JavaScript) — Seph Gentle's rope focused on collaborative editing.
- **Fleck** and various academic papers — rope + splay-tree hybrids for cache-friendliness.

### Piece table

Different structure, same problem. Instead of chopping the string into balanced chunks, a piece table keeps the ORIGINAL immutable string plus a growing "add buffer" of inserted text, and records the document as a sequence of `{buffer, offset, length}` pieces. Edits append to the add buffer and rewrite the piece list; no chunk ever moves. Concatenation and insertion are O(1) if you're at a piece boundary, O(log n) otherwise (with a balanced piece-index tree).

- **Microsoft Word (original)** — the design that made piece tables famous.
- **VS Code / Monaco editor** — uses a piece-tree variant. Chose it over ropes after benchmarking their editor's actual edit patterns.
- **atom.io** (defunct) — used a similar structure.
- **Neovim** — line-based buffer with a chunk allocator; not a strict piece table but adjacent lineage.

### Journaled edits over an immutable base

The pattern Miko describes for a "sort of mutable" bigstring: the source stays put, every edit (insert / delete / move / replace) is recorded as an operation with byte positions in a log, and the "current" content is the fold of the log over the base. This has a long lineage in text tools.

- **Piece table / piece tree** — see the § above. The canonical implementation of this pattern: immutable original + add buffer + piece list (which is the operation log). Every edit appends to the add buffer and rewrites the piece list; original never changes. MS Word (original), VS Code / Monaco, atom.io.
- **Emacs `buffer-undo-list`** — every buffer change appends an entry recording position, deleted text, and inserted text. The list can be replayed in reverse to undo. Not quite "immutable base + log" (the buffer itself is mutable), but the log structure is exactly this shape and is the standard reference for "record edits as data."
- **Operational Transformation (OT)** — the collaborative-editing engine used by Google Docs, older Etherpad, ShareJS. Edits are operations `insert(pos, text)`, `delete(pos, len)`, etc. Concurrent operations from different users are transformed so they compose correctly. Wire-level format is the exact base+ops shape.
- **CRDTs for text** — Yjs, Automerge, Diamond Types, Peritext, Y-CRDT. Each character has a globally-unique identifier; edits are add/remove operations on IDs. The document literally IS the set of operations replayed in causal order. Modern successor to OT for distributed editing.
- **CodeMirror 6 transactions** — every edit is a `Transaction` object with a list of changes at specific positions. The document is the fold of transactions over the initial state. Explicitly log-based by design.
- **Xi editor (defunct but influential)** — used a rope for the current content plus an OT-flavored engine to record and merge edits. The design write-ups are widely referenced.
- **Datomic** — not text, but the same shape at the database level: every "fact" is an immutable timestamped datom; the current DB is the aggregate of all datoms. You can query "as of any point in time" by cutting off the log at a timestamp.
- **Git's blob + diff model** — files are stored as immutable blobs; changes tracked as diffs between revisions. Different scope (revision control not real-time editing) but the same immutable-base-plus-recorded-changes philosophy.
- **CRIU-style incremental snapshots** — process state saved as base snapshot + deltas since. Same pattern applied to memory rather than text.

**What's different in bigstring's case.** The pattern is well-established but usually applied where the base is IN memory and edits are frequent (interactive editors, collaborative sessions). Bigstring flips both: the base is ON DISK and edits are less frequent than reads. That changes some trade-offs — the edit log can afford to be structured (a SQLite table with an index) rather than optimized for micro-latency; a full "materialize" step is more expensive so is done more selectively. But the operation-log shape is the same.

### Builder / accumulator

Not really "huge strings" — just avoiding the O(n²) trap when building a string via repeated concatenation. The builder is a mutable container that appends efficiently; you extract the final string once at the end.

- **Java `StringBuilder` / `StringBuffer`** — canonical name. Buffer is thread-safe; Builder isn't.
- **C# `StringBuilder`** — same shape.
- **Go `strings.Builder`** — modern equivalent, minimal API.
- **Python `io.StringIO`** — file-like interface; write chunks, `.getvalue()` to materialize.
- **Ruby `StringIO`** — same idea.
- **Node.js — array + `.join('')`** — the idiomatic way in JS is to push chunks into an array and `.join('')` at the end. No dedicated Builder class in the standard library.
- **Rust `String::push_str` on a growing `String`** — the `String` type IS the builder; extract by consuming.

### Iolist / iodata

Erlang and Elixir's answer: build a nested list (a tree, in effect) of binary chunks and character-integer values. Never flatten during construction — I/O routines that accept iodata walk the tree and emit chunks straight to the socket / file. If you never actually need the concatenated string as one object, you never pay for concatenation.

- **Erlang iolist** — deeply nested list of binaries, chars, and integer bytes. Used pervasively for building HTTP responses, database queries, etc.
- **Elixir iodata** — same as Erlang, one call away.
- **Haskell `Data.ByteString.Builder`** — similar spirit, functional style. Compose builders with `<>`, run to a bytestring at the end.
- **F# `TextWriter` composition** — less structured but same intent.

### Substring views / slices with shared storage

Not for building big strings but for referring to pieces of them without copying. If you have a 500 MB string and want a 3 MB substring, a slice-view lets you reference it without allocating 3 MB more.

- **Rust `&str`** — a fat pointer (pointer + length) into a `String`; no copy. Zero-cost substrings.
- **Python `memoryview`** — analogous for `bytes` / `bytearray` (works for text via encode/decode).
- **Java `String.subSequence`** — used to share the backing array (was reverted in Java 7 because of the "hold onto a huge string via a small substring" leak). Modern Java copies.
- **Go `string[a:b]`** — slice syntax on strings creates a view into the same backing array. Same leak potential as old Java; Go accepts it.
- **Haskell `Data.Text` / `Data.ByteString`** — slice types share storage explicitly; `copy` is opt-in.
- **C++17 `std::string_view`** — non-owning window into a string. Standard-library companion to `string`.

### Memory-mapped

For strings that don't fit comfortably in resident memory. The OS handles paging; the string LOOKS contiguous but only the pages you touch actually load.

- **Python `mmap`** — module in stdlib; treat a file as a mutable byte array.
- **Rust `memmap2` crate** — mmap wrapper.
- **Java `MappedByteBuffer`** — nio-based memory-mapped access.
- **C `mmap(2)`** — the underlying POSIX syscall everyone else wraps.

Trade: mmap gives you address-space access but doesn't help if you want to CONSTRUCT the huge string in memory. It's for READING (and sometimes editing in place) large existing content.

### Streaming / iterator-oriented

Treat the string as a stream, not a value. You never hold the whole thing; you process chunks as they arrive.

- **Java `Reader` / `Writer`** — character streams; `BufferedReader.lines()` for line-at-a-time.
- **Python iterators over file objects** — `for line in open(path):` is idiomatic.
- **Node.js Streams** — `Readable`/`Writable` streams with backpressure.
- **Go `bufio.Scanner`** — line/token scanning without full buffering.
- **Elixir `Stream` module** — lazy enumerables including strings.
- **Rust `Read` trait** — buffered reader adapters.

Adjacent design in Caspian's neighborhood: [faucets and sinks](https://puck.uno/requirements/plumbing/) already provide streaming I/O primitives; a "big string" primitive could plug into that rather than exist as a standalone type.

### Compression-oriented

Rare but real: keep the big string compressed in memory, decompress on access. Trade CPU for RAM.

- **Fastutil / Trove (Java)** — some collections offer compressed variants.
- **zstd/lz4 wrapper libraries in most languages** — DIY: keep a compressed buffer, decompress a window when needed.
- **Snappy / Brotli / gzip** — same DIY posture.

Usually applied to specific structures (huge JSON blobs, log spool) rather than as a general "big string" type. Worth mentioning because the trade-off exists.

### Interning

Not "huge string" but adjacent: if you have many strings that are equal, deduplicate them so only one copy exists in memory.

- **Java `String.intern()` / `String` literal pool** — automatic for compile-time literals; explicit for runtime strings.
- **Python `sys.intern()`** — explicit; automatic for identifier-shaped strings.
- **Ruby symbols** — related but distinct concept.
- **Rust `Arc<str>` patterns + custom interners** — no built-in, but common enough to have crates (`string-interner`, `lasso`).

Useful when your working set has few distinct string values but many uses of them.

### Lua ecosystem specifically

Caspian's reference engine (Lucy) is Lua, so what already exists in the Lua ecosystem matters for implementation. The space is smaller than JavaScript/Rust/Python — most Lua work here is streaming-or-basic-buffers rather than dedicated big-string abstractions — but the useful pieces exist.

**Ropes:**

- **[lua-datastructures](https://github.com/CurtisFenner/lua-datastructures)** (CurtisFenner) — immutable ropes with O(log n) gets and concatenations. Modeled after Lua's string immutability.
- **[Splay Ropes](https://lua-users.org/wiki/SplayRopes)** — lua-users wiki page. Binary tree with functional splay-tree balancing. Notes "particularly useful for large text strings where there are random changes at localised points, making them ideal for implementing a text editor."
- **[thyer/Ropes](https://github.com/thyer/Ropes)** — third-party rope implementation on GitHub.

**String buffers (avoid the O(n²) concat trap):**

- **[LuaJIT `string.buffer`](https://luajit.org/ext_buffer.html)** — built-in string-buffer library. Mutable sequences of string-like data; high-performance manipulation without triggering Lua's immutable-string copy semantics.
- **[lua_bufflib](https://luarocks.org/modules/choonster/lua_bufflib)** (choonster) — on LuaRocks. String-buffer library with methods that mirror Lua's `string` library.
- **`table.concat`** — the idiomatic Lua pattern: push chunks into a table, `table.concat(t, '')` at the end. Stdlib-only, no dependency.

**Streaming chunks of large files (no full load):**

- **[stringstream-lua](https://github.com/gilzoide/stringstream-lua)** (gilzoide) — object that loads chunks on demand. Compatible with a subset of the Lua string API sufficient for parsing. Pattern-matches on loaded content with lazy loading; maximum extra-bytes-loaded is configurable. This is the closest existing Lua library to bigstring's "acts like a string" surface.
- **[stream](https://github.com/erdian718/stream)** (erdian718) — generic Lua streaming library.
- **[lua-resty-upload](https://github.com/openresty/lua-resty-upload)** (openresty) — streaming HTTP upload reader; small constant memory for gigabyte-scale uploads.

**Memory-mapped files:**

- **[lua-mmapfile](https://luarocks.org/modules/geoffleyland/mmapfile)** (geoffleyland) — simple mmap interface for binary data, on LuaRocks.
- **[luapower/mmap](https://github.com/luapower/mmap)** — portable mmap API, marked deprecated in favor of the luapower `fs` module.
- **[luaposix](https://github.com/luaposix/luaposix)** — POSIX bindings including mmap; supports Lua 5.1–5.4 and LuaJIT.

**Notable gaps in the Lua ecosystem** (as of this search):

- **No dedicated piece-table library.** The closest analogs come out of C/C++ (which Lua can FFI into) but there's no idiomatic Lua piece-table gem.
- **No CRDT text library.** OT / CRDT text data structures don't have Lua implementations comparable to Yjs / Automerge / Diamond Types in JS/Rust land.
- **No dedicated file-backed "value" abstraction** in the shape bigstring would use. `stringstream-lua` is the closest — chunked-lazy access with a partial string API — but it's read-oriented and doesn't support the derived-view / metadata-sidecar composition sketched above.

**Practical implication for Lucy:** the pieces exist for a bigstring prototype — mmap for source-file access, LuaJIT string.buffer for materialize-a-chunk operations, lsqlite3 (already bundled) for metadata storage — but the composition into a bigstring surface with derived-view semantics is Caspian's own work; there's no drop-in library to lean on.
