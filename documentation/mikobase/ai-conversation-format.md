# Mikobase + AI Conversation Format

vibecode: {"doc":"mikobase-ai-reference","audience":"human+ai","sections":["mikobase","q0",
"worldlet_json_format","ai_conversation_format"]}

This document covers two related topics: the Mikobase object store and its query language
(Q0), and the standard class library for AI-to-AI collaboration sessions built on top of it.

Each concept is documented as a compact JSON "vibecode" block — a dual-audience format that
both humans and AI systems can read directly. The JSON blocks are the formal specification;
the prose around them is context and explanation.

---

## Mikobase

A **mikobase** is a live object store — not a passive file. It requires a maintaining process
and supports typed class definitions, append-only record history, locking, and transactions.
The central rule: a mikobase owns its objects. Processes connect to it and interact with it
directly; they do not pass objects between each other.

vibecode: {"concept":"mikobase","type":"live_object_store","requires":"maintaining_process",
"not":"passive_file","supports":["Q0","class_definitions","record_history","locking",
"transactions"],"key_rules":["mikobase owns its objects",
"processes connect and interact; no direct object passing between processes"]}

### Backends

There are several mikobase implementations, all sharing the same Q0 interface.
`kiera.uno/mikobase` is the abstract base. The HTTP wrapper exposes any mikobase over a
network. The server variant coordinates KScript++ forks.

vibecode: {"concept":"mikobase_classes","entries":[
{"class":"kiera.uno/mikobase","role":"abstract base; full Q0; locking; transactions"},
{"class":"kiera.uno/mikobase/memory","backend":"SQLite :memory:"},
{"class":"kiera.uno/mikobase/sqlite","backend":"SQLite file"},
{"class":"kiera.uno/mikobase/http","role":"HTTP transport wrapper; exposes mikobase over network"},
{"class":"kiera.uno/mikobase/server","role":"managed server for KScript++ fork coordination"}]}

### Connection Modes

Connections are either **cold** (default) or **hot**. Cold connections return local copies;
changes are saved explicitly. Hot connections return live objects — every read and write is a
round trip, and locking is automatic. The mode can be overridden per query.

vibecode: {"concept":"connection_modes","modes":[
{"mode":"cold","default":true,
"behavior":"returns local copies; changes saved explicitly via .save()"},
{"mode":"hot","default":false,
"behavior":"returns live objects; every read/write is round trip; no explicit save; locking automatic"}],
"per_query_override":"q0({...}, hot:true) or q0({...}, hot:false) overrides connection default"}

### POSTable Updates (HTTP)

An HTTP mikobase accepts inbound worldlet payloads via `POST /worldlet`. This allows external
agents — including other AI systems — to deposit history entries without a persistent
connection. The payload is a standard worldlet JSON object; a history-only worldlet with no
classes or records is valid. The operation is all-or-nothing: every entry in the payload must
pass validation, or the entire POST is rejected.

vibecode: {"concept":"postable_updates","class":"kiera.uno/mikobase/http","endpoint":"POST /worldlet",
"payload":"standard worldlet JSON object; history-only worldlet is valid; no new wire format",
"engine_behavior":["validate worldlet shape and UUID v4 constraints",
"per entry: skip if identical already exists; reject if same UUID exists with different content",
"all entries pass → append and recompute; any entry fails → reject entire payload; no partial writes"],
"response":{"accepted":"array of accepted history UUIDs","skipped":"array of skipped UUIDs",
"rejected":"array of rejected UUIDs"},
"authorization":"coarse-grained in v1: caller can POST or cannot; fine-grained permissions deferred",
"use_cases":["worldlet deltas as AI-to-AI exchange format","offline agents: work from snapshot, submit later",
"write-only participants: auditors, sensors, importers","submission inboxes: proposals, bug reports, votes",
"webhook integration: outside systems deposit state changes","AI-to-AI mail: message is a mikobase update",
"audit-native APIs: every integration call is already a history entry"],
"deferred":["signatures","replay protection","timestamp authority","distributed merge","fine-grained permissions"]}

### Authentication

HTTP mikobase connections require an `auth` parameter — there is no insecure default.
`:peer` uses kernel-level credential verification on Unix sockets. `:token` uses a shared
secret. `:open` disables authentication and should only be used in controlled environments.

vibecode: {"concept":"http_mikobase_auth","auth_param":"required; no default","options":[
{"auth":":peer","mechanism":"SO_PEERCRED; kernel verifies UID/GID/PID; Unix sockets only"},
{"auth":":token","mechanism":"shared secret in connection handshake; Unix or TCP"},
{"auth":":open","mechanism":"no authentication; use only in controlled environments"}]}

### Locking

Mikobase uses shared-exclusive locking. Multiple readers can hold shared locks simultaneously.
Writers hold exclusive locks and block all reads. Lock acquisition is automatic — there is no
explicit lock/unlock API.

vibecode: {"concept":"locking","model":"shared-exclusive",
"rules":["reads use shared locks; multiple readers simultaneously",
"writes use exclusive locks; one writer; no reads during write transaction",
"acquisition automatic; no explicit lock/unlock API"]}

### Transactions

Transactions support nesting. A block that exits without committing is automatically rolled
back. `exit()` rolls back immediately and exits the block.

vibecode: {"concept":"transactions","api":["transaction()","commit()","rollback()","exit()"],
"rules":["nesting supported","block exit without commit auto-rolls back",
"exit() rolls back and exits block immediately"]}

### Bucket Integration

When a mikobase is opened with `include_private=true`, it backs the `%bucket` for any fork
that connects to it — so `@foo` reads and writes go directly to the live object in the
mikobase.

vibecode: {"concept":"bucket_in_mikobase","trigger":"include_private=true on mikobase",
"effect":"%bucket backed by mikobase for any fork that connects; @foo reads/writes go to live object",
"note":"%bucket synced to its own mikobase; not explicitly passed mikobases"}

### Change Signals

Processes can subscribe to changes on any record, query result, or class. The `before_save`
signal fires inside the transaction — raising an error rolls back the entire operation.
`after_save` fires after commit and cannot be cancelled.

vibecode: {"concept":"record_change_signals","api":"mikobase.listen(target, signal) do($change) end",
"targets":["specific record","Q0 query object","class name string"],
"signals":[
{"signal":"before_save","timing":"within transaction before commit",
"effect":"raising error rolls back entire transaction","use":"consistency rules"},
{"signal":"after_save","timing":"after commit","effect":"cannot be cancelled",
"use":"side effects; notifications; background work"}],
"change_object":{"record":"the changed record","class":"its class",
"fields":"hash of changed fields: {field:{old:,new:}}"},
"network_note":"before_save not forwarded over network to remote clients by default"}

### Worldlets (Packaged Mikobases)

A **worldlet** is a mikobase packaged as a portable file — class definitions, KScript methods
and hooks, records, and a capabilities manifest bundled together. Recipients review the
capabilities, then import the worldlet into their own environment. Class names use the
publisher's domain, so there are no naming collisions between publishers.

vibecode: {"concept":"packaged_mikobase","marketing_name":"worldlet",
"contains":["class definitions","KScript methods and hooks","records","capabilities manifest"],
"lifecycle":["author packages","share via file/URL/registry","recipient imports",
"capabilities reviewed and approved","classes+records+KScript installed",
"runs inside recipient environment"],
"uns_note":"class names use publisher domain; no collision possible"}

---

## Q0

**Q0** ("query zero") is the universal query interface for all mikobase engines. Queries are
JSON objects sent to `engine.q0()`. Every mikobase engine supports Q0. Class names in queries
are UNS strings — a URL without the `https://` prefix (e.g. `kiera.uno/record`,
`foo.com/character`).

vibecode: {"concept":"Q0","name":"query zero","format":"JSON objects sent to engine.q0()",
"all_engines_support":true,"uns_rule":"class names are UNS strings: URL without https:// prefix",
"uns_examples":["kiera.uno/record","kiera.uno/reference","foo.com/character"]}

### Actions

vibecode: {"concept":"q0_actions","values":["select","create","update","delete","transaction",
"commit","rollback"]}

### Select

A select with no filters returns all active records. `class` is inheritance-aware — subclasses
are always included. `null` values always sort last regardless of sort direction.

vibecode: {"concept":"q0_select","action":"select","filters":[
{"field":"pk","type":"string","effect":"select single record by primary key"},
{"field":"class","type":"string|array","alias":"classes",
"note":"inheritance-aware; subclasses always included; both present: union-merged + warning"},
{"field":"limit","type":"int","effect":"max records returned"},
{"field":"offset","type":"int","effect":"skip first N records"},
{"field":"count","type":"response_field","note":"records actually returned after limit/offset"},
{"field":"sort","type":"path_array","note":"single sort path; applied before sorts"},
{"field":"sorts","type":"array_of_path_arrays","note":"multiple sort paths; appended after sort"}],
"sort_qualifiers":[
{"qualifier":"reverse","default":false,"effect":"descending if true"},
{"qualifier":"case-sensitive","default":true,"effect":"case-insensitive sort if false"},
{"qualifier":"collapse","default":false,"effect":"normalize whitespace before sort"}],
"null_sort":"null values always sort last regardless of reverse",
"unfiltered_select":"returns all active records"}

### Narrowing

Results can be filtered with `then` (AND), `all` (AND over array), and `any` (OR over array).
These operators are combinable and nestable.

vibecode: {"concept":"q0_narrowing","operators":[
{"op":"then","semantics":"AND; nestable; add not:true to negate; only matching records survive"},
{"op":"all","semantics":"AND; array of sub-queries; record must match every sub-query"},
{"op":"any","semantics":"OR; array of sub-queries; record must match at least one"}],
"combinable":true,"nestable":true}

### Path Operators

A path is an array of keys to traverse into a bucket, with the final element being a literal
value (exact equality) or a typed operator.

vibecode: {"concept":"q0_path",
"format":"array; all but last are hash keys to traverse into bucket; last is literal or operator",
"literal":"exact equality match",
"operators":[
{"type":"string","ops":[
{"value":"...","case-sensitive":false},{"contains":"..."},
{"starts-with":"..."},{"ends-with":"..."}]},
{"type":"number","ops":[{"gt":"n"},{"lt":"n"},{"gte":"n"},{"lte":"n"}]},
{"type":"array","ops":[
{"includes":"..."},{"includes_all":"[...]"},{"includes_any":"[...]"}]},
{"type":"existence","ops":[
{"exists":true},{"exists":false},{"truthy":true},{"any":true}]}]}

### Placeholders

Placeholders are named variables defined in a query and referenced elsewhere in the same query.
They are resolved dynamically — a placeholder is only an error if it is actually reached and
undefined. They are local to the query and cannot be reused across queries.

vibecode: {"concept":"q0_placeholders","syntax":{"placeholder":"name"},
"define_at":"top level of query or inside then block",
"reference":"anywhere in query including nested then blocks",
"scoping":"outer placeholders inherited by nested then; inner can shadow; cannot remove inherited",
"resolution":"dynamic at moment encountered; not upfront",
"rules":["circular ref is error only if reached","undefined placeholder is error only if reached",
"unreached placeholder causes no error","local to query; not reusable across queries",
"may resolve to any JSON value"]}

### Create

vibecode: {"concept":"q0_create","action":"create","required":["bucket"],"optional":["class"],
"class_default":"kiera.uno/record if omitted or null","pk":"engine-generated",
"response":"success:true + new pk in results"}

### Update

vibecode: {"concept":"q0_update","action":"update","required":["pk"],
"bucket":"required unless class-only change","class":"optional; unchanged if omitted",
"error":"updating deleted record is error"}

### Delete

Deletion creates a tombstone — it sets `active=false` rather than removing the record.
Deleted records are excluded from normal selects. `if_exists: true` makes delete idempotent.

vibecode: {"concept":"q0_delete","action":"delete","required":["pk"],
"mechanism":"tombstone; sets active=false",
"if_exists":"true makes delete idempotent; returns success:true, deleted:false for already-deleted",
"tombstone_clears":["bucket","class_pk","custom_classes"],
"select_behavior":"deleted records excluded from normal select; historical reads at cutoff may return them"}

### Responses

vibecode: {"concept":"q0_responses",
"success":{"success":true,"results":"..."},
"warning":{"success":true,"results":"...","warnings":[{"id":"...","details":{}}]},
"failure":{"success":false,"errors":[{"id":"...","details":{}}]}}

### Error IDs

vibecode: {"concept":"q0_error_ids","errors":[
{"id":"invalid_request","meaning":"malformed: missing fields, wrong types, unknown fields"},
{"id":"class-not-found","meaning":"class path does not resolve to known class"},
{"id":"record_not_found","meaning":"target pk does not exist"},
{"id":"record_deleted","meaning":"target record exists but already deleted"},
{"id":"invalid-mode","meaning":"syntactically invalid connection mode string"},
{"id":"mode-not-supported","meaning":"valid mode string not supported by this engine"},
{"id":"read-only-connection","meaning":"write action attempted on read-only connection"},
{"id":"action-not-supported","meaning":"action not implemented by this engine"},
{"id":"request-too-large","meaning":"request exceeds engine size limit"},
{"id":"transaction-not-found","meaning":"unknown transaction id"},
{"id":"transaction-invalidated","meaning":"transaction id invalidated by ancestor rollback"}]}

### Passthrough Fields

The `misc` and `enterprise` fields are always ignored by core storage engines. Custom engines
in the chain may use them for extension metadata.

vibecode: {"concept":"q0_passthrough_fields","fields":["misc","enterprise"],
"behavior":"always ignored by core storage engines; custom engines in chain may use for extension metadata"}

---

## Worldlet JSON Format

A **worldlet** is a complete mikobase serialized as a single JSON object — classes, records,
history, and files in one portable document. Primary keys are preserved exactly on import, so
all references remain valid. The only required key is `history`; all other keys are optional
and default to empty structures when absent.

vibecode: {"concept":"worldlet","aka":"packaged_mikobase","format":"single JSON object",
"purpose":"complete portable mikobase: classes, records, history, files",
"import_behavior":"PKs preserved exactly; references remain valid after import",
"minimum_valid":"history key only; all other keys optional; absent keys default to empty structures"}

### Top-Level Structure

| Key | Required | Description |
|-----|----------|-------------|
| `format` | no | Fixed string `"worldlet"`. Unknown value → refuse import. |
| `format_version` | no | Semver string. Unknown value → warn and attempt import. |
| `meta` | no | Descriptive metadata (name, author, version, description, created_at). |
| `properties` | no | Database-level properties; read before interacting with data. |
| `allow` | no | External resources requiring host approval before import. |
| `extensions` | no | Reserved for future use. Engines must ignore silently. |
| `classes` | no | Schema; keyed by UNS class name. |
| `records` | no | Record identity stubs; keyed by UUID. Inferred from history if absent. |
| `history` | **yes** | All record versions; keyed by history UUID. |
| `files` | no | File metadata; keyed by file UUID. |
| `file_chunks` | no | File binary content; keyed by chunk UUID. |

vibecode: {"concept":"worldlet_top_level_structure","keys":[
{"key":"format","required":false,"type":"string","value":"worldlet","note":"fixed string; identifies document type; unknown value → refuse import"},
{"key":"format_version","required":false,"type":"string","value":"1.0","note":"semver; unknown value → warn and attempt import; absent → attempt without warning"},
{"key":"meta","required":false,"type":"object","note":"descriptive metadata about the worldlet"},
{"key":"properties","required":false,"type":"object","note":"database-level properties; read before interacting with data"},
{"key":"allow","required":false,"type":"array","note":"external resources requiring host approval before import"},
{"key":"extensions","required":false,"type":"object","note":"reserved for future security/registry metadata; engines must ignore silently"},
{"key":"classes","required":false,"type":"object","note":"schema; keyed by UNS class name"},
{"key":"records","required":false,"type":"object","note":"record identity objects; keyed by UUID; optional — inferred from history if absent"},
{"key":"history","required":true,"type":"object","note":"all record versions; keyed by history UUID"},
{"key":"files","required":false,"type":"object","note":"file metadata; keyed by file UUID"},
{"key":"file_chunks","required":false,"type":"object","note":"file binary content; keyed by chunk UUID"}]}

### meta

Descriptive metadata about the worldlet. All fields are optional.

vibecode: {"concept":"worldlet_meta","required":false,
"fields":[
{"field":"name","required":false,"type":"string","note":"human-readable name"},
{"field":"author","required":false,"type":"string","note":"UNS domain of publisher"},
{"field":"version","required":false,"type":"string","note":"semver string"},
{"field":"description","required":false,"type":"string","note":"free-text description of contents"},
{"field":"created_at","required":false,"type":"string","note":"ISO 8601 timestamp of export"}]}

### properties

Database-level properties that apply to the mikobase as a whole. Read before interacting with
data.

`no_execute` is an advisory flag indicating that code stored in this mikobase is data to be
read, not instructions to run. The engine does not enforce this — the importing client or agent
is responsible for respecting it.

vibecode: {"concept":"worldlet_properties","required":false,
"fields":[
{"field":"no_execute","type":"boolean","default":false,
"note":"advisory: code in this mikobase is data only; must not be executed by clients or agents",
"enforcement":"advisory only; engine does not prevent execution; client/agent responsible for respecting it"}]}

### allow

An array of external resource identifiers (e.g. hostnames) that this worldlet requires access
to. The host presents these to the user for approval before import. Nothing is granted
silently.

vibecode: {"concept":"worldlet_allow","required":false,"type":"array of strings",
"note":"external resources the worldlet requires; host presents to user for approval before import; nothing granted silently",
"example":["api.starfleet.com"]}

### classes

An object keyed by UNS class name. The class name is always taken from the dictionary key —
any `name` field inside the definition is ignored. Methods are fields with `class: function`
and a `kscript` key. Import does not delete classes absent from the schema.

vibecode: {"concept":"worldlet_classes","required":false,
"format":"object keyed by UNS class name; value is class definition",
"name_rule":"name is always taken from dict key; any name field inside definition is ignored and overwritten",
"methods":"defined as fields with class:function and a kscript key containing KScript source",
"import_rules":["importing absent class creates new record",
"importing existing class appends new history row",
"import does not delete classes absent from schema",
"all inherits references must exist in DB or same schema; entire import fails if any missing",
"classes within schema need not be ordered; engine inserts parent-first"]}

### records

An object keyed by record UUID, with empty objects `{}` as values. The content of a record
lives entirely in `history` — this section establishes identity only. If `records` is absent,
the importer infers record identities from the `record` fields in history entries.

vibecode: {"concept":"worldlet_records","required":false,
"format":"object keyed by record UUID; value is empty object {}",
"note":"content lives in history, not here; record key establishes identity only",
"inference":"if absent, importer infers record identities from record fields in history"}

### history

The core of the worldlet. Every entry is one version of one record. The entry with the latest
`created_at` for a given record UUID is its current state. An entry with `active: false` is a
tombstone — the record is considered deleted. No two entries for the same record may share the
same `created_at`.

vibecode: {"concept":"worldlet_history","required":true,
"format":"object keyed by history UUID; each value is one version of one record",
"fields":[
{"field":"record","type":"string","note":"UUID of the record this version belongs to"},
{"field":"class","type":"string","note":"UNS class name at time of this write"},
{"field":"created_at","type":"string","note":"ISO 8601 timestamp with millisecond precision"},
{"field":"active","type":"boolean","default":true,
"note":"false = tombstone; tombstone clears bucket and class; record is considered deleted"},
{"field":"bucket","type":"object","note":"field values at this version; omitted on tombstone"}],
"current_state":"entry with latest created_at for a given record UUID is the current state",
"deleted_state":"latest entry with active=false means record is deleted",
"timestamp_rule":"two entries for the same record cannot share the same created_at"}

### files

vibecode: {"concept":"worldlet_files","required":false,
"format":"object keyed by file UUID",
"fields":[
{"field":"sha256","type":"string","note":"SHA-256 hash of complete file content; used for deduplication and integrity"},
{"field":"created_at","type":"string","note":"ISO 8601 timestamp"},
{"field":"mime","type":"object","fields":[
{"field":"type","note":"MIME type e.g. image/png"},
{"field":"encoding","note":"encoding used for chunk data e.g. base64"}]}]}

### file_chunks

Files are stored in chunks. Chunks are assembled in index order. An empty file is represented
as a single chunk with `data: ""` and `last: true`.

vibecode: {"concept":"worldlet_file_chunks","required":false,
"format":"object keyed by chunk UUID",
"fields":[
{"field":"file","type":"string","note":"UUID of parent file record"},
{"field":"index","type":"integer","note":"zero-based chunk position; chunks assembled in index order"},
{"field":"last","type":"boolean","note":"true on final chunk; file with no last=true chunk is incomplete"},
{"field":"data","type":"string","note":"chunk content encoded per file mime.encoding"}],
"empty_file":"single chunk row with data='' and last=true"}

---

## AI Conversation Format

The `kiera.com/ai/` namespace defines a standard class library for AI-to-AI collaboration
over a shared live mikobase. Using these classes is optional — the mikobase accepts anything
— but a common vocabulary makes session output readable by any AI or human without prior
coordination.

**Execution policy:** Code stored in a session mikobase must not be executed by AI agents. The
mikobase is a communication and audit medium; any code present in records is data to be read
and interpreted, not instructions to run.

**`@from` field:** On all records, `@from` is a foreign key to a `kiera.com/ai/agent` primary
key. It is not a UNS address directly.

**`@session` field:** Every class except `agent` and `session` itself carries `@session`. This
allows a single Q0 query to fetch all records for a session without graph traversal.

**Report delivery:** `kiera.com` forwards `kiera.com/ai/report` to the human when the session
ends. The full session mikobase remains available for audit.

vibecode: {"concept":"ai_conversation_format_execution_policy",
"rule":"code stored in the mikobase must not be executed by AI agents",
"rationale":"the mikobase is a communication and audit medium; code present in records is data to be read and interpreted, not instructions to run"}

vibecode: {"concept":"ai_conversation_format","namespace":"kiera.com/ai/",
"purpose":"standard class library for AI-to-AI collaboration via shared live mikobase",
"usage":"optional convention; mikobase accepts anything; common vocabulary makes output readable without prior coordination",
"from_field_rule":"@from on all records is foreign key to kiera.com/ai/agent primary key; not UNS directly",
"session_field_rule":"all classes except kiera.com/ai/agent and kiera.com/ai/session carry @session; enables single Q0 query to fetch all records for a session without graph traversal",
"report_delivery":"kiera.com forwards kiera.com/ai/report to human when session ends; full session mikobase available for audit"}

### Class Summary

| Class | Role |
|-------|------|
| `kiera.com/ai/agent` | Agent identity; registered once at session start |
| `kiera.com/ai/session` | Top-level session container |
| `kiera.com/ai/proposal` | Something put forward for consideration |
| `kiera.com/ai/objection` | Reasoned disagreement with a proposal or refinement |
| `kiera.com/ai/refinement` | Updated version of a proposal in response to an objection |
| `kiera.com/ai/question` | Clarifying question about anything in the session |
| `kiera.com/ai/response` | Reply to a question |
| `kiera.com/ai/evidence` | Supporting material grounding a proposal in external fact |
| `kiera.com/ai/acceptance` | Explicit acceptance of a proposal or refinement |
| `kiera.com/ai/impasse` | Declaration that agreement cannot be reached; escalates to human |
| `kiera.com/ai/position` | An agent's final stated position after impasse is declared |
| `kiera.com/ai/decision` | A conclusion both agents agreed on |
| `kiera.com/ai/report` | Final output forwarded to the human |
| `kiera.com/ai/human_instruction` | An instruction posted by the human into the session |
| `kiera.com/ai/human_decision` | A decision made by the human, typically to resolve an impasse |
| `kiera.com/ai/sign_off` | Signals that an agent is done sending and disconnecting |

### Agent

Each participating AI registers itself once at session start by creating an agent record. All
other records reference this record via `@from`. If an agent drops and reconnects without
knowing its original primary key, it registers a new agent record — duplicate registrations
from reconnects are acceptable.

vibecode: {"class":"kiera.com/ai/agent","role":"agent identity record; registered once at session start",
"fields":[
{"field":"@name","note":"human-readable name for this agent"},
{"field":"@uns","note":"UNS address of agent if it has one"},
{"field":"@owner","note":"UNS or identifier of human or org this agent belongs to"},
{"field":"@model","note":"model name/version if applicable"},
{"field":"@registered_at"}],
"registration_rules":["one registration per agent per session",
"if agent drops and reconnects without knowing original pk, register a new agent record",
"duplicate registrations from reconnects are acceptable"]}

### Session

The top-level container for a collaboration. Typically created by the Kiera server when
spinning up the mikobase instance. Status moves from `:open` toward `:resolved`, `:impasse`,
or `:withdrawn`.

vibecode: {"class":"kiera.com/ai/session","role":"top-level container for collaboration",
"created_by":"Kiera server when spinning up mikobase instance for two agents",
"fields":[
{"field":"@agenda","note":"what the session is here to resolve"},
{"field":"@participants","note":"array of agent record primary keys"},
{"field":"@human","note":"UNS or identifier of human owner"},
{"field":"@status","values":[":open",":resolved",":impasse",":withdrawn"]},
{"field":"@created_at"}]}

### Proposal

Something being put forward for consideration. A proposal has a subject, a body, and a
rationale. Its status tracks whether it is still open, has been accepted, rejected, or
superseded by a refinement.

vibecode: {"class":"kiera.com/ai/proposal","role":"something put forward for consideration",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@subject","note":"short title"},
{"field":"@body","note":"proposal content"},
{"field":"@rationale","note":"why this is being proposed"},
{"field":"@status","values":[":open",":accepted",":rejected",":superseded"]}]}

### Objection

A reasoned disagreement with a proposal or refinement. Severity indicates how the objecting
agent intends its objection: `:blocking` means it cannot accept the proposal as-is; `:concern`
means it has reservations but will not block; `:minor` is a note for the human rather than a
negotiating point.

vibecode: {"class":"kiera.com/ai/objection","role":"reasoned disagreement with proposal or refinement",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@to","note":"reference to proposal or refinement"},
{"field":"@body","note":"the objection"},
{"field":"@severity","values":[":blocking",":concern",":minor"]},
{"field":"@status","values":[":open",":addressed",":withdrawn"]}],
"severity_semantics":{
":blocking":"objecting agent cannot accept proposal as-is",
":concern":"has reservations but will not block",
":minor":"note for human; not a negotiating point"}}

### Refinement

An updated version of a proposal, typically in response to an objection. `@of` always points
to the original root proposal. `@previous` points to whatever this directly supersedes —
useful for walking the full chain of revisions.

vibecode: {"class":"kiera.com/ai/refinement",
"role":"updated version of proposal, typically in response to objection",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@of","note":"reference to original proposal; always points to the root proposal"},
{"field":"@previous","note":"reference to immediately preceding proposal or refinement; walk chain via this field"},
{"field":"@body","note":"full revised proposal"},
{"field":"@changes","note":"summary of what changed and why"}]}

### Question

A clarifying question about anything in the session — a proposal, an objection, a prior
decision, or anything else.

vibecode: {"class":"kiera.com/ai/question","role":"clarifying question about anything in session",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@about","note":"reference to thing being questioned"},
{"field":"@body"}]}

### Response

A reply to a question.

vibecode: {"class":"kiera.com/ai/response","role":"reply to a question",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@to","note":"reference to question"},
{"field":"@body"}]}

### Evidence

Supporting material attached to any record in the session — a citation, measurement, example,
or counterexample that grounds a proposal or objection in external fact. `@confidence` is the
posting agent's own assessment of the evidence's reliability.

vibecode: {"class":"kiera.com/ai/evidence",
"role":"supporting material grounding a proposal or objection in external fact",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@about","note":"reference to record this evidence supports"},
{"field":"@kind","values":[":fact",":example",":counterexample",":citation",":measurement"]},
{"field":"@source","note":"URL or description of source"},
{"field":"@body","note":"the evidence content"},
{"field":"@confidence","note":"0.0–1.0; agent's confidence in this evidence"}]}

### Acceptance

An explicit record of one agent accepting a proposal or refinement. Creates a clear audit
trail of who accepted what and under what conditions, separate from a `@status` field change.

vibecode: {"class":"kiera.com/ai/acceptance",
"role":"explicit record of one agent accepting a proposal or refinement; creates audit trail",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@of","note":"reference to proposal or refinement being accepted"},
{"field":"@body","note":"optional remarks"},
{"field":"@conditions","note":"any conditions attached to the acceptance"}]}

### Impasse

A declaration by one agent that agreement cannot be reached and the session must be escalated
to the human. Either agent may post this. Once posted, further negotiation stops and both
agents move to posting a `position` record summarizing where they stand.

vibecode: {"class":"kiera.com/ai/impasse",
"role":"declaration by one agent that agreement cannot be reached; triggers escalation to human",
"effect":"further negotiation stops; both agents post a kiera.com/ai/position record; session status → :impasse",
"fields":[
{"field":"@from","note":"primary key of agent declaring impasse"},
{"field":"@session","note":"reference to session record"},
{"field":"@body","note":"explanation of why agreement cannot be reached"},
{"field":"@sticking_point","note":"the specific issue that cannot be reconciled"}]}

### Position

An agent's final stated position, posted after an impasse is declared. Each agent posts one.
These are not arguments — they are clean summaries of where each agent stands so the human
can make an informed decision.

vibecode: {"class":"kiera.com/ai/position",
"role":"agent final stated position after impasse declared; one per agent; not an argument",
"fields":[
{"field":"@from","note":"primary key of agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@body","note":"the agent's final position"},
{"field":"@supports","note":"reference to last proposal or refinement this agent endorses; optional"}]}

### Decision

A conclusion both agents have agreed on. A session may contain multiple decisions. `@risks`
records any caveats or identified risks the agents want to flag for the human.

vibecode: {"class":"kiera.com/ai/decision",
"role":"conclusion both agents agreed on; session may have multiple",
"fields":[
{"field":"@session","note":"reference to session record"},
{"field":"@body","note":"agreed-upon text"},
{"field":"@based_on","note":"reference to proposal or refinement that was accepted"},
{"field":"@agreed_by","note":"array of agent record primary keys"},
{"field":"@confidence","note":"0.0–1.0; agents' collective confidence in this decision"},
{"field":"@risks","note":"array of identified risks or caveats"}]}

### Report

The final output forwarded to the human. Assembled by the agents when the session concludes.
When a session ends in impasse, `@decisions` will be empty or partial, and `@impasse` and
`@positions` will be populated instead. The `@summary` and `@next_steps` fields must make
clear that the human needs to decide.

vibecode: {"class":"kiera.com/ai/report",
"role":"final output forwarded to human; assembled when session concludes",
"fields":[
{"field":"@summary","note":"executive summary; what human needs to read first"},
{"field":"@decisions","note":"array of decisions reached"},
{"field":"@open_items","note":"things not resolved with context"},
{"field":"@next_steps","note":"recommended actions for human"},
{"field":"@session","note":"reference to full session for audit"},
{"field":"@impasse","note":"reference to impasse record; present only if session ended in impasse"},
{"field":"@positions","note":"array of position records; present only if session ended in impasse"}],
"impasse_report_rules":["@decisions will be empty or partial","@summary and @next_steps must make clear human must decide",
"@impasse and @positions replace the normal resolution fields"]}

### Human Instruction

An instruction posted by the human into the session mikobase. Agents must read and respect it.
`@from` is a plain string identifier because the human does not register as an agent.

vibecode: {"class":"kiera.com/ai/human_instruction",
"role":"instruction posted by human into session mikobase; agents must read and respect it",
"from_field_note":"@from is string identifier; human does not register as agent",
"fields":[
{"field":"@session","note":"reference to session record"},
{"field":"@from","note":"identifier of human; string, not agent record pk"},
{"field":"@body","note":"the instruction"},
{"field":"@created_at"}]}

### Human Decision

A decision made by the human, typically to resolve an impasse or override the agents. Like
`human_instruction`, `@from` is a plain string.

vibecode: {"class":"kiera.com/ai/human_decision",
"role":"decision made by human; typically resolves impasse or overrides agents",
"from_field_note":"@from is string identifier; human does not register as agent",
"fields":[
{"field":"@session","note":"reference to session record"},
{"field":"@from","note":"identifier of human; string, not agent record pk"},
{"field":"@body","note":"the decision"},
{"field":"@resolves","note":"reference to impasse or open item being resolved"},
{"field":"@created_at"}]}

### Sign-off

Posted by an agent as the last record in its final batch of updates. Signals only that the
agent is done sending and is disconnecting — nothing more. A sign-off does not imply
resolution, agreement, success, or any particular session outcome. Session status is a
separate concern and must be set explicitly.

vibecode: {"class":"kiera.com/ai/sign_off",
"role":"final record in an agent's last batch; means only that the agent is hanging up",
"semantics":"carries no implication about resolution, agreement, or session outcome; session status is a separate concern",
"protocol":"posted as the last record in the final update batch",
"fields":[
{"field":"@from","note":"primary key of the agent record"},
{"field":"@session","note":"reference to session record"},
{"field":"@body","note":"optional closing remarks"}]}

### Import Rules for Worldlet Deltas

When agents exchange delta updates via `POST /worldlet`, the following rules govern what the
receiving mikobase will accept.

vibecode: {"concept":"worldlet_import_rules",
"uuid_constraint":"all keys in records/history/files/file_chunks and all record reference values must be UUID v4; malformed UUID → reject",
"conflict_policy":[
{"case":"history entry UUID already exists with identical content","action":"skip silently; import is idempotent"},
{"case":"history entry UUID already exists with different content","action":"error; abort entire import"}],
"reference_encoding":"reference fields in bucket are plain UUID strings; class definition declares field type; no wrapper syntax in bucket",
"validation_checks":["all history entries have record, class, created_at",
"all record values in history resolve to a known UUID",
"all class values are built-in or defined in classes or already in target mikobase",
"all file values in file_chunks reference a UUID in files",
"created_at is ISO 8601 with millisecond precision",
"no two history entries for same record share same created_at"],
"atomicity":"all-or-nothing; any error aborts entire import; no partial writes"}

vibecode: {"concept":"references",
"note":"fields like @to, @of, @based_on reference other records in session mikobase via standard mikobase record linking pattern"}

---

## Example Session Worldlet

The following is the complete final mikobase from an actual AI-to-AI schema review session.
Two AI instances (one acting as Spec Maintainer, one as Schema Reviewer) used a shared
mikobase to review and agree on the AI conversation protocol class definitions. The session
concluded with a decision to adopt all proposed class additions, with a note that the field
type notation in the draft schema would need to be rewritten in valid Kiera format before
production use.

The `classes` section reflects the draft schema that was under review and uses simplified type
notation (`"string"`, `"record"`, etc.) rather than standard Kiera field definitions — this
was the subject of the objection raised and resolved during the session.

vibecode: {"concept":"example_session_worldlet","note":"complete session mikobase from a real AI-to-AI schema review conversation; classes section uses the draft field types that were under review (non-standard Kiera format); a decision was reached that field types must be corrected before production use"}

```json
{
  "format": "worldlet",
  "format_version": "1.0",
  "meta": {
    "name": "AI Conversation Protocol Starter",
    "author": "kiera.com",
    "version": "0.1.0",
    "description": "Starter mikobase/worldlet schema for auditable AI-to-AI collaboration.",
    "created_at": "2026-05-03T00:00:00.000Z"
  },
  "properties": {
    "no_execute": true
  },
  "classes": {
    "kiera.com/ai/agent": {
      "fields": {
        "@name": "string",
        "@uns": "string",
        "@owner": "string",
        "@model": "string",
        "@registered_at": "datetime"
      }
    },
    "kiera.com/ai/session": {
      "fields": {
        "@agenda": "string",
        "@participants": "array:record",
        "@human": "string",
        "@status": "symbol",
        "@created_at": "datetime"
      }
    },
    "kiera.com/ai/proposal": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@subject": "string",
        "@body": "string",
        "@rationale": "string",
        "@status": "symbol"
      }
    },
    "kiera.com/ai/objection": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@to": "record",
        "@body": "string",
        "@severity": "symbol",
        "@status": "symbol"
      }
    },
    "kiera.com/ai/refinement": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@of": "record",
        "@previous": "record",
        "@body": "string",
        "@changes": "string"
      }
    },
    "kiera.com/ai/question": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@about": "record",
        "@body": "string"
      }
    },
    "kiera.com/ai/response": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@to": "record",
        "@body": "string"
      }
    },
    "kiera.com/ai/evidence": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@about": "record",
        "@kind": "symbol",
        "@source": "string",
        "@body": "string",
        "@confidence": "number"
      }
    },
    "kiera.com/ai/acceptance": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@of": "record",
        "@body": "string",
        "@conditions": "string"
      }
    },
    "kiera.com/ai/decision": {
      "fields": {
        "@session": "record",
        "@body": "string",
        "@based_on": "record",
        "@agreed_by": "array:record",
        "@confidence": "number",
        "@risks": "array:string"
      }
    },
    "kiera.com/ai/impasse": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@body": "string",
        "@sticking_point": "string"
      }
    },
    "kiera.com/ai/position": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@body": "string",
        "@supports": "record"
      }
    },
    "kiera.com/ai/human_instruction": {
      "fields": {
        "@session": "record",
        "@from": "string",
        "@body": "string",
        "@created_at": "datetime"
      }
    },
    "kiera.com/ai/human_decision": {
      "fields": {
        "@session": "record",
        "@from": "string",
        "@body": "string",
        "@resolves": "record",
        "@created_at": "datetime"
      }
    },
    "kiera.com/ai/report": {
      "fields": {
        "@session": "record",
        "@summary": "string",
        "@decisions": "array:record",
        "@open_items": "array:string",
        "@next_steps": "array:string",
        "@impasse": "record",
        "@positions": "array:record"
      }
    },
    "kiera.com/ai/sign_off": {
      "fields": {
        "@from": "record",
        "@session": "record",
        "@body": "string"
      }
    }
  },
  "records": {
    "02000000-0000-4000-8000-000000000001": {},
    "02000000-0000-4000-8000-000000000002": {},
    "02000000-0000-4000-8000-000000000003": {},
    "02000000-0000-4000-8000-000000000004": {},
    "02000000-0000-4000-8000-000000000005": {},
    "02000000-0000-4000-8000-000000000006": {},
    "02000000-0000-4000-8000-000000000007": {},
    "02000000-0000-4000-8000-000000000008": {},
    "02000000-0000-4000-8000-000000000009": {}
  },
  "history": {
    "41000000-0000-4000-8000-000000000001": {
      "record": "02000000-0000-4000-8000-000000000001",
      "class": "kiera.com/ai/agent",
      "created_at": "2026-05-03T00:05:00.000Z",
      "active": true,
      "bucket": {
        "@name": "Spec Maintainer",
        "@model": "claude-sonnet-4-6",
        "@registered_at": "2026-05-03T00:05:00.000Z"
      }
    },
    "41000000-0000-4000-8000-000000000002": {
      "record": "02000000-0000-4000-8000-000000000002",
      "class": "kiera.com/ai/session",
      "created_at": "2026-05-03T00:05:00.001Z",
      "active": true,
      "bucket": {
        "@agenda": "Review the AI conversation protocol starter schema.",
        "@participants": ["02000000-0000-4000-8000-000000000001"],
        "@human": "user",
        "@status": ":open",
        "@created_at": "2026-05-03T00:05:00.001Z"
      }
    },
    "41000000-0000-4000-8000-000000000003": {
      "record": "02000000-0000-4000-8000-000000000003",
      "class": "kiera.com/ai/proposal",
      "created_at": "2026-05-03T00:05:00.002Z",
      "active": true,
      "bucket": {
        "@from": "02000000-0000-4000-8000-000000000001",
        "@session": "02000000-0000-4000-8000-000000000002",
        "@subject": "Accept new classes and field additions",
        "@body": "The substantive design additions should be adopted into the standard class library. (1) kiera.com/ai/evidence: supports attaching cited sources to any session record; useful for grounding proposals. (2) kiera.com/ai/acceptance: explicit acceptance creates a clear audit trail of who accepted what, cleaner than status fields alone. (3) kiera.com/ai/human_instruction and kiera.com/ai/human_decision: essential human oversight classes; @from as string rather than record reference is correct since the human may not have an agent record. (4) @session on every class: improves queryability; all records for a session can be found without graph traversal. (5) @previous on refinement: tracks the full chain of revisions. (6) @status on objection: allows marking objections as addressed. (7) @confidence and @risks on decision: useful metadata for the human reviewing the outcome.",
        "@rationale": "Each addition addresses a real gap in the existing design. None conflict with existing classes.",
        "@status": ":open"
      }
    },
    "41000000-0000-4000-8000-000000000004": {
      "record": "02000000-0000-4000-8000-000000000004",
      "class": "kiera.com/ai/objection",
      "created_at": "2026-05-03T00:05:00.003Z",
      "active": true,
      "bucket": {
        "@from": "02000000-0000-4000-8000-000000000001",
        "@session": "02000000-0000-4000-8000-000000000002",
        "@to": "02000000-0000-4000-8000-000000000003",
        "@body": "The field type notation in this schema is non-standard for Kiera class definitions. Types like \"string\", \"datetime\", \"record\", \"array:record\", \"symbol\", and \"array:string\" do not match the standard Kiera format, which wraps each type as {\"class\": \"typename\"}. Several of these types — \"datetime\", \"record\", \"array:record\", \"symbol\" — are also not currently defined in the Kiera type system. This schema as written would not be importable by a standard Kiera engine. The types need to be mapped to valid Kiera field definitions before this schema can be used in production.",
        "@severity": ":concern",
        "@status": ":open"
      }
    },
    "41000000-0000-4000-8000-000000000005": {
      "record": "02000000-0000-4000-8000-000000000005",
      "class": "kiera.com/ai/sign_off",
      "created_at": "2026-05-03T00:05:00.004Z",
      "active": true,
      "bucket": {
        "@from": "02000000-0000-4000-8000-000000000001",
        "@session": "02000000-0000-4000-8000-000000000002",
        "@body": "Substantive design accepted. One concern raised on field type notation; awaiting response."
      }
    },
    "41000000-0000-4000-8000-000000000006": {
      "record": "02000000-0000-4000-8000-000000000006",
      "class": "kiera.com/ai/refinement",
      "created_at": "2026-05-03T00:05:00.005Z",
      "active": true,
      "bucket": {
        "@from": "02000000-0000-4000-8000-000000000001",
        "@session": "02000000-0000-4000-8000-000000000002",
        "@of": "02000000-0000-4000-8000-000000000003",
        "@previous": "02000000-0000-4000-8000-000000000003",
        "@body": "Adopt the proposed AI conversation schema additions, but revise all class field definitions to use the standard Kiera field declaration format. Conceptual type labels such as string, datetime, record, array:record, symbol, and array:string must not appear as bare field values in production schema. Each field should instead use a valid Kiera class reference object. Where the underlying Kiera type system lacks a dedicated primitive, use the closest existing valid type or define a first-class Kiera class before import.",
        "@changes": "Resolved the concern about non-standard field type notation. The substantive class additions remain accepted, but the starter schema must be rewritten into valid Kiera class-definition syntax before production use."
      }
    },
    "41000000-0000-4000-8000-000000000007": {
      "record": "02000000-0000-4000-8000-000000000007",
      "class": "kiera.com/ai/acceptance",
      "created_at": "2026-05-03T00:05:00.006Z",
      "active": true,
      "bucket": {
        "@from": "02000000-0000-4000-8000-000000000001",
        "@session": "02000000-0000-4000-8000-000000000002",
        "@of": "02000000-0000-4000-8000-000000000006",
        "@body": "Refinement accepted. The field type concern is resolved. Substantive additions stand; starter schema to be rewritten in valid Kiera class-definition syntax before production use."
      }
    },
    "41000000-0000-4000-8000-000000000008": {
      "record": "02000000-0000-4000-8000-000000000008",
      "class": "kiera.com/ai/decision",
      "created_at": "2026-05-03T00:05:00.007Z",
      "active": true,
      "bucket": {
        "@session": "02000000-0000-4000-8000-000000000002",
        "@body": "The AI conversation protocol schema additions are accepted: kiera.com/ai/evidence, kiera.com/ai/acceptance, kiera.com/ai/human_instruction, kiera.com/ai/human_decision, @session on all classes, @previous on refinement, @status on objection, @confidence and @risks on decision. The field type notation in the starter schema must be rewritten to standard Kiera field definition format before production use.",
        "@based_on": "02000000-0000-4000-8000-000000000006",
        "@agreed_by": ["02000000-0000-4000-8000-000000000001"]
      }
    },
    "41000000-0000-4000-8000-000000000009": {
      "record": "02000000-0000-4000-8000-000000000002",
      "class": "kiera.com/ai/session",
      "created_at": "2026-05-03T00:05:00.008Z",
      "active": true,
      "bucket": {
        "@agenda": "Review the AI conversation protocol starter schema.",
        "@participants": ["02000000-0000-4000-8000-000000000001"],
        "@human": "user",
        "@status": ":resolved",
        "@created_at": "2026-05-03T00:05:00.001Z"
      }
    },
    "41000000-0000-4000-8000-000000000010": {
      "record": "02000000-0000-4000-8000-000000000009",
      "class": "kiera.com/ai/report",
      "created_at": "2026-05-03T00:05:00.009Z",
      "active": true,
      "bucket": {
        "@session": "02000000-0000-4000-8000-000000000002",
        "@summary": "The starter schema is substantively sound. All new classes and field additions are accepted. The field type notation must be corrected to standard Kiera format before the schema can be imported by a Kiera engine.",
        "@decisions": ["02000000-0000-4000-8000-000000000008"],
        "@open_items": [
          "Rewrite starter schema field types to standard Kiera format.",
          "Define or map datetime, record, array:record, symbol, and array:string to valid Kiera types."
        ],
        "@next_steps": [
          "Update ai-classes.md with new classes and field additions.",
          "Update ai-conversation-format.md vibecode blocks.",
          "Produce a corrected starter schema worldlet with valid Kiera field definitions."
        ]
      }
    },
    "41000000-0000-4000-8000-000000000011": {
      "record": "02000000-0000-4000-8000-000000000005",
      "class": "kiera.com/ai/sign_off",
      "created_at": "2026-05-03T00:05:00.010Z",
      "active": true,
      "bucket": {
        "@from": "02000000-0000-4000-8000-000000000001",
        "@session": "02000000-0000-4000-8000-000000000002"
      }
    }
  }
}
```
