# Sticky Notes — Development Plan

## Current State

### Delphi Version
- **Project target**: Delphi 11 Alexandria (from .dproj: `<ProjectVersion>17.0</ProjectVersion>` - actually indicates Delphi 10.3 Rio)
- **Available compiler**: Delphi 10.3 Rio (Embarcadero Delphi for Win32 compiler version 34.0)
- **Note**: ProjectVersion 17.0 corresponds to RAD Studio 10.3 Rio, not Delphi 11 Alexandria (which would be version 28.0)
- VCL framework
- Target platform: Win32 only

### Architecture
```
StickyNotes.dpr (entry point)
    └── TTrayForm (hidden main form, owns tray icon)
        ├── TNoteManager (note orchestration)
        ├── TJsonStorage (JSON file-per-note persistence)
        ├── TAutosaveService (debounced autosave)
        ├── TBackupService (ZIP backup/restore)
        ├── THotkeyService (global hotkeys)
        ├── TStartupService (autostart registry)
        ├── TThemeService (light/dark themes)
        └── TSettings (INI-based settings)
```

### Storage Mechanism
- **Primary**: JSON files (one per note) in `%APPDATA%\StickyNotes\notes\####.json`
- **Settings**: INI file at `%APPDATA%\StickyNotes\settings.ini`
- **Backup**: ZIP archives in `%APPDATA%\StickyNotes\backups\`

### Major Services
1. **TNoteManager**: Creates, deletes, saves, loads notes
2. **TJsonStorage**: JSON serialization, file I/O
3. **TAutosaveService**: Debounced timer-based autosave (1 second default)
4. **TBackupService**: ZIP backup/restore with progress callbacks
5. **THotkeyService**: Global hotkey registration (Ctrl+Alt+N, Ctrl+Alt+F)
6. **TStartupService**: Windows Run-key autostart
7. **TThemeService**: VCL style management, color palettes
### Existing Features
- Create, edit, delete, duplicate notes
- Move, resize, collapse notes
- Pin/always-on-top
- Change note color (8 colors)
- Lock notes
- Autosave with debounce
- JSON persistence
- Tray icon with menu
- Global hotkeys
- Settings (autosave delay, theme, hotkeys, backup, autostart)
- Backup/restore
- Multi-monitor positioning
- Position/size persistence
- Dark/light theme

## Current Risks (Verified)

### 1. Autosave Single-Pending-Note Behavior (CRITICAL)
**File**: `src/Services/uAutosaveService.pas`
**Issue**: `FPendingNote: TNote` is a single field. If Note A schedules a save, then Note B schedules a save before the timer fires, Note A's pending save is **replaced** and never saved.
**Impact**: Data loss for rapidly edited notes.
**Status**: FIXED - Redesigned `FPendingNotes` as `TDictionary<Int64, TNote>` to support multiple independent pending saves.

### 2. Non-Atomic JSON Writes (HIGH)
**File**: `src/Storage/uJsonStorage.pas`
**Issue**: `SaveNote` writes JSON directly to the destination file using `TFileStream.Create(FileName, fmCreate)`. If the write fails mid-stream, the `.json` file is left in a corrupted state.
**Impact**: Note data corruption, potential data loss.
**Status**: FIXED - Implemented atomic save strategy: write to `.tmp` file first, then atomically replace the destination using Win32 `MoveFileEx` with `MOVEFILE_REPLACE_EXISTING`. This eliminates the delete-then-move window where a move failure would destroy the original file.

### 3. Silent Storage Errors (MEDIUM)
**File**: `src/Storage/uJsonStorage.pas`
**Issue**: `SaveNote` returns `Boolean` but errors are silently swallowed. Callers have no visibility into why a save failed.
**Impact**: Silent data loss, difficult debugging.
**Status**: PARTIALLY FIXED - Added ILogger integration to log save/load errors. Still returns Boolean for backward compatibility.

### 4. Silent Corrupted-Note Handling (MEDIUM)
**File**: `src/Storage/uJsonStorage.pas` lines 288-302
**Issue**: When loading notes, corrupted JSON files are silently skipped with no logging. The application continues but the user has no idea a note was lost.
**Impact**: Silent data loss, poor user experience.
**Status**: FIXED - Added ILogger warning when corrupted JSON files are skipped during load.

### 5. Lack of Automated Tests (HIGH)
**Issue**: No test project exists. No unit tests for Models, Storage, or Services.
**Impact**: Refactoring is risky, regressions are likely.
**Status**: IN PROGRESS - Created test foundation with TNoteTests, TSettingsTests, TJsonStorageTests, TAutosaveServiceTests.

### 6. High-DPI Limitations (LOW)
**Issue**: The application may not handle high-DPI displays properly. VCL styles may not scale correctly.
**Impact**: Blurry UI on high-DPI displays.
**Status**: Not addressed in this phase.

### 7. TTrayForm Centralization (MEDIUM)
**Issue**: `TTrayForm` is the hidden main form that owns all services and creates note forms. This creates a central point of failure and makes the architecture difficult to test.
**Impact**: Tight coupling, difficult to test, single point of failure.
**Status**: Not addressed in this phase (architecture refactor comes later).

## Development Phases

### Phase 0 - Baseline & Safety (CURRENT)
- [x] Inspect repository
- [x] Create DEVELOPMENT_PLAN.md
- [x] Create test foundation (DUnitX structure)
- [x] Fix JSON persistence safety (atomic saves)
- [x] Fix autosave race condition (multiple pending notes)
- [x] Add lightweight logging (ILogger)
- [x] Improve corrupted JSON handling
- [x] Build and verify (Main application: PASS)

### Phase 1 - Reliability
- [x] Comprehensive error handling - Added try/except in SaveNote, LoadAllNotes, Backup, Restore
- [x] Retry logic for file operations - 3 attempts with 10ms delay in SaveNote
- [x] Backup before overwrite - Atomic save preserves existing file until new file is ready; original deleted only after temp file is successfully written
- [x] Corruption detection and recovery hints - LoadAllNotes logs corrupted files with filename and error, continues loading valid notes, preserves corrupted files
- [x] Autosave safety - Multiple pending notes via TDictionary<Int64,TNote>; debounce preserved; CancelSave/Flush work correctly

### Phase 2 - Architecture
- [ ] Replace TTrayForm with TNoteApplication
- [ ] Introduce dependency injection
- [ ] Decouple services from forms
- [ ] Add proper event system

## Test Foundation

### DUnitX Test Project Structure
```
tests/
  StickyNotes.Tests.dpr
  Models/
    TNoteTests.pas
    TSettingsTests.pas
    TJsonStorageTests.pas
    TAutosaveServiceTests.pas
```

### Priority Tests (Created but not compilable in Delphi 10.3)
1. TNote serialization/deserialization ✅ (test code written)
2. TSettings serialization/deserialization ✅ (test code written)
3. JSON save/load ✅ (test code written)
4. Atomic save (temporary file + replace) ✅ (test code written)
5. Multiple-note autosave ✅ (test code written)
6. Autosave debounce behavior ✅ (test code written)
7. Corrupted JSON handling ✅ (test code written)

### Test Compilation Status
- **DUnitX custom attributes** (`[TestFixture]`, `[Test]`) not supported in Delphi 10.3 - removed from test units
- **Test project search path** - Complex directory structure causes "Unit not found" errors with absolute paths in `uses` clauses
- **Test units created**: TNoteTests.pas, TSettingsTests.pas, TJsonStorageTests.pas, TAutosaveServiceTests.pas (all in tests\Models\)
- **Status**: NOT VERIFIED - Cannot compile/execute in Delphi 10.3 environment without DUnitX 10.3-compatible version or project restructuring

## Build Results

### Environment
- **Delphi Compiler**: Delphi 10.3 Rio (Embarcadero Delphi for Win32 compiler version 34.0) - Available at `C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\dcc32.exe`
- **MSBuild**: Not available in Embarcadero bin; dcc32 used directly for compilation
- **Git**: Not a repository (no .git folder)

### Build Status (Verified)
- **Win32 Debug**: PASS - Main application compiles successfully with dcc32 (4136 lines, 3237308 bytes code, 147928 bytes data)
- **Win32 Release**: PASS - Same binary produced (dcc32 doesn't distinguish Debug/Release via .dproj configurations; both produce identical output with current command line)
- **Tests**: NOT VERIFIED - DUnitX custom attributes require Delphi 10.4+; test project has search path compatibility issues in Delphi 10.3. Test units created but not compilable in this environment.

## Known Limitations

1. **Delphi version discrepancy**: Project targets Delphi 11 Alexandria but only Delphi 10.3 Rio (version 34.0) is available. Code changes are compatible with both.
2. **ILogger**: Uses OutputDebugString for lightweight logging; no file logging or log rotation
3. **Atomic save strategy**: Uses Win32 `MoveFileEx` with `MOVEFILE_REPLACE_EXISTING` for true atomic replacement — original file is only removed if the replacement succeeds; verified with failure-safety regression test
3. **Autosave redesign**: Uses dictionary keyed by note ID - preserves existing public API; stores TNote references (not copies) - depends on TNoteManager ownership
4. **BackupService**: CreateBackupZip has unused return value and unused Stream variable (minor warnings)
5. **Test infrastructure**: DUnitX v1.0 (installed with Delphi 10.3 Rio) works correctly — all 16 tests compile and pass using `[TestFixture]` and `[Test]` attributes
6. **uMonitorUtils**: Removed from project (compilation errors, unused); source file retained
7. **No runtime verification**: Application not executed in this environment

## Next Recommended Task

**Phase 3A — Persistence Architecture Analysis — is now complete**.

- 19/19 DUnitX tests compile and execute ✅
- Application builds with 0 errors ✅
- Full persistence flow documented (create, edit, autosave, startup, backup, restore) ✅
- INoteStorage confirmed as a clean, storage-agnostic abstraction ✅
- JSON format is NOT versioned — schema versioning recommended as Phase 3B ✅
- Recommendation: JSON NOW → SQLITE LATER (when search/scale requires it) ✅
- Roadmap defined through Phase 3E ✅

**Next steps**:

1. **Runtime verification** (in Delphi IDE if available): Execute the compiled application and verify the full note create/edit/delete/close/restart cycle
2. **Proceed to Phase 3B**: JSON Schema Versioning — add schema version field, implement read-compatibility

**Immediate next task**: Phase 3B — JSON Schema Versioning

---

## Files Changed During Verification

| File | Change |
|------|--------|
| `src/Storage/uJsonStorage.pas` | Atomic saves (temp file + `MoveFileEx` `MOVEFILE_REPLACE_EXISTING`), `CreateLogger` integration, corrupted JSON warning logs in `LoadAllNotes`, retry logic (3 attempts); uses `Winapi.Windows` |
| `src/Services/uAutosaveService.pas` | `FPendingNotes: TDictionary<Int64,TNote>` for multi-note pending saves, `CancelSave(const ANoteID)`, `CreateLogger` integration |
| `src/Services/uBackupService.pas` | `CreateLogger` integration, `DoRestore` split for try/except/finally clarity, `HandleMessage` public API |
| `src/Services/uHotkeyService.pas` | Added public `HandleMessage` method for message routing |
| `src/Utils/uILogger.pas` | Renamed from `ILogger.pas` → `uILogger.pas` (unit/interface name conflict), added `CreateLogger` factory function |
| `src/Forms/uNoteForm.pas` | Added `uAutosaveService`, `uEnums` to uses; removed `Flat` property (Delphi 10.3 incompatibility); fixed `FormStyle` assignment; added public `Save` wrapper |
| `src/Forms/uTrayForm.pas` | Added `Winapi.ShlObj` for `SHGetFolderPath`; use `FHotkeyService.HandleMessage`; call `Form.Save` instead of private `SaveNote` |
| `src/Forms/uAboutForm.pas` | Added `Winapi.ShellAPI` for `ShellExecute` |
| `build_tests.bat` | Changed `-I` (include path) to `-U` (unit path) for proper dcc32 unit resolution; replaced absolute paths with relative `..\src\*` paths |
| `src/StickyNotes.dpr` | Added `uILogger`, removed `uMonitorUtils` (unused, compilation issues) |
| `tests/StickyNotes.Tests.dpr` | DUnitX console runner using `TDUnitX.CreateRunner`, `TDUnitXConsoleLogger`, and `TDUnitX.CheckCommandLine` |
| `src/StickyNotes.dproj` | Removed `uMonitorUtils` from compilation |
| `tests/Models/TJsonStorageTests.pas` | Added `TestSaveNoteFailureSafety` regression test; added `System.SyncObjs` uses |
| `tests/Models/*.pas` | Converted to DUnitX `[TestFixture]`/`[Test]` attributes; fixed E2532 generic inference errors with explicit `<Int64>`/`<string>`/`<TNoteColor>` type parameters; fixed `IsNotNil` → `IsNotNull`; added `System.Generics.Collections` and `System.SyncObjs` uses; fixed use-after-free bug in loaded-note assertions; fixed TDictionary "Item not found" error with `AddOrSetValue` |
| `docs/DEVELOPMENT_PLAN.md` | Updated with verified build status, completed tasks, and Phase 1 completion status |

```
Phase 2 — Architecture: COMPLETE
  Phase 2A — TNoteApplication extraction: COMPLETE
    - [x] TNoteApplication class created in src/Application/uNoteApplication.pas
    - [x] Services extracted from TTrayForm to TNoteApplication
    - [x] Initialize/Shutdown lifecycle methods
    - [x] 3 architecture-level tests added (19 total, all pass)
  Phase 2B — Service/Form Decoupling: COMPLETE
    - [x] INoteEditorContext narrow interface created
    - [x] TNoteEditorContext adapter class created
    - [x] TNoteForm decoupled from 4 direct service dependencies
    - [x] TNoteForm now depends only on INoteEditorContext
  Phase 2C — Application/UI Event Boundary: COMPLETE
    - [x] Event flow analysis complete
    - [x] FNoteForms ownership analysis complete
    - [x] TNoteForm.OnClosed event added to fix dangling reference bug
    - [x] All 19 tests pass
Phase 3A — Persistence Architecture Analysis: COMPLETE
    - [x] Full persistence flow documented
    - [x] INoteStorage confirmed as clean abstraction
    - [x] JSON format versioning gap identified
    - [x] Recommendation: JSON NOW → SQLITE LATER
    - [x] Roadmap defined through Phase 3E
Explicit dependency injection: USED PRAGMATICALLY
DI container/framework: NOT PLANNED
SQLite storage: NOT IMPLEMENTED (stub only)
High-DPI: NOT ADDRESSED
Search: NOT IMPLEMENTED
Rich text: NOT IMPLEMENTED
```

## Phase 2A — TNoteApplication Extraction

### Architecture After

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
        ├── FNoteForms: TList<TNoteForm> (UI tracking, stays)
        └── FTrayController (dead code, documented)
```

### Ownership Table

| Object | Owner | Created By | Destroyed By |
|---|---|---|---|
| TNoteApplication | TTrayForm | TTrayForm.FormCreate | TTrayForm.FormDestroy |
| TNoteManager | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TSettingsController (owns TSettings) | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TAutosaveService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| THotkeyService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TThemeService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| TBackupService | TNoteApplication | TNoteApplication.Create | TNoteApplication.Destroy |
| INoteStorage (interface) | TNoteApplication | TNoteApplication.Create | auto (interface) |
| TList<TNoteForm> | TTrayForm | TTrayForm.FormCreate | TTrayForm.FormDestroy |
| TTrayController (unused) | TTrayForm | TTrayForm.FormCreate | TTrayForm.FormDestroy |
| TNoteForm | TTrayForm (Owner) | CreateNoteForm | VCL close |
| TTrayForm | VCL Application | .dpr CreateForm | VCL |

### Files Changed During Phase 2A

| File | Change |
|------|--------|
| `src/Application/uNoteApplication.pas` | **Created** — New application orchestration class |
| `src/Forms/uTrayForm.pas` | Thinned: removed 10 service fields, load/save/getAppDataPath; delegated to FApplication |
| `src/StickyNotes.dpr` | Added `uNoteApplication` to uses |
| `src/StickyNotes.dproj` | Added `Application\uNoteApplication.pas` compile item |
| `tests/Models/TNoteApplicationTests.pas` | **Created** — 3 architecture-level tests |
| `tests/StickyNotes.Tests.dpr` | Added TNoteApplicationTests unit |
| `build_tests.bat` | Added `..\src\Application` and `..\src\Controllers` to -U paths |
| `docs/DEVELOPMENT_PLAN.md` | Updated with Phase 2A completion status |
```

---

*Document created: 2026-08-31*
*Last updated: 2026-09-01*