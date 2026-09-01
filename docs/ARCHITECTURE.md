# VNotes Architecture

## Application Layer

```
StickyNotes.dpr (entry point)
    └── TTrayForm (thin UI / tray form)
        ├── TNoteApplication (application orchestration)
        │     ├── TNoteManager (note orchestration)
        │     ├── TSettingsController (owns TSettings)
        │     ├── TAutosaveService (debounced autosave)
        │     ├── THotkeyService (global hotkeys)
        │     ├── TThemeService (light/dark themes)
        │     ├── TBackupService (ZIP backup/restore)
        │     └── INoteStorage → TJsonStorage (persistence)
        │
        ├── TNoteEditorContext (implements INoteEditorContext)
        ├── FNoteForms: TList<TNoteForm> (UI tracking)
        └── FTrayController (dead code, documented)
```

## Note Form Dependency Boundary

```
TNoteForm (UI)
    │  depends only on
    ▼
INoteEditorContext (narrow interface)
    │  implemented by
    ▼
TNoteEditorContext (adapter)
    │  delegates to
    ▼
TNoteApplication services
    ├── TNoteManager
    ├── TAutosaveService
    ├── TThemeService
    └── TSettings
```

## INoteEditorContext Interface

Defined in `src\Application\uNoteEditorContext.pas`.

| Method | Delegates to |
|--------|-------------|
| `SaveNote(const ANote: TNote)` | `FNoteManager.SaveNote` |
| `DeleteNote(const ANoteID: Int64): Boolean` | `FNoteManager.DeleteNote` |
| `CreateNote(const ATitle, AContent: string; AColor: TNoteColor): TNote` | `FNoteManager.CreateNote` |
| `ScheduleSave(const ANote: TNote)` | `FAutosaveService.ScheduleSave` |
| `CancelSave(const ANoteID: Int64)` | `FAutosaveService.CancelSave` |
| `GetNoteColor(ANoteColor: TNoteColor): TColor` | `FThemeService.GetNoteColor` |
| `GetNoteTextColor(ANoteColor: TNoteColor): TColor` | `FThemeService.GetNoteTextColor` |
| `GetConfirmDelete: Boolean` | `FSettings.ConfirmDelete` |

## Ownership Table

| Object | Owner | Created By | Destroyed By |
|---|---|---|---|
| TNoteApplication | TTrayForm | TTrayForm.FormCreate | TTrayForm.FormDestroy |
| TNoteManager | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TSettingsController (owns TSettings) | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TAutosaveService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| THotkeyService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TThemeService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TBackupService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| INoteStorage (interface) | TNoteApplication | TNoteApplication.Create | auto (interface ref) |
| TNoteEditorContext (INoteEditorContext) | TTrayForm (per-note-form) | TTrayForm.CreateNoteForm | auto (interface ref) |
| TList\<TNoteForm\> | TTrayForm | TTrayForm.FormCreate | TTrayForm.FormDestroy |
| TTrayController (unused) | TTrayForm | TTrayForm.FormCreate | TTrayForm.FormDestroy |
| TNoteForm | TTrayForm (Owner) | CreateNoteForm | VCL close |
| TTrayForm | VCL Application | .dpr CreateForm | VCL runtime |

## TNoteForm Dependency Map

| Before Phase 2B | After Phase 2B |
|---|---|
| TNoteManager (4 usages) | |
| TAutosaveService (3 usages) | |
| TThemeService (2 usages) | |
| TSettings (1 usage) | |
| | INoteEditorContext (single interface, 8 methods) |

## File Layout

```
src\
├── Application\
│   ├── uNoteApplication.pas      (TNoteApplication — application orchestration)
│   └── uNoteEditorContext.pas    (INoteEditorContext + TNoteEditorContext adapter)
├── Controllers\
│   ├── uNoteManager.pas          (TNoteManager — note CRUD orchestration)
│   ├── uSettingsController.pas   (TSettingsController — settings INI lifecycle)
│   └── uTrayController.pas       (TTrayController — unused, preserved as dead code)
├── Forms\
│   ├── uTrayForm.pas/.dfm        (TTrayForm — thin UI tray form)
│   ├── uNoteForm.pas/.dfm        (TNoteForm — note editor window)
│   ├── uSettingsForm.pas/.dfm    (TSettingsForm — settings dialog)
│   └── uAboutForm.pas/.dfm       (TAboutForm — about dialog)
├── Models\
│   ├── uNote.pas                 (TNote — domain object)
│   ├── uSettings.pas             (TSettings — persisted INI settings)
│   └── uEnums.pas                (TNoteColor, TStorageType + helpers)
├── Services\
│   ├── uAutosaveService.pas      (TAutosaveService — debounced timer save)
│   ├── uBackupService.pas        (TBackupService — ZIP backup/restore)
│   ├── uHotkeyService.pas        (THotkeyService — global hotkeys)
│   ├── uStartupService.pas       (TStartupService — Run-key autostart)
│   └── uThemeService.pas         (TThemeService — color palettes, VCL styles)
├── Storage\
│   ├── uStorage.pas              (INoteStorage interface + TStorageFactory)
│   ├── uJsonStorage.pas          (TJsonStorage — JSON file-per-note)
│   └── uSQLiteStorage.pas        (stub only, not functional)
└── Utils\
    ├── uColorUtils.pas, uIso8601.pas, uJsonUtils.pas
    ├── uMonitorUtils.pas, uWindowUtils.pas
    └── uILogger.pas
```

## Application/UI Event Boundary

### TNoteForm → TTrayForm Events

| Event | Direction | Purpose |
|-------|-----------|---------|
| `OnClosed: TNotifyEvent` | TNoteForm → TTrayForm | Notifies owner when form closes so it can be removed from FNoteForms tracking list |

### TNoteApplication → TTrayForm Events (via TNoteManager → TNoteApplication passthrough)

| Event | Direction | Purpose | Currently used? |
|-------|-----------|---------|-----------------|
| `OnNoteCreated: TNoteEvent` | TNoteManager → TNoteApplication → TTrayForm | Opens a note window when a new note is created (by duplicate, hotkey, etc.) | YES — creates TNoteForm, adds to FNoteForms |
| `OnNoteChanged: TNoteEvent` | TNoteManager → TNoteApplication → TTrayForm | Notification that a note was saved/persisted | NO — handler is empty (placeholder for future UI refresh) |
| `OnNoteDeleted: TNoteEvent` | TNoteManager → TNoteApplication → TTrayForm | Closes the note window when a note is deleted from storage | YES — finds form in FNoteForms, calls CloseWithoutSaving, removes from list |

### TTrayForm → TNoteApplication Operations

All delegated through `TNoteApplication` service properties by TTrayForm event handlers.

### FNoteForms Ownership

`FNoteForms: TList<TNoteForm>` is owned by `TTrayForm` and is classified as **UI state** (window tracking). It maps TNote domain objects to their TNoteForm window presentations.

Operations:
- **Add** — in `CreateNoteForm` (when a new note window is created)
- **Find** — in `OnNoteDeleted` (to find the form for a deleted note)
- **Find** — in `OpenAllNotes` (to avoid duplicate windows)
- **Iterate** — in `CloseAllNotes` (application shutdown)
- **Iterate** — in `SaveAllNotes` (application shutdown)
- **Remove** — in `OnNoteDeleted` handler (when a note is deleted externally)
- **Remove** — in `OnClosed` handler (when a form is closed by the user)

The list must NOT be moved to TNoteApplication because it tracks window lifecycle, not application state.

### TNoteForm Lifecycle

1. **Created** by `TTrayForm.CreateNoteForm` → `TNoteForm.CreateNote(Self, ...)`
2. **Added** to `FNoteForms` immediately after creation
3. **Shown** via `Form.Show`
4. **Closed** by user (X button) → `FormClose` fires → saves note, cancels autosave, fires `OnClosed`, VCL frees form
5. **Closed** by application (`OnNoteDeleted` handler) → `CloseWithoutSaving` sets `FIsClosing := True`, close, form freed
6. **Closed** during shutdown (`CloseAllNotes`) → `CloseWithoutSaving` on each form
7. **Removed** from `FNoteForms` in `OnClosed` handler (any close path)

## Persistence Architecture Analysis

### Current Persistence Flow

```
Create note:
    TNoteForm.miNewNoteClick / miDuplicateClick
        → INoteEditorContext.CreateNote
            → TNoteManager.CreateNote
                → TNote.Create(FStorage.GetNextID, ...)
                → FNotes.Add(Note)
                → SaveNote(Note) → FStorage.SaveNote
                    → TJsonStorage.SaveNote
                        → NoteToJson → TJSONObject
                        → Write to .tmp file
                        → MoveFileEx(.tmp → .json, MOVEFILE_REPLACE_EXISTING)
                → FOnNoteCreated(Note)

Edit note (autosave):
    TNoteForm.mmContentChange / pnlHeaderMouseMove
        → INoteEditorContext.ScheduleSave
            → TAutosaveService.ScheduleSave (timer-based debounce)
                → OnTimer fires → FOnSave(Note)
                    → TNoteManager.SaveNote → (same as above)

Startup:
    TNoteApplication.Initialize
        → TNoteManager.Initialize
            → FStorage.Initialize
                → TJsonStorage.Initialize: scan *.json in notes dir, set FNextID
            → LoadNotes
                → FStorage.LoadAllNotes
                    → TJsonStorage.LoadAllNotes: iterate *.json files, parse each

Backup:
    TBackupService.Backup
        → Export each TNoteManager.Note[i] as JSON → temp dir
        → Export settings.ini → temp dir
        → Zip temp dir → timestamped .zip in backups folder

Restore:
    TBackupService.Restore(backup.zip)
        → Extract zip to temp dir
        → Parse each notes/*.json → TNote
        → TNoteManager.AddNote(Note) per note (imports + persists)
        → Load settings.ini into TSettings
```

### INoteStorage Analysis

| Aspect | Assessment |
|--------|-----------|
| **Abstraction quality** | Good — clean 6-method interface. No JSON-specific concepts leaked. |
| **Storage-independent?** | YES — all methods use domain types (TNote, Int64, TObjectList\<TNote\>) |
| **Factory** | TStorageFactory supports 'JSON' and 'SQLITE' strings, defaulting to JSON |
| **SQLite stub** | TSQLiteStorage exists but all methods return stub/empty results |
| **Missing capability** | No batch operations, no transaction support, no search/query interface |
| **Future-proof?** | YES — interface is minimal and correct. TNoteManager never touches storage internals. |

### JSON Storage Analysis

#### File Layout

| Aspect | Detail |
|--------|--------|
| **Base directory** | `%APPDATA%\StickyNotes` (fallback: `%TEMP%\StickyNotes`) |
| **Notes directory** | `<base>\notes\` |
| **File naming** | `%.10d.json` — zero-padded 10-digit ID, e.g. `0000000001.json` |
| **Settings file** | `<base>\settings.ini` (separate INI format, NOT JSON) |
| **Backup directory** | `<base>\backups\` |
| **Backup files** | `StickyNotes_Backup_yyyymmdd_hhnnss.zip` |

#### JSON Data Model

| JSON field | Type | TNote property | Nullable | Default |
|-----------|------|---------------|----------|---------|
| `ID` | Integer | `ID: Int64` | No | 0 |
| `Title` | String | `Title: string` | Yes | '' |
| `Content` | String | `Content: string` | Yes | '' |
| `Color` | Integer | `Color: TNoteColor` | No | `ncYellow (0)` |
### Recovery Analysis

| Scenario | Current behavior | Safe? | Recommendation |
|----------|-----------------|-------|---------------|
| Crash during single SaveNote | Original file preserved (atomic replace) | YES | Already safe |
| Crash during SaveNote between .tmp write and MoveFileEx | Original file intact, .tmp orphaned | YES | Orphan .tmp is harmless |
| Corrupt JSON file | Logged warning, file skipped in LoadAllNotes | YES for load | Corrupt file preserved on disk |
| Missing JSON file | Treated as empty note set | YES | Graceful |
| Orphan .tmp file | Ignored (LoadAllNotes only reads *.json) | YES | Harmless |
| Duplicate note IDs | FNextID scan finds max ID | PARTIAL | Edge case, low risk |
| Partial autosave flush (crash during Flush) | Some notes saved, some not | NO | No application-level transaction |
| Backup file corruption | Exception caught, logged, reported | YES | Safe |
| Partial restore | Each note imported individually via AddNote | PARTIAL | Some notes may be restored before failure |

### Backup Analysis

| Aspect | Detail |
|--------|--------|
| **What is backed up** | All notes (iterated from TNoteManager.FNotes) + settings.ini |
| **How notes are discovered** | In-memory iteration of FNoteManager.Notes[] |
| **Format** | Each note serialized to JSON, all files zipped |
| **Restore mechanism** | Extract zip, parse each JSON, call AddNote for each |
| **Assumes JSON files?** | YES — backup exports via in-memory JSON; restore parses JSON |
| **Restore atomicity** | Each note restored individually. Failure mid-restore leaves partial state |
| **SQLite compatibility** | Would require fundamental rewrite — couples to JSON file format |

### Autosave Analysis

| Aspect | Detail |
|--------|--------|
| **Persistence coupling** | TAutosaveService does NOT assume JSON files. Calls FOnSave(Note) → TNoteManager.SaveNote → FStorage.SaveNote. Storage-agnostic. |
| **One-note-one-file assumption** | NONE — AutosaveService has no knowledge of storage format |
| **SQLite compatibility** | COMPATIBLE — AutosaveService would work unchanged with SQLite storage |
| **Timer-based** | TTimer on VCL main thread. Single-threaded. |
| **Flush behavior** | Iterates all pending notes and saves each. No transaction wrapping. |

### Concurrency Analysis

| Aspect | Detail |
|--------|--------|
| **Threading model** | Single-threaded (VCL main thread). All operations are synchronous. |
| **Which thread calls SaveNote?** | VCL main thread (UI timer, FormClose, etc.) |
| **Which thread calls LoadAllNotes?** | VCL main thread (startup) |
| **Can multiple saves occur concurrently?** | NO — all operations are on the main thread |
| **Can autosave overlap with shutdown?** | YES — shutdown calls Flush which manually processes pending saves. Timer is disabled during Flush. Safe. |
| **Concurrency protection** | NONE — not needed for single-threaded VCL model. Would be needed for future background threads. |

### Settings Persistence

| Aspect | Detail |
|--------|--------|
| **Format** | INI file (NOT JSON, NOT through INoteStorage) |
| **Location** | `%APPDATA%\StickyNotes\settings.ini` |
| **Versioning** | NONE — missing keys default to current defaults |
| **Backup behavior** | Included in ZIP backup/restore alongside notes |
| **Failure behavior** | Missing file → defaults used. Partial write → INI is atomic at OS level for small writes |
| **Should merge with note storage?** | NO — settings have different lifecycle, format, and access patterns. Keeping them separate is correct. |
| `Left` | Integer | `Left: Integer` | No | 100 |
| `Top` | Integer | `Top: Integer` | No | 100 |
| `Width` | Integer | `Width: Integer` | No | 300 |
| `Height` | Integer | `Height: Integer` | No | 250 |
| `AlwaysOnTop` | Boolean | `AlwaysOnTop: Boolean` | No | False |
| `Collapsed` | Boolean | `Collapsed: Boolean` | No | False |
| `Locked` | Boolean | `Locked: Boolean` | No | False |
| `CreatedAt` | String (ISO 8601) | `CreatedAt: TDateTime` | Yes | Now |
### JSON vs SQLite

| Factor | JSON | SQLite |
|--------|------|--------|
| **Simplicity** | ✅ Excellent — no setup, zero dependencies | ⚠️ Requires Delphi SQLite library (FireDAC) |
| **Portability** | ✅ Files can be synced with Git/Dropbox/OneDrive | ❌ Single binary file, harder to diff/merge |
| **Human readability** | ✅ Each note is a readable JSON file | ❌ Requires tool to read |
| **Backup** | ✅ Simple ZIP of files | ⚠️ Requires PRAGMA or VACUUM before safe backup |
| **Corruption recovery** | ✅ Per-file atomicity, isolated damage | ⚠️ Single file corruption affects all notes |
| **Startup performance** | ⚠️ O(n) file reads, each parsed individually | ✅ Single query, indexed |
| **Number of notes** | ✅ Adequate for 100s of notes | ✅ Adequate for 10,000s |
| **Search** | ⚠️ O(n) scan all files | ✅ SQL WHERE/LIKE/FTS5 |
| **Transactions** | ❌ Per-note only | ✅ Full ACID transactions |
| **Schema evolution** | ❌ No versioning, migration on read | ✅ Schema version table, ALTER TABLE |
| **Delphi compatibility** | ✅ Built-in System.JSON | ⚠️ Requires FireDAC (available in Delphi 10.3) |
| **Deployment** | ✅ No extra DLLs | ⚠️ sqlite3.dll or FireDAC driver |

### Recommendation

**JSON NOW → SQLITE LATER**

The current JSON storage is appropriate for VNotes at its current scale:
- Note count is typically small (10-50 notes)
- No concurrent users
- No search requirement
- Human-readable JSON files are a feature (Git-syncable, Dropbox-friendly)
- Per-note atomic save is already implemented
- Backup/restore works well with ZIP

SQLite should be planned when:
- Search becomes a feature requirement (FTS5)
- Note count exceeds practical JSON limits (500+)
- Tags/categories need cross-note querying
- Multi-process or sync conflict resolution is needed

The `INoteStorage` interface is already storage-agnostic and ready for SQLite.

### Target Architecture

```
TNoteManager
    │
    ▼
INoteStorage
    │
    ├── TJsonStorage (current, default)
    │
    └── TSqliteStorage (future, when justified)
```

No additional abstraction layers are needed. `INoteStorage` is sufficient.

---

## Phase 3C — SQLite Readiness & Migration Design Analysis

This section is the Phase 3C analysis. **It is a design document, not an implementation.**

### Current Persistence Architecture (verified from source)

```text
TNoteManager (Controllers/uNoteManager.pas)
    │
    ├── FStorage: INoteStorage
    │       │
    │       └── TJsonStorage (Storage/uJsonStorage.pas)   ← default and only live impl
    │
    │            └── one JSON file per note
    │
    └── FNotes: TObjectList<TNote>

TNoteApplication (Application/uNoteApplication.pas)
    │
    └── FStorage := TJsonStorage.Create(FAppDataPath);     ← hard-coded
```

Confirmed in source:

- `TNoteApplication.Create` line 69: `FStorage := TJsonStorage.Create(FAppDataPath);` — there is no setting-driven switch in the live code path.
- `TStorageFactory.CreateStorage` (Storage/uStorage.pas) already supports the strings `'JSON'`, `'SQLITE'`, and defaults to JSON. It is **not** currently called by `TNoteApplication`.
- `TSQLiteStorage` (Storage/uSQLiteStorage.pas) is a **stub** — all method bodies are TODO comments, `SaveNote` returns `False`, `LoadAllNotes` returns an empty list. It compiles only because no implementation is required.
- `INoteStorage` is unchanged from Phase 2/3B and remains storage-agnostic.

### SQLite Requirement Assessment (concrete evidence only)

A search of the live codebase (excluding the two large `4neem` transcript artefacts that exist in the repo root) for SQLite / FTS / search / tags / categories / indexes returned:

| Evidence | Location | Verdict |
|---|---|---|
| `TStorageType` enum with `stJson, stSQLite, stCloud` | `Models/uEnums.pas` | Plausible future option, not a current requirement. |
| `TSQLiteStorage` stub | `Storage/uSQLiteStorage.pas` | Placeholder only; no callsite, no tests. |
| README mentions `Ctrl+Alt+F` for "Search Notes" | `README.md` | Hotkey is registered, but **no search UI or backend exists**. |
| Future roadmap: "5 Search, hotkeys, backup / 6 Rich text / 7 Cloud sync / 8 Plugins, reminders, tags" | `DEVELOPMENT_PLAN.md` | Explicitly labelled "future" milestones, not current. |
| Phase 3A "Recommendation: JSON NOW → SQLITE LATER" | `docs/ARCHITECTURE.md` | Phase 3A concluded: not justified now. |

**No call site, no user-facing feature, no test, and no scheduled milestone in the current development plan requires SQLite.** Tags, categories, full-text search, and large datasets appear only as "should be planned when" triggers in the existing recommendation table — they are not active requirements.

### Current Data Scale (only what is documented)

| Metric | Value | Source |
|---|---|---|
| Typical note count | "10-50 notes" (informal) | `docs/ARCHITECTURE.md` line 332 |
| Practical JSON limit | "500+" notes (informal) | `docs/ARCHITECTURE.md` line 341 |
| Maximum note count | **Not specified** | — |
| Average note size | **Not specified** | — |
| Measured startup time | **Not specified** | — |
| Autosave debounce delay | 1000 ms (default) | `uAutosaveService.pas` line 19/32 |
| Backup size | **Not specified** | — |
| Search requirement | **None currently** | No search code, no FTS module, no UI |

This phase does **not** invent benchmarks. If a decision later depends on scale, a measurement pass must be performed first.

### INoteStorage Sufficiency Assessment

| INoteStorage operation | JSON support | Future SQLite feasibility (conceptual) | Interface sufficient? |
|---|---|---|---|
| `SaveNote(const ANote: TNote): Boolean` | Yes — atomic write of one file | Yes — `INSERT OR REPLACE` | **Yes** |
| `DeleteNote(const ANoteID: Int64): Boolean` | Yes — `TFile.Delete` | Yes — `DELETE FROM notes WHERE id = ?` | **Yes** |
| `LoadAllNotes: TObjectList<TNote>` | Yes — directory scan + parse each | Yes — `SELECT * FROM notes` | **Yes** |
| `GetNextID: Int64` | Yes — `FNextID` (max filename + 1) | Yes — `SELECT MAX(id) + 1 FROM notes` (or sequence) | **Yes** |
| `Initialize` | Yes — `EnsureDirectories`, scan IDs | Yes — `CREATE TABLE IF NOT EXISTS`, load FNextID | **Yes** |
| `Finalize` | Yes (no-op today) | Yes — close connection | **Yes** |

**Conclusion:** The current 6-method interface is sufficient for a future `TSQLiteStorage`. **No new methods need to be added to `INoteStorage`.** If `BeginTransaction/Commit/Rollback` are ever required for batch operations, that is a separate decision and is not required for the current shape of `TNoteManager`.

**Known gap (already documented in Phase 3A):** the interface intentionally has **no query/search methods.** If search is later added, the most natural extension is a separate interface (e.g. `INoteQuery`) rather than overloading `INoteStorage`.

### JSON → SQLite Conceptual Field Mapping

For the currently persisted v1 schema (post-Phase 3B):

| JSON field | JSON type | `TNote` property | Conceptual SQLite column | Conceptual SQLite type |
|---|---|---|---|---|
| `schemaVersion` (JSON only) | Integer (1) | n/a | n/a (replaced by SQLite `user_version` PRAGMA, see below) | — |
| `ID` | Integer | `ID: Int64` | `id` | `INTEGER PRIMARY KEY` |
| `Title` | String | `Title: string` | `title` | `TEXT` |
| `Content` | String | `Content: string` | `content` | `TEXT` |
| `Color` | Integer (0..7) | `Color: TNoteColor` | `color` | `INTEGER` |
| `Left` | Integer | `Left: Integer` | `pos_left` | `INTEGER` |
| `Top` | Integer | `Top: Integer` | `pos_top` | `INTEGER` |
| `Width` | Integer | `Width: Integer` | `pos_width` | `INTEGER` |
| `Height` | Integer | `Height: Integer` | `pos_height` | `INTEGER` |
| `AlwaysOnTop` | Boolean | `AlwaysOnTop: Boolean` | `always_on_top` | `INTEGER` (0/1) |
| `Collapsed` | Boolean | `Collapsed: Boolean` | `collapsed` | `INTEGER` (0/1) |
| `Locked` | Boolean | `Locked: Boolean` | `locked` | `INTEGER` (0/1) |
| `CreatedAt` | String (ISO 8601) | `CreatedAt: TDateTime` | `created_at` | `TEXT` (ISO 8601) — preserves JSON semantics |
| `UpdatedAt` | String (ISO 8601) | `UpdatedAt: TDateTime` | `updated_at` | `TEXT` (ISO 8601) — preserves JSON semantics |

The Phase 3B `schemaVersion` field is **not** stored as a per-row column in SQLite. Instead, the SQLite database itself carries a single schema-version integer (see below).

### JSON Schema Version vs SQLite Database Schema Version

These are **two independent versioning systems** and must not be conflated.

```text
JSON schema version          →  per-file integer ("schemaVersion": 1)
                                describes the SHAPE of a single note's JSON

SQLite database schema ver  →  database-wide integer (e.g. PRAGMA user_version = 1)
                                describes the SHAPE of the database tables
```

Why they are separate:
- A SQLite database can contain rows imported from many JSON files with different per-file `schemaVersion` values (v0, v1). The DB schema is the contract for what columns/types exist, not what each row's provenance is.
- Per-file `schemaVersion` in JSON evolved to track field changes over time. In SQLite, column changes are tracked by `ALTER TABLE` and the DB-level schema version.
- If a future DB column rename is needed, that is a DB-level migration (DB schema v1 → v2) independent of the source JSON's per-file version.

The conceptual mapping is therefore:

```text
JSON file (schemaVersion = 0 or 1)     →   SQLite DB (user_version = 1)
```

Both can be v1 at the same time, but they are different numbers in different places, evolved by different mechanisms.

### Migration Strategy (conceptual only — not implemented)

Recommended approach: **B. First-run migration**, with strict non-destructive guarantees.

```text
Application startup
    ↓
Detect: any *.json files in <base>\notes\ AND notes.db does NOT exist
    ↓
Run JSON → SQLite import
    ↓
   - Open notes.db (or notes.db.tmp)
   - Create schema at DB schema v1
   - For each *.json in notes\:
       * Read file (TJsonStorage.JsonToNote)
       * If success → INSERT into notes
       * If legacy/v0 → row imported using same reader as live
       * If corrupt or future-schema → SKIP, log warning, KEEP original file
   - Run integrity check / row count
   - Close DB
    ↓
On full success: mark migration done (e.g. settings flag)
On partial failure: ABORT, rename notes.db to notes.db.failed-yyyymmdd_hhnnss,
                    keep all *.json files untouched
    ↓
Subsequent startups use SQLite
```

**Decision: do not use Dual-write (option C).** Dual-write is the highest-risk option (two systems can diverge) and is only justified when users must be able to roll back the storage engine at runtime — VNotes has no such requirement. Option A (offline tool) adds scope and is not needed for a single-user desktop app.

Key safety invariants (no code today, just a contract):

| Scenario | Required behavior |
|---|---|
| One JSON file is corrupt | Log warning, skip row, continue import. Do not abort the whole migration. |
| One JSON file is unsupported/future version | Log warning, skip row, continue import. Do not touch the file. |
| SQLite insert fails halfway through | Abort import, rename notes.db to `*.failed-…`, keep all JSON files, surface a user-visible error. JSON files remain the source of truth. |
| Resumability | Optional: track imported IDs in a side file to allow resume. Recommended but not required because full re-import is fast at current scale. |
| Rollback | Implicit: if SQLite is absent or marked as not-yet-fully-migrated, the app falls back to JSON. The user is never locked out of their data. |
| When is a JSON file considered "migrated"? | Only when it has been successfully INSERTed and the overall migration has committed. Until that point it is never deleted or modified. |

### Rollback Strategy (conceptual)

Because the recommended approach is **B (first-run migration) with no source destruction**, rollback is trivial by design:

```text
100 notes exist (JSON)
   70 inserted into SQLite
    1 fails
        ↓
    abort migration
    ↓
    rename notes.db → notes.db.failed-2026-09-01-120000
    leave all 100 *.json files untouched
    app continues to use JSON
```

There is **no scenario** in which a SQLite migration failure can corrupt the original JSON files. The JSON files are treated as read-only inputs throughout the migration. **This is the single most important safety property of the future migration design.**

### Backup/Restore Strategy (current vs future)

| Aspect | Current (JSON) | Future (with SQLite) |
|---|---|---|
| What is backed up | Notes (one file each) + `settings.ini` | Notes DB file + `settings.ini` + JSON files (kept for rollback window) |
| Mechanism | `System.Zip` of a temp dir | Same `System.Zip`, but contents differ |
| Restore | Parse each JSON → `AddNote` | Decide: restore-by-DB (drop-in file) OR restore-by-JSON (re-parse). Decision deferred. |
| Code that must not change in this phase | `TBackupService` | None additional, but a SQLite-aware variant may exist later |

**For Phase 3C: `TBackupService` is unchanged.** During the rollback window the JSON files remain the source of truth, so today's ZIP format continues to work. Any SQLite-aware backup is a Phase 3E concern.

### Autosave Impact (verified from source)

`TAutosaveService` is **storage-agnostic**:

- Its `OnSave: TProc<TNote>` callback is assigned by `TNoteApplication.Create` to `FNoteManager.SaveNote` (line 78-81 of `uNoteApplication.pas`).
- `TNoteManager.SaveNote` calls `FStorage.SaveNote(ANote)`.
- The service holds a `TDictionary<Int64, TNote>` of pending notes and a `TTimer`. It knows nothing about file paths, SQL, or storage backends.

**Conclusion: `TAutosaveService` would require zero changes** if the storage implementation switched from `TJsonStorage` to a future `TSQLiteStorage`. The same is true for `INoteEditorContext` — it never references storage.

### Performance (no fabricated numbers)

| Operation | Current complexity | File-per-note concern? |
|---|---|---|
| `LoadAllNotes` | O(n) file reads, each parsed | Yes — scales linearly with note count. Not a problem at 10-50 notes. |
| `SaveNote` | O(1) — single file rewrite with atomic move | No |
| `DeleteNote` | O(1) — single file delete | No |
| `Backup` | O(n) — zip all files | Yes — scales linearly |
| `Restore` | O(n) — parse + re-insert each JSON | Yes — scales linearly |
| Future search | O(n) full scan | Yes — biggest single motivator for SQLite, but no search exists today |

**No benchmarks exist in this repository.** The numbers above are algorithmic complexity, not measured throughput. If a future phase makes a performance claim, it must be backed by a benchmark, not by this analysis.

### Delphi 10.3 Rio / Win32 Considerations (decisions, not actions)

When (and if) `TSQLiteStorage` is implemented, the following decisions must be made. **None of them is resolved in this phase.** They are recorded here so that the future phase does not start from zero.

| Concern | Options to evaluate | Notes |
|---|---|---|
| SQLite engine | `sqlite3.dll` (dynamic) **or** statically linked source amalgamation | Win32 deployment currently ships zero extra DLLs (only `System.Zip` + built-in `System.JSON`). Adding a DLL is a deployment change. |
| Delphi component / API | FireDAC `TFDConnection`+`TFDQuery` (Embarcadero, available in Delphi 10.3) **or** `mORMot` / `ZeosLib` / direct sqlite3.pas binding | No FireDAC or third-party SQLite unit is currently in any `uses` clause. Introducing one is a dependency change. |
| Static vs dynamic | Trade-off: simpler deployment (static) vs smaller EXE (dynamic) | Must be decided before code is written. |
| Unicode | All string columns are `TEXT`; encoding is UTF-8 by default in modern SQLite. TNote fields are Delphi `string` (UTF-16). | Conversion at the `TNote` ↔ SQL boundary. |
| Transactions | Single-statement per save is sufficient for current model. Batch migration uses one transaction. | No change required to `INoteStorage` for single-statement mode. |
| Threading | App is single-threaded on VCL main thread. SQLite connection should be created and used only on the main thread. | No change to threading model. |
| Database file location | `<base>\notes.db` (matches the stub's choice). | Coexists with `notes\` folder during the rollback window. |
| User_version PRAGMA | Used for SQLite-side schema versioning (see Versioning section). | Independent of the per-file JSON `schemaVersion`. |

### Decision Gate

```text
Decision: B — Prepare for SQLite, but defer implementation.
```

**Why B, not C:** no current feature, call site, scheduled milestone, or test requires SQLite. The existing JSON storage is documented as adequate for the current scale, the schema is now properly versioned (Phase 3B), and no new requirement has emerged. Implementing SQLite now would add a FireDAC dependency, deployment complexity, and migration risk **without** removing any current pain point.

**Why not A:** option A ("stay JSON forever") would lock out legitimate future needs (search, scale, tags). Option B is the same as A today while keeping the door open: the abstraction is already in place, the conceptual design is now documented, and Phase 3D can start with a clear specification the moment a real trigger (FTS5 search, 500+ notes, tags/categories) is requested.

**Why B includes no JSON-side improvements:** this phase found no concrete JSON bug or limitation that would justify scope creep. The schema versioning from Phase 3B is sufficient; no migration framework, no validation framework, no manifest, and no startup optimization is justified by current evidence. Any such improvement must be motivated by a real measurement or a real defect, not by speculative future need.

### Target Architecture (current recommendation)

```text
TNoteManager
      │
      ▼
INoteStorage               (unchanged 6-method interface)
      │
      ├── TJsonStorage     (current, default — keeps working)
      │
      └── TSqliteStorage   (NOT BUILT — designed for when a real trigger exists)
```

**No additional abstraction layer is created.** `INoteStorage` is sufficient.

### Future Roadmap (smallest sensible)

These phases are not assumed — each must be triggered by concrete evidence.

| Phase | Trigger | Scope |
|---|---|---|
| **Phase 3C** | This document | SQLite readiness analysis, migration design. **COMPLETE** |
| **Phase 3D — SQLite Implementation** | A real trigger: FTS5 search becomes a feature requirement, OR note count regularly exceeds ~500, OR tags/categories are added to the development plan | Build `TSQLiteStorage` behind the unchanged `INoteStorage`; no changes to `TNoteManager`, `TNoteApplication`, `INoteEditorContext`, `TAutosaveService`, or `TBackupService`. Decide FireDAC vs alternatives, static vs dynamic linking, schema column types. Add tests for CRUD + schema versioning. |
| **Phase 3E — First-Run Migration** | After Phase 3D is shippable | Implement the read-only JSON → SQLite importer with the rollback contract above. User-confirmed one-time migration. JSON files retained for one full release cycle, then optionally archived. |
| **Phase 3F — Backup/Restore Adaptation** | After Phase 3E | Decide whether backups zip the SQLite DB or continue to re-export to per-file JSON. Most likely: a SQLite-aware `TBackupService` that zips `notes.db` + `settings.ini`. |

If none of the Phase 3D triggers materialize, the application stays on `TJsonStorage` indefinitely. The Phase 3C design is intentionally cheap to leave on the shelf.

### Future Roadmap

| Phase | Task | Description |
|-------|------|-------------|
| Phase 3A | Persistence Architecture Analysis | COMPLETE |
| Phase 3B | JSON Schema Versioning | COMPLETE — schemaVersion field, legacy v0 reader, future/invalid rejection |
| Phase 3C | SQLite Readiness & Migration Design Analysis | COMPLETE — Decision B (defer). Full design in § "Phase 3C" below. |
| Phase 3D | SQLite Implementation | NOT STARTED (triggered by real FTS5/scale/tags need) |
| Phase 3E | First-Run JSON → SQLite Migration | NOT STARTED (after 3D) |
| Phase 3F | Backup/Restore Adaptation | NOT STARTED (after 3E) |
| `UpdatedAt` | String (ISO 8601) | `UpdatedAt: TDateTime` | Yes | Now |

#### Versioning (Phase 3B — COMPLETE)

**The JSON format is explicitly versioned.** Every note written by `SaveNote` begins with:

```json
{
  "schemaVersion": 1,
  "ID": 1,
  "Title": "...",
  "Content": "...",
  "Color": 0,
  "Left": 100, "Top": 100, "Width": 300, "Height": 250,
  "AlwaysOnTop": false, "Collapsed": false, "Locked": false,
  "CreatedAt": "2026-09-01T12:00:00",
  "UpdatedAt": "2026-09-01T12:00:00"
}
```

Rules enforced by `TJsonStorage.JsonToNote`:

| Input | Behavior |
|---|---|
| Missing `schemaVersion` | Legacy/unversioned format → interpreted as schema version **0**, read with the legacy field mapping (same defaults as before versioning). File is **not** rewritten on load. |
| `schemaVersion = 0` or `1` | Loaded normally. |
| `schemaVersion < 0` | Rejected (`EJsonSchemaException`), logged as warning, file preserved. |
| `schemaVersion > CURRENT_SCHEMA_VERSION` (e.g. 999) | Rejected as unsupported future schema, logged as warning, file preserved, other notes still load. |
| Wrong type (`"abc"`, `null`, `{}`, `[]`) | Rejected as invalid schema metadata, logged as warning, file preserved. |

- Version constants live in one place: `TJsonStorage.CURRENT_SCHEMA_VERSION = 1`, `LEGACY_SCHEMA_VERSION = 0`, `SCHEMA_VERSION_FIELD = 'schemaVersion'`.
- No general migration framework exists yet. For v1 there is no field transformation; the version boundary is what was established.
- Legacy files are **never** automatically rewritten. Future enhancement (deferred): optional normalization pass that rewrites legacy files as v1.
- `LoadAllNotes` distinguishes diagnostics: corrupt JSON vs unsupported/invalid schema version.
- `TBackupService` restore parses known fields directly and ignores unknown fields, so backups of versioned JSON restore unchanged. No BackupService changes were required.

#### Atomicity

Per-note atomicity: YES — Phase 1 implemented `MoveFileEx` with `.tmp` file for atomic replace.
Cross-note atomicity: NO — each note save is individually atomic. No transaction across multiple notes.
## Phase Status

| Phase | Status |
|-------|--------|
| Phase 1 — Reliability | COMPLETE |
| Phase 2 — Architecture | COMPLETE |
| Phase 2A — TNoteApplication extraction | COMPLETE |
| Phase 2B — Service/Form decoupling | COMPLETE |
| Phase 2C — Application/UI event boundary | COMPLETE |
| Phase 3A — Persistence Architecture Analysis | COMPLETE |
| Phase 3B — JSON Schema Versioning | COMPLETE |
| Phase 3C — SQLite Readiness & Migration Design Analysis | COMPLETE |
| Phase 3D — SQLite Implementation | NOT STARTED (deferred — see Phase 3C roadmap) |

## Dependency Injection Status

| Aspect | Status |
|--------|--------|
| Explicit constructor/interface injection | USED WHERE JUSTIFIED |
| DI container/framework | NOT USED |
| DI container/framework | NOT PLANNED |

## Known Limitations

- Full manual application smoke testing in a Delphi IDE environment remains unverified.
- `TTrayController` is dead code (preserved, documented).
- `TNoteApplication.Initialize` uses `TStyleManager.TrySetStyle` which cannot be tested in a DUnitX console environment (hangs). The `TestApplicationInitializeShutdown` test was replaced with `TestApplicationShutdownIsSafe` for this reason.
