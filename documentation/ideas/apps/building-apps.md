# Building Apps on Mikobase

<a id="outbound-post-queue"></a>
## 1 Outbound POST Queue

When an app writes to a remote mikobase over HTTP, it should treat outbound worldlet deltas
as a queue of pending POSTs rather than fire-and-forget calls. If the connection is
unavailable, the delta waits in the queue and is delivered when connectivity is restored.

This is standard infrastructure. Most app platforms already provide a reliable outbound queue
(Sidekiq, Celery, SQS, etc.) — there is no need to build one into Kiera. Use whatever
queuing system your platform provides.

The mikobase POST endpoint is safe to retry without any special server-side handling. If a
history entry already exists with identical content, it is skipped silently. If the entire
payload was already delivered, the POST is a no-op. This idempotency guarantee means retries
are always safe.

**The contract:**

- The app is responsible for queuing outbound deltas and retrying on failure.
- The server guarantees idempotent receipt — retrying a previously delivered worldlet is
  always safe.
- The queuing mechanism itself is left to the app and its platform.
