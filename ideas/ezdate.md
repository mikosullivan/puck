# EzDate: lessons for Caspian's time class

~~~vibecode
{"vibecode": {
	"doc": "ezdate",
	"role": "mining Miko's old Perl Date::EzDate module (CPAN, ~2001-2007) for design ideas applicable to Caspian's basic time class",
	"source": "https://www.cpan.org/modules/by-module/Object/MIKO/Date-EzDate-1.16.readme",
	"status": "design notes — not a spec; informs the eventual puck.uno/time class design",
	"key_concepts": ["one_point_in_time", "assignable_properties_with_recalculation",
		"format_strings_with_embedded_properties", "multiple_epoch_granularities",
		"smart_range_formatting", "forgiving_parsing"]
}}
~~~

Miko's old Perl module `Date::EzDate` (CPAN, ~2001-2007) had several design ideas
worth carrying forward into Caspian's basic time class. This doc mines that module
for what was good, flags what didn't work, and notes what EzDate didn't solve that
Caspian needs to from day one.

EzDate's central insight: **a date/time object represents a single point in time,
and every property of that point — hour, weekday, month, epoch seconds — is both
readable and assignable, with auto-recalculation**. Set `weekday = "Monday"` and
the object jumps to the Monday of the same week. Set `epoch_day++` and the date
advances by one day, hour/minute/second preserved. Set `month_number = 5` and you
get the same day-of-month in month 5 (with boundary handling for Jan 31 → Feb 28).

That model still holds up. Most of what's worth pulling forward orbits around it.

---

## Ideas worth carrying forward

### Single point in time with rich properties

The object IS one instant in time. Every property of that instant is reachable
as a field: hour, minute, second, weekday (number/short/long), day of month,
day of year, month (number/short/long), year, am/pm, etc. No method calls
needed for the common reads; just access the field.

For Caspian this translates naturally to:

~~~caspian
$now = %('puck.uno/time').new()
$now.year         # 2026
$now.month_long   # "May"
$now.weekday_short # "Sat"
$now.day_of_year  # 144
~~~

### Assignable properties with auto-recalculation

This is the killer feature. Set any property and the rest of the time-point
recalculates to satisfy the new value:

~~~caspian
$d = %('puck.uno/time').new('2001-04-14')  # Saturday
$d.weekday_number = 1                       # Monday → now 2001-04-09
$d.epoch_day = $d.epoch_day + 1             # next day → 2001-04-10
$d.month_number = 2                         # → 2001-02-10 (or 2001-02-28 if was 31st)
~~~

Properties not affected by the change stay put. Setting `month_number` doesn't
touch the time-of-day. Setting `hour` doesn't touch the date. The mental
model is: "this object IS a point in time; assigning to a property means
'I want to move to a different point where this property is X'."

For Caspian, this composes with deterministic GC: each assignment can either
mutate in-place (EzDate's choice) or return a new immutable time (Miko's
[Fiona-inspired](fiona.md) "objects immutable, relationships mutable" preference).
Worth deciding — see [open questions](#open-questions).

### Multiple epoch granularities for arithmetic

EzDate exposed `epoch_second`, `epoch_minute`, `epoch_hour`, and `epoch_day`.
Each is a single integer counting that unit since 1970-01-01 UTC. Pick the
granularity for your math:

~~~caspian
$d.epoch_day = $d.epoch_day + 7   # one week later
$d.epoch_hour = $d.epoch_hour + 3 # three hours later
$tomorrow_at_same_time = $d.epoch_day + 1
~~~

Cleaner than dragging in a separate `Duration` type for the simple cases.
Combine with a real `puck.uno/duration` class for the not-simple cases.

### Format strings with embedded properties

EzDate let you ask for any property combination as a single brace-delimited
string:

~~~caspian
$d.format('{weekday_long}, {month_long} {day_of_month}, {year}')
# "Saturday, April 14, 2001"
~~~

Much better than method-call concatenation. Caspian's heredoc / interpolation
syntax probably lets this drop in naturally as a method on the time class.

Also supported Unix-style `%`-codes for strftime compatibility:

~~~caspian
$d.format('%Y-%m-%d %H:%M:%S')   # "2001-04-14 09:06:26"
~~~

Worth supporting both — `%`-codes for interop with anything that already speaks
strftime; brace-properties for Caspian-native usage.

### Named custom formats

Define a format once, use it everywhere:

~~~caspian
%('puck.uno/time').define_format('miko_default',
    '{weekday_long}, {month_long} {day_of_month}, {year}')

$d.miko_default   # "Saturday, April 14, 2001"
~~~

Per-class registry of formats. Default format used when the object is
stringified. EzDate let users redefine the default per-object too — useful for
"this report uses ISO, this email uses 'Tuesday, June 4, 2024' style."

### Smart range formatting

EzDate's `date_range_string()` produced concise spans by dropping repeated parts:

| Start | End | Output |
|---|---|---|
| Mar 5, 2004 | Mar 7, 2004 | `Mar 5-7, 2004` |
| Feb 20, 2004 | Mar 3, 2004 | `Feb 20-Mar 3, 2004` |
| Dec 23, 2004 | Jan 3, 2005 | `Dec 23, 2004-Jan 3, 2005` |
| Dec 23, 2004 | Dec 23, 2004 | `Dec 23, 2004` |

And `time_range_string()` for time-of-day spans:

| Start | End | Output |
|---|---|---|
| 10:00am | 11:00am | `10:00-11:00am` (am/pm dropped from start) |
| 10:00am | 2:00pm | `10:00am-2:00pm` |

Useful for any UI that displays schedules, event listings, calendar entries.
Should be in V1 as utility methods on the time class (or as static functions
on a date-utilities module).

EzDate also had `day_lumps()` for collapsing an array of individual dates
into contiguous runs ("Jan 3-6, 10, 15-17"). Same family of utility; worth
having.

### Forgiving parsing

EzDate accepted almost any reasonable string a human might type:

- `"2001-04-14"`
- `"Apr 14, 2001"`
- `"April 14 2001"`
- `"14APR2001"`
- `"14 April, 2001"` (note odd comma placement)
- `"Jan 31, 2003 4 pm"`
- `"July 23 2003 noon"`
- `"July 23 2003 midnight"`
- `"yesterday"`, `"tomorrow"`
- Perl epoch integer

Miko's note in the original README: *"I've aggressively tried to find formats
that EzDate can't understand. If you have some reasonably unambiguous date format
that EzDate is unable to parse correctly, please send it to me."*

That posture (best-effort permissive parsing, treat un-handled formats as bugs
to fix) is worth keeping. Combined with a strict ISO mode for when callers want
no surprises.

### Sensible operator overloading

EzDate overloaded comparison and arithmetic:

~~~caspian
$a < $b           # epoch comparison
$a == $b          # same point in time
$a + 3            # three days later (default granularity)
$d++              # one day later
~~~

Caspian's user-defined operators (via `method_missing` and friends) should make
this clean to implement. The default granularity for `+`, `-`, `++`, `--` was
`epoch_day` in EzDate — sensible default for human use. EzDate let users set
the global comparison/arithmetic granularity via a package variable; Caspian
should expose this per-class or per-instance instead of globally.

### `next_month()` with boundary handling

Months aren't all the same length, so "epoch month" doesn't exist as a clean
integer. EzDate had `next_month(N)`: same day-of-month, N months forward (or
backward). The case where the source day doesn't exist in the target month has
to snap: Jan 31 + 1 month → Feb 28 (or 29 in leap years), not "Mar 3" or an
error.

Likely also wants:

- `next_year(N)` — same date, N years forward; handles Feb 29 in leap years
- `next_weekday(name)` — next occurrence of "Tuesday" from this date
- `previous_weekday(name)` — symmetric

### `clone()` method

Cheaper than constructing a new object and copying every property. Standard.

### `yesterday` / `tomorrow` / `now` string shortcuts

EzDate accepted `"yesterday"` and `"tomorrow"` as construction strings. Cheap
and useful. Should extend: `"now"`, `"midnight"`, `"noon"`, maybe `"next monday"`
/ `"last friday"` if the parsing layer wants to grow.

---

## Things to drop or adapt

### Drop: Perl tied-hash mechanism

EzDate used Perl's `tie` interface so that `$mydate->{'weekday long'}` would
trigger property access. Perl-specific machinery; Caspian has direct method
dispatch and `method_missing`. Just use them.

### Drop: global config variables

EzDate had `$Date::EzDate::overload`, `$Date::EzDate::default_warning`, etc.
Global mutable state is an anti-pattern in modern languages. Caspian should
expose these as class methods or per-instance configuration. The `overload`
question (which property gets compared by `<` `>` etc.) can be a per-class
default with per-instance override.

### Drop: case- and space-insensitive property names

EzDate accepted `weekdaylong`, `WEEKDAYLONG`, `WeekDay Long`, even `Wee Kdaylong`
as the same property. Cute but slows lookup and produces typo-tolerance bugs.
Pick one name (`weekday_long`, snake_case per Puck convention) and use it.

### Adapt: pick one behavior for partial time assignments

EzDate had `zero_hour_ampm(0|1)` as a toggle: setting `"4 pm"` either zeros
minute/second (new default) or preserves them (old behavior). Configurable
behaviors that affect parsing are confusing. Pick one default; document; move
on. Probably "zero the unspecified components" matches what users mean when
they type `"4 pm"`.

### Adapt: `set_warnings(0|1|2)` → use `%chain.warn`

EzDate had a per-instance warning level: silent / stderr / stderr+exit. Caspian
has `%chain.warn` (per the existing roles / GC docs), which is the standard
way to surface non-fatal issues. Time class uses that instead of inventing its
own warning mechanism. For "fatal," raise. For "noisy," warn. No knob.

---

## Things EzDate didn't solve (should be in V1)

### Time zones

EzDate's TODO list called this out as a known gap. Modern apps need time-zone
awareness from day 1. Minimum:

- Every time-point carries an explicit zone (`UTC`, `America/New_York`, etc.)
- Conversion to a different zone keeps the same instant (5pm NYC ↔ 2pm LA)
- Format methods can render in the carried zone or any other
- Parsing accepts both timezone-bearing strings (`2001-04-14T09:06:26-04:00`)
  and naive ones (in which case UTC is the safest default, with a configurable
  override)

This is non-trivial — Olson zone database, DST transitions, leap seconds (or
deliberate ignoring thereof). Caspian probably leans on the host's tz database
(via Lua's `os.date` and the OS) rather than shipping its own.

### Date range: BCE through far future

EzDate inherited Perl's `localtime` limitations (~1902 - ~2037). 64-bit epoch
math handles ±292 billion years. Caspian's time class should use a wide-range
representation natively. Edge cases:

- BCE dates (year 0, year -44 for Julius Caesar, etc.)
- Calendar reform (Julian → Gregorian, 1582-ish, varies by jurisdiction)
- Pre-modern dates have ambiguous representations

V1 minimum: ISO 8601 dates covering at least 0000-01-01 to 9999-12-31. Beyond
that range is a research project.

### Time intervals as first-class

**Decided — landed in [time.md § Time spans](../requirements/time.md#time-spans).**
EzDate's TODO mentioned wanting a "time interval" class for "2 days, 3 hours,
18 seconds." Caspian ships one as a peer to the point-in-time class. Modern
date libraries (Java's `Duration`, Python's `timedelta`, Go's
`time.Duration`) all do the same thing.

Class name still TBD (`puck.uno/timespan` vs `puck.uno/duration` — see
canonical doc).

### Mutable vs immutable

EzDate was mutable: setting a property changed the object in place. That made
the API feel natural ("the object IS a date; change its date by setting its
properties") but meant aliasing bugs (two references to the same object, one
mutates, both observe).

Modern designs lean immutable: each "change" returns a new object. Java's
`Instant`, Python's `datetime`, JavaScript's modern `Temporal` proposal all
do this. Matches Miko's [Fiona-inspired](fiona.md) "objects immutable,
relationships mutable" mental model.

For Caspian, recommended: **immutable**. Each assignment-like operation returns
a new time object. The fluent style still works:

~~~caspian
$tomorrow = $now.with(epoch_day: $now.epoch_day + 1)
$next_month = $now.next_month  # returns a new instant, not mutates
~~~

Costs more allocations than mutable; reads cleaner; eliminates a class of bugs.
Worth the trade in the runtime hash era — small time objects, deterministic GC
collects them at scope exit.

---

## Sketch of Caspian time class

Not a spec — just a shape to argue with. Name TBD: `puck.uno/time`,
`puck.uno/instant`, `puck.uno/datetime` are all candidates.

### Construction

~~~caspian
$now = %('puck.uno/time').new
$d   = %('puck.uno/time').new('2026-05-23T14:30:00Z')
$d   = %('puck.uno/time').new('May 23, 2026 2:30pm', zone: 'America/New_York')
$d   = %('puck.uno/time').new(epoch_second: 1748000000)
$d   = %('puck.uno/time').new('yesterday')
~~~

### Property access

~~~caspian
$d.year             # 2026
$d.month_number     # 5  (1-based for humans; consider 0-based separately if needed)
$d.month_long       # "May"
$d.month_short      # "May"
$d.day_of_month     # 23
$d.weekday_long     # "Saturday"
$d.weekday_short    # "Sat"
$d.weekday_number   # 6  (decide 0- vs 1-based)
$d.hour             # 14  (24-hour)
$d.ampm_hour        # 2   (12-hour)
$d.ampm             # "pm"
$d.minute           # 30
$d.second           # 0
$d.day_of_year      # 143
$d.is_leap_year?    # false  (read-only)
$d.days_in_month    # 31  (read-only)
$d.epoch_second     # 1748000000
$d.epoch_day        # 20240
$d.zone             # "America/New_York"
~~~

### Modification (immutable)

~~~caspian
$tomorrow      = $d.with(epoch_day: $d.epoch_day + 1)
$next_year     = $d.with(year: $d.year + 1)
$same_day_4pm  = $d.with(hour: 16, minute: 0, second: 0)
$next_month_d  = $d.next_month
$in_utc        = $d.in_zone('UTC')
~~~

### Formatting

~~~caspian
$d.format('%Y-%m-%d %H:%M:%S')                              # strftime style
$d.format('{weekday_long}, {month_long} {day_of_month}')    # brace style
$d.iso8601                                                   # built-in: "2026-05-23T14:30:00Z"

# named format, defined once per class:
%('puck.uno/time').define_format('miko',
    '{weekday_long}, {month_long} {day_of_month}, {year}')
$d.format('miko')
~~~

### Comparison and arithmetic

~~~caspian
$a < $b                # epoch comparison (default granularity: second)
$a == $b               # equal instants
$d + 86400             # one day later (epoch_second arithmetic)
$d.add(days: 1)        # named-argument form, cleaner for humans
$diff = $b - $a        # returns puck.uno/duration
~~~

### Range utilities

~~~caspian
$start.range_to($end)              # "Mar 5-7, 2004"  (date_range_string)
$start.time_range_to($end)         # "10:00-11:00am"  (time_range_string)
%('puck.uno/time').lump_days($dates)  # → array of [start, end] spans
~~~

---

## Open questions

### Class name

`puck.uno/time`, `puck.uno/instant`, `puck.uno/datetime`, `puck.uno/moment`,
`puck.uno/timestamp` — all plausible. `time` is broad; `instant` matches Java
and emphasizes "single point"; `datetime` matches Python; `moment` evokes
Moment.js; `timestamp` matches DB conventions.

### Mutable or immutable

Recommended: immutable. EzDate was mutable. Decide.

### Weekday and month numbering base

EzDate: weekday 0-based (Sun=0), month 0-based (Jan=0). Modern conventions
mostly use 1-based (Mon=1, Jan=1). Caspian should pick one and stick. If
both are useful, expose both (`month_number_1based` and `month_number_0based`)
rather than a global toggle.

### Default time zone for naive parsing

`new('2026-05-23 14:30')` — no zone in the string. Defaults to UTC? Local
host time? Throw and require explicit zone? Most safety-conscious choice is
**throw**; most convenient is **local**. UTC is the middle ground.

### Leap seconds

Java ignores them, Python ignores them, Go ignores them. Caspian probably
ignores them too — but should document it explicitly.

### Calendar systems beyond Gregorian

Julian, Hebrew, Hijri, Persian, Buddhist, etc. Most apps don't need them.
Should the time class be extensible (via a `calendar` parameter) or
Gregorian-only with separate classes for other systems? Defer until a real
use case appears.

### Relationship with MVM

Time objects are small, immutable, and pure data — perfectly serializable.
They'd live in the runtime hash with zero special handling.
[MVM](mvm.md) doesn't need any time-class-specific machinery; the
class just has to round-trip via its standard JSON serialization (probably
ISO 8601 + zone).
