# String Methods

## Overview (Rayner DISCO)

```
vibecode: {
	"section": "overview",
	"type": "string",
	"encoding": "utf8",
	"mutable": false,
	"key_facts": ["all_methods_return_new_string", "engine_validates_utf8_at_boundary"]
}
```

Strings are immutable UTF-8 sequences. Every method returns a new string (or a value of
another type); none mutate in place. A compliant engine must ensure all strings are valid
UTF-8 at system boundaries before passing them to KScript.

---

## Operators (Moll)

```
vibecode: {
	"section": "operators",
	"operators": ["+", "*", "[]"],
	"notes": ["right_operand_coerced_to_string_for_plus",
		"repeat_requires_nonneg_integer",
		"subscript_supports_offset_and_length",
		"end_anchored_slicing_via_colon_end",
		"indices_are_unicode_codepoints_not_bytes"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `+` | String | Concatenate. Right operand coerced to string. `'Hello, ' + $name` |
| `*` | String | Repeat. `'ha' * 3` → `'hahaha'`. Right operand must be a non-negative integer. |
| `[]` | String | Subscript. `$str[n]` returns the character at index `n` (0-based). `$str[$start, $length]` returns `$length` characters starting at `$start`. Passing `:end` as the last argument switches to end-anchored slicing (see `end` below): `$str[n, :end]` is sugar for `$str[n, 1, :end]`; `$str[n, $length, :end]` returns `$length` characters ending at position `n` from the end. Indices count Unicode code points, not bytes. Returns empty string if out of range. |

---

## Testing (Moll DISCO)

```
vibecode: {
	"section": "testing",
	"returns": "Boolean",
	"methods": ["==", "include?", "match?", "starts_with?", "start_with?",
		"ends_with?", "end_with?"],
	"notes": ["start_with_and_end_with_are_aliases"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `==` | Boolean | True if both strings are identical |
| `include?($substr)` | Boolean | True if `$substr` appears anywhere in the string |
| `match?($pattern)` | Boolean | True if the string matches the regex `$pattern` |
| `starts_with?($prefix)` | Boolean | True if the string begins with `$prefix` |
| `start_with?($prefix)` | Boolean | Alias for `starts_with?` |
| `ends_with?($suffix)` | Boolean | True if the string ends with `$suffix` |
| `end_with?($suffix)` | Boolean | Alias for `ends_with?` |

---

## Case (L'ak)

```
vibecode: {
	"section": "case",
	"methods": ["upper_case", "lower_case"],
	"returns": "String"
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `upper_case` | String | All characters uppercased |
| `lower_case` | String | All characters lowercased |

---

## Whitespace (Vellek)

```
vibecode: {
	"section": "whitespace",
	"methods": ["left_strip", "right_strip", "collapse", "chomp"],
	"returns": "String",
	"notes": ["collapse_strips_and_normalizes_internal_whitespace",
		"chomp_removes_trailing_newlines_and_carriage_returns"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `left_strip` | String | Remove leading whitespace |
| `right_strip` | String | Remove trailing whitespace |
| `collapse` | String | Remove leading and trailing whitespace, then collapse every internal run of whitespace to a single space. `'  hello   world  '.collapse` → `'hello world'`. Whitespace includes spaces, tabs, and newlines. |
| `chomp` | String | Remove all trailing newline (`\n`) and carriage return (`\r`) characters. No-op if the string does not end with either. |

---

## Prefix and Suffix (La'an)

```
vibecode: {
	"section": "prefix_and_suffix",
	"methods": ["delete_prefix", "delete_suffix"],
	"returns": "String",
	"notes": ["returns_string_unchanged_if_prefix_or_suffix_not_present"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `delete_prefix($prefix)` | String | Remove `$prefix` from the start of the string if present; return the string unchanged otherwise |
| `delete_suffix($suffix)` | String | Remove `$suffix` from the end of the string if present; return the string unchanged otherwise |

---

## Search and Replace (Ortegas)

```
vibecode: {
	"section": "search_and_replace",
	"methods": ["match", "replace"],
	"replace_scope_options": [":all", ":first", ":last"],
	"notes": ["match_returns_match_object_or_nil",
		"replace_pattern_may_be_string_or_regex",
		"default_scope_is_all",
		"returns_original_if_no_match"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `match($pattern)` | Match or nil | Return the first match object for `$pattern`, or nil if no match. The match object carries the matched string and any capture groups. |
| `replace($pattern, $replacement, $scope = :all)` | String | Replace occurrences of `$pattern` with `$replacement`. `$pattern` may be a string or regex. `$scope` controls which matches are replaced: `:all` (default) replaces every match, `:first` replaces only the first, `:last` replaces only the last. Returns the original string unchanged if no match is found. |

### replace scope options

| Scope | Behaviour |
|-------|-----------|
| `:all` | Replace all matches (default) |
| `:first` | Replace the first match from the start |
| `:last` | Replace the last match from the end |

```
$foo = 'Mike Stuart Mike'

$foo.replace('Mike', 'foo')         -> 'foo Stuart foo'
$foo.replace('Mike', 'foo', :all)   -> 'foo Stuart foo'
$foo.replace('Mike', 'foo', :first) -> 'foo Stuart Mike'
$foo.replace('Mike', 'foo', :last)  -> 'Mike Stuart foo'
$foo.replace('xyz', 'bar')          -> 'Mike Stuart Mike'
```

---

## Formatting (M'Benga)

```
vibecode: {
	"section": "formatting",
	"methods": ["left_justify", "right_justify"],
	"returns": "String",
	"notes": ["pads_with_spaces", "no_op_if_already_at_or_above_width"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `left_justify($width)` | String | Pad with spaces on the right to at least `$width` characters. Returns the string unchanged if already at or above `$width`. |
| `right_justify($width)` | String | Pad with spaces on the left to at least `$width` characters. Returns the string unchanged if already at or above `$width`. |

---

## Splitting (Chapel SNW)

```
vibecode: {
	"section": "splitting",
	"methods": ["lines"],
	"returns": "Array",
	"notes": ["line_endings_stripped_from_each_element"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `lines` | Array | Split into an array of lines. Line endings (`\n`, `\r\n`) are stripped from each element. |

---

## Size (Hemmer)

```
vibecode: {
	"section": "size",
	"methods": ["length", "size"],
	"returns": "Number",
	"notes": ["counts_unicode_codepoints_not_bytes", "size_is_alias_for_length"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `length` | Number | Number of Unicode code points |
| `size` | Number | Alias for `length` |

---

## Conversion (Pelia)

```
vibecode: {
	"section": "conversion",
	"methods": ["to_number", "hex", "reverse"],
	"notes": ["to_number_raises_if_invalid",
		"hex_parses_hexadecimal_integer",
		"reverse_returns_characters_in_reverse_order"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `to_number` | Number | Parse as a number. Raises an exception if the string is not a valid number. |
| `hex` | Number | Parse as a hexadecimal integer. `'ff'.hex` → 255. Raises an exception if the string is not valid hex. |
| `reverse` | String | Characters in reverse order |
| `incremented` | String | Returns the next string in Perl/Ruby-style alphanumeric sequence. Increments the rightmost alphanumeric character and carries left. `'az'.incremented` → `'ba'`. `'zz'.incremented` → `'aaa'`. Non-alphanumeric characters are left alone. |
| `decremented` | String | Returns the previous string in alphanumeric sequence — the exact reverse of `incremented`. `'ba'.decremented` → `'az'`. `'aaa'.decremented` → `'zz'`. Raises an exception if called on an empty string. |

---

## End-Anchored Slicing (Sam Kirk)

```
vibecode: {
	"section": "end_anchored_slicing",
	"concept": "end_object_wraps_string_for_right_indexed_access",
	"access": "$str.end[$offset] or $str.end[$offset, $length]",
	"sugar": "$str[n, :end] and $str[n, $length, :end]",
	"implementation": "$str.end[$offset, $length] == $str.reverse[$offset, $length].reverse",
	"parser_note": "end_after_dot_is_method_name_not_block_closing_keyword"
}
```

`end` is a method on String that returns an **end object** — a thin wrapper that holds a
reference to the string and provides end-anchored slicing via its own `[]` method.

| Method | Returns | Description |
|--------|---------|-------------|
| `end` | End object | Returns the end object for this string. |

The end object has a `[]` method with the same signature as String's `[]`, but indexing
from the right:

| Method | Returns | Description |
|--------|---------|-------------|
| `end[]($offset)` | String | The character at position `$offset` from the end. `0` is the last character. |
| `end[]($offset, $length)` | String | `$length` characters ending at position `$offset` from the end. |

The end object's `[]` is defined in terms of existing String primitives:

```
$str.end[$offset, $length]  =  $str.reverse[$offset, $length].reverse
```

Examples with `$foo = 'abcdef'`:

```
$foo.end[0]      -> 'f'
$foo.end[0, 2]   -> 'ef'
```

The `:end` keyword in String's `[]` is sugar for calling the end object:

```
$foo[0, :end]    -> 'f'    # sugar for $foo.end[0]
$foo[0, 2, :end] -> 'ef'   # sugar for $foo.end[0, 2]
```

The end object may grow additional methods in later versions. In KScript, the `[]` method
on the end object can be defined as:

```
function end[]()
end
```

**Parser note:** `end` after a `.` is a method name, not the block-closing keyword. The
parser must handle this disambiguation.

---

## Open Questions (Sam)

- `[]` with `:end`: resolved — see End-Anchored Slicing section.
- `match` return type: the Match object API is not yet designed.
- `left_justify` and `right_justify`: should a custom fill character be supported as a second argument?
