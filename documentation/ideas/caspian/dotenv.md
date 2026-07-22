# dotenv

~~~vibecode
{"vibecode": {
	"doc": "ideas_dotenv",
	"role": "note on a possible `caspian.uno/dotenv.casp` class for loading `.env` files. Not V1, but the idea is saved here so the design isn't lost when we revisit standard-library scope later.",
	"status": "deferred — nice to have, not V1"
}}
~~~

`.env` files are the widespread dev-tooling convention: a plain-text file at project root with `KEY=value` lines holding local secrets and per-dev overrides that don't belong in version control. Committed as `.env.example` (a template); the real `.env` is `.gitignore`d.

```
DATABASE_URL=postgres://localhost/dev
STRIPE_KEY=sk_test_...
DEBUG=true
```

## Shape

A first-party download at `caspian.uno/dotenv.casp` that parses a `.env` file and returns a hash. That's it. No mutation of the running process's environment — the program decides what to do with the returned hash.

```caspian
$env = %['caspian.uno/dotenv.casp'].load('.env')
$db_url = $env.DATABASE_URL
```

Merge into config, feed into a database connector, whatever — the class stays out of the way. Rationale for return-a-hash: `%chain.env` is Caspian's read-only view of the real process environment. Silently splatting a `.env` file into it would make debugging "where did this value come from?" harder and give dotenv paternalistic control over the process — the "return a hash" shape puts that decision on the caller (fits the no-nanny-code stance).

## Why not V1

Genuinely useful, but every real project ends up wiring config into its own layer rather than calling a dotenv parser directly. Not urgent enough to spend V1 scope on. When someone actually needs it, the class is a fifty-line parser sitting behind `%[...]` — takes an afternoon to write.
