# Sticky Notes - Architecture Documentation

## Overview

A lightweight desktop sticky notes application for Windows, built with Delphi using a clean, modular architecture that separates concerns across Forms, Controllers, Models, Storage, Services, and Utilities.

## Architecture

```
src/
├── Forms/              # UI Layer (Views)
│   ├── uNoteForm.pas       # Individual note window
│   ├── uTrayForm.pas       # System tray application
│   ├── uSettingsForm.pas   # Settings dialog
│   └── uAboutForm.pas      # About dialog
│
├── Controllers/        # Business Logic Layer
│   ├── uNoteManager.pas    # Core note management (CRUD, events)
│   ├── uTrayController.pas # Tray menu handling
│   └── uSettingsController.pas # Settings persistence & application
│
├── Models/             # Data Models
│   ├── uNote.pas           # TNote class with properties
│   ├── uSettings.pas       # TSettings class with INI persistence
│   └── uEnums.pas          # Enumerations (colors, storage types)
│
├── Storage/            # Data Persistence Abstraction
│   ├── uStorage.pas        # INoteStorage interface + factory
│   ├── uJsonStorage.pas    # JSON file-per-note implementation
│   └── uSQLiteStorage.pas  # SQLite implementation (stub)
│
├── Services/           # Cross-cutting Concerns
│   ├── uAutosaveService.pas    # Debounced auto-save (1s default)
│   ├── uHotkeyService.pas      # Global hotkey registration
│   ├── uStartupService.pas     # Auto-start registry management
│   ├── uThemeService.pas       # Light/Dark theme management
│   └── uBackupService.pas      # ZIP-based backup/restore
│
├── Utils/              # Shared Utilities
│   ├── uWindowUtils.pas      # Borderless window handling (WM_NCHITTEST)
│   ├── uJsonUtils.pas        # JSON helper methods
│   ├── uColorUtils.pas       # Color manipulation helpers
│   └── uMonitorUtils.pas     # Multi-monitor support
│
├── Resources/          # Images, icons, manifests
│
└── StickyNotes.dpr     # Main entry point
```

## Key Design Decisions

### 1. Storage Abstraction (INoteStorage)
- Interface-based design allows swapping storage backends
- JSON implementation: one file per note (`%APPDATA%\StickyNotes\notes\####.json`)
- Easy Git/Dropbox/OneDrive sync - no database lock contention
- Corruption affects single note only
- No FireDAC/SQLite DLL dependencies

### 2. Note Manager as Central Hub
- `TNoteManager` owns all note instances
- Events: `OnNoteCreated`, `OnNoteChanged`, `OnNoteDeleted`
- No form directly saves files - all persistence goes through manager
- Enables future features: search, tags, cloud sync without UI changes

### 3. Autosave Service
- Debounced save (default 1 second) via `TTimer`
- Restarts timer on each keystroke/resize/move
- Prevents excessive disk writes

### 4. Borderless Windows with Native Behavior
- `WM_NCHITTEST` returns `HTCAPTION`, `HTLEFT`, `HTRIGHT`, etc.
- Windows handles all dragging/resizing natively - no flicker
- Custom caption area with buttons (close, pin, collapse, lock, color)

### 5. Event System for Extensibility
```pascal
type
  TNoteEvent = procedure(const ANote: TNote) of object;

  TNoteManager = class
  public
    OnNoteCreated: TNoteEvent;
    OnNoteChanged: TNoteEvent;
    OnNoteDeleted: TNoteEvent;
  end;
```
Allows plugins/services to subscribe without modifying core code.

## Building

### Requirements
- Delphi 11 Alexandria or later (VCL)
- Windows 10/11

### Steps
1. Open `src/StickyNotes.dproj` in Delphi IDE
2. Build (Ctrl+F9) or Run (F9)
3. Executable outputs to `src/Win32/Debug/` or `src/Win32/Release/`

### Command Line (MSBuild)
```bash
msbuild src/StickyNotes.dproj /p:Config=Release /p:Platform=Win32
```

## Data Storage

### Location
```
%APPDATA%\StickyNotes\
├── settings.ini
└── notes\
    ├── 0000000001.json
    ├── 0000000002.json
    └── ...
```

### Note JSON Format
```json
{
  "ID": 1,
  "Title": "Shopping List",
  "Content": "Milk\nEggs\nBread",
  "Color": 0,
  "Left": 100,
  "Top": 100,
  "Width": 300,
  "Height": 250,
  "AlwaysOnTop": false,
  "Collapsed": false,
  "Locked": false,
  "CreatedAt": "2026-01-15T10:30:00",
  "UpdatedAt": "2026-01-15T10:35:00"
}
```

### Settings INI Format
```ini
[General]
AutoStart=0
ConfirmDelete=1
AutosaveDelay=1000
DefaultColor=0
DefaultWidth=300
DefaultHeight=250
DefaultAlwaysOnTop=0
EnableHotkeys=1

[Backup]
Enabled=1
IntervalDays=1

[Appearance]
DarkTheme=0

[Hotkeys]
NewNote=Ctrl+Alt+N
Search=Ctrl+Alt+F
```

## Features

### Current (Phase 1-4)
- ✅ System tray application
- ✅ JSON file-per-note storage
- ✅ Borderless note windows with native drag/resize
- ✅ 8 colors (Yellow, Green, Blue, Pink, Purple, Orange, White, Gray)
- ✅ Always on Top, Collapse, Lock
- ✅ Right-click context menu
- ✅ Global hotkeys (Ctrl+Alt+N = New Note)
- ✅ Auto-save with configurable delay
- ✅ Light/Dark theme
- ✅ Auto-start with Windows
- ✅ Backup/Restore (ZIP)
- ✅ Multi-monitor support

### Planned (Phase 5-8)
- 🔲 Search across all notes (Ctrl+Alt+F)
- 🔲 Rich text / Markdown support
- 🔲 Checklists with checkboxes
- 🔲 Reminders with notifications
- 🔲 Tags (#work, #home)
- 🔲 Pin notes (always above others)
- 🔲 Export (TXT, HTML, PDF, Markdown)
- 🔲 Cloud sync (OneDrive, Dropbox, Google Drive, Nextcloud)
- 🔲 Plugin architecture

## Extending Storage

To add a new storage backend (e.g., SQLite, Cloud):

1. Implement `INoteStorage` interface
2. Add to `TStorageFactory.CreateStorage`
3. No UI or controller changes needed

```pascal
type
  TCloudStorage = class(TInterfacedObject, INoteStorage)
  public
    function SaveNote(const ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function LoadAllNotes: TObjectList<TNote>;
    function GetNextID: Int64;
    procedure Initialize;
    procedure Finalize;
  end;
```

## Hotkeys

| Action | Default | Configurable |
|--------|---------|--------------|
| New Note | Ctrl+Alt+N | Yes |
| Search | Ctrl+Alt+F | Yes |

Format: `Ctrl+Alt+Shift+Win+Key` (e.g., `Ctrl+Alt+N`, `Shift+F1`)

## Themes

### Light Theme (Default)
Standard Windows 10 style with colored sticky notes

### Dark Theme
Windows 10 Dark style with muted note colors

## License

MIT License - See LICENSE file for details.

## Contributing

1. Follow the existing architecture patterns
2. Keep Forms free of business logic
3. Use interfaces for cross-layer communication
4. Add events to `TNoteManager` for new cross-cutting features
5. Write unit tests for Models and Services