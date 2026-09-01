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
6. **uMonitorUtils**: Reserved for the Phase 4C monitor-clamp task (one-line header comment added in Phase 4A.5); re-registered in `StickyNotes.dproj`. Standalone compile on Delphi 12 FAILS until `Winapi.MultiMon` is added to its `uses` clause (monitor API moved out of `Winapi.Windows`) — fix deferred to Phase 4C when it is wired into `TNoteForm.FormShow`
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
Phase 3B — JSON Schema Versioning: COMPLETE
    - [x] schemaVersion field added (CURRENT_SCHEMA_VERSION = 1)
    - [x] Unversioned legacy files interpreted as schema version 0
    - [x] Future schema versions (> 1) safely rejected, file preserved
    - [x] Invalid schemaVersion (string/null/object/array/negative) safely rejected
    - [x] Legacy files are NOT automatically rewritten
    - [x] LoadAllNotes distinguishes corrupt JSON vs unsupported schema
    - [x] No migration framework (deferred); v0→v1 requires no field transformation
    - [x] INoteStorage unchanged; BackupService unchanged (tolerant parser)
    - [x] All 24 tests pass (19 existing + 5 new schema tests)
Phase 3C — SQLite Readiness & Migration Design Analysis: COMPLETE (analysis only)
    - [x] Current persistence boundary re-verified from source (TNoteManager → INoteStorage → TJsonStorage)
    - [x] SQLite requirement assessment: no call site, no scheduled feature, no test requires SQLite
    - [x] INoteStorage confirmed sufficient for a future TSQLiteStorage (no new methods needed)
    - [x] JSON → SQLite conceptual field mapping documented
    - [x] Two versioning systems distinguished: per-file JSON schemaVersion vs SQLite user_version PRAGMA
    - [x] Migration strategy designed (B. First-run migration, read-only JSON, automatic rollback on partial failure)
    - [x] Rollback strategy designed (impossible to corrupt JSON sources by design)
    - [x] Backup/Restore strategy analyzed: TBackupService unchanged in this phase
    - [x] Autosave impact verified: TAutosaveService is storage-agnostic, no changes required
    - [x] Delphi 10.3 / Win32 decision points recorded (FireDAC vs alternatives, static vs dynamic)
    - [x] Decision: B — Prepare for SQLite, defer implementation
    - [x] Future roadmap defined (3D SQLite impl, 3E first-run migration, 3F backup adaptation)
    - [x] No source files modified
    - [x] All 24 tests still pass (no test changes)

Phase 4A — Product Development Roadmap Analysis: COMPLETE (analysis only)
    - [x] Full source-grounded feature inventory (no claims accepted from README alone)
    - [x] Feature matrix compiled (see `docs/PHASE_4A_ANALYSIS.md` § "Feature Matrix")
    - [x] User-facing workflow audit completed (tray, note CRUD, positioning, autosave, backup, hotkeys, settings, multi-monitor, themes, shutdown)
    - [x] Technical-debt inventory by priority
    - [x] Test coverage gap analysis
    - [x] Dead-code review
    - [x] Documentation-vs-source accuracy check
    - [x] SQLite-trigger re-verification: NONE present → SQLite remains DEFERRED
    - [x] Recommended next phase selected: **Phase 4B — Note list + in-memory search**
    - [x] Smallest sensible Phase 4 roadmap (4B, 4C, 4D) drafted
    - [x] No source files modified
    - [x] No tests modified
    - [x] Test baseline preserved: 24/24 PASS

**Full Phase 4A analysis:** see `docs/PHASE_4A_ANALYSIS.md` (analysis only — no source/test changes; this file documents feature matrix, technical debt, test coverage gaps, architecture assessment, dead code, documentation accuracy, SQLite status, the recommended Phase 4B next step, the smallest-sensible Phase 4 roadmap (4B, 4C, 4D), and the manual smoke-test plan).
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

## Phase 4A.5 — Repo & Build Hygiene

> Status: COMPLETE + VALIDATED (2026-09-01). No `src/Application`, `src/Controllers`, `src/Models`, `src/Services`, `src/Storage`, or `src/Forms` files were modified — the only source change is `src/Utils/uMonitorUtils.pas` (marked as reserved for Phase 4C) plus its re-registration in `src/StickyNotes.dproj`. No tests modified; baseline 24/24 PASS preserved. Toolchain: **Delphi 12 Athens / RAD Studio 23.0** (dcc32 v36.0).

### Toolchain Bootstrap (both scripts)

`build.bat` and `build_tests.bat` now self-configure the Delphi toolchain before invoking dcc32:
- If `DELPHI_ROOT` is set and contains `bin\rsvars.bat`, that is used.
- Otherwise probe in order: `C:\Program Files (x86)\Embarcadero\Studio\23.0`, then `22.0`, then `21.0`.
- First existing `bin\rsvars.bat` wins and is `call`ed (sets PATH/BDS).
- If none found: clear error naming all tried paths, then `exit /b 1`.
- After rsvars, echo the resolved `dcc32` path and version banner (absorbs `check_version.bat`'s role).
- `build.bat` also `mkdir`s the `-N` output dir (`Win32\Debug` — dcc32 does not auto-create it), so a fresh checkout succeeds.

### What Changed

- [x] **`build_log.txt` deleted** — contained a stale/misleading dcc32 log that compiled `StickyNotes.dproj` (XML) instead of `StickyNotes.dpr`. `.gitignore` already ignores `build_log.txt`, so it will not reappear.
- [x] **18 root build/helper scripts consolidated to two**:
  - `build.bat` — canonical main-app build (Win32 Debug), portable via `%~dp0`, self-bootstrapped toolchain.
  - `build_tests.bat` — canonical DUnitX test build; `DUNITX_PATH` derived from the resolved Delphi root (`%DELPHI_ROOT%\source\DunitX`).
  - Deleted 17 redundant scripts: `build_main.bat`, `build_main2.bat`, `build_main3.bat`, `build_backup.bat`, `build_tests2..9.bat`, `build_tnote_test*.bat`, `build_unote.bat`, `check_version.bat`. (The plan tabulated 18 scripts including `check_version.bat`.)
  - No dangling references: grep for `build_main`, `build_tests2..9`, `build_backup`, `build_unote`, `build_tnote`, `check_version` found hits only in history/plan docs (DEVELOPMENT_PLAN, VNOTES_ACTION_PLAN) and `build.bat`'s own REM comment; no `<PreBuildEvent>`/`<PostBuildEvent>` nodes in `StickyNotes.dproj`; no CI config present.
- [x] **`src/Utils/uMonitorUtils.pas` resolved** — was orphaned (unreferenced, absent from `StickyNotes.dproj`). Now: one-line header comment marks it **reserved for the Phase 4C monitor-clamp task**, and it is re-registered in `src/StickyNotes.dproj`. **Note:** its first standalone compile on Delphi 12 FAILS (see Validation) — the monitor API (`TMonitorInfo`, `MonitorFromWindow`, etc.) lives in `Winapi.MultiMon` in Delphi 12, not `Winapi.Windows`; fix deferred to Phase 4C per task instruction (report, do not fix).
- [x] **`.gitignore` extended** for IDE-generated project-local files: `*.local`, `*.dsk`, `*.dproj.local`, `*.dpr.local`, `*.stat`, `*.ddp` (in addition to the existing `*.dcu`, `*.exe`, `*.identcache`, `__history/`, `Win32/`, `*.log`, etc.).
- [x] **`README.md` corrected**:
  - "Search Notes" hotkey (`Ctrl+Alt+F`) marked **PLANNED (Phase 4B)** — hotkey is registered but the handler is a `// TODO: Show search form` stub that currently falls back to re-showing note windows.
  - Multi-monitor support marked **PARTIAL** — notes restore to their last monitor, but there is no clamp-to-monitor logic yet (`uMonitorUtils` reserved for Phase 4C).
  - Build section documents `build.bat` / `build_tests.bat` and their self-configuring toolchain.

### Validation Results (2026-09-01, plain cmd — no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, Delphi 12) | **PASS** — `dcc32 v36.0`, 4415 lines, 0 errors (only H2219/H2077/H2164/H2269/H2443 hints). Output: `src\Win32\Debug\StickyNotes.exe` |
| 2 | `build_tests.bat` + test run | **PASS** — 38628 lines, 0 errors; `StickyNotes.Tests.exe` ran **24/24 PASS, 0 Failed, 0 Erred, 0 Leaked, 0 Ignored** |
| 3 | `msbuild src\StickyNotes.dproj /t:Build /p:Config=Debug /p:Platform=Win32` | **PASS** — project file well-formed (0 errors, only hints); confirms the `uMonitorUtils` compile-item edit is valid |
| 4 | Standalone compile of `uMonitorUtils.pas` (same search paths as build.bat) | **FAILS** — first real compile; E2003 undeclared identifiers (verbatim below). Reported per task 6.4; **not fixed here** (deferred to Phase 4C with the FormShow wire-up) |
| 5 | Full build -> `git status` | **CLEAN** — no regenerated build artifacts appear (validates new `.gitignore`). **Note:** `msbuild` regenerates the tracked `src/StickyNotes.res` (cgrc); it was restored with `git checkout` after validation. |

**uMonitorUtils standalone compile errors (verbatim, Delphi 12 / dcc32 36.0):**

```
Utils\uMonitorUtils.pas(17) Error: E2003 Undeclared identifier: 'TMonitorInfo'
Utils\uMonitorUtils.pas(32) Error: E2003 Undeclared identifier: 'MonitorFromWindow'
Utils\uMonitorUtils.pas(32) Error: E2003 Undeclared identifier: 'MONITOR_DEFAULTTONEAREST'
Utils\uMonitorUtils.pas(37) Error: E2007 Constant or type identifier expected
Utils\uMonitorUtils.pas(40) Error: E2066 Missing operator or semicolon
Utils\uMonitorUtils.pas(47) Error: E2007 Constant or type identifier expected
Utils\uMonitorUtils.pas(50) Error: E2066 Missing operator or semicolon
Utils\uMonitorUtils.pas(62) Error: E2003 Undeclared identifier: 'MonitorFromPoint'
Utils\uMonitorUtils.pas(62) Error: E2003 Undeclared identifier: 'MONITOR_DEFAULTTOPRIMARY'
Utils\uMonitorUtils.pas(65) Error: E2005 'TMonitorInfo' is not a type identifier
Utils\uMonitorUtils.pas(67) Error: E2066 Missing operator or semicolon
Utils\uMonitorUtils.pas(68) Error: E2033 Types of actual and formal var parameters must be identical
Utils\uMonitorUtils.pas(105) Error: E2003 Undeclared identifier: 'MonitorFromPoint'
Utils\uMonitorUtils.pas(105) Error: E2003 Undeclared identifier: 'MONITOR_DEFAULTTONEAREST'
Utils\uMonitorUtils.pas(110) Error: E2003 Undeclared identifier: 'MonitorFromRect'
Utils\uMonitorUtils.pas(110) Error: E2003 Undeclared identifier: 'MONITOR_DEFAULTTONEAREST'
Utils\uMonitorUtils.pas(151) Error: E2003 Undeclared identifier: 'MonitorFromPoint'
Utils\uMonitorUtils.pas(151) Error: E2003 Undeclared identifier: 'MONITOR_DEFAULTTONEAREST'
```

Root cause (confirmed against Delphi 12 RTL source): `Winapi.Windows.pas` does NOT declare the monitor API in Delphi 12 — `tagMONITORINFO`/`TMonitorInfo`/`MonitorFrom...` are declared in `Winapi.MultiMon.pas` (a separate unit at `source\rtl\win\Winapi.MultiMon.pas`). Phase 4C monitor-clamp work must add `Winapi.MultiMon` to `uMonitorUtils.pas`'s `uses` clause when it is referenced from `FormShow`.

### Files Changed During Phase 4A.5

| File | Change |
|------|--------|
| `build_log.txt` | **Deleted** — stale dcc32 run against `.dproj` XML instead of `.dpr` |
| `build.bat` | **Created** — canonical main build; self-bootstrap toolchain (DELPHI_ROOT / 23.0 / 22.0 / 21.0), `mkdir Win32\Debug`, version banner echo (absorbs `check_version.bat`), portable `%~dp0` |
| `build_tests.bat` | `cd` portable; self-bootstrap toolchain; `DUNITX_PATH` derived from resolved Delphi root |
| `build_main*.bat`, `build_backup.bat`, `build_tests2..9.bat`, `build_tnote_test*.bat`, `build_unote.bat`, `check_version.bat` | **Deleted** — redundant per-script build helpers (17 files) |
| `src/Utils/uMonitorUtils.pas` | One-line header comment: reserved for Phase 4C monitor-clamp task |
| `src/StickyNotes.dproj` | Re-added `Utils\uMonitorUtils.pas` to `<Compile>` items |
| `.gitignore` | Added `*.local`, `*.dsk`, `*.dproj.local`, `*.dpr.local`, `*.stat`, `*.ddp` |
| `README.md` | Search hotkey marked Planned (Phase 4B); multi-monitor marked Partial; build section self-configuring toolchain |
| `docs/DEVELOPMENT_PLAN.md` | This Phase 4A.5 entry (now COMPLETE + VALIDATED) |

## Phase 4B - Note List + In-Memory Search - COMPLETE + VALIDATED (2026-09-02)

> **Status:** **COMPLETE + VALIDATED** - `INoteQuery` abstraction + DUnitX coverage landed first, then the `TNotesListForm` UI on top. Application and test builds pass; **38/38 tests** (24 baseline + 14 new query tests); msbuild `.dproj` build passes. **No commit made** (awaiting review).

### What Changed

- [x] **`src/Storage/uNoteQuery.pas` (new)** - `INoteQuery.Search(AQuery, ANotes: TObjectList<TNote>): TObjectList<TNote>` implemented by `TNoteQuery`. Case-insensitive substring match across `Title` + `Content` (`ContainsText`); `Trim`med query; empty/blank query returns ALL notes; nil source safe. Deterministic order: `UpdatedAt` descending, tie-broken by `ID` descending. **Ownership contract (documented on the interface):** the query never owns notes - every result/temporary list is created `OwnsObjects := False`; search never mutates notes or touches persistence.
- [x] **`tests/Models/TNoteQueryTests.pas` (new)** - 14 DUnitX tests: empty collection, empty query, exact/partial title, case-insensitive, content match, no match, multiple matches, no-mutation, **ownership safety** (result `OwnsObjects = False`; freeing results leaves manager-owned notes alive), whitespace tolerance, nil source, plus 2 ordering tests (most-recent-first; `ID`-desc tie-break) using explicit `UpdatedAt` stamps.
- [x] **`src/Forms/uNotesListForm.pas` + `.dfm` (new)** - search `TEdit` + `TListView` (Title/Modified, RowSelect) + Open button. `CreateFor(AOwner, TNoteManager, INoteQuery)`; `RefreshList` builds an `OwnsObjects := False` snapshot from the manager, runs the query, stores `TNote` pointers in `ListView.Data` (display-only); Enter/Esc/DblClick handling; `caHide` on close (form reused, never owns notes); `OnOpenNote: TOpenNoteEvent` (`of object`, matching `TNoteEvent` conventions).
- [x] **`src/Forms/uTrayForm.pas`** - `FNoteQuery := TNoteQuery.Create` at startup; lazy-created `FNotesListForm`; `ShowNotesList(AFocusSearch)`; new `FindNoteForm`/`ShowNoteWindow` (bring an already-open note window to front/restore it, else reuse the single `CreateNoteForm` path - no duplicated note lifecycle); tray menu "Open Notes List" now shows the list; **`Ctrl+Alt+F` (`OnHotkeySearch`) opens the list and focuses+selects the search box** (replaces the 4A.5 TODO stub); list resyncs (`RefreshList`) on note created/deleted.
- [x] **Registrations** - `StickyNotes.dpr` (+2 units), `StickyNotes.dproj` (+2 `<Compile>`, +1 `<FormResource>`), `tests/StickyNotes.Tests.dpr` (+fixture).

### Design Notes / Deviations

- Result ordering lives in the **query layer**, not the form - single source of truth; subsumes the action plan's "sort in list form" item.
- `OnOpenNote` uses an `of object` event type instead of `TProc<TNote>` to match existing codebase conventions (`TNoteEvent`).
- No sorting/grouping/tagging, no persistence changes, no `TNoteManager` modifications.

### Validation Results (2026-09-02, plain shell - no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, Delphi 12 / dcc32 v36.0) | **PASS** - exit 0, 4750 lines, 0 errors (only pre-existing hints) |
| 2 | `build_tests.bat` + run | **PASS** - BUILD SUCCESSFUL; **Tests: 38 Found / 38 Passed / 0 Failed / 0 Errored / 0 Leaked / 0 Ignored** (24 baseline + 14 new) |
| 3 | `msbuild src\StickyNotes.dproj /t:Build /p:Config=Debug /p:Platform=Win32` | **PASS** - exit 0, 0 errors; validates the new dproj registrations |
| 4 | Full build -> `git status` | **CLEAN** - no build artifacts reappeared; msbuild-regenerated `src/StickyNotes.res` restored via `git checkout` (known cgrc behavior from 4A.5) |

### Manual Verification Still Recommended (VCL behavior, not unit-testable here)

Hotkey `Ctrl+Alt+F` focus/select-all; open list from tray menu; typing filters; clearing restores all; opening an already-open note brings its window to front instead of duplicating; deleting a note while the list is open resyncs the list; app shutdown with the list open.

### Files Changed During Phase 4B

| File | Change |
|------|--------|
| `src/Storage/uNoteQuery.pas` | **Created** - `INoteQuery`/`TNoteQuery` (ownership contract documented) |
| `tests/Models/TNoteQueryTests.pas` | **Created** - 14 DUnitX tests incl. ownership-safety |
| `src/Forms/uNotesListForm.pas` + `.dfm` | **Created** - note list/search window |
| `src/Forms/uTrayForm.pas` | Query instance, list-form lifecycle, hotkey + tray-menu wiring, note create/delete resync, `FindNoteForm`/`ShowNoteWindow`/`ShowNotesList` |
| `src/StickyNotes.dpr`, `src/StickyNotes.dproj` | Register `uNoteQuery`, `uNotesListForm` (+ dfm resource) |
| `tests/StickyNotes.Tests.dpr` | Register `TNoteQueryTests` |
| `docs/DEVELOPMENT_PLAN.md` | This Phase 4B entry |

### Out-of-Scope Observation (NOT fixed, flagged for a later phase)

While integrating, a **suspected pre-existing double-open on new notes** was noticed: `TTrayForm.OnNewNote` calls `NoteManager.CreateNote` (which fires `OnNoteCreated` -> `CreateNoteForm`) and *then* calls `CreateNoteForm(Note)` explicitly again - likely opening two windows per new note. Unverified at runtime; predates Phase 4B; left untouched per scope guardrails.

---

*Document created: 2026-08-31*
*Last updated: 2026-09-02*