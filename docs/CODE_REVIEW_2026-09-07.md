# V-Notes Code Review — 2026-09-07

> **Fix log (same day):** B1–B7 and the autosave format strings were fixed after this review.
> See [Fix log](#fix-log---2026-09-07) at the bottom. Test suite: 210 → **212/212 passing**
> (2 new regression tests); main app builds clean.

Scope: full `src/` tree (Delphi VCL, Delphi 12.3 / Studio 23.0), plus test-suite run.
Baseline: `build_tests.bat` succeeds; all **210 DUnitX tests pass**; main app builds (Debug).

Two RTL behaviors were verified empirically (probe compiled with dcc32, Studio 23.0) because
the findings depend on them:

- `Format('...%', [x])` — a trailing `%` does **not** raise; it silently truncates output and
  drops the remaining arguments (System.SysUtils.WideFormatBuf: `if FormatPtr >= FormatEndPtr then Break`).
- `TList<T>.Delete(staleIndex)` **does** raise `EArgumentOutOfRangeException` ("List index out of bounds").

---

## Critical bugs

### B1. Delete flow: stale-index double-remove corrupts the window list — `TTrayForm.OnNoteDeleted`
`OnNoteDeleted` does:
```pascal
Form.CloseWithoutSaving;   // FormClose fires OnClosed -> NoteFormClosed -> FNoteForms.Remove(Form)
FNoteForms.Delete(I);      // I is now stale
```
`Close` runs `FormClose` (and therefore `OnClosed` → `NoteFormClosed`) **synchronously**, so the
form is already removed from `FNoteForms` when `Delete(I)` runs.

- Deleting the note whose window is **last** in `FNoteForms` (the common case: newest window)
  → `EArgumentOutOfRangeException` raised *inside* `TNoteManager.DeleteNote`, before
  `FNotes.Delete(Index)` executes → the note stays in the in-memory list while its file is gone.
- Deleting any **earlier** window → silently removes the *wrong* form from tracking (its window
  stays open but is orphaned: missed by `SaveAllNotes`/`CloseAllNotes`, can be double-opened).

Fix: drop the `FNoteForms.Delete(I)` line — `NoteFormClosed` already owns removal.

### B2. Delete flow: note is resurrected in storage immediately after deletion
`TNoteManager.DeleteNote` fires `OnNoteDeleted` (which closes the window) **before** removing the
note from `FNotes`. The closing form runs `FormClose` → `SaveNote` → `TNoteManager.SaveNote`
→ storage write, and `SaveNote` has **no membership check** — it persists any note handed to it.
So `FStorage.DeleteNote` is immediately followed by a fresh write of the same note. The file/row
survives; the note vanishes from the list and reappears after the next restart ("ghost note").
`CloseWithoutSaving` is misnamed here: `FormClose` saves unconditionally (`FIsClosing` only
suppresses `FormDestroy`).

Fix (two small changes):
```pascal
// TNoteManager.DeleteNote: drop from memory BEFORE notifying
if FStorage.DeleteNote(ANoteID) then
begin
  FNotes.Delete(Index);               // first
  if Assigned(FOnNoteDeleted) then
    FOnNoteDeleted(Note);             // window close can no longer resurrect
end;

// TNoteManager.SaveNote: refuse notes the manager no longer owns
procedure TNoteManager.SaveNote(const ANote: TNote);
begin
  if (ANote = nil) or (FNotes.IndexOf(ANote) < 0) then
    Exit;
  ...
end;
```

### B3. Restore (SQLite-active) leaves open note windows holding freed `TNote` pointers — use-after-free
In `TBackupService.DoRestore`, the DB path calls `FNoteManager.Finalize` → `FNotes.Clear`
(frees every `TNote`) with **no `OnNoteDeleted` fired and no windows closed**. Open `TNoteForm`s
still reference the freed notes; after `Initialize`/`LoadNotes` the manager holds *new* objects.
Any subsequent keystroke (`mmContentChange` → `ScheduleSave(FNote)`), autosave flush, or the
shutdown `SaveAllNotes` reads freed memory (autosave keys by `FNote.ID` from a freed object).

Note: the JSON-restore path avoids this only by accident — deleting each note closes its window
via B1/B2's (buggy) flow.

Fix: close all note windows before `FNoteManager.Finalize` and reopen them afterwards. Cleanest is
an `OnBeforeStorageSwap` / `OnAfterStorageSwap` callback pair on `TBackupService` that
`TTrayForm` wires to `CloseAllNotes` / `OpenAllNotes` (the service currently has no reference to
the forms).

### B4. First restore permanently swaps the backup completion handler — `TTrayForm.OnRestore`
`OnRestore` sets `BackupService.OnComplete := RestoreComplete`, overwriting `BackupComplete`.
Every later backup (manual or scheduled) then reports through the restore dialog path.
Fix: save and restore the previous handler, or re-assign `BackupComplete` at the end of
`RestoreComplete`.

---

## Important bugs

### B5. `UpdatedAt` always lags one save behind — `TNoteManager.SaveNote`
```pascal
if FStorage.SaveNote(ANote) then
begin
  ANote.Touch;                 // after persisting: the stored timestamp is the OLD one
  ...
```
The row/file written contains the pre-touch `UpdatedAt`; memory and disk disagree until the next
save. Because the notes-list sorts by `UpdatedAt DESC`, ordering effectively uses the *previous*
save time. Fix: `ANote.Touch` before `FStorage.SaveNote(ANote)`.

### B6. `TNoteApplication` constructor failure path crashes in `Shutdown`
If construction raises after `FBackupScheduler` is nil but before/around service creation (e.g.
storage-migration exception), `Destroy` → `Shutdown` dereferences unguarded fields:
`FAutosaveService.Flush` and `FNoteManager.Finalize` have no nil-guard (only `FBackupScheduler`
has one). A failed `Create` runs `Destroy` in Delphi — so a mid-construction failure becomes an
AV that masks the original error. Fix: guard every field in `Shutdown`/`Destroy`, or use a
two-phase init where the constructor can't fail.

### B7. Backup scheduler never catches up after downtime — `TBackupScheduler`
- `LastBackupAt` is read but never used to decide anything: after an app restart the timer re-arms
  for a **full interval**, so a 1-day backup can silently go weeks without running.
- Intervals are clamped to `High(Integer)` (~24.8 days), so the settings dialog's 25–30 day range
  silently becomes ~24.8 days.
- A `TTimer` doesn't accumulate while the machine sleeps.
Fix: on `Start`, compute `Now - LastBackupAt` and fire immediately if overdue; clamp to the true
`TTimer.Interval` maximum (Cardinal) or switch to a frequent tick that checks due-date.

---

## Minor issues / hygiene

- **`uAutosaveService`**: four format strings use `'ID %'` instead of `'ID %d'` (`OnTimer`,
  `ScheduleSave`, `CancelSave`, `Flush`). Verified: the `%` silently swallows the ID — logs read
  "Saving note ID " with no number. Harmless but wrong; fix the format specifiers.
- **Serialization is triplicated**: `uJsonStorage.NoteToJson` / `uBackupService.CreateBackupZip`
  (which re-implements note→JSON and hardcodes `schemaVersion = 3`) / `DoRestore`'s hand-rolled
  JSON parser. Every schema bump must now touch three places or backups and live storage drift.
  Extract one shared note-JSON codec (write + tolerant read) and use it everywhere.
- **Two storage factories**: `TStorageFactory.CreateStorage` (`uStorage`) and
  `TStorageResolver.ResolveStorage` (`uStorageResolver`) do the same job with different defaults
  ('JSON' fallback vs settings-driven). Only the resolver is used in the real flow — delete the
  factory (and its README example contract) or route both through one.
- **`TLogger` per call**: `CreateLogger` allocates a new object per log statement
  (`uILogger`), and `TJsonStorage.JsonToNote` creates one *per note loaded*. The logger is
  stateless; make `CreateLogger` return a shared singleton.
- **Timestamps**: JSON/SQLite persist `'yyyy-mm-dd"T"hh:nn:ss'` — no milliseconds, no UTC
  marker; `ISO8601ToDateTime` falls back to `Now` on parse failure (silently rewriting history),
  and migration equivalence checks tolerate 1 ms skew to paper over precision loss. Consider
  ms precision or ISO-8601 with an explicit zone if cloud sync (Phase 7) is coming.
- **SQLite durability**: `LockingMode=Normal`, no WAL. For a notes app with 1 s autosave this is
  acceptable, but `journal_mode=WAL` would remove the tiny corruption window on power loss and
  make the DB copy in backups safer while the app runs.
- **Test isolation**: `TNoteApplicationTests` builds a real `TNoteApplication` against the real
  `%APPDATA%\StickyNotes` (constructor runs migration orchestration on live data; teardown calls
  `SaveSettings`). Tests should run against an injected temp base path.
- **Dead code**: `TNoteManager.OpenAllNotes/CloseAllNotes` (placeholders — the real ones live in
  `TTrayForm`), `TWindowDragHelper`, and possibly `TJsonUtils`/`uIso8601` (duplicate of the
  `DateTimeToISO8601` defined in three other units). Global `NoteForm`/`NotesListForm` vars are
  unneeded.
- **New notes stack at the same spot**: `TTrayForm.OnNewNote` passes hardcoded `100,100`; several
  quick `Ctrl+Alt+N`s pile windows exactly on top of each other. A small cascade offset would help.
- **Naming leftovers**: mutex name, `Run` registry value, backup zip prefix and `miNewNote`
  shortcut still say "StickyNotes" while the product is V-Notes. Cosmetic, but it affects users
  who rename/install alongside the old version.
- **`uNoteForm.MemoContainerResize`**: mixes `Align=alClient` with manual `Width/Height` math
  (`Width := pnlMemoContainer.Width + 30` to shove the native scrollbar off-screen). Fragile
  under DPI scaling; pick one layout strategy (custom thumb drawn from scroll info is fine — the
  native bar can simply be hidden with `ShowScrollBar`).
- **`TNote.ColorAsTColor`/`ColorToNoteColor`**: dark-theme colors can never round-trip
  (`ColorToNoteColor` matches only the light palette, and falls back to `ncYellow`). Currently
  unused in the real flow, so latent — but it's a trap for the next feature.
- **Misleading comment**: `uStorageMigrationOrchestrator` claims `TSQLiteStorage.Initialize`
  "validates connection and runs PRAGMA quick_check" — it only opens the DB and creates the
  schema. If corruption detection on startup is intended (the message says so), run
  `quick_check` there explicitly.

---

## What's genuinely good

- Clean layered architecture (Forms/Controllers/Models/Storage/Services/Utils) with **written
  ownership contracts** (who owns `TNote` lists, non-owning query results, `caHide` vs `caFree`)
  — unusually disciplined for a solo Delphi project.
- Atomic note writes (temp file + `MoveFileEx`), schema versioning with tolerant legacy readers
  and *safe rejection* of future versions, per-note JSON isolation that predates SQLite.
- The JSON→SQLite migration is done properly: strict pre-validation, single transaction,
  post-migration field-level verification, quarantine (not delete) of a mismatched DB, and a
  reconcile path for interrupted migrations.
- Restore makes a pre-restore backup and validates the SQLite payload (`quick_check`) before
  swapping files, with rollback of the swap on failure.
- 210 DUnitX tests, including pure-function tests for the monitor-clamping and query-ordering
  math — the testable core is genuinely separated from the UI.
- Single-instance guard with a graceful "surface the existing instance" message and a
  deliberate fallback if the mutex fails.
- The DFM-independent runtime construction of the memo/scrollbar panels, and the
  `TEdgeHitTestHook` design for making child controls pass resize-band hits through — that's a
  genuinely tricky Win32 problem handled carefully (with class-destructor cleanup and
  `FreeNotification` detach).

## Suggested fix order

1. B1 + B2 (delete path — one edit in `TTrayForm`, two small ones in `TNoteManager`).
2. B3 (restore UAF — callback pair around storage swap).
3. B4, B5, B6 (small, high value).
4. B7 + scheduler catch-up.
5. Hygiene batch (format strings, logger singleton, dead code, cascade offsets).
6. Only then the dedup refactors (serialization codec, storage factory) — bigger changes,
   well covered by the existing test suite.

---

## Fix log — 2026-09-07

All fixes applied and verified (`build_tests.bat` + full suite: **212/212 pass**; `build.bat`
succeeds). One behavior contract changed and one test was updated accordingly.

- **B1 — stale-index double-remove** (`uTrayForm.pas`): removed the extra `FNoteForms.Delete(I)`
  in `OnNoteDeleted`; `NoteFormClosed` (via `OnClosed`) is the single removal path.
- **B2 — note resurrection** (`uNoteManager.pas`):
  - `DeleteNote` now **Extract**s the note from the owned list (not `Delete`, which would free
    it), fires `OnNoteDeleted` while the object is still valid, and frees it afterwards.
  - `SaveNote` gained a membership guard: it refuses to persist a note the manager no longer
    owns. This kills the closing-window resurrection and makes a late autosave of a deleted
    note a harmless no-op.
  - New private `PersistNote` writes through to storage without `Touch`. `CreateNote`/`AddNote`
    use it so created/imported/restored notes keep their original timestamps; `SaveNote` now
    `Touch`es **before** persisting (**B5** — stored `UpdatedAt` no longer lags one save).
- **B3 — restore use-after-free** (`uBackupService.pas` + `uTrayForm.pas`): new
  `OnBeforeStorageSwap`/`OnAfterStorageSwap` events on `TBackupService`, fired around **both**
  swap blocks in `DoRestore` (direct SQLite restore and legacy-JSON migration). `TTrayForm`
  wires them to `CloseAllNotes` / `OpenAllNotes`, so no open window ever holds a freed `TNote`.
- **B4 — swapped backup handler** (`uTrayForm.pas`): `OnRestore` now restores the previous
  `OnComplete` handler in a `finally` after the synchronous restore.
- **B6 — constructor-failure AV** (`uNoteApplication.pas`): `Shutdown` guards every service
  field; `SaveSettings`/`LoadSettings` guard `FSettingsController`.
- **B7 — scheduler catch-up** (`uBackupScheduler.pas`): new `IsOverdue`; `Start` runs a backup
  tick immediately when overdue (or never backed up), `Refresh` catches up when a settings
  change makes the schedule due. Interval clamp raised `High(Integer)` → `High(Cardinal)`
  (verified `TTimer.Interval` is Cardinal in Delphi 12), so 25–30 day intervals are honoured.
- **Autosave log format strings** (`uAutosaveService.pas`): `%` → `%d` in all four messages.
- **Test updates**:
  - `TPhase6MActivationTests.TestBackupAndRestoreWithSQLitePrimary` used the old permissive
    `TNoteManager.SaveNote` to persist a note that was never added to the manager — exactly the
    anti-pattern the new membership guard blocks. Switched to `AddNote` (ownership transfer),
    which matches real usage.
  - Added regression tests: `TNoteManagerTests.TestSaveNoteRefusesNoteNotOwnedByManager` and
    `TestDeleteNoteLeavesNoStorageFile`.

**Not addressed (intentionally — bigger refactors, see review body):** shared note-JSON codec
(triplicated serialization), storage-factory consolidation, test isolation for
`TNoteApplicationTests`, naming leftovers, cascade positioning for new notes.

Changes are left uncommitted for review.
