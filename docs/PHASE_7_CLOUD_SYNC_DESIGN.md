# Phase 7 — Cloud Sync: Design Analysis

**Status:** Design document only — **no implementation, no source changes.**
**Author:** engineering
**Reviewed against:** `main` @ `1da05d2` (Phase 6M/6N complete; schema v3; `INoteManager` extracted)
**Date:** 2026-09-25

> This follows the project's own discipline (see the Phase 3C SQLite analysis): decide the
> design and its decision gates **before** writing code, and justify each choice with
> evidence from the source tree rather than assumption.

---

## 1. Executive summary

Cloud sync is the project's Phase 7. It is **not** "a new `INoteStorage` backend" — the hard
part is not where bytes live, it is **identity, deletion, and conflict resolution across
independently-edited replicas**. Storage is already abstracted and portable, so the work is to
add (a) a globally-unique note identity, (b) tombstones, (c) a revision-based reconcile step,
and (d) a pluggable transport.

**Recommendation (to be ratified by the decision gates in §9):**

- Offline-first, **manual-then-automatic** sync. The UI is never blocked.
- Interchange format = **the existing JSON note payload** (schema-versioned, diffable), *not*
  the SQLite file. SQLite stays a local cache/optimisation.
- New plugin boundary `ISyncBackend`; first reference implementation = **WebDAV/Nextcloud**
  (real `ETag`-based conflict detection, no vendor lock-in), with a **shared-cloud-folder**
  backend as the low-effort fallback for Drive/Dropbox/OneDrive.
- Conflict policy = **last-writer-wins per note, decided by a monotonic `rev`, with `updatedAt`
  only as a tie-break**, and **never discard the loser** (keep a conflict copy).
- **Device-local fields are not synced** (see §6 — window geometry).

Explicitly deferred: a bespoke server backend, real-time collaboration, and CRDT text merge.

---

## 2. What the current architecture already gives us (evidence)

| Capability | Where | Consequence for sync |
|---|---|---|
| 6-method storage seam | `INoteStorage` (`src/Storage/uStorage.pas`) | A sync engine can read/write notes without knowing the local backend |
| Portable, versioned payload | JSON per note, `schemaVersion` (`uJsonStorage.pas`) | Sync operates on JSON notes; versioned readers tolerate old/new files |
| Offset-aware timestamps | `uIso8601.pas` (`+hh:mm` / `Z`, legacy-naive tolerated) | Usable for LWW — but see clock-skew risk (§4.4) |
| Format-agnostic backup | ZIP backup/restore (`uBackupService.pas`) | Sync metadata rides along automatically |
| Placeholder enum | `TStorageType.stCloud` (`uEnums.pas`) | The concept was anticipated; no wiring exists yet |
| Versioned SQLite schema | `NoteSchemaVersion` + `PRAGMA user_version` (`uSQLiteStorage.pas`) | A v4 migration has a defined, tested home |

**Not yet available (the actual gaps):** global note identity, tombstones, revision ordering,
and any transport.

---

## 3. The four hard problems

### 3.1 Identity — local IDs collide across devices
`TJsonStorage.GetNoteFileName` writes `Format('%.10d.json', [AID])` and `GetNextID` is
`max(existing) + 1` (`uJsonStorage.pas`). Two devices each creating their fifth note both
produce `0000000005.json` with **different content** — a silent overwrite if those files meet
in a shared folder.

→ **Requires a stable, globally-unique identity** independent of the local integer.

### 3.2 Deletion — an absent file is ambiguous
`DeleteNote` removes the file. On a shared folder, "file absent on B" cannot be distinguished
from "note never existed on B there" versus "note was deleted on A". Naïve polling **resurrects
deleted notes** and **resurrects deleted-and-recreated IDs**.

→ **Requires tombstones** (`deleted` + `deletedAt`) that themselves sync.

### 3.3 Conflicts — the same note edited on two devices
Options, cheapest first:

| Policy | Behaviour | Fit |
|---|---|---|
| Last-writer-wins **per note** | Whole note replaced by the higher revision | **Recommended first** — matches sticky-note semantics |
| LWW **per field** | Independent fields merge (e.g. colour vs body) | Later refinement; add only if LWW proves too lossy |
| 3-way merge | Needs a base revision per replica | Only if body-text merging is demanded |
| CRDT (per-character) | Concurrent text merges without conflict | Over-engineering for sticky notes; **non-goal** |

The current note model (`uNote.pas`: title, content, colour, geometry, flags, tags, checklist)
is a whole-object replace under LWW; there is **no per-field edit tracking** today, so LWW-per-note
is the only policy that needs no new bookkeeping.

### 3.4 Clocks — LWW needs trustworthy ordering
LWW keyed on `updatedAt` breaks under device clock skew, and this project has **already been
bitten by a timestamp bug** (see `CODE_REVIEW_2026-09-17` C1). `updatedAt` is a wall clock, not
an order.

→ **Order by a monotonic per-note `rev` (integer), not by wall-clock time.** Use
`updatedAt` only to break ties, and optionally add a Hybrid Logical Clock later if multi-device
ordering proves insufficient.

---

## 4. Proposed data model (schema v4 — proposal, not implemented)

Add to **each note payload** (JSON field, and SQLite column):

| Field | Type | Purpose |
|---|---|---|
| `guid` | string (UUIDv4/ULID) | Stable global identity; replaces reliance on the local `ID` |
| `rev` | integer (monotonic) | Authoritative conflict ordering; bumped on every local edit |
| `deviceId` | string | Which device produced the current `rev` (diagnostics / tie-break) |
| `deleted` | boolean | Tombstone — the note is logically deleted but still syncs |
| `deletedAt` | ISO-8601 | Tombstone age → enables safe tombstone retention/GC |

**Compatibility:** this is purely *additive*. The project's established policy (Phase 3B,
reused in 6A) is **"default rather than reject"**: a v3 file without `guid`/`rev` is read with
sentinels; `guid` is generated on first save/sync; `rev` starts at 0; `deleted` defaults false.

**Version bumps:** `NoteSchemaVersion` 3 → 4 (JSON `schemaVersion`); SQLite
`PRAGMA user_version` 3 → 4 via `ApplySchemaMigrations` (`ALTER TABLE notes ADD COLUMN ...`) —
the migration hook that Phase #3 landed exists precisely for this.

---

## 5. Proposed architecture

```
TNoteApplication (composition root, owns lifetime)
  └── TSyncEngine                     (orchestration; implements ISyncService)
        ├── local side:  INoteManager / INoteStorage  (read + reconcile writes)
        └── remote side: ISyncBackend                 (transport abstraction)
                          ├── TFolderSyncBackend      (Drive/Dropbox/OneDrive local folder)
                          ├── TWebDavBackend          (first reference impl — ETag conflict detection)
                          └── TApiBackend             (later; per-provider SDK)
```

- **`ISyncService`** (proposed in `uServiceInterfaces.pas`, alongside the other service
  interfaces): `SyncNow`, `GetStatus`, plus `OnProgress` / `OnComplete` events — mirroring the
  existing `IBackupService` shape so the UI wiring is familiar.
- **`ISyncBackend`**: `Pull`, `Push`, `List`, `GetMetadata` (ETag/revision). Swapping the
  backend never touches the engine — the same "drop-in" property `INoteStorage` already gives us.
- **Interchange = the JSON note payload.** SQLite is a *local* cache; its `.db` file is opaque
  and must never be the synced artefact.
- **What is synced vs not:**

  | Synced | Device-local (never synced) |
  |---|---|
  | title, content, colour, tags, checklist, favorite, locked | **window geometry** (`Left/Top/Width/Height`), collapsed state |

  Geometry is device-specific (screen layout; the app already clamps to a monitor work area on
  load). Syncing it would fling windows to coordinates that mean nothing on another machine.

  **Never place in the shared location:** `vnotes.db*`, `vnotes.log*`, `settings.ini`,
  `backups/` — provider file-sync would corrupt or churn them.

- **Reconcile algorithm (per note, by `guid`):**
  1. If remote `deleted` and remote `rev` > local `rev` → delete locally (keep tombstone).
  2. If local `rev` > remote `rev` → push.
  3. If equal `rev`, differing content → tie-break on `updatedAt`, then `deviceId`; **write the
     loser to a conflict copy** (`<title> (conflict from <deviceId>)`), never drop it.
  4. New `guid` seen only remotely → add locally.
  5. `guid` seen only in a tombstone → propagate the delete.

---

## 6. Provider options (trade-off)

| Option | Effort | Conflict detection | Notes |
|---|---|---|---|
| **A. Shared cloud folder** (Drive/Dropbox/OneDrive) | Lowest | Weak (provider-dependent, no ETag) | Reuses the project's existing "JSON is Dropbox-friendly" value; good first demo, poor guarantees |
| **B. WebDAV / Nextcloud** | Medium | Strong (`ETag` + `If-Match`) | **Recommended first reference backend** — real conflict detection, no vendor lock-in, self-hostable |
| **C. Provider SDK/API** (Drive/Dropbox) | High | Strong (change feeds) | Per-provider OAuth + code; only if users demand it |
| **D. Custom backend** | Highest | Full control | **Explicitly deferred** — decision gate, not a starting point |

Design `ISyncBackend` so A, B, C are all expressible; ship B first.

---

## 7. Security

- **Credentials** must never land in `settings.ini`, notes, or the shared folder. Use the OS
  credential store (Windows Credential Manager / DPAPI) behind a small `ICredentialStore`.
- **Transport:** HTTPS/TLS only; reject plain HTTP.
- **End-to-end encryption** (client-side, before upload): a decision gate — the app currently
  stores **plaintext JSON** locally, so E2E only helps against the remote, not a compromised
  local machine. Non-trivial (key management/recovery); defer until a provider is chosen.
- **Scope:** sync only note payloads; never logs, backups, credentials, or the local DB file.

---

## 8. Compatibility & migration

- **Additive v4 reader** (default-not-reject) — no migration framework needed for the new fields.
- **SQLite:** `ApplySchemaMigrations` handles `user_version` 3 → 4 (`ADD COLUMN`).
- **Cross-version interop:** an older client reading a v4 JSON file ignores unknown fields (safe);
  a newer client reads a v3 file with sentinels and upgrades it on next save.
- **Backup:** tombstones are included in backups (so a restore doesn't resurrect deleted notes).

---

## 9. Phased plan with decision gates

| Phase | Scope | Gate before starting |
|---|---|---|
| **7A** | Identity + schema v4 (`guid`, `rev`, `deviceId`, `deleted`, `deletedAt`) — no network | Only if sync is committed; otherwise this is speculative |
| **7B** | `ISyncBackend` + `TFolderSyncBackend`, manual "Sync now", LWW-per-note | 7A landed |
| **7C** | Conflict surfacing (conflict copies + replace/discard UI) | Real conflicts observed in practice |
| **7D** | Background/interval sync + tray status (mirrors the backup scheduler UX) | 7B/7C stable |
| **7E** | `TWebDavBackend` with `ETag`/`If-Match` | A provider target is chosen |
| **7F** | End-to-end encryption | Legal/privacy requirement demonstrated — **decided: deferred** ([PHASE_7F_ENCRYPTION_DESIGN.md](PHASE_7F_ENCRYPTION_DESIGN.md)) |

Each gate is evidence-driven (matches the project's existing decision-gate discipline) — do not
front-run later phases.

---

## 10. Open questions

1. **Which provider first?** WebDAV/Nextcloud (recommended) vs a consumer cloud folder.
2. **Single-note-set vs per-device notes?** Are all notes shared, or only some? (Affects UX: 7 §5 assumes a single shared set.)
3. **Tombstone retention window** before GC (e.g. 90 days) and whether it is user-configurable.
4. **Does `favorite`/`locked`/theme sync, or stay local?** (Currently proposed as synced.)
5. **Is body-text merging ever required?** If yes, revisit conflict policy toward 3-way merge.

---

## 11. Non-goals

- Real-time collaborative editing.
- CRDT per-character text merge.
- A bespoke server backend (unless gate D is consciously chosen).
- Syncing window geometry or other device-local state.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| LWW silently drops a concurrent edit | Never discard the loser — write a conflict copy |
| Device clock skew corrupts ordering | Order by `rev`, not wall-clock; `updatedAt` is tie-break only |
| Provider file-sync touches the DB/log/backups | Keep those out of the shared set; sync only note payloads |
| Credential leakage | OS credential store; never in settings/notes |
| Identity collisions persist for pre-v4 notes | Backfill `guid` for all existing notes in 7A before any push |
