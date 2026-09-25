# Phase 7F — End-to-End Encryption: Decision & Design

**Status:** **DECISION — DEFERRED.** No implementation in this phase.
**Reviewed against:** `main` @ `68b5e55` (sync 7A–7E complete and wired)
**Date:** 2026-09-25

> Phase 7F is a **decision gate** (see the roadmap in
> [`PHASE_7_CLOUD_SYNC_DESIGN.md`](PHASE_7_CLOUD_SYNC_DESIGN.md)): implement only when the
> gate condition — *"legal/privacy requirement demonstrated"* — is actually met. This document
> records the decision and, if the gate is ever satisfied, the design to follow.

---

## 1. Decision

**Deferred.** Rationale, in order of weight:

1. **The gate is not met.** No concrete legal, contractual, or user-privacy requirement has been
   demonstrated. Building key management without one is speculative cost.
2. **Cost sits in key management, not in the cipher.** The crypto itself is a few hundred lines;
   the *passphrase UX, recovery, and "I lost my key" support burden* is the real work — and an
   irrecoverable-data failure mode is a serious product risk for a notes app.
3. **It only changes the *remote* trust assumption.** Notes are stored in **plaintext** locally
   (`%APPDATA%\StickyNotes`). E2E protects the remote object store; it does nothing against a
   compromised local machine, which is the more likely threat for a desktop sticky-notes app.
4. **The folder backend is often already provider-protected.** For Drive/Dropbox/OneDrive, the
   remote is typically the user's own account with the provider's own (server-side) encryption.

**Revisit trigger:** an actual requirement (e.g. a compliance obligation, a customer demand, or a
decision to use an untrusted/unmanaged WebDAV host).

---

## 2. Threat model (what E2E would and would not buy)

| Scenario | E2E helps? |
|---|---|
| Remote object store is read by someone who shouldn't (host operator, shared host, leaked backup of the remote) | **Yes** — content is ciphertext |
| Remote is tampered with in transit or at rest | **Yes** — an AEAD tag detects modification |
| Local machine compromised / malware reads `%APPDATA%` | **No** — local storage stays plaintext |
| Attacker obtains the passphrase | **No** |
| Metadata (which notes exist, sizes, timing) | **No** — see §5.4 |

The honest summary: **E2E raises the bar for the remote only.**

---

## 3. What a remote object contains today (metadata leakage)

Objects are stored one-per-file named `<note-guid>.json` (`TFolderSyncBackend.PathFor`), and the
payload is the **full note record** — verified in `uJsonStorage.NoteToJson`:

`Title`, `Content`, `Color`, geometry, flags, `tags`, `checklistItems`, plus the sync identity
(`Guid`, `Rev`, `DeviceId`, `Deleted`, `DeletedAt`, `ConflictOf`).

So even with content encrypted, a remote observer still learns: **the set of note guids, the note
count, object sizes, and modification times**. Encryption must be understood as protecting
*content*, not *existence*.

---

## 4. Available crypto in this toolchain (important constraint)

Checked against the installed Delphi 12 toolchain:

| Unit | Present? | Notes |
|---|---|---|
| `Winapi.WinCred` | **Yes** | already used by `uCredentialStore.pas` for credential storage |
| `WinAPI.Security.Cryptography` | **Yes** (`.dcu`) | a CNG wrapper unit — API must be verified before use |
| `Winapi.BCrypt` / `Winapi.Wincrypt` | **Not found** (no source or `.dcu` in the searched paths) | so the commonly cited `BCryptEncrypt` / `CryptProtectData` route is **not** a safe assumption here |

**Consequence — an implementation risk to note up front:** any 7F work must *first* verify which
cryptographic API is actually available (or vendor a small, well-reviewed AES-GCM implementation /
add a maintained third-party library such as DCPcrypt or TurboPower LockBox). This is exactly the
class of blind-API risk that made the WebDAV transport slow to get right — budget for it.

**DPAPI note:** `CryptProtectData` (if available) encrypts *to the current user/machine*. That is
useful for **at-rest** protection but is **not** end-to-end encryption across devices — a second
device cannot decrypt. Do not conflate the two.

---

## 5. Design (if the gate is opened)

### 5.1 Cipher
**AES-256-GCM** (AEAD). Authenticated encryption gives confidentiality **and** tamper detection in
one primitive, and a wrong-key or modified object fails cleanly (no "decrypts to garbage and
overwrites the note").

### 5.2 Key derivation
- **PBKDF2-HMAC-SHA256**, 32-byte output, **16-byte random salt per vault**, high iteration count
  (OWASP-style baseline; tune to ~250 ms on target hardware).
- Derived **once per session**; held in memory only. Never written to disk or `settings.ini`.
- Optional convenience: cache the *passphrase* (not the key) in the Windows Credential Manager via
  the existing `ICredentialStore`, opt-in and user-clearable.

### 5.3 Envelope (what the remote stores)
The note payload is encrypted and wrapped:

```json
{
  "v": 1,
  "alg": "AES-256-GCM",
  "kdf": "PBKDF2-SHA256",
  "salt": "<base64, 16 bytes>",
  "iters": 600000,
  "nonce": "<base64, 12 bytes, fresh per write>",
  "ct": "<base64: ciphertext || 16-byte GCM tag>"
}
```

- `v` is the envelope version → future-proof, mirrors the note `schemaVersion` discipline.
- The **nonce must never repeat** for a given key; generate 12 random bytes per write.

### 5.4 What is not protected
Object names (= guids), object count, sizes, and mtimes remain visible. Padding objects to a coarse
size bucket could reduce size leakage, but that is a separate, optional hardening step.

### 5.5 Integration point
Encrypt/decrypt **only at the sync boundary** — `TSyncEngine` wraps each payload read/write with an
`ICipher`:

- **Local storage is unchanged** (plaintext, existing schema).
- The vault records `encrypted: true` in `sync-state.json`.
- Reading an object whose envelope `v` is unknown or whose `alg` differs → **skip + warn**, never
  overwrite (same policy the engine already applies to unreadable remote payloads).

---

## 6. Failure modes to handle explicitly

| Failure | Required behaviour |
|---|---|
| Wrong passphrase | Decrypt fails → skip the object, warn, **never** overwrite; repeatable |
| Tampered object | GCM tag mismatch → skip + warn |
| **Mixed vault** (some plaintext, some encrypted) | Refuse to sync the vault and warn loudly — never silently downgrade |
| Lost passphrase, no recovery key | Data on the remote is unrecoverable — must be an **informed, explicit** choice |
| Interrupted migration | Each object is independent; partial state is resumable |

---

## 7. Phased plan (only if green-lit)

| Phase | Scope | Notes |
|---|---|---|
| **7F.1** | Verify available crypto API; `ICipher` + AES-256-GCM implementation + tests | **Blocker first.** Round-trip, tamper, wrong-key, nonce-uniqueness tests |
| **7F.2** | Envelope + `TSyncEngine` integration (encrypt on write, decrypt on read) | Testable entirely with the **folder backend** — no server needed |
| **7F.3** | Passphrase UI (prompt, optional credential-store cache) + recovery-key flow | The UX/recovery burden — the actual cost |
| **7F.4** | Vault migration: encrypt existing remote objects on first use | Resumable, per object |

---

## 8. Test plan (7F.1–7F.2)

- Encrypt → decrypt round-trips the exact payload bytes.
- Decrypt with the wrong key **fails** and returns no plaintext.
- A single flipped ciphertext byte **fails** authentication.
- The same plaintext encrypted twice yields **different** ciphertext and **different** nonces.
- Envelope with an unknown `v` / `alg` is **rejected**, not misinterpreted.
- Engine: with encryption on, a push writes an envelope and a pull restores the original note —
  verified end-to-end against the folder backend, exactly like the existing sync tests.

---

## 9. Open questions

1. **Recovery model:** a one-time recovery key (shown at setup), or explicit "no recovery"? A notes
   app that silently loses data is worse than one that stores plaintext on the user's own cloud.
2. **Encrypt the local at-rest copy too?** Different threat model (machine compromise); DPAPI could
   cover it, but it is not E2E.
3. **Passphrase caching policy:** every launch? Per session? Credential Manager by default?
4. **Should the vault be per-backend?** A user switching folder ↔ WebDAV with different passphrases
   needs the state to be per-backend, not a single global flag.

---

## 10. Decision record

| Date | Decision | Reason | Revisit when |
|---|---|---|---|
| 2026-09-25 | **Deferred** | Gate ("legal/privacy requirement demonstrated") not met; cost is key management, benefit is remote-only | A concrete requirement appears, or the remote becomes an untrusted host |
