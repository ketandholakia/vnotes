# V-Notes Code Review — 2026-09-10

Scope: all uncommitted working-tree changes vs `main` (21 modified files + 5 new units in
`src/Components/`), i.e. the B1–B7 fix batch from the 2026-09-07 review **plus** the new
UI componentization (header bar, color picker, tag strip, checklist panel, custom
scrollbar), the VirtualTreeView notes list, font/auto-hide settings, and the window
arrange menu.

Verification performed in this review:

- `build.bat`: all units compile clean (link step only fails because `StickyNotes.exe`
  is currently **running** — PID 13644 locks the output file). One new compiler warning
  (see H6).
- `build_tests.bat` + run: **212 tests, 211 passed, 1 error**. The single error is
  `TPhase6LReadinessTests.TestProductionBackendIsJsonInNoteApplication` — "cannot access
  the file … vnotes.db, used by another process". Environmental: the running app holds
  the live DB. Re-run with the app closed for a clean 212/212. (This also re-demonstrates
  the known test-isolation issue — tests still touch real `%APPDATA%\StickyNotes`.)
- Win32 probe (`tools/ScrollProbe.dpr`, compiled with dcc32 36.0) to settle a
  scrollbar question empirically:
  - multiline EDIT **without** `WS_VSCROLL` → `GetScrollInfo(SB_VERT)` **fails**,
    `GetLastError = 1447` (`ERROR_NO_SCROLLBARS`)
  - multiline EDIT **with** `WS_VSCROLL`, then `ShowScrollBar(SB_VERT, False)` →
    `GetScrollInfo` returns valid data (`nMax=200 nPage=9`)
  - i.e. scroll info exists only when the style exists; hiding the bar is safe,
    removing the style is not.

## Confirmation: 2026-09-07 fixes are correctly in place

- **B1** — `TTrayForm.OnNoteDeleted` no longer deletes from `FNoteForms`; comment
  documents why. ✔
- **B2** — `TNoteManager.DeleteNote` Extracts (not Deletes), notifies while the object is
  alive, frees after; `SaveNote` has the membership guard; new `PersistNote` write-through.
  Two new regression tests pass (`TestSaveNoteRefusesNoteNotOwnedByManager`,
  `TestDeleteNoteLeavesNoStorageFile`). ✔
- **B3** — `TBackupService` fires `OnBeforeStorageSwap`/`OnAfterStorageSwap` around **both**
  swap blocks (direct SQLite restore and legacy-JSON migration); `TTrayForm` wires them to
  `CloseAllNotes`/`OpenAllNotes`. ✔ (Minor gap noted in H7.)
- **B4** — `OnRestore` saves and restores the previous `OnComplete` in a `try/finally`. ✔
- **B5** — `Touch` now happens before persist. ✔
- **B6** — `Shutdown`, `LoadSettings`, `SaveSettings` all nil-guarded. ✔
- **B7** — `IsOverdue`; `Start`/`Refresh` catch up immediately; clamp raised to
  `High(Cardinal)`. ✔
- Autosave `%` → `%d` format strings. ✔

## Critical (functional regressions introduced by the componentization)

### C1. The custom scrollbar can never render — memo loses `WS_VSCROLL`
`uNoteForm.pas:203` sets `mmContent.ScrollBars := ssNone`, which removes the
`WS_VSCROLL` style. `TNoteScrollBar` reads position via `GetScrollInfo`, and the probe
above proves that call **fails with ERROR_NO_SCROLLBARS** without the style — so
`UpdateScrollInfo` always exits with `FThumbVisible := False`: no thumb, no drag, no
page-click. The custom bar is dead weight; only wheel scrolling still works.

The component was designed for the other pattern, and `Attach` already implements it
(`uNoteScrollBar.pas:125`): keep `ssVertical` (the DFM still says `ssVertical` — just
delete the `ssNone` line) and hide the native bar with `ShowScrollBar(SB_VERT, False)`.

Two follow-ups for that fix:
- `Attach` is called from `LoadNote` (pre-handle) — the `ShowScrollBar` hide is skipped
  when the handle isn't allocated yet and is never retried. Re-hide in the 50 ms poll
  (cheap) or on first handle creation.
- A multiline EDIT re-shows its hidden bar when content grows (classic sticky-scrollbar
  behavior). The poll re-hide from the previous bullet covers this too.

### C2. First checklist item is unreachable — checklist gating on empty notes
`uNoteForm.pas:543` `UpdateContentMode` shows the checklist only when
`FChecklist.Visible and (FNote.ChecklistTotalCount > 0)`. `HeaderButtonClick(nhbChecklist)`
sets `Visible := True` and immediately calls `UpdateContentMode`, which flips it back to
hidden when the note has zero items. The `+ Add item…` edit lives **inside** the panel,
so a note with no items can never get its first item through the UI. The old
`FForcingChecklistMode` explicitly allowed forcing the (empty) panel visible — this is a
regression.

Suggested: let the explicit toggle win (show the panel whenever the button was pressed;
only use the `ChecklistTotalCount > 0` rule to *auto* select the content mode on load),
e.g.:

```pascal
nhbChecklist:
begin
  if FNote.Locked then Exit;
  FChecklist.Visible := not FChecklist.Visible;
  mmContent.Visible  := not FChecklist.Visible;
end;
```

Related, smaller: `CollapseNote` forces `FChecklist.Visible := False`, and `ExpandNote`
then calls `UpdateContentMode`, which reads that now-false flag — so collapse+expand
silently drops a note out of checklist mode. Consider saving the pre-collapse mode and
restoring it in `ExpandNote`.

## Important

### H1. Checklist row freed inside its own `OnKeyDown` — use-after-free risk
`TNoteChecklistPanel.RemoveRow` (`uNoteChecklistPanel.pas:423-428`) does
`FRows[AIndex].Free` synchronously. It is invoked from `TNoteChecklistRow.EditKeyDown`
(Ctrl+Delete), i.e. while the row's `TEdit` is mid-`WM_KEYDOWN` — after the event
returns, VCL continues message processing on the freed control. The classic safe pattern
is deferred destruction (`PostMessage(Handle, CM_RELEASE, 0, 0)` on the row, free in its
`CM_RELEASE` handler, or defer the array rebuild to the next idle). `TNoteForm`-level
`ChecklistItemRemoved` also calls `FChecklist.SetItems(...)` while the stale row pointer
is still in `FRows` — same deferred fix covers it.

### H2. Checklist row edit: width never set, `akRight` captured at the wrong reference width
`TNoteChecklistRow.CreateRow` sets `FEdit.Left` and `Anchors := [akLeft, akRight, akTop]`
(`uNoteChecklistPanel.pas:171`) but never `FEdit.Width`. The anchor rules are captured
while the row is still at its default `TControl` width (~100 px), where the edit's right
edge (Left 24 + default ~100) already overhangs the parent. From then on every row
resize stretches the edit 1:1 with the row, leaving it permanently overhanging the right
edge by ~24 px (text/caret can extend past the visible row; not clipped because child
windows aren't clipped to their parent). Fix: set `FEdit.Width :=
RowWidth - FEdit.Left - margin` **before** assigning `Anchors` (and after the row has its
final width), or set the anchors after sizing. Verify visually either way.

### H3. Notes list: `ncOrange` and `ncGray` unhandled in all three `case` blocks
`uNotesListForm.pas` handles only 6 of the 8 `TNoteColor` values in
`vstNotesBeforeCellPaint` (:169), the group-name case (:210), and the emoji case (:248).
The color menu previously offered Orange and Gray, so real notes will have those colors:
their group headers render as `"📁  - N Notes"` (empty name), with no row highlight and
no emoji. Add the missing cases plus an `else` fallback in each block.

### H4. VirtualTreeView search path: `build.bat` hard-codes a machine-specific absolute path
`build.bat` re-introduces `D:\delphi\vcl\Athens_vcl\03_Virtual-TreeView-8.3\Source` —
two lines above a comment bragging that the previous hard-coded path was dropped for
portability. It is also **not** in `StickyNotes.dproj`'s `DCC_UnitSearchPath`, so IDE
(F9) builds fail unless the IDE's global library path already has it. Suggest an
environment variable (e.g. `%VTV_SRC%`) with a documented default, and mirror it into
the dproj. Also note `build_tests.bat` still lacks the `Components` path — currently
harmless only because the test dpr doesn't compile the form units; it will break the
moment a test touches them.

### H5. Arrange menu bumps `UpdatedAt` for every note
All four `miArrange*` handlers call `FApplication.NoteManager.SaveNote(Form.Note)`, which
now (post-B5) `Touch`es before persisting. A pure layout action therefore rewrites every
note's modified timestamp, and since the notes list sorts `UpdatedAt DESC`, arranging
reshuffles list order. Consider a `MoveNote`/`PersistNote` path that persists geometry
without `Touch` (the manager already has the private `PersistNote` — expose it for this).
Also: all arrange modes use `Screen.WorkAreaRect` (primary monitor only), so notes living
on secondary monitors get pulled to the primary one; and cascade/grid can place windows
smaller than `MIN_WIDTH/MIN_HEIGHT`, which the form's `WM_GETMINMAXINFO` will then veto,
causing overlaps.

### H6. Compiler warning: `W1036 Variable 'CurrentColor' might not have been initialized`
`uTrayForm.pas:657` (`miArrangeByColorClick`). Logically safe (guarded by the
`FNoteForms.Count = 0` exit), but initialize `CurrentColor := ncYellow` (and
`CurrentTag := ''` in the ByTag twin) to keep the build warning-free.

### H7. Restore callbacks: small gap in `DoRestore`
If `FNoteManager.Initialize` itself raises inside the `finally` in `DoRestore`,
`OnAfterStorageSwap` never fires and all note windows stay closed until the next manual
action. Wrapping Initialize + the after-swap event in a nested `try/finally` (or firing
the event in an outer finally with a "was swapped" flag) closes the gap. Low
probability, cheap to harden.

## Minor / hygiene

- **Hover highlight invisible on light notes**: `TNoteHeaderBar.DeriveHotPressed` blends
  toward `clWhite` — on White/Yellow notes the hot state is indistinguishable. Blend
  toward black for light backgrounds (pick direction by luminance).
- **DPI**: header icons are fixed `Canvas.Font.Size := 12` while button size comes from
  `GetCaptionHeight` (scaled) — icons shrink relative to buttons at 150 %+.
  Same for the fixed 8 pt strip/row fonts in `TNoteTagStrip`/`TNoteChecklistRow`.
- **Polling**: `TNoteScrollBar` timer (50 ms) and `TNoteForm.ToolbarTimer` (100 ms) run
  forever per open note window, even when idle / auto-hide disabled. Gating the toolbar
  timer on `GetAutoHideToolbar` is free. The scroll poll is fine but could re-hide the
  native bar here (see C1).
- **`WM_MOUSEWHEEL` result**: `TNoteScrollBar.WMMouseWheel` and `TNoteTagStrip.WMMouseWheel`
  set `Message.Result := 1`; 0 is the "handled" value for wheel messages.
- **`TNoteScrollBar.Detach`** doesn't restore the target's native scrollbar
  (`ShowScrollBar(SB_VERT, True)`), leaving a target that's re-shown natively later
  without its bar.
- **`TNoteColorPicker.ShowAt`** doesn't clamp to the work area — anchored under a
  right-edge Color button, the ~300 px popup opens partly off-screen.
- **Auto-hide + context menu**: `ToolbarTimerTick` keeps the bar visible while the color
  picker is up but doesn't check for the open `pmNote` context menu; the header can hide
  behind an open menu. Cosmetic.
- **Locked-note behavior change**: the header drag zone now resolves via
  `HTTRANSPARENT → HTCAPTION`, so **locked** notes are draggable (the old
  `pnlHeaderMouseDown` explicitly required `not FNote.Locked`). Arguably an improvement —
  noting it in case it was unintentional.
- **Test-isolation issue carried over** (from 2026-09-07 review): `TNoteApplicationTests`
  still runs against live `%APPDATA%\StickyNotes`; this run's one error is exactly that
  design meeting the running app. Injecting a temp base path remains the fix.
- Still open from the previous review (intentionally deferred): shared note-JSON codec,
  storage-factory consolidation, naming leftovers, new-note cascade offset.

## What's genuinely good

- The componentization is a real architecture improvement: `uNoteForm` shrank from a
  monolith into a wiring layer; the fragile `Width + 30` scrollbar hack and the per-chip
  panel churn are gone; DFM and unit stay consistent through the removal (no orphan
  fields/events).
- `TNoteColorPicker` popup (Deactivate/Escape handling, tool-window style) and
  `TNoteHeaderBar` (HTTRANSPARENT drag zone + pressed/hot state machine) are clean,
  self-contained owner-drawn controls.
- The VirtualTreeView migration preserves the non-owning `TNote` reference discipline,
  and `FResults`/group data handling is careful about ownership throughout.
- The B1–B7 fixes are all present, correctly ordered, and now regression-tested; the
  storage-swap callback pair is fired at both swap sites, not just one.
- The 50 ms scroll poll / 100 ms toolbar poll pattern is pragmatic and the early-exit
  guards (`HandleAllocated`, `FIsLoaded`, `FIsClosing`) are consistently applied.

## Suggested fix order

1. C1 (delete one line, re-hide native bar in poll) — the headline feature of this
   changeset is currently inert.
2. C2 (checklist gating) — blocks the checklist feature on empty notes.
3. H1 + H2 (checklist row lifetime + edit anchoring).
4. H3 (Orange/Gray in notes list) — small, user-visible.
5. H4 + H6 (build hygiene).
6. H5 + H7 + minor batch.

---

## Fix log — 2026-09-10 (same day)

All findings fixed in commit `536414d` ("fix(6N): address code review 2026-09-10
findings"). Verified: full dcc32 compile + link clean (W1036 gone); test suite 211/212
— the single error is `TestProductionBackendIsJsonInNoteApplication`, which cannot run
while `StickyNotes.exe` holds the live `vnotes.db`. Re-run with the app closed for
212/212.

- **C1** — `ScrollBars := ssNone` removed (DFM `ssVertical` kept); `TNoteScrollBar.OnTimer`
  now re-hides the native bar every tick (covers pre-handle `Attach` and the EDIT
  sticky-scrollbar re-show); `Detach` restores the native bar.
- **C2** — the header checklist toggle sets `FChecklist.Visible`/`mmContent.Visible`
  directly (empty checklists are now reachable); `LoadNote` calls `UpdateContentMode`
  to auto-select checklist mode by item count (pre-6N behavior restored);
  `CollapseNote` remembers the content mode in `FChecklistWasVisible` and `ExpandNote`
  restores it.
- **H1** — `TNoteChecklistPanel.RemoveRow` shifts the array first, then defers the row
  destruction via `PostMessage(row, CM_RELEASE)` (`TNoteChecklistRow.CMRelease` → Free).
- **H2** — `TNoteChecklistRow` no longer uses `akRight`; width maintained in a `Resize`
  override (`CL_MIN_EDIT_W` floor).
- **H3** — `ncOrange`/`ncGray` added to all three `case` blocks in `uNotesListForm`
  (light-orange/gray group backgrounds, `Projects (Orange)`/`Archive (Gray)` names,
  🟧/⬛ emoji) plus `else` fallbacks.
- **H4** — `build.bat` uses `%VTV_SRC%` (defaults to the current machine path, overridable);
  dproj search path gains `$(VTV_SRC)`; `build_tests.bat` gains the `Components` path.
- **H5** — `TNoteManager.PersistNote` is public; all four arrange handlers persist via it
  (no `Touch`, `UpdatedAt` untouched by arranging).
- **H6** — `CurrentColor`/`CurrentTag` initialized unconditionally; W1036 gone.
- **H7** — both swap blocks in `DoRestore` fire `OnAfterStorageSwap` in a nested `finally`
  even when `Initialize` raises.
- **Minor** — header hover/pressed colors adapt to background luminance; header glyph
  font scales with the DPI-scaled button size; wheel handlers return 0; color picker
  clamps to the anchor monitor's work area.

### Incident: test run clobbered live settings (test isolation is now P1)

Running the suite while `StickyNotes.exe` was open errored mid-test and left the live
`%APPDATA%\StickyNotes\settings.ini` overwritten with test values
(`Backend=JSON`, `MigrationCompleted=0`, default font, empty `LastBackupAt`). The
originals survived in the test's own `settings.ini.testbak` residue and were restored
manually. The running instance holds the same values in memory, so its exit-time
`SaveSettings` stays consistent — but this is exactly the `TNoteApplicationTests`
against-live-APPDATA problem upgraded from hygiene to data-loss risk. Recommended next
step: inject a temp base path into `TNoteApplication`/`TNoteApplicationTests` before the
next test run.
