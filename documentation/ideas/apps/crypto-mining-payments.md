# Crypto Mining as a Payment System

<a id="status"></a>
## 1 Status

Future consideration. Not part of early versions.

---

<a id="overview"></a>
## 2 Overview

Charlie's sandbox, trust policy, and blockchain integration make it a natural platform
for a generalised opt-in compute payment system. Any two parties can use it: a user pays
for a service by donating compute time; the recipient verifies and records the work on
the blockchain.

This is not specific to kiera.uno. Any site can offer it, accept it, or build on top of
it using a standard Charlie library.

---

<a id="how-it-works"></a>
## 3 How It Works

1. A site offers something in exchange for compute time — a service, credits, a free
   tier, a charitable donation.
2. The user agrees explicitly. The mining session is clearly marked as such in the UI.
3. The Charlie runtime executes the mining library in a sandboxed environment for a
   defined duration. The sandbox enforces the time limit; the user's machine cannot be
   exploited beyond what was agreed.
4. The completed work is verified and recorded on the blockchain. Both parties can audit
   the transaction.
5. The site delivers whatever was promised.

---

<a id="why-charlie-is-a-good-fit"></a>
## 4 Why Charlie Is a Good Fit

- **Sandbox** — secure, time-limited execution. Mining runs in a controlled environment
  with explicit permissions. The trust policy governs what the mining code is allowed
  to do.
- **Timeouts** — `%timeout` is already a first-class language feature. Mining sessions
  are naturally expressed as timed blocks.
- **Blockchain** — already part of the Kiera ecoverse for object signing and trust. The
  same infrastructure can record and verify compute payments.
- **Standard library** — a single well-known mining library means users recognise and
  trust the interface. Sites do not roll their own.
- **Transparency** — any object intended for crypto mining must explicitly declare itself
  as such (see official docs). There is no hidden mining. Failure to properly identify
  a crypto mining object is an ethical violation.

---

<a id="use-cases"></a>
## 5 Use Cases

- **kiera.uno services** — pay for signed object publishing by donating compute time
  instead of money.
- **Free tiers** — SaaS products offer a free tier funded by optional mining sessions.
- **Game credits** — earn in-game currency by running a mining session.
- **Charitable compute** — donate CPU cycles to a cause (protein folding, climate
  modelling, etc.) in exchange for something.
- **General payments** — any two parties can exchange compute time for anything they
  agree on.

---

<a id="open-questions"></a>
## 6 Open Questions

- **What is actually mined?** Pure proof-of-work hashing is verifiable but wasteful.
  Useful work (protein folding, AI training, rendering) is a better story but harder
  to standardise. Worth exploring both.
- **Exchange rate** — how much compute equals how much value? Needs to be defined and
  stable enough to be practical.
- **Verification** — how does the recipient confirm the work was done honestly and not
  faked? The blockchain handles recording but the proof-of-work mechanism needs design.
- **Legal exposure** — compute-for-payment has regulatory implications in some
  jurisdictions. Get legal advice before launching.
- **Energy consumption** — users should have visibility into how much power a session
  uses. May need a disclosure requirement.

---

<a id="relationship-to-trust-policy"></a>
## 7 Relationship to Trust Policy

Mining sessions run under the standard trust policy. A mining object must declare itself
as such (setting TBD). The engine can enforce a default maximum duration for mining
sessions on untrusted code — preventing surreptitious crypto mining is the same mechanism
that defines the ceiling for legitimate sessions. See [trust-policy.md](../security/trust-policy.md).
