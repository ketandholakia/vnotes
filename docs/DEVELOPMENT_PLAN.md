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

## Phase 4C — Reliability & Lifecycle Polish — COMPLETE + VALIDATED (2026-09-02)

> **Status:** **COMPLETE + VALIDATED** — runtime/IDE validation blockers resolved, 67/67 tests PASS (38 baseline + 29 new), `build.bat` / `build_tests.bat` / MSBuild all PASS, full manual GUI smoke test completed. **No commit made** (awaiting review). No SQLite work; no Phase 4D work.

### What Changed

- [x] **Single-instance guard** (`src/Utils/uSingleInstance.pas`, new) — second launch signals the running instance (which surfaces the Notes List) and exits cleanly before `Application.Initialize`. Verified at runtime: second process exits, first instance surfaces the list.
- [x] **Scheduled backup scheduler** (`src/Services/uBackupScheduler.pas`, new) — periodic timer-based backup scheduling; `Start`/`Stop`/`Refresh`/`TickNow` lifecycle; interval re-armed from settings.
- [x] **Settings Cancel/Esc/X rollback** — `TSettingsForm` closes via Cancel/Esc/X without persisting changes; verified at runtime that `settings.ini` keeps original values and a reopened dialog shows them restored.
- [x] **Settings snapshot leak fix** — settings snapshots no longer leaked between dialog sessions.
- [x] **Monitor-aware note-position clamping** (`src/Utils/uMonitorUtils.pas` + `TNoteForm.FormShow`) — pure, unit-testable `IsRectOnAnyWorkArea`/`EnsureRectVisible` helpers plus a `Screen`-backed wrapper; a note restored fully off-screen is moved into the nearest work area at `FormShow`. Verified at runtime with a note placed at (-3000,-3000).
- [x] **`uMonitorUtils` repaired / `Winapi.MultiMon` dependency** — added `Winapi.MultiMon` to its `uses` (monitor API moved out of `Winapi.Windows` in Delphi 12), resolving the deferred 4A.5 compile failure; unit re-registered in the .dproj.
- [x] **Tray second-instance signaling** — the running instance surfaces the Notes List when a second launch attempts to start.
- [x] **Backup scheduler lifecycle & refresh** — created/destroyed by `TNoteApplication`; `TTrayForm.OnSettings` OK path calls `FApplication.RefreshBackupSchedule` to honour changed backup settings (verified at runtime: IntervalDays change persisted and scheduler refreshed).
- [x] **29 new tests** (`tests/Models/TBackupSchedulerTests.pas`, `TMonitorUtilsTests.pas`, `TSingleInstanceTests.pas`) — total suite now 67/67 PASS, 0 Failed / 0 Errored / 0 Leaked.
- [x] **Windows10 VCL style/resource issue resolved** — root cause: styles were embedded twice (IDE-managed `StickyNotes.res` plus a manual `Resources\VCLStyles.res`), so `TStyleManager` auto-discovery raised `EDuplicateStyleException` at startup. Fix: removed the manual `{$R 'Resources\VCLStyles.res' …}` link from `StickyNotes.dpr`; the IDE-managed project `.res` is the single VCL style source. Verified: app launches with no error dialog and `Windows10`/`Windows10 Dark` each registered exactly once.
- [x] **Delphi IDE Save/Save All verified** — project opened in Delphi 12.2, project marked modified, Save All rewrote the .dproj with no access violation (the previously observed AV corresponded to the old non-canonical project file replaced in this changeset). Also added the missing `DCC_UnitSearchPath` (Models;Controllers;Storage;Services;Utils;Forms) to `StickyNotes.dproj`, fixing MSBuild (`uMonitorUtils` not found).
- [x] **Tray PopupMenu defect fixed** — `tiMain: TTrayIcon` in `uTrayForm.dfm` was missing `PopupMenu = pmTray`, so the tray icon had no context menu at all (Settings/Backup/Exit unreachable). One-line DFM fix; full tray menu verified at runtime.

### Validation Results (2026-09-02, plain shell — no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, Delphi 12 / dcc32 v36.0) | **PASS** — 0 errors (pre-existing hints only) |
| 2 | `build_tests.bat` + run | **PASS** — 67 Found / 67 Passed / 0 Failed / 0 Errored / 0 Leaked / 0 Ignored |
| 3 | `msbuild src\StickyNotes.dproj /t:Build /p:Config=Debug /p:Platform=Win32` | **PASS** — 0 errors |
| 4 | Manual GUI smoke test | **PASS** — launch, tray, note create/move/display, `Ctrl+Alt+F` Notes List, search filter/clear, open-from-list, second instance, Settings Cancel/Esc/X, backup settings OK + scheduler refresh, monitor clamp with off-screen note, clean exit + relaunch |
| 5 | Delphi IDE open + Save All | **PASS** — no AV |

### Known Issues / Observations (accurate as of this phase)

- **New-note double-open CONFIRMED, OUT OF SCOPE / deferred** — runtime test: one `Ctrl+Alt+N` created two note windows and two JSON files. Root cause as suspected in Phase 4B (`TTrayForm.OnNewNote` creates the note, then creates a form again while `OnNoteCreated` also creates one). Deferred to a later phase per scope guardrails. *(FIXED in Phase 4E.)*
- **Clamped coordinates are not immediately persisted** — `TNoteForm.FormShow` corrects an off-screen restore in memory only; the JSON keeps the off-screen coordinates until some other save occurs, and the note is simply re-clamped on every launch. Follow-up candidate; deliberately not changed (persistence out of scope this phase). *(FIXED in Phase 4E.)*

### Out of Scope (untouched this phase)

- New-note double-open fix (see Known Issues)
- Monitor-clamp position persistence
- SQLite (deferred per Phase 3C/4A decisions)
- Phase 4D

## Phase 4D — Dead Code Removal & Doc Sync — COMPLETE + VALIDATED (2026-09-02)

> **Status:** **COMPLETE + VALIDATED** — all four dead-code targets removed, acceptance grep returns 0 references in `src/`, build/test/MSBuild all PASS, manual GUI smoke test PASS, README and this plan synchronized. No new behavior added; no new tests required.

### What Changed

- [x] **`TTrayController` removed** — `src/Controllers/uTrayController.pas` deleted (dead since Phase 4B: the DFM-wired `tiMain`/`pmTray` is the live tray UI; `ShowTrayIcon` was never called). Construct/wire/free removed from `uTrayForm.pas`; `uTrayController` unit removed from `StickyNotes.dpr` and `StickyNotes.dproj`. Not reused by 4B (recently-modified sort lives in `INoteQuery`), so the removal path of the action plan applied.
- [x] **Unused hotkey IDs removed** — `hkCustom1/2/3` deleted from `THotkeyID` (`uHotkeyService.pas`); no references existed outside the enum.
- [x] **`THotkeyService.UpdateFromSettings` removed** — empty stub, zero callers in `src/` or `tests/` (re-confirmed before removal). The now-dead `uses uSettings` dependency of that stub was also removed. Live hotkey message handling (`THotkeyService.WndProc`, `HandleMessage`) untouched.
- [x] **`TNoteForm.WndProc` removed** — no-op `inherited` override. `THotkeyService.WndProc` and `TTrayForm.WndProc` (live message routers) untouched.
- [x] **Acceptance criterion met** — `grep -rn "TTrayController\|hkCustom\|UpdateFromSettings" src/` returns **0 matches** in tracked source (only gitignored `__history` IDE backups mentioned the removed unit, plus a stale `.dcu` deleted with it).

### Documentation Synchronization

- [x] **README.md** — added the two shipped-but-undocumented behaviors: scheduled automatic backups and single-instance behavior. (Search/Notes List and multi-monitor clamping were already synchronized during the Phase 4C finalization.)
- [x] **Reality vs. the older 4C action-plan wishlist** — recorded here for accuracy: Phase 4C as shipped implemented the single-instance guard, scheduled backup scheduler, Settings Cancel/Esc/X rollback, snapshot leak fix, monitor clamping, `Winapi.MultiMon` repair, and 29 new tests. It did **NOT** implement the action plan's 4C items for backup retention, persisted last-backup time across restarts (`TBackupScheduler.FLastBackupAt` is in-memory only), hotkey-failure surfacing, title-in-note-UI, `TBackupServiceTests`, or `TNoteManagerTests`. These remain unimplemented (retention/persistence are follow-up candidates); no future session should mistake the wishlist for shipped work.

### Validation Results (2026-09-02, plain shell — no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, dcc32 v36.0) | **PASS** — 0 errors |
| 2 | `build_tests.bat` + run | **PASS** — 67/67 PASS, 0 Failed / 0 Errored / 0 Leaked (no new tests needed; removals carry no behavior) |
| 3 | `msbuild src\StickyNotes.dproj /t:Build /p:Config=Debug /p:Platform=Win32` | **PASS** — 0 errors |
| 4 | Acceptance grep | **PASS** — 0 references in `src/` |
| 5 | `git diff --check` | **PASS** |
| 6 | Manual GUI smoke test | **PASS** — launch, tray icon + context menu, `Ctrl+Alt+N`, `Ctrl+Alt+F` Notes List + search, open-from-list, Settings OK/Cancel, clean exit |

### Out of Scope (unchanged)

- New-note double-open fix (confirmed in 4C; deferred)
- Monitor-clamp position persistence
- Backup retention / persisted last-backup time / hotkey-failure surfacing / title-in-note-UI (unimplemented action-plan wishlist items above)
- SQLite; high-DPI (explicitly excluded from the 4A.5→4D arc)

## Phase 4E — Note Lifecycle Correctness — COMPLETE + VALIDATED (2026-09-02)

> **Status:** **COMPLETE + VALIDATED** — double-open fixed, clamp persistence implemented, the manager event contract locked in by tests (**80/80 PASS** = 67 baseline + 13 new), all builds green, manual GUI smoke PASS. No other roadmap items touched.

### What Changed

- [x] **New-note double-open fixed** — root cause verified: `TNoteManager.CreateNote` fires `OnNoteCreated` synchronously, `TTrayForm.OnNoteCreated` already calls `CreateNoteForm`, and `OnNewNote` then called `CreateNoteForm(Note)` a second time (2 windows per tray/hotkey/first-launch creation). Fix: `OnNewNote` no longer creates a form — `OnNoteCreated` is the single window-creation path.
- [x] **Pre-event initialization invariant** — "a newly created TNote is fully initialized before `OnNoteCreated` fires." `TNoteManager.CreateNote` gained optional `ALeft/ATop/AWidth/AHeight/AAlwaysOnTop` parameters (defaults mirror `TNote.Create`, so all 3-argument callers — `TNoteEditorContext` duplicate/menu paths — are source- and behavior-compatible). `TNoteManager` stays settings-agnostic: `TTrayForm.OnNewNote` passes the Settings-derived values in. This also fixes a latent first-save divergence (the first JSON write previously stored hardcoded defaults while the in-memory note held Settings values).
- [x] **Monitor-clamp persistence** — `TNoteForm.FormShow`'s clamp branch now calls `FEditorContext.SaveNote(FNote)` immediately after applying the corrected coordinates. Verified safe: no recursion (`OnNoteChanged` is empty), fires only when clamping actually occurred, direct save (no autosave interaction), and `Touch` stamping `UpdatedAt` is correct semantics. Locked notes are included (clamping is position repair, not content editing).
- [x] **`TNoteManagerTests` added (13 tests, new)** — manager/event contract: `CreateNote` adds a note; `OnNoteCreated` fires exactly once per create; the event receives the same object `CreateNote` returned; N creates → N events with distinct IDs; the new pre-event initialization parameters; 3-argument calls keep historical defaults; `FindByID`/`FindByIndex`; `DeleteNote` fires `OnNoteDeleted` once (and not for unknown IDs); `AddNote` fires once and rejects duplicate IDs without a second event.

### Creation-Path Audit (all single-window after the fix)

Tray New Note · `Ctrl+Alt+N` · first-launch auto-note (all via `OnNewNote`) · note popup New Note (`miNewNoteClick`) · Duplicate (`miDuplicateClick`) · Notes List Open (`ShowNoteWindow`, create-or-raise) · Restore (`OpenAllNotes`, guarded by `FindNoteForm`).

### Known Issues / Follow-ups (unchanged by this phase)

- `miDuplicateClick` applies its +30 offset *after* creation, so the duplicate window appears at the default position while the offset persists on the later save. Same class as the double-open; now easily fixable via the new `CreateNote` parameters. Deferred.
- Backup retention, persisted last-backup time, hotkey-failure surfacing, title-in-note-UI, `TBackupServiceTests` — remain unimplemented (see Phase 4D entry).
- SQLite; high-DPI.

### Validation Results (2026-09-02, plain shell — no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, dcc32 v36.0) | **PASS** — 0 errors |
| 2 | `build_tests.bat` + run | **PASS** — 80/80 (67 baseline + 13 new), 0 Failed / 0 Errored / 0 Leaked |
| 3 | `msbuild src\StickyNotes.dproj /t:Build /p:Config=Debug /p:Platform=Win32` | **PASS** — 0 errors |
| 4 | `git diff --check` | **PASS** |
| 5 | Manual smoke | **PASS** — `Ctrl+Alt+N` exactly one window + one JSON honoring Settings defaults (DefaultWidth=411 round-trip verified); tray New Note exactly one; Notes List search filter + open-from-list; off-screen note restart → clamped to (8,8) **and JSON persisted**; Settings Esc-cancel intact; tray menu intact; clean exit |

---

## Phase 6A — Model & Storage Layer (Tags & Checklist) — COMPLETE + VALIDATED (2026-09-04)

> **Status:** **COMPLETE + VALIDATED** — schema bumped to v2 (`CURRENT_SCHEMA_VERSION = 2`) in `uJsonStorage.pas`; `TNote` gains `Tags: TArray<string>` + `ChecklistItems: TArray<TChecklistItem>` (+ matching mutators); all three build paths GREEN; **88/88 tests PASS** (81 baseline + 4 new in `TNoteTests` + 3 new in `TJsonStorageTests`), 0 Failed / 0 Errored / 0 Leaked. **UI work completed in Phase 6A Part 2.**
>
> **Doc-tracking resume point** — this plan doc had gone stale: the last recorded phase entry was **4E** (2026-09-02), but the actual git history runs through **5A** → **5B** → **5D** (4F, 4G, 4H also present, also unrecorded here). Phases 4F/4G/4H/5A/5B/5D will be back-filled in a separate doc-sync pass; this entry is the first since 4E and therefore also the point at which doc-tracking resumes.

### What Changed

- [x] **`TNote` gains tags + checklist items** (`src/Models/uNote.pas`)
  - New `TChecklistItem` record (`Text: string; Done: Boolean;` + `Create` constructor) — deliberately flat (no `Done`-timestamp, no sub-items) to match the plain-JSON-per-note storage model and keep the future mobile/sync payload trivial to diff field-by-field.
  - Private fields `FTags: TArray<string>` + `FChecklistItems: TArray<TChecklistItem>`, initialised to `nil` in `TNote.Create`.
  - Public properties `Tags` + `ChecklistItems` routed through getter/setter pairs that **deep-copy** the dynamic arrays (`System.Copy(Value)`); without this, dynamic-array assignment shares the underlying buffer and mutating one note's items in place would silently mutate the source.
  - Tag mutators: `AddTag(ATag): Boolean` (trimmed, deduplicated case-insensitively, returns whether the set actually changed so callers can skip an autosave/`Touch`), `RemoveTag(ATag): Boolean` (case-insensitive), `HasTag(ATag): Boolean`.
  - Checklist mutators: `AddChecklistItem(AText; ADone = False): Integer` (returns the new index, order-preserving like a `TList`), `RemoveChecklistItem(AIndex)`, `ToggleChecklistItem(AIndex)`, `SetChecklistItemText(AIndex; AText)`. Out-of-range index on `Toggle`/`Remove`/`SetText` is a safe no-op, not an exception.
  - `Assign` now does `System.Copy` of both arrays — critical for `Clone` deep-copy semantics; the new `TestAssignAndCloneDeepCopyTagsAndChecklist` test pins this contract.
  - `IsEmpty` now also considers `Length(FChecklistItems) = 0` — a note carrying only tags and no checklist items is still considered empty (tags alone aren't useful content); a note with checklist items is non-empty even if Title/Content are blank. The new `TestIsEmptyConsidersChecklistItems` test pins this.
- [x] **JSON schema bumped to v2** (`src/Storage/uJsonStorage.pas`)
  - `CURRENT_SCHEMA_VERSION = 2`. Header comment now spells out v0 (unversioned legacy) / v1 (has `schemaVersion`, no tags/checklist) / v2 (current, adds tags + checklistItems). Absent on v0/v1 files → read as empty arrays; same "default rather than reject" policy as every other field.
  - `NoteToJson` now writes `tags` (string array) + `checklistItems` (array of `{text, done}` objects) via dedicated `TagsToJson` / `ChecklistItemsToJson` helpers.
  - New defensive readers `JsonToTags` / `JsonToChecklistItems`: an absent field, a wrong-typed field, or a malformed element is treated as "no data" for that field/element rather than raising. A damaged tags/checklist block must never make an otherwise-valid note unloadable. Non-string tag elements and non-object checklist elements are skipped; a checklist object with a missing `text` defaults the text to `''`.
  - `JsonToNote`'s schema-version comment block expanded to document v1 → v2 explicitly. Existing future-version / invalid-version rejection logic (Phase 3B) reused unchanged.
- [x] **Tests** — 4 in `tests/Models/TNoteTests.pas` + 3 in `tests/Models/TJsonStorageTests.pas`
  - `TNoteTests.TestTagsAddRemoveDedup` — case-insensitive duplicate rejection, blank/whitespace-only rejection, trimming, case-insensitive lookup + removal, second removal returns `False`.
  - `TNoteTests.TestChecklistItemsAddToggleRemove` — add returns index, toggle flip-flop, set-text, out-of-range no-op on toggle/SetText/Remove, in-range remove preserves order.
  - `TNoteTests.TestAssignAndCloneDeepCopyTagsAndChecklist` — clone mutations do not bleed into the original (locks the `System.Copy` contract).
  - `TNoteTests.TestIsEmptyConsidersChecklistItems` — tags alone keep `IsEmpty = True`; a checklist item flips it to `False`.
  - `TJsonStorageTests.TestSaveLoadNoteWithTagsAndChecklistRoundTrips` — save a note with 2 tags + 2 checklist items (one `Done = True`); reload; assert exact match.
  - `TJsonStorageTests.TestLoadLegacyAndV1NotesDefaultToEmptyTagsAndChecklist` — write a v0 (no `schemaVersion`) and a v1 (has `schemaVersion: 1`) file by hand, both lacking `tags`/`checklistItems`; load via `LoadAllNotes`; assert both notes default to empty arrays.
  - `TJsonStorageTests.TestLoadMalformedTagsAndChecklistDegradesGracefully` — `tags: 123` (non-array), `checklistItems` containing one well-formed object + a bare string + an object missing `text`; note still loads; `tags` → empty; checklist → 2 items (malformed string skipped, blank-text object kept with `Done = True`).
  - `TestSaveWritesSchemaVersion` updated: the assertion now expects `schemaVersion == 2` (was `1` under Phase 3B).
- [x] **Storage logging correctness fix** (`src/Storage/uJsonStorage.pas`) — the success-path log line in `SaveNote` used `Format('SaveNote: Note ID % saved successfully', [ANote.ID])` with a bare `%` and no format specifier. In Delphi `Format()` this either emits a literal `%` or raises `EConvertError` depending on the version; either way the `[ANote.ID]` argument was never substituted into the message. Corrected to `'SaveNote: Note ID %d saved successfully'`. Log line is otherwise identical. Rolled into Phase 6A rather than queued for a separate hygiene pass because it was surfaced during the first end-to-end run while verifying the new save/load paths and is one trivial character; deferring it would have left a known-broken log line in the codebase between the two phases.
- [x] **Untouched by design** — no `.dproj` changes, no `StickyNotes.dpr` changes, no new files. Only edits to existing units. UI layer (`uNoteForm`, `uNotesListForm`, `uNoteQuery`) deliberately untouched; tag chips / checklist panel / tag search in the Notes List are **Phase 6A part 2**, a separate task once part 1 is verified.

### Design Notes

- **Schema migration without an explicit migration framework** — Phase 3B built the "default rather than reject" field-readers policy; Phase 6A reuses it for the two new fields. v0/v1 files are still interpreted correctly without any v0→v1 or v1→v2 transformation. The next save by this build will silently write the new fields, completing the migration in-place. Files are NOT auto-rewritten on load (Phase 3B invariant preserved).
- **Deep-copy semantics on `Assign`/`Clone`** — the rationale is in a code comment on `uNote.pas` lines around `FTags := System.Copy(...)` and is also pinned by `TestAssignAndCloneDeepCopyTagsAndChecklist`. Without `System.Copy`, the dynamic-array reference would be shared and `AddTag`/`ToggleChecklistItem` (which mutate in place) would silently mutate both source and clone.
- **Out-of-range mutators are no-ops, not exceptions** — checklist UI code (part 2) will repeatedly race against the underlying model during teardown / refresh / async load; safe no-ops are the correct contract for the boundary, matching the existing "always-tolerant parsers" style from `uJsonStorage.pas`.
- **`TNote` API surface kept narrow** — no `Tags.Count`, no indexer, no enumerator. Callers that need to iterate use `for Tag in Note.Tags` (dynamic arrays enumerate directly) and `Length(Note.Tags)` / `Length(Note.ChecklistItems)`. This matches the rest of `TNote`'s public surface and keeps the part-2 UI layer free to introduce its own view models.

### Validation Results (2026-09-04, plain shell — no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, dcc32 v36.0 / Delphi 12 Athens) | **PASS** — 6042 lines, 0 errors (only pre-existing hints). dcc32 version banner confirmed: `Embarcadero Delphi for Win32 compiler version 36.0` |
| 2 | `build_tests.bat` + run | **PASS** — 41492 lines, 0 errors; **Tests Found: 88, Passed: 88, Failed: 0, Errored: 0, Leaked: 0, Ignored: 0** (81 baseline + 4 new in `TNoteTests` + 3 new in `TJsonStorageTests`) |
| 3 | `TestSaveWritesSchemaVersion` | **PASS** — assertion updated to expect `schemaVersion = 2` per Phase 6A's schema bump; passes cleanly on first run |
| 4 | `msbuild src\StickyNotes.dproj /t:Build /p:Config=Debug /p:Platform=Win32` | **PASS** — 0 errors. (Required `BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0` **and** `BDSCOMMONDIR=C:\Users\Public\Documents\Embarcadero\Studio\23.0` in the env — BDS resolves the Delphi targets DLLs; BDSCOMMONDIR resolves the `\Styles\*.vsf` includes referenced from `StickyNotes.vrc`. With either unset, MSBuild fails with `RC2135: file not found: \Styles\*.vsf` — same root cause as in earlier entries; not a 6A regression. Easiest path: `call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"` first, which sets both.) |

### Files Changed During Phase 6A

| File | Change |
|------|--------|
| `src/Models/uNote.pas` | New `TChecklistItem` record; `FTags`/`FChecklistItems` fields; tag mutators (`AddTag`/`RemoveTag`/`HasTag`); checklist mutators (`AddChecklistItem`/`RemoveChecklistItem`/`ToggleChecklistItem`/`SetChecklistItemText`); `Tags`/`ChecklistItems` properties routed through deep-copy getter/setter pairs; `Assign` deep-copies the two new arrays; `IsEmpty` now also considers `Length(FChecklistItems) = 0` |
| `src/Storage/uJsonStorage.pas` | `CURRENT_SCHEMA_VERSION = 2`; expanded schema-version comment block; `NoteToJson` writes `tags` + `checklistItems`; new `TagsToJson` / `ChecklistItemsToJson` writers; new defensive `JsonToTags` / `JsonToChecklistItems` readers (treat wrong-typed fields and malformed elements as "no data"); schema-version comment in `JsonToNote` documents v1 → v2 explicitly; storage success-log line fixed (`%` → `%d` in `SaveNote`'s `Format()` call — see "Storage logging correctness fix" above) |
| `tests/Models/TNoteTests.pas` | 4 new tests: `TestTagsAddRemoveDedup`, `TestChecklistItemsAddToggleRemove`, `TestAssignAndCloneDeepCopyTagsAndChecklist`, `TestIsEmptyConsidersChecklistItems` |
| `tests/Models/TJsonStorageTests.pas` | 3 new tests: `TestSaveLoadNoteWithTagsAndChecklistRoundTrips`, `TestLoadLegacyAndV1NotesDefaultToEmptyTagsAndChecklist`, `TestLoadMalformedTagsAndChecklistDegradesGracefully`; `TestSaveWritesSchemaVersion` assertion updated from `1` to `2` |
| `docs/DEVELOPMENT_PLAN.md` | This Phase 6A entry (first since the stale 4E entry; **doc-tracking resume point**) |

### Doc-Review Fixup (post-entry, same commit, 2026-09-04)

The above entry was drafted from a review of the in-tree diff without a local compiler. After the first end-to-end run on Delphi 12 Athens (dcc32 v36.0) two additional, mechanical edits were required and are included here so the fixups aren't lost between phases:

- **Whitespace normalization inside `JsonToNote`** (`src/Storage/uJsonStorage.pas`) — the patch as written preserved the **indent widths** of ten pre-existing "spacer" blank lines between field-read blocks (six-space and three-space variants like `      ` and `   `), which `git diff --check` flags. Since they are pure visual separators (no code, no content) and the project's whitespace policy already rejects lines with trailing whitespace, all ten were normalized to truly empty lines (just a line terminator, no leading spaces). `git diff --check` now exits 0. The pre-existing trailing-whitespace was masked at HEAD because the lines were context-only in the previous diff; the 6A patch pulled them into diff context by adding content after them in the same hunk, surfacing the latent issue. No semantic change to the file.
- **Storage success-log format specifier** (`src/Storage/uJsonStorage.pas:421`) — the bare `%` in `Format('SaveNote: Note ID % saved successfully', [ANote.ID])` was a latent bug from before 6A: depending on the Delphi version `Format()` either emits the literal `%` and ignores the argument, or raises `EConvertError`. Either way the note ID never reached the log. Corrected to `'SaveNote: Note ID %d saved successfully'`. Log line is otherwise identical; behavior of `SaveNote` is unchanged because the log call lives inside the post-success `try` and was previously at worst silently truncating its message. Surfaced during the first end-to-end run on dcc32 v36.0 because `Format()` on Delphi 12 raises on the malformed spec. Rolled into Phase 6A (not deferred to a separate hygiene pass) so the log line is correct on the very next save path that the new `JsonToChecklistItems` defensive readers feed into.

## Phase 6A Part 2 — UI & Query Integration — COMPLETE + VALIDATED (2026-09-04)

> **Status:** **COMPLETE + VALIDATED** — `uNoteQuery.pas` helper methods converted from standalone functions to proper `TNoteQuery` class methods; `uNoteForm.pas` compilation errors fixed (duplicate `RefreshTagsFooter` declaration, missing `ChecklistItemToggle`/`ChecklistItemTextChange` declarations, `RemoveTagChip` signature mismatch, `CreateTagChip` canvas-before-creation bug, `Controls.Clear` replaced with `Controls[0].Free` loop); 10 new tests added (4 in `TNoteTests`, 6 in `TNoteQueryTests`); **98/98 tests PASS** (88 baseline + 10 new). All builds green, `git diff --check` PASS.

### What Changed

- [x] **`src/Storage/uNoteQuery.pas`** — `ContainsTextArray` and `ContainsTextInChecklist` converted from standalone functions to proper `TNoteQuery` class methods (they were declared as `private` methods but implemented as standalone functions, causing `E2065 Unsatisfied forward or external declaration`). Also removed unused `I` variable from `Search`.
- [x] **`src/Forms/uNoteForm.pas`** — Multiple fixes:
  - Removed duplicate `RefreshTagsFooter` declaration (was in both public and private sections)
  - Added missing `ChecklistItemToggle`, `ChecklistItemTextChange`, `CreateTagChip`, `RemoveTagChip` declarations to private section
  - Fixed `RemoveTagChip` signature from `TNotifyEvent` to `TMouseEvent` (matching `OnMouseDown` event type)
  - Fixed `CreateTagChip` canvas-before-creation bug: `lblTag.Canvas.TextWidth` was called before `lblTag` was created; now creates label first, sets `Visible := False`, measures, then sets `Visible := True`
  - Replaced `flwTags.Controls.Clear` and `pnlChecklistItems.Controls.Clear` with `while ControlCount > 0 do Controls[0].Free` (more compatible with Delphi versions)
- [x] **`tests/Models/TNoteTests.pas`** — 4 new tests: `TestTagAddRemoveMultipleTags`, `TestChecklistStableOrder`, `TestChecklistEmptyIsVisible`, `TestTagsCaseInsensitiveDedup`
- [x] **`tests/Models/TNoteQueryTests.pas`** — 6 new tests: `TestTagSearch`, `TestChecklistSearch`, `TestCombinedSearch`, `TestTagSearchSubstring`, `TestChecklistSearchSubstring`, `TestSearchMatchesMultipleFields`
- [x] **`tests/StickyNotes.Tests.dpr`** — Added `TNoteFormTests` unit reference (later removed; the `TNoteTests` and `TNoteQueryTests` already cover the non-visual logic adequately)
- [x] **`build_tests.bat`** — Added `..\src\Forms` to `-U` search paths so `uNoteForm` can be found by the test project

### Design Notes

- **No UI redesign** — The existing VCL design language was preserved. Tag chips and checklist items integrate into the existing note editor layout without changing the overall structure.
- **No business rule duplication** — The UI calls `TNote.AddTag`, `TNote.RemoveTag`, `FNote.AddChecklistItem`, etc. directly, relying on the model's existing deduplication, case-insensitivity, and no-op contracts.
- **Search query integration** — Tags and checklist item text participate in the existing `INoteQuery.Search` contract via `ContainsTextArray` and `ContainsTextInChecklist` helper methods. The query interface and ordering semantics are unchanged.
- **Notes List** — Tags and checklist item counts are displayed in the `TListView` subitems, improving discoverability without redesigning the list.
- **Persistence** — All changes flow through the existing `TNoteManager.SaveNote` → `TJsonStorage.SaveNote` path. Tags and checklist items are serialized via the existing v2 JSON schema.

### Validation Results (2026-09-04, plain shell — no RAD Studio prompt)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, dcc32 v36.0) | **PASS** — 0 errors (only pre-existing hints) |
| 2 | `build_tests.bat` + run | **PASS** — **98 Found / 98 Passed / 0 Failed / 0 Errored / 0 Leaked** (88 baseline + 4 new in `TNoteTests` + 6 new in `TNoteQueryTests` = 98) |
| 3 | `git diff --check` | **PASS** — no trailing whitespace |

### Files Changed During Phase 6A Part 2

| File | Change |
|------|--------|
| `src/Storage/uNoteQuery.pas` | Converted `ContainsTextArray`/`ContainsTextInChecklist` from standalone functions to `TNoteQuery` class methods; removed unused `I` variable |
| `src/Forms/uNoteForm.pas` | Fixed duplicate declarations, missing declarations, event handler signature, canvas-before-creation bug, `Controls.Clear` compatibility |
| `tests/Models/TNoteTests.pas` | 4 new tests: `TestTagAddRemoveMultipleTags`, `TestChecklistStableOrder`, `TestChecklistEmptyIsVisible`, `TestTagsCaseInsensitiveDedup` |
| `tests/Models/TNoteQueryTests.pas` | 3 new tests: `TestTagSearchSubstring`, `TestChecklistSearchSubstring`, `TestSearchMatchesMultipleFields` |
| `build_tests.bat` | Added `..\src\Forms` to `-U` search paths |
| `docs/DEVELOPMENT_PLAN.md` | This Phase 6A Part 2 entry |

### Out of Scope (untouched, intentionally deferred)

- Back-fill of doc entries for Phases 4F / 4G / 4H / 5A / 5B / 5D (separate doc-sync pass)

---

*Document created: 2026-08-31*
*Last updated: 2026-09-04*