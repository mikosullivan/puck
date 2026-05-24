# Caspian time class

~~~json
{"vibecode": {
	"doc": "caspian_time",
	"role": "basic time / date class for Caspian — represents a single point in time with rich, addressable properties; immutable",
	"status": "placeholder — design notes in [ideas/ezdate.md](../ideas/ezdate.md); concrete spec TBD",
	"key_concepts": ["point_in_time", "addressable_properties", "immutable",
		"epoch_granularities", "format_strings", "utc_offsets_only_no_named_zones"]
}}
~~~

Caspian's basic time class represents **a single point in time** with all its
properties — hour, minute, second, weekday, day of month, month, year, day of
year, epoch (in several granularities) — accessible as fields on the object.

**Time objects are immutable.** Once constructed, a time's properties never
change. Operations that would "modify" a time (advance by a day, change the
hour, switch zones) return a *new* time object; the original is untouched.

The design lineage is Miko's old Perl `Date::EzDate` module; see
[ideas/ezdate.md](../ideas/ezdate.md) for the mined-for-ideas writeup and the
open design questions.

This doc is a placeholder — the spec will fill in as decisions land.

---

<a id="status"></a>
## Status

Placeholder. Major design questions are still open:

<a id="open-class-name"></a>
### Class name

`puck.uno/time` vs `puck.uno/instant` vs other.

<a id="open-mutable-vs-immutable"></a>
### Mutable vs immutable

**Resolved: immutable.** Time objects don't mutate after construction.
Operations that would change a time (advance a day, set the hour, switch
zones) return a new time object. Aligns with modern designs (Java `Instant`,
Python `datetime`, JS `Temporal`) and with the Caspian
[Fiona-inspired](../ideas/fiona.md) "objects immutable, relationships
mutable" mental model.

<a id="open-default-zone"></a>
### Default offset for naive parsing

`new('2026-05-23 14:30')` — string has no offset. Default to UTC,
host-local, or throw?

(Updated 2026-05-23: question is now about **UTC offsets**, not named
zones — see [Time zones — UTC offsets only](#zones).)

<a id="open-numbering-base"></a>
### Weekday / month numbering base

**Resolved:** both are exposed. `.month.index` is 0-based (Jan = 0); `.month.number`
is 1-based (Jan = 1). Same pattern for days of the week. Callers reach for whichever
convention fits their use; no global toggle.

<a id="open-calendar-systems"></a>
### Calendar systems

Gregorian-only for now? Other calendars (Julian, Hebrew, Hijri, Persian,
Buddhist, etc.) deferred or supported as extensions?

See [ezdate.md § Open questions](../ideas/ezdate.md#open-questions) for the
full list and current thinking.

---

<a id="purpose"></a>
## Purpose

A Caspian program needs to represent and manipulate moments in time:

- Read the current time
- Parse a date/time string a user typed
- Format a time for display
- Move to a different time (next day, same hour; same date, next year)
- Compare two times
- Compute differences between times

The basic time class covers all of these. **Time spans** (lengths of time —
"2 days, 3 hours") are a separate class with its own section below; see
[Time spans](#time-spans).

---

<a id="methods"></a>
## Methods

~~~json
{"vibecode": {
	"section": "methods",
	"patterns": ["hierarchical_sub_objects: $date.month.X, $date.year.X, $date.day.X",
		"predicate_methods_with_question_mark_suffix: .january?, .leap_year?, .monday?",
		"both_index_0_based_and_number_1_based_exposed"]
}}
~~~

Confirmed methods so far. List is illustrative, not exhaustive — more will land
as the design fills in.

<a id="month"></a>
### Month

~~~caspian
$date.month.name            # "May"
$date.month.short_name      # "May" (or "Jan"/"Feb"/... — three-letter form)
$date.month.index           # 4   (0-based; Jan = 0)
$date.month.number          # 5   (1-based; Jan = 1)
$date.month.days            # 31  (number of days in this month)
$date.month.january?        # false
$date.month.february?       # false
# ... predicates for each of the 12 months
~~~

<a id="year"></a>
### Year

~~~caspian
$date.year                  # 2026
$date.year.leap_year?       # false
~~~

<a id="day"></a>
### Day

~~~caspian
$date.day.number            # 23  (day-of-month; consider also a 0-based form if needed)
$date.day.monday?           # false
$date.day.tuesday?          # false
# ... predicates for each of the 7 days
$date.day.leap_day?         # true iff this is February 29
~~~

<a id="time-of-day"></a>
### Time of day

Unlike `.month`, `.year`, and `.day` (which return sub-objects with their own
methods), the time-of-day accessors return **plain numbers**:

~~~caspian
$time.hour                  # number
$time.seconds               # number
~~~

Naming preserved verbatim from the source examples — `hour` (singular) and
`seconds` (plural). The other components (`minute`/`minutes`, etc.) will be
confirmed as the design fills in.

<a id="arithmetic"></a>
### Arithmetic

~~~caspian
$timea - $timeb             # time span object
~~~

Subtracting one time from another yields a **time span object** representing
the interval between them. See [Time spans](#time-spans) below for the span
class.

Other arithmetic operations (adding a span to a time, comparison via `<` /
`>` / `==`, etc.) are likely but not yet confirmed.

<a id="zones"></a>
### Time zones — UTC offsets only

A time carries an explicit **UTC offset**, expressed as a signed hour:minute
string. **Named zones like `America/New_York` are not supported.** No IANA
tzdata dependency, no DST handling, no zone history — just a fixed offset
from UTC.

~~~caspian
$time.offset                  # read: current offset (e.g. "-08:00")

$time.offset = '-04:00'       # write: preserve wall clock, change offset
                              # "3 pm at -08:00" becomes "3 pm at -04:00"
                              # — the actual instant moves; the displayed
                              # numbers don't

$utc = $time.in_zone('UTC')   # returns new time: preserve actual instant
                              # "3 pm at -08:00" becomes "11 pm UTC" — same
                              # moment on the universal timeline, different
                              # display
~~~

Accepted offset forms:

| Form | Meaning |
|---|---|
| `'UTC'` or `'Z'` | zero offset |
| `'+05:00'`, `'-08:00'` | ISO 8601 signed hour:minute |
| `'+0500'`, `'-0800'` | same, no colon |

**Why no named zones.** Named time zones (IANA `America/New_York`, etc.)
require a maintained tzdata database with decades of historical rules and
DST transitions, updated multiple times per year. Caspian's runtime ships
none of that. Offset-only keeps the time class self-contained and
predictable across hosts.

**What this means for applications.** If your application needs DST-aware
zone behavior — a calendar app, a scheduling system, anything that has to
get "Eastern time on October 31, 2027" right — you'll need to compute the
correct offset yourself (from a zone library outside Caspian) and pass it
in. Caspian's time class won't do it for you.

**Immutability still holds.** `$time.offset = '-04:00'` doesn't mutate the
underlying time object — it rebinds the variable `$time` to a new time
constructed with the modified offset. Anything else holding a reference to
the original time sees the original unchanged.

**Pick the right operation carefully.** `.offset =` changes the actual
instant (same wall-clock numbers, different moment in the universe);
`.in_zone()` preserves the actual instant. Mixing them up silently moves
a time to a different real moment without warning.

<a id="formatting"></a>
### Formatting

~~~caspian
$date.iso8601                                     # built-in ISO 8601 format
$date.format('{Mon} {day pad}, {year}')           # "Jan 07, 2026"
~~~

Format tokens are **space-separated, case-sensitive words inside braces**. Two
conventions visible in the token list:

- **Case of the token determines case of the output.** `{mon}` emits `jan`,
  `{Mon}` emits `Jan`, `{MON}` emits `JAN`. Same pattern for weekday tokens.
- **`pad` suffix means zero-pad to the natural width.** `{hour}` emits `2`;
  `{hour pad}` emits `02`. Same for `{month num}` / `{month num pad}`,
  `{day}` / `{day pad}`, etc.

Confirmed tokens so far:

| Token | Example output |
|---|---|
| `{mon}` | `jan` |
| `{Mon}` | `Jan` |
| `{MON}` | `JAN` |
| `{month num}` | `1` |
| `{month num pad}` | `01` |
| `{year}` | `1967` |
| `{wkday}` | `thu` |
| `{Wkday}` | `Thu` |
| `{weekday}` | `thursday` |
| `{Weekday}` | `Thursday` |
| `{WEEKDAY}` | `THURSDAY` |
| `{day pad}` | `07` |
| `{hour}` | `2` |
| `{hour pad}` | `02` |
| `{ampm}` | `am` |
| `{AMPM}` | `AM` |

Escape tokens for emitting literal braces in the output:

| Token | Example output |
|---|---|
| `{lb}` | `{` |
| `{rb}` | `}` |

More tokens (long-form month name, lowercase 4-character weekday, minute,
second, time-zone, etc.) will fill in as the design proceeds.

---

<a id="time-spans"></a>
## Time spans

~~~json
{"vibecode": {
	"section": "time_spans",
	"role": "the time-span class — a length of time (e.g. '2 days, 3 hours, 18 seconds') separate from a point in time",
	"relationship_to_time": "time - time = span; addition, multiplication, etc. likely but not yet confirmed",
	"mutability": "immutable, same as puck.uno/time",
	"class_name": "TBD — puck.uno/timespan or puck.uno/duration",
	"status": "early sketch — fills in alongside the time class"
}}
~~~

A **time span** is a length of time, distinct from a point in time. Where
`puck.uno/time` represents "Saturday May 23 2026 14:30:00 UTC" (a moment),
a time span represents something like "8 days, 12 hours, 23 minutes,
2.30487 seconds" (a duration). The two classes are peers.

Spans are produced naturally by subtracting two times:

~~~caspian
$span = $timeb - $timea     # time span object
~~~

Modern date libraries (Java's `Duration`, Python's `timedelta`, Go's
`time.Duration`) all separate point-in-time from span-of-time. Caspian
follows the same shape.

Time spans are **immutable**, same as `puck.uno/time`.

<a id="span-decomposition"></a>
### Decomposition

~~~caspian
$span.dhms                  # {"days": 8, "hours": 12, "minutes": 23, "seconds": 2.30487}
~~~

Breaks a span down into a hash of days / hours / minutes / seconds, with
fractional seconds preserved. Useful for "how long is this?" displays.

<a id="span-relationships-with-time"></a>
### Relationships with `puck.uno/time`

The full algebra (none of these confirmed beyond `time - time = span`):

| Operation | Result |
|---|---|
| `time - time` | `span` ✓ confirmed |
| `time + span` | `time` (likely) |
| `time - span` | `time` (likely) |
| `span + span` | `span` (likely) |
| `span - span` | `span` (likely) |
| `span * N` | `span` (likely) |
| `span / N` | `span` (likely) |

Fill in as decisions land.

<a id="span-class-name"></a>
### Class name

TBD. Two leading candidates:

- **`puck.uno/timespan`** — matches the term "time span" used in
  conversation and in this doc; reads naturally
- **`puck.uno/duration`** — matches Java / Python / Go convention; more
  familiar to developers from those ecosystems

---

<a id="design-patterns"></a>
## Design patterns

Three conventions visible in the method list above are worth naming explicitly
so they're consistent as more methods are added:

<a id="pattern-helpers"></a>
<a id="pattern-hierarchical-accessors"></a>
### Helpers for grouped methods

`.month`, `.year`, `.day` aren't plain sub-objects — they're
**[helpers](lucy/lucy.md#helpers)**, the established Caspian mechanism for
namespacing methods on an object without polluting the main method namespace.
So `$date.month.short_name` calls a method on the `month` helper, which
carries a `@reference` back to `$date`.

This is **not** universal. Components that don't have a meaningful method
surface beyond their numeric value just return plain numbers: `$time.hour`,
`$time.seconds`. Use a helper where the grouping earns its keep; skip it
where the helper would just wrap a single integer.

<a id="pattern-predicate-question-mark"></a>
### Predicate methods end with `?`

Methods that return a boolean answering a yes/no question use the `?` suffix:
`.january?`, `.leap_year?`, `.monday?`, `.leap_day?`. Consistent with the
existing Caspian convention (e.g. `$loop.active?`).

<a id="pattern-both-index-and-number"></a>
### Both 0-based `.index` and 1-based `.number` exposed

Rather than picking one and forcing callers to convert, both conventions are
first-class. Use `.index` when you want 0-based (array indexing math); use
`.number` when you want 1-based (human display, "the fifth month").

---

<a id="related-classes"></a>
## Related classes

These don't exist yet either; flagged here so the time class isn't designed
in isolation:

<a id="related-time-zones"></a>
### Time zones (UTC offsets only)

Every time-point carries an explicit UTC offset (e.g. `-08:00`, `+05:30`,
`UTC`). **Named zones (IANA `America/New_York` etc.) are not supported** —
no tzdata dependency, no DST handling. See
[Time zones — UTC offsets only](#zones) above for the rationale and
operations.

Applications that need DST-aware named-zone behavior have to compute the
correct offset themselves (via an external library) and pass it in.

---

<a id="see-also"></a>
## See also

- **[ideas/ezdate.md](../ideas/ezdate.md)** — mined-for-ideas writeup based on Miko's old Perl module
- **[ideas/fiona.md](../ideas/fiona.md)** — the immutable-objects mental model relevant to the mutability decision
