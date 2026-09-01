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

### Future Roadmap

| Phase | Task | Description |
|-------|------|-------------|
| Phase 3A | Persistence Architecture Analysis | COMPLETE |
| Phase 3B | JSON Schema Versioning | COMPLETE — schemaVersion field, legacy v0 reader, future/invalid rejection |
| Phase 3C | SQLite Storage Implementation | Implement TSqliteStorage with FireDAC |
| Phase 3D | Migration Infrastructure | JSON → SQLite migration tooling, dual-write |
| Phase 3E | Backup/Restore Adaptation | Update backup for both JSON and SQLite backends |
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
| Phase 3C — SQLite Storage Implementation | NOT STARTED |

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
