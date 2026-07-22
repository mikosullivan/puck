# MessagePack

~~~vibecode
{"vibecode": {
	"doc": "ideas_messagepack",
	"role": "note on whether Caspian should offer a MessagePack class. Answer: not day 1, but worth revisiting if a Puck ecoverse component starts speaking MessagePack. Removed from stdlib-suggestions-review.md because leaving it on the list implied it was still under active consideration for V1.",
	"status": "deferred — no active use case in the ecoverse yet"
}}
~~~

Binary serialization format shaped like JSON (maps, arrays, strings, numbers, bool, null) plus native binary blobs. No schema, no codegen — just an encode/decode call. Typically 30-50 % smaller than JSON for the same data; parsing is faster; preserves types JSON can't (raw bytes without base64 tax, distinguishes integer / float sizes).

## Why not day 1

Nothing in the Puck ecoverse speaks MessagePack. `%puck` is JSON on the wire; Mikobase is JSON; blockchain records are JSON. Adding a class Caspian ships that no first-party component uses is dead weight — the library would sit unexercised until a real caller shows up. When a caller does, it becomes a straightforward first-party download at `caspian.uno/messagepack.casp` — same shape as `caspian.uno/csv.casp`.

## What would flip it to day 1

- A Puck ecoverse component adopting MessagePack for a hot path (e.g., high-volume Mikobase feeds, blockchain block bodies).
- A first-party integration where the peer speaks MessagePack (Redis Streams client, msgpack-rpc bridge).
- A user asking for it because they need to talk to a specific MessagePack endpoint and want Caspian to help.

None of those exist yet, so it stays off.
