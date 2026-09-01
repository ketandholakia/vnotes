# VNotes — Detailed Development Action Plan

> Based on source-level audit of `ketandholakia/vnotes` (commit `a8fcc7c`, 2026-09-01).
> Builds on the existing `docs/PHASE_4A_ANALYSIS.md` roadmap; adds a cleanup phase, concrete
> file-level tasks, effort estimates, and acceptance criteria for each item.

---

## Phase 4A.5 — Repo & Build Hygiene (0.5 day)

Do this first — it's cheap and removes noise before touching feature code.

| # | Task | Files | Action | Acceptance |
|---|---|---|---|---|
| 1 | Remove stale failed build log | `build_log.txt` | Delete from repo (or regenerate from a real `build_main3.bat` run and keep only that) | File either gone or contains a genuine PASS log matching current source |
| 2 | Consolidate build scripts | `build_main.bat`, `build_main2.bat`, `build_main3.bat`, `build_tests.bat` … `build_tests9.bat`, `build_tnote_test*.bat`, `build_unote.bat`, `build_backup.bat`, `check_version.bat` (18 files total) | Keep one canonical `build.bat` (based on working `build_main3.bat` logic) and one `build_tests.bat`; delete the rest | Repo root has 2 build scripts, both run clean on the target toolchain |
| 3 | Remove orphaned utility | `src/Utils/uMonitorUtils.pas` | Either delete (if Phase 4C's monitor-clamp work will be written fresh) or explicitly re-add to `StickyNotes.dproj` and wire into `TNoteForm.FormShow` as part of Phase 4C item 5 below — do not leave it dangling | File is either gone from repo or is compiled + referenced |
| 4 | Confirm `.gitignore` is complete | `.gitignore` | Verify `__history/`, `*.dcu`, `*.exe`, `*.identcache` all covered (already mostly done in the last commit) — add `*.stat` / `*.local` if IDE regenerates them | `git status` stays clean after a full IDE build |
| 5 | Fix README inaccuracies | `README.md` | Remove "Search Notes" from the hotkey table until Phase 4B ships it, or mark it "planned"; note that multi-monitor support is partial | README matches actual behavior |

**Deliverable:** clean git status, 2 build scripts, no misleading log files.

---

## Phase 4B — Notes List + In-Memory Search (2–3 days)

**Why first:** biggest user-facing gap; needs no storage changes; removes the main argument for ever needing SQLite.

| # | Task | New/Changed files | Detail |
|---|---|---|---|
| 1 | Query interface | `src/Storage/uNoteQuery.pas` (new) or `src/Query/uNoteQuery.pas` | `INoteQuery` with `function Search(const AText: string; const ANotes: TObjectList<TNote>): TObjectList<TNote>`. Case-insensitive substring match across `Title` + `Content`. Empty query returns all notes, most-recently-modified first. |
| 2 | List form | `src/Forms/uNotesListForm.pas` + `.dfm` (new) | `TListView` (or `TVirtualStringTree` if already available) bound to `TNoteManager`'s notes; a `TEdit` search box wired to `OnChange` → re-filter via `INoteQuery`; double-click / Enter brings the note window to front (`BringToFront` + `SetForegroundWindow`) or creates it if closed. |
| 3 | Wire hotkey | `src/Forms/uTrayForm.pas` | Replace the `// TODO: Show search form` stub in `OnHotkeySearch` with: create-or-show `TNotesListForm`, focus the search box. |
| 4 | Wire tray menu | `src/Forms/uTrayForm.pas` | `OnOpenNotesList` shows the same form (unfocused search box, full list). |
| 5 | Recently-modified sort | `src/Controllers/uTrayController.pas` (only if you decide to un-deprecate it) **or** inline in the new list form | If `TTrayController` stays dead (recommended — see 4D), implement sort directly in `TNotesListForm.PopulateList`, sorting by `TNote.UpdatedAt` descending. |
| 6 | Tests | `tests/Models/TNoteQueryTests.pas` (new) | Cover: empty query → all notes; case-insensitive match; match in Title only; match in Content only; match in neither → empty result; ordering (most-recent first). |
| 7 | Smoke test | manual, see Phase 4A checklist item 2 in `PHASE_4A_ANALYSIS.md` | `Ctrl+Alt+F` opens list populated from a live `TNoteManager`; selecting a note brings its window to front. |

**Acceptance:** `Ctrl+Alt+F` and tray → "Open Notes List" both open a working, searchable list; new unit tests pass; existing 24 tests unaffected.

---

## Phase 4C — Reliability & Lifecycle Polish (2–3 days)

Bundle these together — none overlaps 4B's code.

| # | Task | Files | Detail |
|---|---|---|---|
| 1 | Single-instance guard | `src/StickyNotes.dpr`, possibly `src/Application/uNoteApplication.pas` | `CreateMutex` with a named mutex (e.g. `Global\VNotes_SingleInstance`) at startup; if it already exists, activate the existing tray icon (or just exit) instead of racing `FNextID`. |
| 2 | Wire scheduled backup | `src/Services/uBackupService.pas` | Add an internal `TTimer` (or have `TNoteApplication` own one) gated by `TSettings.BackupEnabled`; interval from `TSettings.BackupIntervalDays` (convert days → ms, or check daily and compare last-backup timestamp). Persist "last backup time" somewhere (new `TSettings` field or a marker file) so it doesn't re-fire every app restart. |
| 3 | Backup retention | `src/Services/uBackupService.pas` | After a successful backup, list `backups\*.zip`, sort by date, delete beyond the newest N (make N a `TSettings` field, default e.g. 10). |
| 4 | Settings-Cancel rollback | `src/Forms/uSettingsForm.pas` | `btnCancelClick` currently only resets in-memory `FSettings`. Capture a snapshot of live-applied state (theme, autosave interval, hotkeys) on dialog open; on Cancel, re-apply that snapshot via the same code path `OnSettings`/`ApplyTheme` uses on OK. |
| 5 | Monitor clamp on show | `src/Forms/uNoteForm.pas` (`FormShow`), `src/Utils/uMonitorUtils.pas` | On `FormShow`, check `FNote` bounds against `Screen.Monitors[]` work areas; if the note's saved position doesn't intersect any current monitor, reposition to the primary monitor (centered or cascaded). This is the natural home for `uMonitorUtils.pas` — resolves the Phase 4A.5 orphan-file question. |
| 6 | Surface hotkey failures | `src/Services/uHotkeyService.pas`, `src/Forms/uTrayForm.pas` / `uSettingsForm.pas` | `RegisterHotkey` return value is currently discarded. On `False`, show a non-blocking notification (balloon tip via `NIM_MODIFY`/tray icon, or a `ShowMessage` from Settings) naming the conflicting combination. |
| 7 | Title visible in note UI | `src/Forms/uNoteForm.pas` / `.dfm` | `TNote.Title` round-trips through JSON but is never shown. Add a small title label/edit in the header, defaulting to first line of content if blank — this also makes Phase 4B search results more useful. |
| 8 | Tests | `tests/Models/TBackupServiceTests.pas` (new — currently 0 coverage) | Cover: zip contains expected files; restore recreates notes; corrupt-zip tolerance; missing-`settings.ini` restore path; retention deletes oldest beyond N. |
| 9 | Tests | `tests/Models/TNoteManagerTests.pas` (new — currently 0 direct coverage) | Cover: Create/AddNote/FindByID/FindByIndex/DeleteNote/SaveNote/LoadNotes directly (currently only exercised indirectly via `TNoteApplicationTests`). |

**Acceptance:** all 7 functional items verified via the manual smoke-test plan already in `docs/PHASE_4A_ANALYSIS.md` §"Manual Smoke Test Plan"; new unit tests pass; existing 24 (soon 24+) tests unaffected.

---

## Phase 4D — Dead Code Removal & Doc Sync (0.5–1 day)

Do last, once nothing added in 4B/4C depends on these.

| # | Task | Files |
|---|---|---|
| 1 | Remove `TTrayController` | `src/Controllers/uTrayController.pas` (delete), `src/Forms/uTrayForm.pas` (remove construct/wire/free) — **unless** you chose to reuse it for Phase 4B item 5's recently-modified logic, in which case document it as live instead |
| 2 | Remove unused hotkey IDs | `src/Services/uHotkeyService.pas` — delete `hkCustom1/2/3` from `THotkeyID` |
| 3 | Remove empty stub | `src/Services/uHotkeyService.pas` — delete `UpdateFromSettings` (confirm no caller first) |
| 4 | Remove empty override | `src/Forms/uNoteForm.pas` — delete the no-op `WndProc` override |
| 5 | Final README pass | `README.md` | Update feature list and roadmap to reflect Phase 4B/4C additions (search, scheduled backup, single-instance) |
| 6 | Update `docs/DEVELOPMENT_PLAN.md` | append Phase 4B/4C/4D completion status in the same format as prior phases, for continuity with future sessions |

**Acceptance:** no references to removed symbols remain (`grep -rn "TTrayController\|hkCustom\|UpdateFromSettings" src/` returns nothing); build and full test suite still pass; docs match source.

---

## Sequencing & Effort Summary

| Phase | Effort | Depends on | Unlocks |
|---|---|---|---|
| 4A.5 — Hygiene | 0.5 day | — | Clean baseline for everything below |
| 4B — Search & list | 2–3 days | 4A.5 | Closes the single biggest user-facing gap; defers SQLite indefinitely |
| 4C — Reliability | 2–3 days | 4A.5 (no code overlap with 4B) | Fixes the two silent-failure bugs (backup, hotkeys) most likely to erode user trust |
| 4D — Cleanup | 0.5–1 day | 4B, 4C | Repo hygiene; nothing user-facing |

**Total: ~6–8 working days** for the full 4A.5→4D arc, deliberately excluding SQLite (no current trigger — FTS/search need is met by 4B's in-memory filter at the documented 10–50 note scale) and excluding rich text / cloud sync / plugins (README wishlist items with no current design work behind them).

## Suggested order of implementation sessions

1. **Session 1:** Phase 4A.5 in full (fast, low-risk, immediately visible in `git status`/repo tree).
2. **Session 2–3:** Phase 4B — `INoteQuery` + tests first (pure logic, easy to verify), then `TNotesListForm` + wiring.
3. **Session 4–5:** Phase 4C — do items 1–3 (single-instance, backup timer, retention) together since they're all "silent correctness" fixes; then items 4–7 (UI polish) as a second pass.
4. **Session 6:** Phase 4D + doc sync.

Each session should end with the full test suite run and a note in `docs/DEVELOPMENT_PLAN.md` recording status, in keeping with how the prior phases were tracked.

---

*Generated from source-level audit — see prior chat analysis for verification detail against `docs/PHASE_4A_ANALYSIS.md`.*
