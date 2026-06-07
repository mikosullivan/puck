# SMTP — sending email

~~~json
{"vibecode": {
	"doc": "network_smtp",
	"role": "spec for Caspian's SMTP-send client — puck.uno/smtp/client. The primary email-send class. Built on the raw socket layer with STARTTLS for TLS. Receiving email (IMAP/POP3) is post-V1.0 and stubbed at the bottom.",
	"parent_doc": "network/index.md",
	"classes": ["puck.uno/smtp/client"],
	"open_question": "smtp_direct_vs_provider_api_as_primary_surface_see_issue_579",
	"audience": "Caspian programmers sending email from scripts",
	"key_concepts": ["smtp_direct_send_client",
		"starttls_default_on",
		"message_hash_form",
		"receiving_email_post_v1"]
}}
~~~

The primary email-send client. Sketched; design conversation needed on the open questions (provider-API vs SMTP-direct as the default, attachment handling, MIME encoding details — see [#579](https://github.com/mikosullivan/puck/issues/579)).

See [the network index](index.md) for the top-level `%net` surface, the permission model, and the cross-cutting exception classes.

---

<a id="client"></a>
## `puck.uno/smtp/client`

```
$mail = %puck['puck.uno/smtp/client'].new(
    host: 'smtp.example.com',
    port: 587,
    user: 'noreply@example.com',
    password: %env['SMTP_PASSWORD'],
    starttls: true
)

$mail.send(
    to:      'alice@example.com',
    from:    'noreply@example.com',
    subject: 'Build complete',
    body:    'Your build succeeded.'
)
```

**Methods:**

| Method | Returns | Purpose |
|---|---|---|
| `.send(message)` | nil | Send a message hash |
| `.send_message(message_obj)` | nil | Send a `puck.uno/email/message` object |
| `.verify(address)` | boolean | Server-side address verification (rarely supported) |
| `.close` | nil | Close the connection |

**Construction options:**

| Option | Default | Description |
|---|---|---|
| `host` | required | SMTP server hostname |
| `port` | 587 (TLS) or 25 | Port |
| `user` / `password` | none | Auth credentials |
| `starttls` | `true` | Upgrade to TLS via STARTTLS |
| `auth` | `:auto` | Auth mechanism: `:plain`, `:login`, `:cram_md5`, `:auto` |
| `timeout` | 30 | Per-operation timeout |

**Message shape** (hash form):

| Key | Type | Required |
|---|---|---|
| `to` | string or array | yes |
| `from` | string | yes |
| `subject` | string | yes |
| `body` | string | yes (or `body_html`, `body_parts`) |
| `body_html` | string | optional |
| `body_parts` | array of part hashes | optional (multipart) |
| `cc` | string or array | optional |
| `bcc` | string or array | optional |
| `reply_to` | string | optional |
| `headers` | hash | optional, additional headers |
| `attachments` | array of attachment hashes | optional |

---

<a id="receiving-email"></a>
## Receiving email — `puck.uno/imap/client`, `puck.uno/pop3/client`

Stubs. Likely post-V1.0. Most scripts that need email need to SEND; receiving is a smaller use case and IMAP/POP3 are larger protocols. Tracked under the [post-V1 protocol enumeration issue](https://github.com/mikosullivan/puck/issues/578).

---

## See also

- [Network index](index.md) — top-level `%net` surface, I/O model, exception classes, permission model.
- [Raw sockets](sockets.md) — the foundation SMTP is built on (TCP + STARTTLS).
- [#579](https://github.com/mikosullivan/puck/issues/579) — SMTP-direct vs provider-API as the V1.0 primary surface.
- [#578](https://github.com/mikosullivan/puck/issues/578) — post-V1 protocol enumeration including IMAP/POP3.
