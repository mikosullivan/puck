# openssl wrapper

*Spec for the Caspian class at `https://puck.uno/linux/cl/openssl.casp` — a wrapper around the `openssl` CLI utility. Scoped narrowly to what the [Passkey subsystem](../secure-memory/passkey/) needs: verify an ES256 or RS256 signature over a message using a supplied public key. Anything beyond that (encryption, key derivation, TLS, other subcommands) is a later addition. Sibling of the [tar wrapper](tar).*

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_linux_support_openssl",
	"role": "spec for the Caspian class at https://puck.uno/linux/cl/openssl.casp — a command-builder wrapper around the openssl CLI utility. Scope is deliberately narrow: verify an ES256 or RS256 signature (the two WebAuthn algorithms libsodium doesn't cover) for the Passkey subsystem. Wrapper does not link a crypto library — it builds a command and hands it to .execute, which runs openssl directly (subprocess, no shell). Second entry in linux-support/ after tar.",
	"status": "spec — invocation shape (openssl pkeyutl -verify with key material via stdin / mode-600 temp files, never argv) and the operator-prerequisite posture settled; exact API property names deferred; other openssl subcommands (encrypt, dgst, x509, ...) are post-V1 additions"
}}
~~~

## What it wraps

Two openssl invocations cover ES256 / RS256 signature verify for WebAuthn:

- `openssl pkeyutl -verify -inkey <pubkey.pem> -sigfile <sig.bin>` — raw signature verify over a message given on stdin.
- `openssl dgst -sha256 -verify <pubkey.pem> -signature <sig.bin>` — signed-digest verify (openssl computes the SHA-256 of the message and checks the signature against it).

Either works for WebAuthn; the wrapper picks one and sticks with it for consistency across algorithms.

## Wrapper responsibilities

- **Serialize the COSE_Key public key into PEM.** The passkey caller has the public key as a hash walked out of a CBOR-decoded COSE_Key structure. The wrapper builds the PEM blob openssl consumes. For ES256 the key is an EC point on P-256; for RS256 it's an RSA modulus + exponent.
- **Feed the message via stdin.** The message being verified (challenge || authenticatorData || clientDataJSON hash, per WebAuthn) is fed via stdin.
- **Feed the signature via a mode-600 temp file.** The `-sigfile` flag takes a path; the wrapper writes the signature bytes to a fresh temp file with mode 0600, passes the path, cleans up after `.execute` returns.
- **Never put key material or signatures on argv.** argv is visible in `ps` output on the same machine. Public keys and signatures aren't secret, but establishing the "never argv for cryptographic data" habit avoids mistakes when the same class gets extended to signing operations that DO handle secrets.
- **Parse the exit code.** `0` means "signature valid." Non-zero means "signature invalid OR openssl error." The wrapper distinguishes those — stderr indicates errors; a clean non-zero without stderr output is a verify failure. The Passkey layer needs the distinction (a verify failure is `puck.uno/passkey/error/signature_invalid`; an openssl error is an infrastructure problem, not a user-facing auth failure).

## Examples

Basic ES256 verify — the primary Passkey use case:

~~~caspian
%vibecode
	role: 'verify an ES256 passkey assertion signature';
end

$verify = %['https://puck.uno/linux/cl/openssl.casp'].new
$verify.algorithm = 'ES256'
$verify.public_key = $pem
$verify.signature = $sig
$verify.message = $signed_data

$result = %fs.cwd.execute $verify

if $result.status == 0
	# signature valid — continue
end
~~~

Distinguishing verify-failure from openssl-infrastructure error (the Passkey.verify path — the two failure modes raise different exception classes):

~~~caspian
%vibecode
	role: 'turn openssl exit code into the right passkey exception';
end

$result = %fs.cwd.execute $verify

if $result.status == 0
	# signature valid — continue
elsif $result.stderr != ''
	# openssl produced an error message — infrastructure, not an auth failure
	raise {kind: 'openssl_infrastructure', stderr: $result.stderr}
else
	# clean non-zero exit — signature rejected
	raise {kind: 'signature_invalid'}
end
~~~

For RS256, only `.algorithm` changes; everything else is identical:

~~~caspian
$verify.algorithm = 'RS256'
~~~

Property names above are illustrative; exact naming is a separate style pass (same caveat as [tar](tar)).

## `.execute`, not shelling out

`openssl` is invoked via `.execute` — a direct subprocess call with argv, not a shell command. Same posture as the [tar wrapper](tar): no shell parses the arguments, so quoting bugs and shell-injection risks don't apply. Argv values pass through as literal byte sequences; the temp-file path is the only path-shaped thing openssl sees. See [linux-support § Not literally shelling out](./#executing-files) for the general rule.

## Where openssl comes from

`openssl` is a documented Caspian prerequisite for the Passkey subsystem. On systems without it the passkey system will not work.

## Detection

At Caspian engine startup, the Passkey subsystem checks for `openssl` in the search path. If missing, the Passkey subsystem doesn't initialize; the first call from user code raises a clear "openssl not found — install it or configure the search path" error rather than a mysterious subprocess-launch failure. Same detection pattern as [luarocks](../lua/third-party).

## Timeout

An `openssl pkeyutl -verify` invocation should complete in milliseconds — for a stuck subprocess (mis-installed openssl, resource exhaustion, kernel weirdness), the wrapper aborts after a bounded timeout (≈5 seconds) rather than blocking the login flow indefinitely. Timeout hit surfaces as an openssl-infrastructure error, distinct from a verify failure.

## Related

- [linux-support](./) — the general model for Linux utility wrappers.
- [tar](tar) — sibling wrapper class for tarball extraction.
- [secure-memory/passkey/](../secure-memory/passkey/) — the primary consumer.
