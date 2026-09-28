# Phase 7G - Sync Reconcile Rewrite (WP5): Design Note

**Status:** DRAFT FOR REVIEW - no code written in this step (Step 0 of the Phase 7G plan; WP1..WP7 start after approval).
**Reviewed against:** `main` @ `f0d597b` (every claim below was re-verified against this tree, not copied from the review brief).
**Date:** 2026-09-28

> This note is the WP5 design. It replaces the reconcile logic of `uSyncEngine.pas`,
> removes deletion-by-absence inference, and defines the tombstone model, the local
> deletion journal, and `sync-state.json` v2. It refines the reconcile sketch in
> `docs/PHASE_7_CLOUD_SYNC_DESIGN.md` (S5) for the hardening work; where the two
> differ, this note governs WP5.

---

## 0. Why the rewrite - verified failure modes at f0d597b

| # | Current behaviour (verified in source) | Where | Consequence |
|---|---|---|---|
| A1 | Deletions are inferred from absence: any guid in `synced` that is not in the local snapshot is marked deleted and the remote object is **physically removed** | `uSyncEngine.pas` L329-340 | An empty or partial local load deletes remote notes (T7 model: 50 -> 0) |
| A2 | Equal-rev conflict: local content is kept and re-written to the remote **at the same rev**; the conflict copy gets `Guid := ''` (a fresh random identity, rev 1) | L410-425 | The other device sees the conflict again on its next run and spawns another copy; counts grow (A: 1,2,4,6 model) |
| A3 | The baseline (`FSynced`) is rebuilt from the **pre-pull** snapshot (`LocalOrder`); notes pulled during the run are not recorded | L452-454 | A note pulled and then deleted before the next sync is re-pulled (resurrects); its deletion is never propagated |
| A4 | Nothing ever produces a tombstone: no `Deleted := True` / non-zero `DeletedAt` exists anywhere in `src`; the fields are only carried through the codec | grep over `src/**/*.pas`; `uJsonStorage` reads/writes them, `CopySyncedFields` copies them | A deletion on A cannot reach B through the store; B just re-pushes the note |
| A5 | Deletion propagation is expressed only as a physical `Remove` of the remote object; the one durable record (`deleted` in sync-state) is consumed only to keep an already-removed guid removed, never to propagate a deletion | L329-340, `TSyncEngine.SaveState` (`deleted` list) | No way to distinguish "user deleted this" from "this was never loaded"; "edit beats delete" is unrepresentable |

What survives the rewrite unchanged: the JSON note codec (`TJsonStorage.NoteToJson/JsonToNote`),
the `ISyncBackend` shape, the runner/scheduler and their threading guarantees, ETag support in both
backends, and the existing test hygiene rules (temp sandboxes, `initialization` registration).

---

## 1. Definitions

- **Baseline (B):** per guid, the Rev recorded in `sync-state.json` as the last fully reconciled
  state for this replica. Absence of an entry = *unknown*, and unknown counts as *changed*.
- **changedL** = `(B unknown) or (revL > B)`; **changedR** = `(B unknown) or (revR > B)`.
- **Content signature:** the synced content fields (Title, Content, Color, AlwaysOnTop, Collapsed,
  Locked, Favorite, Tags, Checklist). Deliberately excludes geometry, ID, Guid, Rev, DeviceId and
  timestamps. Same field set as today's `TSyncEngine.ContentSignature`; WP3 moves it onto `TNote`.
  If WP3's open question (AlwaysOnTop/Collapsed device-local?) is answered "yes", the signature
  scope reduces accordingly - flagged for WP3, not decided here.
- **Version:** a specific `(content, rev, deviceId)` of a note's payload.
- **Tombstone:** a remote object, same JSON codec, with `Deleted = true` and `DeletedAt` set. It is
  the only remote representation of a deletion; objects are never physically removed by the engine
  (the old `Remove` path is gone; `ISyncBackend.Remove` stays for tests until a future GC uses it).
- **Deletion journal:** the local record of deletions that still need propagation (S4). Lives in
  its own file, not in `sync-state.json`, so I5 keeps its meaning for the baseline.
- **Deferred:** an operation the worker planned but could not apply (compare-and-set missed,
  `If-Match` failed). It is skipped, counted, and left for the next run.

---

## 2. Decision table (per guid)

Inputs: the local snapshot, the remote state, the baseline B, the journal. "Write" below means a
remote write, all guarded by the backend's ETag contract where the backend supports it (both
current backends do).

### 2.1 Both sides live

| Condition | Action | Write | Baseline after success |
|---|---|---|---|
| sigL == sigR, revL == revR | nothing | no | B := revL |
| sigL == sigR, revL > revR | push local payload (brings the remote to revL) | yes (If-Match) | B := revL |
| sigL == sigR, revL < revR | adopt revR locally (content already equal; persist without Touch) | no | B := revR |
| sigL != sigR, only remote changed | pull: content := remote (keep local geometry), Rev := revR | no | B := revR |
| sigL != sigR, only local changed | push local @ revL (If-Match) | yes | B := revL |
| sigL != sigR, both changed (or B unknown) | **conflict resolution, S3** | only if the winner is the local version; otherwise pull-only | B := R* (or revR in the pull-only case) |
| sigL != sigR, neither flag set | defensive: treat as a conflict (S3); log Warning. Unreachable with this build; protects against same-rev content swaps from older builds | as S3 | as S3 |

Changes vs the review brief, with justification:

- *"same content signature: align revs to the max"* needs a writer: when the local rev is ahead the
  remote is brought up (one If-Match write), when the remote rev is ahead the local adopts it (no
  write). Without an actual write, revs never equalise and every run would keep seeing "revL > revR"
  forever - I2 ("further syncs write nothing") could never hold.
- *Conflict publish rev* is made precise in S3: all conflict-branch writes go to
  `R* = max(revL, revR) + 1` - a strict bump above both revs - and when the winner is already the
  remote version at a strictly higher rev, the run performs no live-note write at all (see S3).

### 2.2 Remote absent

| Condition | Action | Write | Baseline |
|---|---|---|---|
| local live | push (If-None-Match: *) | yes | B := revL |
| local absent, in journal | drop the journal entry (no remote presence to delete; e.g. deleted before its first sync) | no | unchanged |
| local absent, not in journal | nothing (absence never deletes anything; a note removed remotely outside the app is simply gone here) | no | unchanged |

### 2.3 Remote is a tombstone

| Condition | Action | Write | Baseline |
|---|---|---|---|
| local absent | nothing; drop any stale journal entry for the guid | no | B := revT |
| local unchanged since B (revL == B) | delete locally (do **not** write a new tombstone) | no | B := revT |
| local changed, or B unknown, or revT <= B (stale-tombstone guard) | edit beats delete: push local live @ `max(revL, revT) + 1` (If-Match) | yes | B := pushed rev |

The `revT <= B` guard is defensive: a tombstone older than the common state contradicts it (revs
are monotone) and can only come from a hand-edited store or a foreign writer; re-asserting the live
note is the data-safe direction. Log a Warning when it fires.

### 2.4 Local absent, remote live

| Condition | Action | Write | Baseline |
|---|---|---|---|
| guid in journal, remote unchanged since B (revR == B) | write tombstone @ `rT = max(revR, journal.rev) + 1`; clear the journal entry | yes (If-Match) | B := rT |
| guid in journal, otherwise (revR != B, or B unknown) | edit beats delete: pull, clear the journal entry | no | B := revR |
| not in journal | new remote note: pull | no | B := revR |

This is the complete matrix: live/absent vs live/tombstone/absent. Every row ends a successful run
with the guid's baseline set to the rev actually verified, so a second run with no edits finds no
flags set and writes nothing.

---

## 3. Conflict resolution and the winner rule

### 3.1 Winner rule

Order the two versions by **(Rev desc, DeviceId desc, content hash desc)**. Both replicas compute
the same total order for the same pair, so both agree on the winner and the loser. The content
hash is a deterministic function of the payload (SHA-256 via the RTL `System.Hash` unit - no new
third-party dependency). Ties on the full triple are impossible for *different* content (hash
differs), so the order is total.

### 3.2 Publishing and the copy

Let `R* = max(revL, revR) + 1`.

- **Winner == local version:** write the remote := winner payload with `Rev := R*` (If-Match);
  set the local note's Rev := R* (content unchanged; persist without Touch).
- **Winner == remote version, revR > revL:** the winner is already remotely live at a strictly
  higher rev: pull it (Rev := revR). No live-note write.
- **Winner == remote version, revR == revL:** the remote object already carries the winner (the
  equal-rev tie-break picked it): pull it (Rev := revR). No live-note write. The winner device's
  own run is then a no-op (revs equal, signatures equal).

So a resolution writes the live object exactly when the winner is the local version; when the
winner is already remotely live (both sub-cases above), the resolution is a pull, and the ends
still meet: both sides end at equal revs with equal content.

**The loser copy.** The loser's content is preserved as a conflict copy with a *deterministic*
identity:

- `gC = SHA256(origGuid + '|' + loserDeviceId + '|' + IntToStr(loserRev))`, first 16 bytes rendered
  as lowercase hex, grouped `8-4-4-4-12` (the `GenerateNoteGuid` shape).
  **Binding for WP4:** `IsValidNoteGuid` must accept this canonical shape without version/variant
  nibble constraints, so deterministic copies validate.
- Copy payload: the loser's synced fields with
  `Title := loser.Title + ' (conflict from ' + Copy(loserDeviceId, 1, 8) + ')'` (same visible
  suffix as today's Phase 7C copies; deterministic because both sides derive it from the same
  loser), `Guid := gC`, `Rev := loserRev`, `DeviceId := loserDeviceId`,
  `ConflictOf := origGuid` (stays set; the Phase 7C dialog is unchanged), timestamps := the
  loser's (deterministic, not `Now`). Geometry is device-local and never compared: the creating
  device uses an offset (+30/+30), a pulling device uses the normal pull rule.
- **Creation is idempotent:** create gC locally only if no note with that guid exists locally and
  none appears in the remote listing; if it exists in either place, skip creation - the normal
  pull/push path reconciles it. Push with `If-None-Match: *`; a failed push defers (counted).
- Both devices can independently create gC (e.g. one side's push was deferred); because guid and
  payload are deterministic, the pair converges to exactly one copy object per replica.

### 3.3 Why it converges

1. **Monotone:** every write that changes remote content strictly increases the object's rev
   (pushes carry `revL > revR`; resolutions carry `R* >= max+1`; tombstones carry `rT >= B+1`).
   Revs never decrease anywhere.
2. **Deterministic:** winner order and copy identity are pure functions of the compared versions,
   so both replicas resolve the same pair to the same outcome (same winner content+rev, same gC).
3. **No residue:** after a resolution, the other side either sees a strictly higher rev (pull
   path) or equal revs with equal content signatures (no-op). The exact loop of A2 - same-rev
   rewrite -> re-detected conflict -> another random copy - is impossible: any rewrite that must
   move the remote goes to `max+1`, and the copy identity cannot be re-created under a new guid
   (create-if-absent + deterministic hash).
4. **Termination:** each run either aligns something (revs/content equalise), or advances the
   baseline, or defers with all state unchanged. Copy creation is bounded (one identity per
   conflict pair) and idempotent. So with no new edits the system reaches a fixed point after a
   bounded number of runs; further runs set no flags and write nothing (T2/T3).

**Mixed-version caveat:** an *old* build in the fleet (one that does same-rev rewrites and knows
nothing of tombstones) can force extra reconciliation rounds and can resurrect notes it holds; the
defensive row in 2.1 (sigs differ, no flags) helps but full correctness assumes all devices run
this build. Stated as a limitation; no cross-version negotiation is attempted.

---

## 4. Tombstones and the local deletion journal

### 4.1 Tombstone format

A tombstone is the canonical note JSON (schema v3 unchanged; the `Deleted`/`DeletedAt` fields have
existed since 7A). Shape (fields shown that differ from a normal note):

```json
{
  "schemaVersion": 3,
  "Guid": "<original guid>",
  "Rev": 12,
  "DeviceId": "<deleting device>",
  "Deleted": true,
  "DeletedAt": "2026-09-28T13:45:00.000+05:30",
  "Title": "", "Content": "", "Left": 0, "Top": 0, "Width": 0, "Height": 0,
  "tags": [], "checklistItems": []
}
```

- Written **only by the deleting device** (single writer; no cross-device determinism needed).
- `rT = max(revR, journal.rev) + 1`, written only when the remote is unchanged since B (`revR == B`),
  so `rT >= B + 1` always holds - every other device sees a strictly higher rev.
- Content fields are empty. Deliberate: the journal keeps no note text, so a tombstone cannot leak
  or restore content. (The old engine physically removed the object - same information loss, minus
  the deletion record.)
- Timestamps only via `uIso8601` (`DateTimeToStoredISO8601`); `DeletedAt` = the journal's deletion
  time.
- Written with If-Match against the read ETag; a failure defers and keeps the journal entry.

### 4.2 The local deletion journal

**Location:** `<profile>\sync-journal.json`, a sibling of `sync-state.json` (profile =
`TNoteApplication`'s AppData path; tests use their sandbox path). Rationale for a separate file:
`sync-state.json` is only written after a completed run (I5); the journal must be durable at
deletion time, even if the app never gets a successful sync. Two files, two lifetimes.

**Format:**

```json
{
  "version": 1,
  "deletions": {
    "<guid>": { "rev": 7, "deletedAt": "2026-09-28T13:45:00.000+05:30" }
  }
}
```

- `rev` = the note's Rev at the moment of deletion; `deletedAt` = wall clock at deletion
  (`uIso8601`).
- Written with WP4's `uAtomicFile.WriteTextAtomic`, with the same `.bak` fallback convention as
  `sync-state.json`; unreadable file -> log at Error, try `.bak`; both unreadable -> treat as empty
  + Error log (safe direction: nothing can be deleted wrongly; a deletion may merely fail to
  propagate until the user deletes again).
- `guid` keys are validated with `IsValidNoteGuid` at load; invalid entries are dropped with a
  Warning.

**Population.** Entries are recorded at the moment of a local note deletion, before the note
object is freed. Today `TNoteApplication.Initialize` wires `FNoteManager.OnNoteDeleted :=
FOnNoteDeleted`; that becomes an internal handler which (1) records `{guid, note.Rev, Now}` in the
journal when sync is configured, then (2) forwards to `FOnNoteDeleted` exactly as today. This also
records sync-driven deletions (applying a remote tombstone); those entries self-clean on the next
run via the 2.3 "local absent -> drop" rule, so no engine-to-app suppression signal is needed -
deliberate, to avoid a new interface for a no-op case. Deleting a note that was never synced
creates an entry that is dropped by the 2.2 "remote absent -> drop" rule on the next run.

**Lifecycle (clear vs keep):**

| Event | Entry |
|---|---|
| tombstone written (If-Match ok) | cleared |
| remote live, changed since B -> pulled (edit beats delete) | cleared |
| remote absent (nothing to delete remotely) | dropped |
| remote tombstone + local absent (deletion already represented remotely) | dropped |
| local note live again (stale entry, e.g. restored file) | dropped, Warning |
| any CAS/If-Match deferral | **kept** (retried next run) |

### 4.3 Retention and GC - recommendation (please confirm)

- **Recommendation: tombstone retention 90 days**, measured from `DeletedAt`, matching the
  suggestion in `PHASE_7_CLOUD_SYNC_DESIGN.md` S10. A device that stays offline longer than the
  window can resurrect notes deleted while it was away (its next sync sees no tombstone to learn
  from). That is the accepted trade-off for bounded remote growth; it should be stated in the help
  docs when GC ships.
- **What WP5 leaves out, deliberately:** no tombstone GC, no baseline pruning, no compaction, no
  retention setting, no journal bulk-export. `DeletedAt`/`Rev` are recorded now so a later phase
  can GC mechanically: "during a successful run, remove remote tombstone objects older than the
  window and drop their baseline entries" - resumable and per-object, like 7F's migration story.
- **Deletion-count sanity cap - recommendation: warn-only, do not abort.** When a single run
  writes or applies more than **25** tombstones (or more than 25% of the local note count when that
  is larger), log at Warning and append a note to the completion message. Rationale: with deletions
  now explicit, mass deletion can only come from a mass user action or a hostile/hand-edited
  journal - both worth surfacing - while a hard cap would block legitimate bulk cleanup and add a
  new failure mode without a real security benefit. The threshold is a preference, not a hard
  requirement; tell me if you want a different number or a hard cap after all.

---

## 5. `sync-state.json` v2

### 5.1 Formats

- **v1 (current, no version field):** `{"synced": {guid: rev}, "deleted": [guid]}`.
- **WP4 interim:** adds `"version": 1`; same shape; atomic write + `.bak`; unreadable -> `.bak`
  fallback + Error log (WP4's scope - repeated here only so the numbering is coherent).
- **v2 (WP5):** `{"version": 2, "synced": {guid: rev}}`. The `deleted` list is gone: deletion
  state lives in the journal (S4). `synced` keeps an entry for tombstoned guids (guid -> tombstone
  rev) so later runs see the deletion as reconciled and do nothing.

### 5.2 Loading and migration

- Missing file -> first sync (empty state).
- `version` absent or 1 -> v1 reader. If a `deleted` array is present, **each entry is migrated
  into the journal**: `rev := synced[guid]` when present, else 0 (unknown; used only as a lower
  bound in `max()`), `deletedAt := Now` (the true time is unknowable; logged at Info). Migration is
  persisted by writing the journal **before** the first v2 state write, so a crash in between
  cannot lose entries (the v1 file still carries them and they re-migrate).
- `version` > 2 or non-numeric -> refuse: log Error, abort the run, touch nothing (never
  misinterpret a future format).
- Corrupt JSON -> `.bak` fallback; both corrupt -> Error log and continue as "first sync"
  (conservative: everything becomes B-unknown -> conflicts resolve by rev rather than silently).

How the old `deleted` list is honoured: its meaning - "these guids were deleted here; do not
resurrect them" - is preserved exactly, but the propagation now follows the explicit rules of S2.4
instead of inference, and entries without any remote presence simply drop. Nothing about the old
"absence means deleted" behaviour remains.

### 5.3 Write timing (I5)

- Written **only at the end of a run that was not aborted** (no exception, not cancelled).
- Content: per-guid revs of operations that actually completed (pushed / pulled / applied /
  verified-equal in that run) - never a re-read of the live note. Deferred or skipped guids keep
  their previous value (or stay absent if they had none).
- An aborted run (backend exception, cancel) writes nothing: the file is byte-identical afterwards
  (T8).
- Interpretation to confirm: I read "fully successful run" as "not aborted"; a run with deferrals
  still saves, recording only completed operations, and says so in its completion message. The
  alternative ("save nothing while any defer exists") is safe but makes benign mid-run edits stall
  baseline progress; I recommend the former. Flagged in S9.

---

## 6. How this stays correct with WP1's snapshot + compare-and-set model

1. **Snapshot (main thread, once per run):** per note `{Guid, Rev, DeviceId, Payload(string),
   Signature(string), Left/Top/Width/Height}`. Payload and signature are serialised on the main
   thread. After the snapshot the worker never dereferences a `TNote` again - it reconciles values
   only.
2. **Every local mutation is a CAS closure** delivered via `TMainInvoker.Run`, re-resolving the
   note **by guid** at apply time and applying only if the note still exists and its Rev equals the
   snapshot Rev. Otherwise: skip, count it as deferred, leave all state for the next run. Mutation
   inventory: (1) create a pulled note; (2) apply a pull to an existing note; (3) set Rev only
   (alignment); (4) apply a resolution (content+Rev per S3); (5) create the conflict copy;
   (6) delete a note (remote-tombstone apply). Persist via `PersistNote` + explicit Rev - never
   `SaveNote`/`Touch` (WP3's signature bookkeeping keeps geometry-only saves from bumping Rev).
3. **Baseline integrity:** the baseline records only what was actually pushed/pulled/applied/
   verified; a deferred item does not advance. A user edit that lands mid-run is therefore never
   recorded as "synced" and is re-evaluated next run against its new rev (no lost update, no false
   success). This is exactly what keeps I1 and I5 true under WP1's concurrency.
4. **Cancellation:** `ISyncService.Cancel` is checked between per-note operations and before each
   backend call; a cancelled run aborts without a state write. Remote writes already performed are
   idempotent and are reconciled by the next run (the decision table tolerates any prefix of a run
   having happened).
5. **Non-reentrancy:** `SyncNow` is guarded (lock/interlocked); a concurrent second call returns
   immediately. `TSyncRunner` keeps its single-worker guard on top.
6. **Shutdown order (WP1):** stop schedulers -> cancel -> `WaitForIdle` -> flush autosave -> save
   settings -> `Finalize`. The reconcile design holds no `TNote` references outside CAS closures,
   so once the worker has been waited for, nothing can outlive `FNoteManager.Finalize`.
7. **Reporting:** counters = pushed / pulled / conflicts / removed (tombstones written + local
   deletions applied); message keeps the current format and appends `"; N deferred"` when anything
   was skipped or deferred. Failure and cancellation have their own messages.

---

## 7. Test plan: T1-T9, fixtures, and the invariant map

**Fixture:** two `TNoteApplication` sandboxes (as in `TSyncIntegrationTests`) over one shared
`TFolderSyncBackend` root, plus a **write-counting decorator** implementing `ISyncBackend` that
delegates to the folder backend and counts `Write`/`WriteIfMatch` calls (and can be told to fail a
specific write for T8/T9). Syncs are driven by explicit `SyncService.SyncNow` calls in a chosen
order. Temp paths + `APPDATA` redirect as usual; fixtures self-register.

| Test | Scenario (condensed) | Asserts | Pre-fix |
|---|---|---|---|
| **T1** lost update [I1] | A: one content edit; B: three content edits; sync in both interleavings | both texts survive (one live - the higher rev - one as exactly one conflict copy); nothing lost | **FAILS** - the rev-based overwrite path drops A's edit with no copy |
| **T2** convergence [I2][I5] | equal-rev conflict; alternate A,B,A,B,A (5 rounds) | exactly one conflict copy in the system (same guid both sides); stable note counts on both devices and the remote; **zero backend writes in the last two rounds**; both sides hold the winner's content at the same final rev (asserted per fixture) | **FAILS** - copies multiply, every round rewrites (A2) |
| **T3** order independence [I1][I2] | T2 with B syncing first | same final state as T2 | **FAILS** - same root causes |
| **T4** delete propagation [I3][I4] | A deletes; A syncs; B syncs | gone on B; tombstone object on the remote (parses, `Deleted=true`, rev == old+1, `DeletedAt` set); stable afterwards; no resurrection on A | **FAILS** - no tombstones exist; B re-pushes (A4) |
| **T5** edit beats delete [I4][I1] | A deletes + syncs; B (still holding the note) edits; B syncs; A syncs | live on both with B's edit @ `max(revL, revT)+1` | **FAILS** - A's `FDeleted` rule deletes what B re-pushed; ping-pong, edit never lands on A |
| **T6** pull -> delete before next sync [I3][I5] | B pulls N; B deletes N before its next sync; B syncs; A syncs | N does not come back on B; tombstone on remote; deletion propagates to A | **FAILS** - baseline misses pulled notes (A3); the next pull resurrects N |
| **T7** absence never deletes [I3][I5] | B's local store loads empty while `sync-state.json` survives; B syncs | remote objects byte-unchanged; **zero backend writes**; B pulls everything back | **FAILS** - inference deletes every remote object (A1) |
| **T8** failed run [I5] | backend throws mid-run (wrapper) | failure reported; `sync-state.json` byte-identical after; next normal run reconciles | passes today (guard/regression test) |
| **T9** deterministic copy guid [I1][I2] | equal-rev conflict; suppress the first remote push of the copy once, forcing the second device to create its own copy; sync both, then once more | both copies share one guid; one copy object remote; no duplicate identity; converged | **FAILS** - `Guid := ''` gives every retry/side a fresh identity |

Required pre-fix demonstrations (per the brief): **T1, T2, T4, T6, T7 must be shown failing before
the rewrite starts.** T5/T9 are additionally expected to fail; T3 fails with T2. T8 is expected to
pass before and after.

**Invariant -> test map:**

| Invariant | Tests | What proves it |
|---|---|---|
| I1 no silent loss | T1, T3, T5, T9 | both variants survive in every interleaving; the loser is always materialised as the deterministic copy |
| I2 convergence | T2, T3, T9 | stable counts; zero writes in the last two rounds; single copy identity |
| I3 absence never deletes | T4, T6, T7 | only explicit deletions (journal -> tombstone) remove anything; an empty load touches nothing |
| I4 edit beats delete | T4, T5 | deletion propagates only when the other side did not edit; an edit always survives a concurrent delete |
| I5 baseline after fully successful runs only | T6, T7, T8 | post-reconcile baseline (T6); state semantics keep working when the note store is damaged (T7); byte-identical state on failure (T8) |

---

## 8. WP5 deliverables and doc updates (same commit)

- `uSyncEngine.pas` reconcile rewrite; a small journal unit (planned: `uSyncJournal`, registered in
  `src/StickyNotes.dpr`); new test units registered in `tests/StickyNotes.Tests.dpr`.
- Docs, same commit: `docs/help/sync.md` (deletion paragraph gains the tombstone wording; conflict
  section gains "an edit made before the other side learns of the deletion wins"), `ARCHITECTURE.md`
  (sync section), `docs/DEVELOPMENT_PLAN.md` (Phase 7G entry, per repo convention).
- Existing tests that encode the old remove-on-delete behaviour will be updated deliberately and
  named in the WP5 report. Known today: `TSyncEngineTests.TestLocalDeletionIsPropagatedAndNot
  Resurrected` (asserts the remote file is *absent*; will assert a tombstone instead) and
  `TSyncEngineTests.TestConflictProducesExtraCopy` (copy identity/ordering assumptions).

## 9. Points to confirm (recommendations, not decisions)

1. **Tombstone retention: 90 days** (GC itself deferred; see S4.3). Confirm or adjust.
2. **Deletion-count cap: warn-only at >25 tombstones/run** (or >25% of notes). Confirm or adjust;
   say if you want a hard abort after all.
3. **State save on runs with deferrals:** recommend "save, recording only completed operations"
   (S5.3). If you prefer "no save while any defer exists", say so.
4. **Minor:** log at Warning when the local note set is empty while `synced` is non-empty
   ("possible local store loss; pulling only, not deleting") - recommend yes; it turns a T7-like
   state on a user machine into a diagnosable log line.

## 10. Non-goals / explicitly left out

No tombstone GC, no baseline pruning, no compaction or batching, no end-to-end encryption (7F
stays deferred), no mixed-version fleet guarantees (S3.3), no new user-visible settings, no
interface changes beyond `ISyncService.Cancel` (WP1) and the backend error contract (WP2), no note
payload/schema change (schema stays v3; tombstones use existing fields).
