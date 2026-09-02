# Sticky Notes

A lightweight desktop sticky notes application for Windows, built with Delphi using a clean, modular architecture.

## Features

- **Colorful sticky notes** - 8 colors (Yellow, Green, Blue, Pink, Purple, Orange, White, Gray)
- **Native window behavior** - Drag from header, resize from edges using Windows WM_NCHITTEST
- **Always on Top** - Keep notes visible above other windows
- **Collapse** - Minimize to header only
- **Lock** - Prevent accidental edits
- **Global hotkeys** - `Ctrl+Alt+N` for new note, `Ctrl+Alt+F` opens the Notes List with in-memory search
- **Auto-save** - Debounced save (1 second default) on typing, moving, resizing
- **Light/Dark theme** - Windows 10 / Windows 10 Dark styles
- **Auto-start** - Launch with Windows
- **Backup & Restore** - ZIP-based backups
- **Multi-monitor support** - Notes are restored clamped into a visible monitor work area (positions saved off-screen are moved back on launch; the corrected position is re-clamped on every start)
- **JSON storage** - One file per note, easy to sync with Git/Dropbox/OneDrive

## Architecture

Clean separation of concerns:

```
Forms/          # UI only (Views)
Controllers/    # Business logic (NoteManager, TrayController, SettingsController)
Models/         # Data (Note, Settings, Enums)
Storage/        # Abstract persistence (JSON, SQLite stub)
Services/       # Cross-cutting (Autosave, Hotkeys, Theme, Backup, Startup)
Utils/          # Shared helpers (Window, JSON, Color, Monitor)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed documentation.

## Building

### Requirements
- Delphi 11 Alexandria or later
- Windows 10/11

### Delphi IDE
1. Open `src/StickyNotes.dproj`
2. Build (Ctrl+F9) or Run (F9)

### Command Line
```bash
msbuild src/StickyNotes.dproj /p:Config=Release /p:Platform=Win32
```

Output: `src/Win32/Release/StickyNotes.exe`

Quick `dcc32` builds (no MSBuild or RAD Studio command prompt needed — the scripts auto-locate `rsvars.bat` themselves via `DELPHI_ROOT`, or by probing Studio 23.0 → 22.0 → 21.0):

```bat
build.bat        REM canonical Win32 Debug build -> src\Win32\Debug\StickyNotes.exe
build_tests.bat  REM DUnitX unit-test build -> tests\StickyNotes.Tests.exe
```

## Data Location

```
%APPDATA%\StickyNotes\
├── settings.ini
└── notes\
    ├── 0000000001.json
    └── ...
```

Each note is an independent JSON file - corruption affects only one note, easy to sync.

## Hotkeys

| Action | Default | Status |
|--------|---------|--------|
| New Note | `Ctrl+Alt+N` | Implemented |
| Search Notes | `Ctrl+Alt+F` | Implemented - opens the Notes List (Title/Content search) and focuses the search box |

Configurable in Settings → Hotkeys.

## Extending

The storage abstraction makes it easy to add new backends:

```pascal
type
  TMyStorage = class(TInterfacedObject, INoteStorage)
  public
    function SaveNote(const ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function LoadAllNotes: TObjectList<TNote>;
    function GetNextID: Int64;
    procedure Initialize;
    procedure Finalize;
  end;
```

Add to `TStorageFactory.CreateStorage` - no UI changes needed.

## Roadmap

| Phase | Features |
|-------|----------|
| 1 | Tray app, JSON storage, note manager |
| 2 | Borderless note windows |
| 3 | Drag, resize, autosave |
| 4 | Colors, settings, always-on-top |
| 5 | Search, hotkeys, backup |
| 6 | Rich text, checklists, markdown |
| 7 | Cloud sync |
| 8 | Plugins, reminders, tags |

## License

MIT License