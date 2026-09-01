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

## Phase Status

| Phase | Status |
|-------|--------|
| Phase 1 — Reliability | COMPLETE |
| Phase 2 — Architecture | COMPLETE |
| Phase 2A — TNoteApplication extraction | COMPLETE |
| Phase 2B — Service/Form decoupling | COMPLETE |
| Phase 2C — Application/UI event boundary | COMPLETE |
| Phase 3 — Persistence | NOT STARTED |

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
