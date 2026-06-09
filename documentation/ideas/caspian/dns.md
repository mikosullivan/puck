# DNS resolution (post-V1.0)

~~~vibecode
{"vibecode": {
	"doc": "network_dns",
	"role": "post-V1.0 spec for Caspian's explicit DNS resolution methods on %net — forward and reverse lookups, per-record-type queries. Moved here from the V1 network/ tree because the explicit DNS slot is deferred. Basic name resolution still happens implicitly in V1 when sockets and HTTP client connect by hostname; what's deferred is the programmatic resolver API.",
	"parent_doc": "ideas/index.md",
	"status": "post-V1.0 — design preserved; not in V1.0 scope",
	"v1_fallback": "name resolution happens implicitly via the OS when sockets and HTTP client connect by hostname; no programmatic resolver in V1",
	"surface": "%net.resolve, %net.reverse_resolve",
	"audience": "future Caspian programmers needing programmatic name resolution",
	"key_concepts": ["forward_and_reverse_resolution",
		"per_record_type_queries",
		"available_with_any_network_grant",
		"does_not_check_allowlist_on_lookup",
		"deferred_from_v1_dot_zero"]
}}
~~~

**Post-V1.0.** The DNS slot was moved out of the V1 network spec tree. V1 scripts that need name resolution still get it implicitly — sockets and the HTTP client accept hostnames and the OS resolves them under the hood. What's deferred is the **programmatic resolver** below (the ability to do `%net.resolve(...)` directly, with per-record-type queries, custom resolvers, etc.).

The spec below is preserved as design intent for when this lands post-V1.

---

DNS resolution methods on `%net`. Forward lookup (`%net.resolve`) and reverse lookup (`%net.reverse_resolve`); per-record-type queries via the second argument.

---

<a id="surface"></a>
## API

```
$ips = %net.resolve('foo.com')           # array of IP strings
$name = %net.reverse_resolve('1.2.3.4')   # PTR record or null
```

| Method | Returns | Purpose |
|---|---|---|
| `%net.resolve(host)` | array of strings | A and AAAA records; one or more IPs |
| `%net.resolve(host, type)` | array of strings | Specific record type: `:a`, `:aaaa`, `:mx`, `:ns`, `:txt`, `:cname`, `:srv` |
| `%net.reverse_resolve(ip)` | string or null | PTR record |

---

<a id="permission-interaction"></a>
## Permission interaction

DNS resolution is itself a network operation but it's special — many use cases (logging, diagnostics, `--allow-net` allowlist checking itself) need DNS even when the script has no other network access.

**Default behavior:** DNS is available whenever any `--allow-net` flag has been given (any host), as a side effect. A `--no-dns` flag (TBD) could disable it for paranoid environments.

`%net.resolve` does NOT check the per-host allowlist on each lookup — the lookup itself doesn't contact the named host, only the system resolver. Only actual connections check the allowlist.

---

<a id="exceptions"></a>
## Exceptions

| Class | When |
|---|---|
| `puck.uno/error/network/dns_failure` | DNS resolution failed (NXDOMAIN, server unreachable, malformed query, etc.) |

---

## See also

- [Network index](index.md) — top-level `%net` surface, I/O model, full exception class table, permission model.
- [Raw sockets](sockets.md) — uses DNS implicitly on outbound connect.
- [HTTP](http.md) — uses DNS implicitly when fetching URLs.
