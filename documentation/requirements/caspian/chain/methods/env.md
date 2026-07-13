# `%chain.env`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_env",
	"role": "spec for %chain.env — read-only hash-style accessor for environment variables set when the script was launched"
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.env` is a hash-shaped accessor for environment variables that were set when the script was launched.

~~~caspian
$home = %chain.env['HOME']
%chain.env.has_key?('SHELL')
%chain.env.each do($name, $value) ... end
~~~

Standard hash interface: `[]`, `.has_key?`, `.each`, `.keys`. Read-only — scripts can't mutate the environment of the running process through this surface. (If a future use case needs mutation, a separate write API would be added — `%chain.env` itself stays read-only.)

## Testing

- **`%chain.env` is `null` without the grant** — without the capability, `%chain.env` is `null`.
- **Default-deny across role boundaries** — a non-user role does not see `%chain.env` until the capability is explicitly granted down the chain.
- **`[]` returns the value** — `%chain.env['HOME']` returns the string the launcher set for `HOME`.
- **`[]` on a missing name returns `null`** — `%chain.env['DEFINITELY_NOT_SET']` is `null`, does not raise.
- **`.has_key?` returns `true` for set names** — `%chain.env.has_key?('HOME')` is `true`.
- **`.has_key?` returns `false` for unset names** — `%chain.env.has_key?('DEFINITELY_NOT_SET')` is `false`.
- **`.each` yields all pairs** — the block runs once per env var with `($name, $value)`.
- **`.keys` returns the name array** — every name reachable through `%chain.env[...]` is present.
- **Values are strings** — even numeric-looking values (`PORT=8080`) come back as strings.
- **Unicode values round-trip** — a var set to `"café"` returns the same string.
- **Values with special characters preserved** — newlines, quotes, and other shell-sensitive characters in a value survive intact.
- **Empty-string value distinct from missing** — a var set to `""` returns `""` and `.has_key?` is `true`; an unset var returns `null` and `.has_key?` is `false`.
- **Read-only — index assignment raises** — `%chain.env['FOO'] = 'x'` raises.
- **Read-only — no writer methods** — no `.set`, `.delete`, `.clear`, or similar writer is exposed.
- **Values carry env role provenance** — strings read from `%chain.env` carry the role tag of the env faucet.
- **Launch snapshot** — the surface reflects the environment at process launch; changes to the OS-level environment mid-run are not required to be reflected.
- **Revoke clears the surface** — after the env capability is revoked in a nested block, `%chain.env` inside that block is `null` and reverts on block exit.
