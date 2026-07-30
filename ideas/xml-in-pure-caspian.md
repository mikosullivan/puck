# XML in pure Caspian

~~~vibecode
{"vibecode": {
	"doc": "ideas_xml_in_pure_caspian",
	"role": "exploration of whether Caspian's XML parser could be written entirely in Caspian
		source rather than binding a Lua library (xml2lua today) or shelling to a C tool.
		Surveys motivations, the XML-subset question, parser architecture options
		(hand-rolled recursive descent, LPeg-driven, streaming vs DOM), tree representation
		as Caspian objects, error handling under 'report all errors at once', naming and
		strictness under the 'Only X is X' rule, and where the class would live in the
		Executable / Cache / Prerequisite tier system.",
	"status": "decision landed — the underlying XML backing is now luaexpat
		(a binding to Linux's already-installed libexpat SAX parser), spec'd
		in requirements/caspian/core/ and requirements/caspian/lua/binding/.
		The pure-Caspian option this doc walks was NOT chosen; the exploratory
		content is preserved as receipts for the trade-off.",
	"key_concepts": ["pure_caspian_stdlib", "bootstrap_independence", "lpeg_from_caspian",
		"xml_subset_scoping", "dom_vs_streaming", "strict_by_default"],
	"audience": "Miko; anyone weighing whether Caspian's XML story should live above the
		primitive line the way the JSON class does"
}}
~~~

**Decision landed:** Caspian's XML backing is **luaexpat** — a binding to Linux's already-installed `libexpat` SAX parser, spec'd in [core § Cache tier](https://puck.uno/requirements/core/) and reached from Caspian through [`%lua['lxp']`](https://puck.uno/requirements/lua/binding/). The pure-Caspian option this doc walks was NOT chosen; the exploration is preserved below as receipts for the trade-off (parse-speed, spec coverage, and trust-surface arguments) and as reference material for any future revisit.

Original opening (kept as context for the walk):

Caspian's XML story once leaned on a pure-Lua parser (xml2lua, ≈30 kb Cache tier). This doc asked the parallel-universe question: what would it take, and what would it cost, to write the XML parser **in Caspian itself**, above the primitive line where Password and Passkey already live?

Not a proposal. A design-space walk to see whether the option was worth revisiting when the parser class is actually written.

## Why do this at all

The stated principle is [concepts § Caspian is written in Caspian](https://puck.uno/requirements/concepts#caspian-is-written-in-caspian) — "anything that could be written in Caspian without giving up security, correctness, or usable performance should be." XML is exactly the shape that principle points at: a well-understood grammar, no cryptographic primitive to sink to C, no OS-service dependency. If Password can be Caspian, so can this.

Real reasons a pure-Caspian XML parser earns its keep:

- **Consistency with JSON's design endpoint.** The user-facing JSON class at `caspian.uno/json.casp` IS Caspian — [json § Where the parser lives](https://puck.uno/requirements/json#where-the-parser-lives-and-why-the-engine-layer-has-to-be-lua) makes clear the JSON class delegates to a Lua primitive only because CaspianJ (which the engine parses at startup) is itself JSON. XML has no equivalent bootstrap tie: nothing in the engine's own startup path parses XML. The Lua binding is a convenience, not a floor.
- **Auditable stdlib.** Same argument the concepts doc makes about Password. A user who wants to read, fork, or replace the parser reads Caspian, not Lua.
- **Extensibility in Caspian idioms.** Node classes carry `.buckets`, roles, `vibecode`, downloaded methods, and the rest of the Caspian object model. An xml2lua-backed wrapper produces plain Lua tables — the Caspian wrapper has to reconstitute node identity as Caspian objects anyway, so a chunk of the "Caspian side" already exists in the wrapper case.
- **Trust surface.** Every Lua library counts against the surface the runtime has to trust. Retiring one is one less dependency to pin, patch, or upgrade.

Reasons this is probably not V1:

- **xml2lua already works** and is already listed in the stdlib review as Ships-yes for V1. Rewriting a working library above the primitive line is engineering effort that competes with unbuilt features.
- **Performance floor.** Pure-Caspian character-by-character parsing has to move every byte through the Caspian value model. Rough sketch below suggests this is fine for config-file XML (kilobytes) and painful for feed-scale XML (tens of megabytes).
- **XML is not one thing.** The scope call (see below) is a real design commitment. xml2lua sidesteps that by inheriting Lua's ecosystem history.

The case for doing it is stronger post-V1, when the JSON class has landed as Caspian and the pattern for "primitive-parser as Caspian object" is established.

## Which XML

XML is a family. Any parser design has to name what it accepts and what it rejects. A first-cut allowlist / denylist for a strict-well-formed subset:

Accepted:

- Elements with attributes and mixed content
- Text nodes with the standard entity references (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`)
- Numeric character references (`&#nnn;`, `&#xNN;`)
- Comments (`<!-- ... -->`) — preserved as nodes, not stripped
- CDATA sections (`<![CDATA[ ... ]]>`)
- Processing instructions (`<?target data?>`) — preserved as nodes
- The XML declaration (`<?xml version="1.0" encoding="UTF-8"?>`) — parsed and exposed on the document
- Namespaces at the syntactic level (`xmlns:` attributes, `prefix:local` names) — the parser recognizes them; whether to resolve them into a `{uri}local` form on nodes is a separate call
- Whitespace preservation everywhere (XML's default) — `xml:space="preserve"` is honored but is not the difference between preserving and discarding

Deferred to a companion class or later phase:

- **DOCTYPE**. Parsing an internal subset is nontrivial. External DTD resolution is a security minefield (XXE, billion laughs) and an OS-integration concern. First cut: recognize `<!DOCTYPE ...>` at the top of the stream, skip its body without parsing, and let the parser continue.
- **DTD-validated entity resolution.** Only the five named entities and numeric character references. Custom named entities declared in a DTD are not resolved.
- **XSD schema validation.** Out of scope for the parser; would be a distinct class.
- **XPath / XSLT.** A tree-navigation surface (`.find`, `.each`) is worth having; a full XPath 1.0 engine is a separate project.
- **Alternate encodings.** UTF-8 in, UTF-8 out (matches Caspian's [strings-are-UTF-8](https://puck.uno/requirements/concepts#strings-are-utf-8) posture). The `encoding=` attribute on the XML declaration is read and reported; a non-UTF-8 declaration raises rather than silently transcoding.

The strict-well-formed subset above covers what Caspian programs actually reach for XML for — configuration, RSS/Atom feeds, SOAP responses, occasional API payloads. The deferred pieces are the ones where an in-house implementation gets expensive without buying much.

## Parser architecture options

Three viable shapes, one non-viable.

### Hand-rolled recursive descent

A single Caspian file that walks the input character by character, maintains a position cursor, and calls into itself for elements, attribute lists, text runs, comments, and CDATA. This is what xml2lua does under the hood — the design is well-trodden.

Pros:

- Everything is Caspian. No dependency on any pattern engine beyond String primitives.
- Line/column tracking is straightforward: increment on every character advance.
- Well-formedness errors surface at the exact character position that failed.

Cons:

- Every character touch is a Caspian method call. Even with `.length` and slicing kept off the hot path (indexing into a UTF-8 buffer via an integer cursor rather than repeated `.substring`), the constant factor is going to sting on large inputs.
- More code than a grammar-driven parser. ≈500-800 Caspian lines is a plausible ballpark for a strict-subset parser plus tree builder.

### LPeg-driven grammar

LPeg is bundled in the Executable tier per [core/](https://puck.uno/requirements/core/) — it is Caspian's PEG engine, backing the source parser, regex engine, and JSON parser. In principle, an XML grammar written against LPeg is much shorter than a hand-rolled parser and much faster (LPeg's captures compile down to C).

Open question: **is a Caspian-level LPeg surface a real thing?** [string/regular-expressions](https://puck.uno/requirements/built-in-classes/primitives/string/regular-expressions) commits to `.match` / `.match?` / `.replace` on strings as the pattern surface, but does not (yet) spec a way for user Caspian code to build an arbitrary LPeg grammar object — the surface documented is pattern-matching on strings, not grammar construction. If the LPeg surface is limited to "give me a pattern, I'll match it," an XML parser can't lean on LPeg the way the JSON parser does. If the surface eventually includes grammar-object construction (recursive productions, named nonterminals, captures composed into a tree), this option becomes the leading contender.

Worth flagging as a decision that unblocks this: either an LPeg-grammar surface on top of the pattern-matching methods, or a decision to keep LPeg engine-internal and force user parsers to go character-by-character.

### Streaming / SAX-style callback parser

The parser walks the input and calls user-supplied handlers on element-start / element-end / text / comment / CDATA / processing-instruction events, never building a tree of its own. The user assembles whatever data structure fits their use case.

Pros:

- Bounded memory. A gigabyte-of-RSS-feed use case is viable in a way a DOM parser makes impossible.
- Composable — the same underlying scanner backs a DOM builder (default handlers accumulate into `Xml.Element` nodes), an XPath streaming search, a diff tool, an XML-to-JSON transformer.

Cons:

- Ergonomics. Most Caspian XML programs want the tree. Making the tree the default and streaming the opt-in matches the shape of the calls callers write.

The pragmatic shape: a streaming scanner as the underlying primitive, a DOM builder as the default surface layered on top. `$xml.parse` returns a tree (calls the scanner with tree-building handlers). `$xml.scan(handlers)` exposes the streaming surface for callers who need it. Same code path, two surfaces.

### Regex-driven (not viable)

Pattern-match tags with a regex, recurse on the body. Falls apart on the first attribute containing `>`, on CDATA sections, on unbalanced-looking-but-actually-fine constructs inside CDATA, and on any comment-eaten `<`. Well-formed XML is not regular. Worth naming so nobody re-proposes it a year from now.

## Tree representation

Two shapes to weigh.

### Node classes

Distinct Caspian classes for each node kind:

~~~caspian
vibecode <<END
	Sketch of the node-class shape. `.new` takes named args matching the field
	names auto-declared with `get: true`. `class # element` is the inline label
	convention on class definitions.
END

$xml_element = class # element
	field @name,       class: :string, get: true, set: false
	field @attributes, class: :hash,   get: true, set: false
	field @children,   class: :array,  get: true, set: false
	field @namespace,  class: :string, get: true, set: false, default: null

	method init(@name, @attributes: {}, @children: [], @namespace: null)
	end

	method text()
		$out = ''

		@children.each() as $child
			if $child.obj.isa?($xml_text)
				$out = $out + $child.value
			end
		end

		return $out
	end
end
~~~

Pros:

- Type-tested trees. `$node.obj.isa?($xml_element)` is unambiguous.
- Methods hang naturally on each class. `.text` on Element, `.value` on Text, `.target` and `.data` on ProcessingInstruction.
- Roles and `%bucket` work per-node the way the rest of the language uses them.

Cons:

- More classes to name and maintain (`Element`, `Text`, `Comment`, `CData`, `ProcessingInstruction`, `Document`).
- Downstream serializers have to know all six classes.

### Plain hash tree

Every node is a hash with a `kind:` field:

~~~caspian
{
	kind: :element,
	name: 'book',
	attributes: {isbn: '0-19-853453-9'},
	children: [
		{kind: :text, value: 'Hamlet'},
		{kind: :element, name: 'author', attributes: {}, children: [
			{kind: :text, value: 'Shakespeare'}
		]}
	]
}
~~~

Pros:

- Nothing to learn. `$node['name']`, `$node['children'][0]['value']`. Serializes to JSON with no work.
- One code path in a walker: switch on `$node['kind']`.

Cons:

- No methods on nodes. `.text` is a free function or a wrapper.
- Loses roles / buckets as a per-node concern.

The node-class shape is more Caspian-idiomatic; the hash-tree shape is more portable to non-Caspian contexts. First cut probably picks node classes and offers a `.to_hash` method that produces the portable shape on demand. Callers who need JSON compatibility get it explicitly; nothing forces the class hierarchy on callers who don't want it.

### Access surface

Whatever the internal representation, the read surface probably includes:

- `$doc.root` — the document element
- `$element.children` — array of child nodes
- `$element.attributes` — hash of name → string
- `$element.attributes['xmlns:foo']` — namespaces live in the same attribute hash
- `$element.text` — concatenation of direct-child text nodes
- `$element.each() as $child` — Caspian's [array iteration](https://puck.uno/requirements/syntax/loops) surface
- `$element.find('book/title')` — a small path-selector surface, not full XPath. Whether the syntax is XPath-flavored or Caspian-native is open.

## Error handling

Two knobs: fail-fast vs collect-all, and how much recovery to attempt.

Caspian's user-level default is **report all errors at once** where a pass can find multiple. XML parsing is a case where that principle can apply cleanly: after a well-formedness violation, the parser can advance past the offending construct and continue scanning for further violations, aggregating them into a single exception rather than raising at the first sight of `<foo` unterminated.

Two-mode API:

- `$xml.parse $string` — strict-only, raises on the first well-formedness violation. Matches JSON's `.parse` shape. Fast, obvious, minimal ceremony.
- `$xml.parse $string, collect_errors: true` — parses best-effort, returns a document plus an errors array on the document. Every well-formedness issue is recorded with `line`, `column`, `kind`, and a short message. The tree returned is the parser's best guess at what the input meant.

Line/column tracking is a per-character-advance counter on the scanner. Byte offset is also kept (useful for locating errors in an editor buffer).

The collect-errors path is not lenient parsing — see the strictness section below. It is strict parsing that keeps going after each violation. A separate `Xml.Lenient` companion is where actually-tolerating-broken-XML would live.

## Naming and packaging

Per Miko's Only-X-is-X rule (see [stdlib review](https://puck.uno/ideas/caspian/stdlib-suggestions-review)): a class named `XML` implements XML strictly. If the class is at `caspian.uno/xml.casp`, then `$xml.parse` is XML-well-formed-strict. There is no `lenient: true` flag on the same class — leniency lives in a separately-named module.

Two natural packages, mirroring the JSON precedent:

- `caspian.uno/xml.casp` — strict-only parser. Raises on any well-formedness violation. `collect_errors:` opt-in is still strict, just non-fail-fast.
- `caspian.uno/xml/lenient.casp` (or `caspian.uno/xml_lenient.casp`) — a separate class that tolerates unquoted attribute values, unclosed elements at EOF, tag-soup HTML-ish input. Exists only if there's a caller who actually needs it. Currently nobody does.

Method surface parallel to JSON:

~~~caspian
vibecode <<END
	`.parse` returns the document. `.emit` serializes back to XML source.
	`.emit` with `pretty: true` reindents; without, it round-trips the input's
	whitespace as-received.
END

$xml = %('caspian.uno/xml.casp')

$doc = $xml.parse '<book isbn="0-19-853453-9"><title>Hamlet</title></book>'

$title = $doc.root.children[0].text
$pretty = $xml.emit $doc, pretty: true

return $title
~~~

## Performance, realistic take

No benchmark, order-of-magnitude only.

A hand-rolled recursive-descent parser in Caspian is going to move every character through Caspian's value model — string slicing, method dispatch, hash lookups on tables like the entity-reference map. Rough ballpark against xml2lua (pure Lua, no C):

- **Small inputs (kilobytes)** — configuration files, SOAP responses, RSS entries. Fine. The parse itself is a couple hundred milliseconds even at bad constant factors; well below the network / disk cost that produced the string in the first place.
- **Medium inputs (a few megabytes)** — a moderate feed, a large document. Noticeable but not blocking. Maybe several seconds; xml2lua would be much faster. Callers who care already reach for streaming.
- **Large inputs (tens of megabytes and up)** — dataset dumps, whole-catalog exports. Painful. This is where callers should reach for the streaming surface (which reduces the memory ceiling but not the per-character cost), or fall back to the xml2lua-backed wrapper as an explicit performance escape hatch, or shell to `xmlstarlet` for the pipeline they were probably building anyway.

An LPeg-driven parser sidesteps most of the per-character overhead (captures live in C), but depends on the LPeg-from-Caspian question above.

The honest read: pure Caspian works for the common case, and callers who hit the wall have documented escape hatches. That is probably fine as a positioning story, but it needs to be positioned — a class named XML that gets slower than xml2lua at 5 MB is a surprise unless the docs say so.

## Interaction with the tier system

Three tiers per [core/](https://puck.uno/requirements/core/): Executable (compiled into the caspian binary), Cache (downloaded on install, loaded lazily from disk), Prerequisite (OS-supplied CLI utility). A pure-Caspian XML parser could fit any of them.

- **Executable / Ships-yes.** Bundled with the caspian binary. Costs against the [floppy budget](https://puck.uno/requirements/core/) (currently 210 kb free). ≈15-25 kb of Caspian source is plausible. The argument for bundling is that XML is common enough that first-use latency shouldn't include a `%fetch` round trip. The argument against is that JSON is more common than XML, and even JSON's user-facing class is arguably not Executable — it's fetched via `%('caspian.uno/json.casp')`.
- **Cache tier (fetch-on-demand, Ships-no).** Downloaded to the local byte cache on first `%(URL)` reference. Matches the shape most of the [downloads/](https://puck.uno/requirements/downloads/) family takes. Best fit for a class that most programs won't touch.
- **Prerequisite.** Shell out to `xmlstarlet` or `xmllint`. Common on most systems but not universal; already the pattern for tar/gzip/openssl in the ecoverse. Not a **pure-Caspian** answer — this row is here for completeness.

**The split Miko committed to:** the non-Caspian parts of XML support (any native binding — luaexpat's `.so`, luaexpat's Lua helpers, or the equivalent for libxml2) ship in the **core install download** — the install-time Cache tier that a fresh Caspian install already pulls down. The Caspian-side wrapper (`caspian.uno/xml.casp`) does NOT need to be in the core download — it's fetched lazily from puck.uno on first `%(…)` reference and cached locally.

Rationale: a native `.so` has an install story (per-arch build, `libexpat.so.1` prerequisite, dpkg/rpm/brew coupling); it's not something a runtime `%fetch` fetch can drop into place at first-use time. Caspian source is a plain text file — trivially fetched, trivially cached. Put the awkward-to-install artifacts in the install download; let the language-native artifacts flow through the Puck-fetch path.

Executable-tier promotion for either half — pure-Caspian parser OR native binding — is only worth doing after real usage shows the fetch/cache latency biting often enough to matter. This lines up with [concepts § Lean on installed Linux utilities](https://puck.uno/requirements/concepts#lean-on-installed-linux-utilities-when-theyre-better) — the shape underneath the code (pure Caspian or CLI shell-out) is orthogonal to whether it eats floppy budget.

Access pattern:

~~~caspian
$xml = %('caspian.uno/xml.casp')
$doc = $xml.parse $source
~~~

Same shape as JSON. No `%xml` global.

## System-provided SAX processor

Even with pure Caspian as the goal, an escape hatch that leans on the system's already-installed XML parser is worth naming. Most Linux systems ship libxml2 and expat as C libraries; both expose SAX-style event streams.

### What's actually there

**libxml2** is on essentially every mainstream distro (glibc-based or musl). GNOME depends on it; `xmllint` comes from it. Provides SAX and DOM APIs at the C level.

**expat** is the other common one — smaller, streaming-only, ships nearly as widely.

macOS ships libxml2 in the base system. Windows doesn't ship either but distributes them through most package managers.

"SAX" here means a programming API — `start_element`, `end_element`, `text`, `cdata`, `comment`, `pi` callbacks — not a CLI tool. There's no `sax-parse` shell command; reaching the SAX interface requires a binding.

### How Caspian would call it

Three shapes:

- **Lua binding, Cache tier.** `luaexpat` exists and is stable; libxml2 bindings for Lua also exist. Cache on first `%(…)` reference. Caspian talks to Lua, Lua talks to C. Same packaging shape as any other Cache-tier Lua binding. Cheapest path.
- **Small C shim, Executable/Identity tier.** Purpose-built wrapper compiled into the caspian binary, exposing only the SAX events Caspian wants. Tighter surface, no Lua-binding drift, some kb against the [floppy budget](https://puck.uno/requirements/core/). Only worth it if XML is common enough that the kb are earned.
- **Shell out to `xmllint`.** Not really SAX. `xmllint --stream` walks the document but returns `xmllint`-formatted output on stdout — not a Caspian-side event stream. Fine for validate / pretty-print / `--xpath`; not for an event-driven parser.

The Lua-binding option is the pragmatic first cut, but it is **not** a floppy-budget win over the current `xml2lua` plan. Sizing measured from the Debian `lua-expat` 1.5.1-3 package (single Lua-version target, stripped release build).

### Floppy-budget receipts

| Component                      | xml2lua                | luaexpat                              |
| ---                            | ---                    | ---                                   |
| Parser / binding               | 30 kb (whole module)   | ≈40 kb (`lxp.so`, one arch)           |
| DOM helper (LOM)               | —                      | ≈3 kb (`lxp/lom.lua`)                 |
| SAX-to-table helper            | —                      | ≈3 kb (`lxp/totable.lua`)             |
| Billion-laughs protection      | —                      | ≈17 kb (`lxp/threat.lua`, recommended)|
| **Minimum viable**             | **30 kb**              | **≈40 kb**                            |
| **With Lua-side helpers**      | 30 kb                  | ≈63 kb                                |
| Delta vs xml2lua               | —                      | +10 kb to +33 kb                      |

### Non-kb costs

| Dimension            | xml2lua                        | luaexpat                                                                             |
| ---                  | ---                            | ---                                                                                  |
| Arch coverage        | One arch-neutral file          | `.so` per arch — linux-x86_64, linux-arm64, macos-x86_64, macos-arm64 (≥4 builds)    |
| Host prerequisite    | None                           | `libexpat.so.1` (≈130 kb, universal on Linux, in macOS base, common on Windows)      |
| Trust review target  | Lua source, few hundred lines  | C shim + upstream C library                                                          |
| Parse speed          | Pure Lua (baseline)            | C-native, ≈100× faster                                                               |
| Spec coverage        | Well-formed subset             | Full namespaces, entities, encoding auto-detect                                      |

### Verdict

Luaexpat costs 10-33 kb more per Cache-tier install than xml2lua, plus per-arch distribution and a wider trust surface. What it buys is a ≈100× parse-speed improvement and correct spec coverage for the parts xml2lua doesn't handle. The trade is worth taking only after usage data shows xml2lua's slowness or spec gaps biting real programs.

`libexpat.so.1` itself — the underlying C parser — is already on essentially every host. What Caspian ships is only the `.so` binding shim, not the parser.

### Caspian-side SAX surface

An event-callback shape with `do` blocks matches Caspian idiom:

~~~caspian
vibecode <<EOF
{"role": "SAX walk emitting one line per element enter and exit"}
EOF
$xml = %('caspian.uno/xml.casp')

$xml.sax $source do
	on_element do ($name, $attrs)
		%stdout.puts 'enter: ' + $name
	end

	on_element_end do ($name)
		%stdout.puts 'exit: ' + $name
	end

	on_text do ($text)
		# ...
	end
end
~~~

Or a streaming iterator that yields events for an `each` loop. Both fit; the callback shape is closer to how libxml2 and expat actually work.

### Tradeoffs vs the pure-Caspian shape

- **Performance.** libxml2 parses ≈several MB/s; a Caspian-implemented parser will be one to two orders of magnitude slower. Decisive for anything larger than kb-sized docs.
- **Bootstrap dependency.** Pulls in a C library the runtime otherwise doesn't need. Contradicts the "Caspian is written in Caspian" principle. Escape hatch, not primary story.
- **Feature coverage.** Namespaces, entities, DTD validation, encoding auto-detection are handled correctly by libxml2; replicating them in Caspian is real design work.
- **Portability.** Windows and some minimal container images don't have libxml2 by default. A Cache-tier Lua binding to expat is more portable than assuming libxml2.
- **Trust surface.** A C library is a larger review target than a few hundred lines of Caspian. Matters when the XML input is untrusted.

### Relationship to the pure-Caspian parser

Not either/or. The doc's main thread stays pure Caspian for the common case. A system-SAX handle at `%('caspian.uno/xml.sax.casp')` (or similar name) is the "you have a 500 MB SOAP envelope, hand it off" escape hatch. Both can coexist; the naming should make clear which is which.

## Open questions

Decisions this doc doesn't try to make:

- **LPeg-from-Caspian surface.** Is there or will there be a Caspian-level way to construct an LPeg grammar object (nonterminals, captures, recursion) rather than only matching a compiled pattern? The XML-parser architecture pivots on the answer.
- **Namespace resolution model.** Two options: leave `xmlns:` handling to the caller (attributes are just attributes), or resolve prefixes into a `{uri}local` form on element and attribute names. The first is simpler; the second is what most XML-aware code actually wants.
- **XPath surface.** Not-XPath (`.find('book/title')` with a small subset — child, descendant, index, attribute predicate) is probably enough. A full XPath 1.0 engine is a distinct project. Where between "nothing" and "everything" does the surface land?
- **Comment / PI preservation as default.** Some libraries strip comments and processing instructions on parse; some preserve them. Preserve-by-default matches Caspian's "developer decides" posture; strip-by-default matches most consumer expectations.
- **Round-trip fidelity.** Does `$xml.emit $xml.parse $source` produce byte-identical output for well-formed input? JSON commits to key-order preservation; XML has more knobs (attribute order per element, whitespace between attributes, self-closing vs empty-body tags). The commitment should be spelled out.
- **Retirement path for xml2lua.** If pure Caspian lands post-V1, is the Lua binding removed (retiring the Cache-tier entry), kept as an escape hatch (`%lua['xml2lua']` still works), or explicitly rehomed to a "large-document XML" companion?
- **Whether this is worth doing at all before V1 ships.** The stdlib review has `caspian.uno/xml.casp` as Ships-yes for V1 via xml2lua binding. The pure-Caspian version is a post-V1 conversation unless something forces it earlier.
- **System-SAX naming.** If the system-provided SAX handle is added alongside the pure-Caspian parser, does it live at `caspian.uno/xml.sax.casp`, `caspian.uno/xml-fast.casp`, or does the main `xml.casp` class expose a `.sax_native` method that opts in per call? The name shouldn't imply the pure-Caspian version is broken.
- **Lua binding vs C shim for system-SAX.** `luaexpat` (Cache-tier Lua binding) is the pragmatic starting point; a purpose-built C shim (Executable/Identity) is tighter but pays the floppy budget. Decide when there's usage data to justify.

## Related

- [json](https://puck.uno/requirements/json) — the parallel case that IS committed. Bootstrap constraint forces Lua-side; user-facing class is Caspian. Sets the pattern this doc mirrors.
- [core/](https://puck.uno/requirements/core/) — tier definitions and the floppy budget any Executable-tier proposal has to fit inside.
- [lua/binding/](https://puck.uno/requirements/lua/binding/) — the committed reach-path via `%lua['lxp']` (luaexpat, binding to Linux's installed `libexpat`).
- [concepts § Caspian is written in Caspian](https://puck.uno/requirements/concepts#caspian-is-written-in-caspian) — the design principle this doc is applying to XML.
- [stdlib-suggestions-review](https://puck.uno/ideas/caspian/stdlib-suggestions-review) — the V1 stdlib scoping table where `caspian.uno/xml.casp` currently lives as Ships-yes.
- [downloads/](https://puck.uno/requirements/downloads/) — the shape most V1 first-party downloads take; models the Cache-tier packaging option.
