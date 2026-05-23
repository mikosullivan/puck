# Hexadecimal

~~~json
{"vibecode": {
	"doc": "hex",
	"role": "brainstorm: should Puck have a Hexadecimal class — a Number subclass whose default string form is hex?",
	"status": "closed — may be revisited when a concrete consumer asks for it",
	"closed_on": "2026-05-22",
	"reason_closed": "color library owns its hex parsing/formatting; no other consumer is asking today; format methods on Number cover the same ground without a new type"
}}
~~~

> **Status: closed — may be revisited.** Color owns its hex parsing
> and formatting, and no other consumer is asking for a Hex type today.
> Format methods on Number (e.g. `$n.to_hex(digits:, prefix:)` and
> `Number.from_hex($string)`) cover the same ground without introducing
> a new class. Reach back here if a real consumer (binary protocols,
> file hashes, anything that genuinely wants hex as its own type) shows
> up wanting it.

The brainstorm that follows is preserved for that future revisit.

---

## The idea

```caspian
$n = %puck['puck.uno/hex'].new(255)
$n.to_string    # 'ff'
$n + 1          # 256 (arithmetic stays numeric)

$rgb = Hex.parse('#ff0000')   # 16711680
```

A `Hex` IS a number — arithmetic, comparison, ordering, range membership
all just work. It only differs from a plain Number in two ways: it
parses from hex strings and its default string form is hex.

---

## Why it might be worth it

- **Discoverability.** `Hex.parse('#ff0000')` and `$n.to_string` reading
  out as `'ff'` is more findable than format-string tricks.
- **APIs that accept either.** A function that takes "an RGB channel
  value" can accept either a Number or a Hex transparently — because Hex
  IS a Number, by subclass.
- **Domain intent.** When you're working with binary protocols, file
  hashes, color codes, or memory addresses, you're thinking in hex. A
  Hex type carries that intent through the code.

---

## Why it might not be worth it

- **Hex is presentation, not value.** The number doesn't change — only
  its display does. Most languages handle this with a format method
  (`255.to_s(16)` in Ruby, `(255).toString(16)` in JS) and don't seem
  to miss having a Hex class.
- **Padding / prefix / case is context-dependent.** `#ff0000` vs `0xFF`
  vs `ff` vs `0F` — one class can't pick a default that fits every
  consumer.
- **Color already handles hex.** The most common consumer of "hex" in
  Puck is the [color library](color/), which has its own hex parsing
  and formatting. If color owns its hex needs, Hex's reason for existing
  shrinks.

---

## Open questions

- **What does `$hex.to_string` produce by default?** `'ff'`, `'#ff'`,
  `'0xff'`? Each context wants something different.
- **Padding.** `Hex.new(15).to_string` — `'f'` or `'0f'`? Configurable
  per instance, per call, or fixed?
- **Case.** Lowercase, uppercase, or follow the input?
- **If we don't add a class, what's the API on Number?**
  `$n.to_hex(digits: 2, prefix: '#')` and `Number.from_hex($string)`?
- **Where would Hex actually get used?** Color already plans to handle
  its own hex; binary protocols and file hashes are downstream. Is
  there a concrete consumer that wants this *today*?
