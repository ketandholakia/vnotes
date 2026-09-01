# Phase 4A — Product Development Roadmap Analysis (Analysis only)

> Status: COMPLETE. No source code or tests were modified. Test baseline 24/24 PASS is preserved by construction.

## Executive Summary

VNotes is a feature-light but architecturally-clean Delphi 10.3 / Win32 sticky-notes application. Phases 1–3 hardened the persistence path (atomic save, schema versioning, schema-versioning tests). The application builds clean, all 24 automated tests pass, and the dependency chain `TTrayForm → TNoteApplication → TNoteManager → INoteStorage → TJsonStorage` is intact.

The most significant **user-facing** gap is the absence of a notes-list and search feature. The most significant **technical** gap is that `TSettings.BackupEnabled` / `BackupIntervalDays` are saved into the INI file but **no code ever calls `TBackupService.Backup` periodically** — users believe scheduled backups are happening, but they are not. A handful of small bugs (settings-Cancel doesn't roll back live state, no single-instance guard, no monitor-clamp on note show) round out the high-priority debt.


## Feature Matrix (source-grounded)

| Area | Feature | Status | Evidence | Missing work |
|---|---|---|---|---|
| Persistence | JSON file-per-note | COMPLETE | `uJsonStorage.pas` (Phase 3B schemaVersion 1) | — |
| Persistence | Legacy unversioned JSON read | COMPLETE | `uJsonStorage.JsonToNote` (Phase 3B) | — |
| Persistence | Future/invalid schema rejection | COMPLETE | `EJsonSchemaException` + `LoadAllNotes` distinct warning (Phase 3B) | — |
| Persistence | Atomic save (MoveFileEx) | COMPLETE | `uJsonStorage.SaveNote` + `TestSaveNoteFailureSafety` | — |
| Persistence | SQLite | NOT IMPLEMENTED (stub) | `uSQLiteStorage.pas` TODO bodies; existing tests unaffected | Wait for real trigger |
| Tray | Tray icon + popup menu | COMPLETE | `tiMain` + `pmTray` in `uTrayForm.dfm`; `miNewNote…miExit` | — |
| Tray | "Open Notes List" menu item | PLACEHOLDER | `uTrayForm.OnOpenNotesList` only re-shows forms; no list form | Phase 4B |
| Note CRUD | Create (tray/hotkey/context menu) | COMPLETE | `OnNewNote`, `miNewNoteClick`, `miDuplicateClick` | — |
| Note CRUD | Edit (typing) | COMPLETE | `TNoteForm.mmContentChange` → autosave | — |
| Note CRUD | Delete | COMPLETE | `miDeleteClick` + confirm dialog | — |
| Note CRUD | Duplicate | COMPLETE | `miDuplicateClick` | — |
| Note CRUD | "Properties" dialog | PLACEHOLDER | `miPropertiesClick` is a `ShowMessage` stub (`uNoteForm.pas:440-445`) | Real dialog |
| Positioning | Drag | COMPLETE | `pnlHeaderMouseDown/Move/Up` | — |
| Positioning | Resize | COMPLETE | `WMNCHitTest` + `WMGetMinMaxInfo` | — |
| Positioning | Min-size | COMPLETE | `MIN_WIDTH=200, MIN_HEIGHT=150` | — |
| Positioning | Multi-monitor safety | PARTIAL | `uMonitorUtils` exists; no clamp logic in `TNoteForm.FormShow` | Clamp/restore |
| Note UI | Collapse | COMPLETE | `btnCollapseClick`, `COLLAPSED_HEIGHT=40` | — |
| Note UI | Lock | COMPLETE | `btnLockClick`; respected by drag/color/delete/duplicate | — |
| Note UI | Pin (always-on-top) | COMPLETE | `btnPinClick`, `FormStyle := fsStayOnTop` | — |
| Note UI | Color (8) | COMPLETE | `miYellow…miGray` with `Tag=Ord(ncColor)` | — |
| Note UI | Defaults from settings | COMPLETE | `TTrayForm.OnNewNote` (159-169) | — |
| Note UI | Font-size Ctrl+Wheel | COMPLETE | `FormMouseWheel` (clamped 8..24) | — |
| Note UI | Alt+F4 closes | COMPLETE | `FormKeyDown` | — |
| Notes list | Browse/search | NOT IMPLEMENTED | No `TNotesListForm`; `OnOpenNotesList` and `OnHotkeySearch` are stubs/TODOs | Phase 4B |
| Notes list | Recently-modified | NOT IMPLEMENTED | `TTrayController.UpdateNotesMenu` is empty (`uTrayController.pas:141`) | Phase 4B |
| Autosave | Debounced 1s | COMPLETE | `TAutosaveService` + 5 tests | — |
| Autosave | Multi-note independent | COMPLETE | `FPendingNotes: TDictionary<Int64,TNote>` | — |
| Autosave | Flush on shutdown | COMPLETE | `TAutosaveService.Flush` + `SaveAllNotes` | — |
| Backup | Manual zip | COMPLETE | `TBackupService.Backup`; tray `miBackup` | — |
| Backup | Restore from zip | COMPLETE | `TBackupService.Restore`; tray `miRestore`; `OpenDialog` `*.zip` | — |
| Backup | **Automatic** scheduled | NOT IMPLEMENTED | `TSettings.BackupEnabled`/`BackupIntervalDays` are persisted but **no scheduler ever calls `Backup`** | Phase 4C |
| Backup | Retention | NOT IMPLEMENTED | `GetBackupFileName` always creates new zip; backups grow unbounded | Phase 4C |
| Backup | Progress UI | PARTIAL | `OnProgress`/`OnComplete` exist on service; no UI wires them | Phase 4C |
| Hotkeys | Global register | COMPLETE | `THotkeyService` + `RegisterHotKey`; tray form dispatches `WM_HOTKEY` | — |
| Hotkeys | Ctrl+Alt+F search | PLACEHOLDER | `OnHotkeySearch` body: `// TODO: Show search form` | Phase 4B |
| Hotkeys | `THotkeyService.UpdateFromSettings` | DEAD CODE | Empty stub (`uHotkeyService.pas:188-191`); not called | Phase 4D |
| Hotkeys | `hkCustom1/2/3` | DEAD CODE | Declared in `THotkeyID` but never used | Phase 4D |
| Settings | INI load/save | COMPLETE | `TSettings` (round-trip tested) | — |
| Settings | Modal dialog (4 tabs) | COMPLETE | `uSettingsForm.pas` | — |
| Settings | Live apply on OK | COMPLETE | `TTrayForm.OnSettings` applies theme/autosave/hotkeys | — |
| Settings | Live roll-back on Cancel | PARTIAL | `btnCancelClick` only resets in-memory `FSettings`; live values are not rolled back | Phase 4C |
| Settings | Hotkey parser | COMPLETE | `THotkeyService.ParseHotkey` | — |
| Settings | Hotkey conflict UI | NOT IMPLEMENTED | Failure returns `False` silently | Phase 4C |
| Theme | Light/dark styles | COMPLETE | `TThemeService` + `TSettingsController.ApplyTheme` | — |
| Theme | Per-color palette | COMPLETE | `FNoteColors[]` + `FNoteColorsDark[]` | — |
| Theme | Custom user theme | NOT IMPLEMENTED | Hard-coded `Windows10`/`Windows10 Dark`/`Dark` | (deferred) |
| Startup | AutoStart (Run key) | COMPLETE | `TStartupService` | — |
| Startup | Single-instance | NOT IMPLEMENTED | No mutex; second launch races on `FNextID` | Phase 4C |
| Startup | Start-minimized flag | NOT IMPLEMENTED | No command-line parsing | (deferred) |
| Notes data | Title persisted | COMPLETE | JSON `Title` field; **but UI never shows it** | Phase 4C |
| Notes data | Count badge | NOT IMPLEMENTED | `NoteCount` exists; no UI | (deferred) |
| Logging | `ILogger` (debug/info/warn/error) | COMPLETE | `uILogger.pas` (OutputDebugString) | — |
| Logging | User log viewer | NOT IMPLEMENTED | Logs not surfaced to user | (deferred) |
| Help | About dialog | COMPLETE | `uAboutForm.pas` | — |
| Help | In-app guide | NOT IMPLEMENTED | None | (deferred) |


## Technical Debt (prioritized)

| Severity | Item | Evidence |
|---|---|---|
| **HIGH** | **Scheduled backup never fires.** `TSettings.BackupEnabled` / `BackupIntervalDays` are read into `TSettings` and saved to INI, but nothing in the codebase calls `TBackupService.Backup` on a timer. Users believe backups are happening automatically; they are not. | `uBackupService.pas` (no `TTimer`); `uSettingsController.ApplyToApplication` only sets autostart/theme. |
| **HIGH** | **No single-instance enforcement.** A second `StickyNotes.exe` would create a second tray icon and could race on `FNextID` (Phase 3B documented this as a concern). | `StickyNotes.dpr` (no mutex), `uNoteApplication` (no `CreateMutex`). |
| **HIGH** | **No search / "open notes list" UI.** Ctrl+Alt+F and the "Open Notes List" tray menu both degrade to `OpenAllNotes` or are TODO stubs. Single biggest user-facing gap. | `uTrayForm.pas:171-175` (`OnOpenNotesList`), `uTrayForm.pas:280-284` (`OnHotkeySearch`), `uTrayController.pas:141-144` (`UpdateNotesMenu`). |
| **HIGH** | **Title field is persisted but never displayed.** `TNote.Title` is round-tripped through JSON and is the natural handle for search. Currently invisible to the user. | `uNoteForm.pas` (no title shown). |
| **MEDIUM** | **`TBackupService.OnProgress` / `OnComplete` callbacks are never wired to any UI.** Backups run fire-and-forget; failure is logged only. | `uTrayForm.OnBackup` body (line 211-214): just `FApplication.BackupService.Backup`. |
| **MEDIUM** | **No backup retention.** Backup directory grows forever. | `uBackupService.GetBackupFileName` (no max-N logic). |
| **MEDIUM** | **Settings `Cancel` does not roll back live state.** Theme/autosave/hotkeys are applied only on `mrOk`; Cancel restores only the in-memory `FSettings`. | `uSettingsForm.btnCancelClick` (line 172-176). |
| **MEDIUM** | **Note position not clamped to current monitor geometry after monitor changes.** A note placed on a now-disconnected monitor becomes unreachable. | `uNoteForm.FormShow` (line 190-200) sets bounds from `FNote` without monitor check; `uMonitorUtils` exists but is not used. |
| **MEDIUM** | **Hotkey registration failures are silent.** `RegisterHotkey` can return `False`; the UI shows no error. | `THotkeyService.RegisterHotkey` returns `Boolean`; `TTrayForm` discards the result. |
| **LOW** | **Dead code: `TTrayController`** - fully constructed but never shown. DFM `tiMain` is the live tray. | `uTrayForm.pas:95-103` (construct + assign events), no `ShowTrayIcon` call. |
| **LOW** | **Dead code: `THotkeyID.hkCustom1/2/3`** - declared in `uHotkeyService.pas` but never used. | `uHotkeyService.pas:10` |
| **LOW** | **Dead code: `THotkeyService.UpdateFromSettings`** - empty stub. | `uHotkeyService.pas:188-191` |
| **LOW** | **Note `miProperties` is a `ShowMessage` stub.** | `uNoteForm.miPropertiesClick` (line 440-445). |
| **LOW** | **`TNoteForm.WndProc` is an empty override.** | `uNoteForm.WndProc` (line 494-498). |
| **LOW** | **No tests reference `TBackupService` at all.** | test files: none. |
| **LOW** | **Hard-coded VCL style names** (`Windows10`, `Windows10 Dark`, `Dark`) - silently fall back. | `uThemeService.pas`, `uSettingsController.pas`. |

## Test Coverage Gaps

| Area | Existing tests | Important missing coverage | Priority |
|---|---|---|---|
| `TJsonStorage` | 11 (save/load, atomic, delete, loadAll, schema) | None critical. Phase 3B added 5 schema tests. | - |
| `TAutosaveService` | 5 | `TestSingleSave` **does not assert that the timer fired** - only asserts the service is non-nil. `TestCancelSave` does not assert "save did not happen". | MEDIUM |
| `TNote` | 3 | No coverage of `Touch`, `SetBounds`, `GetBounds`, `Assign`, `Clone`, `ColorAsTColor` round-trip. | MEDIUM |
| `TSettings` | 2 | No coverage of `Assign`, `LoadFromFile` with missing file, defaults persistence. | LOW |
| `TNoteManager` | 0 (only via application test) | Create/AddNote/FindByID/FindByIndex/DeleteNote/SaveNote/LoadNotes have no direct unit tests. | HIGH |
| `TBackupService` | 0 | Backup zip contains correct files; restore re-creates notes; corrupt-zip tolerance; missing-settings file. | HIGH |
| `TTrayForm` / `TNoteForm` / `TSettingsForm` | 0 | VCL forms; smoke-tested manually only. | (out of scope) |
| `THotkeyService` | 0 | Parse round-trips; register/unregister lifecycle with mock HWND. | MEDIUM |
| `TStartupService` | 0 | Round-trip of `IsAutoStartEnabled`/`SetAutoStart` against test registry key. | LOW |
| `TThemeService` | 0 | Color getters return expected values; `SetDarkTheme` toggles `DarkTheme` property. | LOW |
| `TNoteApplication` | 3 | `Initialize` not covered (TrySetStyle hangs in console). | (deferred) |
| `uJsonUtils` / `uColorUtils` / `uMonitorUtils` / `uWindowUtils` / `uIso8601` | 0 | Utility coverage. | LOW |

## Architecture Assessment (post-Phase 1-3)

The boundary is intact:

```
TTrayForm  (hidden, owns FApplication + FNoteForms)
   |
   v
TNoteApplication  (owns all services + INoteStorage)
   |
   v
TNoteManager  (orchestrates notes; owns TObjectList<TNote>)
   |
   v
INoteStorage  (6 methods; no JSON concepts leak)
   |
   v
TJsonStorage  (Phase 3B versioned)
```

And for note windows:

```
TNoteForm
   |
   v
INoteEditorContext
   |
   v
TNoteApplication services
```

**No new architectural issues have been introduced by Phases 1-3.** The Phase 3B `EJsonSchemaException` type is correctly scoped to `uJsonStorage.pas`. No layer violation was introduced.

One soft observation: the **"open notes list" entry point in `OnOpenNotesList` is empty** - it points to where a "browse notes" feature belongs, but no such feature exists. The architecture is ready for it (a new `TNotesListForm` and a new optional `INoteQuery` interface) but no scaffolding was done.


## Dead Code (potential removals)

| Component | Evidence unused | Risk of removal | Recommendation |
|---|---|---|---|
| `TTrayController` (`uTrayController.pas`) | Constructed and `On*` events assigned, but `ShowTrayIcon` is never called. The DFM `tiMain`/`pmTray` are the live tray. | LOW (no side effects, just memory) | Document; remove in Phase 4D. |
| `THotkeyID.hkCustom1/2/3` | Declared but no caller uses them. | LOW | Remove in Phase 4D. |
| `THotkeyService.UpdateFromSettings` | Empty body. Caller (`TTrayForm.OnSettings`) does not use it. | LOW | Remove in Phase 4D. |
| `TNoteForm.miProperties` stub | `ShowMessage` only. | LOW (replacement desired) | Replace with real dialog (Phase 4C or later). |
| `TNoteForm.WndProc` | Empty override (`inherited; // Handle any custom messages`). | NONE | Trivial noise; remove in Phase 4D. |

## Documentation Accuracy

| Doc claim | Source truth | Status |
|---|---|---|
| `README.md` says "Search Notes" hotkey (Ctrl+Alt+F) | Source: `// TODO: Show search form` | **Outdated / incorrect.** README implies a search feature that does not exist. |
| `README.md` says "Auto-save" | Source: yes, debounced 1s | OK |
| `README.md` says "Multi-monitor support - Notes stay on their monitor" | Source: partial - no clamp/restore logic observed | **Partially outdated.** A note can become unreachable if its monitor is disconnected. |
| `README.md` lists "Rich text / Cloud sync / Plugins, reminders, tags" in roadmap | Source: none scheduled in current plan | Outdated forward-looking wishlist, not in current dev plan. OK as a wishlist. |
| `docs/DEVELOPMENT_PLAN.md` lists 11 settings keys | Source: `TSettings` exposes 14 properties | OK (Phase 2 added Hotkey fields) |
| `docs/ARCHITECTURE.md` says "Autosave: COMPATIBLE with SQLite" | Verified in Phase 3C: true | OK |
| `docs/PROJECT_INVENTORY.md` lists `OpenDialog` for restore | Verified: yes, `TOpenDialog.Create(Self)` with `*.zip` filter | OK |
| `docs/PROJECT_INVENTORY.md` says `TSQLiteStorage` is a stub | Verified | OK |
| `docs/ARCHITECTURE.md` says "FTrayController (dead code, documented)" | Verified dead (`uTrayForm.pas:41-43`) | OK |

## SQLite Status

```
DEFERRED.
```

Evidence (none of the Phase 3C triggers is present):

- **FTS5/search**: no UI, no backend, no scheduled milestone. (Phase 4B below *adds* search via in-memory filter - no SQLite needed.)
- **Note count >= ~500**: no user-reported scale data; "10-50 notes" is the documented typical range.
- **Tags/categories**: not in the current development plan; listed only as a future possibility in README.

## Recommended Next Phase

**Phase 4B - Note list + in-memory search (`INoteQuery` + `TNotesListForm`)**

Why this and not SQLite:

- It is the **single largest user-facing gap** (HIGH in the debt list).
- It is implementable **entirely on top of the current JSON storage** - `LoadAllNotes` already returns an in-memory `TObjectList<TNote>`; an in-memory filter is O(n) which is fine at the documented 10-50 note scale.
- It unlocks multiple follow-on features (recently-modified list, Ctrl+Alt+F search, "Open Notes List" tray menu) at near-zero architectural cost.
- It **defers SQLite by removing the FTS5 trigger** - by providing a usable search now, the SQLite search trigger is removed or pushed much further into the future.
- It is testable: the filter logic can be a pure function on `TObjectList<TNote>`, and the existing 24-test foundation gives us a clear place to add unit tests.

Why not "fix the scheduled backup" first:

- The scheduled backup bug is a HIGH-severity correctness gap, but its fix is small (a `TTimer` in `TBackupService` driven by `TSettings.BackupEnabled`/`BackupIntervalDays`) - a few hours of work. It does not warrant a dedicated phase. It can be folded into Phase 4C alongside the other reliability polish.
- In priority order, **"what does the user want most?"** is search/list. Scheduled backup is a silent data-safety improvement with no user-facing discoverability.

Why not "remove dead code" first:

- Dead code is LOW severity and the components are small. Cleanup can be a maintenance phase, not the next phase.

**Phase 4B scope (recommended only - do not implement in this phase):**

- Add a small `INoteQuery` interface (or a free function `TNoteQuery`) with one method: `Search(const AText: string): TObjectList<TNote>`.
- Add `TNotesListForm` (VCL form) with a list view, a search box, and a "Show" / "Bring to front" action.
- Wire the new form to `Ctrl+Alt+F` and to the tray "Open Notes List" menu.
- Optionally, add a "Recently modified" submenu under the tray icon (`TTrayController.UpdateNotesMenu` finally gets a real body).
- Tests: `INoteQuery.Search` filter test (case-insensitive substring across Title+Content, empty query returns all, result ordering), and a smoke test that `TNotesListForm` populates from a known `TNoteManager`.
- Out of scope: persistent search history, regex, FTS5, indexing, SQLite.

## Phase 4 Roadmap (smallest sensible)

| Phase | Objective | Reason | Dependencies | Expected changes | Testing |
|---|---|---|---|---|---|
| **4B** | Note list + in-memory search | Closes HIGH user-facing gap; keeps SQLite deferred | `TNoteManager` (already exists), `TJsonStorage.LoadAllNotes` | New `INoteQuery` (in `Storage/` or new `Query/`); new `TNotesListForm` (in `Forms/`); `TTrayForm.OnOpenNotesList`/`OnHotkeySearch` wire to new form; optional recently-modified submenu | Unit tests for filter; smoke test for form population |
| **4C** | Reliability & lifecycle polish | Bundle several small HIGH/MEDIUM debt items into one phase | Phase 4B (no code overlap) | Single-instance mutex; scheduled-backup timer wired to settings; backup retention (keep last N); `Settings.Cancel` rolls back live state; `TNoteForm` clamps to current monitor on show; `TNoteForm` displays `Title`; hotkey-registration failure surfaced to user | Unit tests for single-instance guard (mock mutex), backup retention, monitor clamp helper; existing tests unchanged |
| **4D** | Dead-code cleanup & docs | Remove now-unused symbols; align docs with reality | Phase 4C (so nothing in 4C depends on them) | Remove `TTrayController`; remove `hkCustom1/2/3`; remove `THotkeyService.UpdateFromSettings`; remove `TNoteForm.WndProc` empty override; implement or remove `miProperties` stub; update README to remove "Search" claim and add a real description of 4B | All existing tests still pass |

**No Phase 4E (SQLite) is in this roadmap.** It will be reconsidered only if a Phase 3C trigger appears.

## Manual Smoke Test Plan (future, IDE-required)

These scenarios are not covered by automated tests because they need a live VCL/Win32 host:

1. Application lifecycle
   - Launch -> tray icon appears
   - First launch -> first note auto-created
   - Second launch (without single-instance guard) -> verify expected behavior before and after Phase 4C
   - Exit via tray menu -> autosave flush verified by inspecting `notes/*.json` modification times
2. Note CRUD
   - Create via tray, hotkey, and note-form context menu
   - Edit text -> autosave fires within delay window
   - Move and resize -> on reopen, position/size restored
   - Delete with confirmation ON / OFF
   - Duplicate -> offset position
3. Visual / behavior
   - Toggle dark theme live
   - Drag collapsed note (locked, unlocked)
   - Lock prevents typing, color change, delete, duplicate, drag
   - Pin (always-on-top) works against other apps
4. Persistence
   - Restart with notes in directory -> all reappear in last position
   - Corrupt one `.json` -> app starts, that note is skipped, other notes load
   - Inject a v999 JSON file -> app starts, future file preserved, other notes load
5. Backup / restore
   - Manual backup -> `backups/StickyNotes_Backup_*.zip` created
   - Delete a note -> restore from zip -> note reappears
   - Restore from a zip with a missing `settings.ini` -> notes restored, settings unchanged
6. Hotkeys
   - `Ctrl+Alt+N` always creates a new note
   - `Ctrl+Alt+F` opens the notes list (after Phase 4B)
   - Re-registering a hotkey that Windows already has -> user-visible error (after Phase 4C)
7. Multi-monitor / DPI
   - Open a note on the secondary monitor
   - Disconnect the secondary monitor -> note remains reachable
   - Change DPI while running -> UI is readable
8. Autostart
   - Enable in settings -> Run-key contains `"...\StickyNotes.exe"`
   - Disable -> Run-key value removed
   - Reboot -> app starts with tray icon

These are **smoke tests** (does it work end-to-end), not exhaustive UI tests. They should be performed on a real Windows 10/11 desktop before each release.
