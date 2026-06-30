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
