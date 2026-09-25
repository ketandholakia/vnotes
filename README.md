# V-Notes

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
- **Backup & Restore** - ZIP-based backups with scheduled automatic backups (interval configurable in Settings)
- **Single instance** - launching a second copy signals the running app (surfaces the Notes List) and exits
- **Multi-monitor support** - Notes are restored clamped into a visible monitor work area; corrected coordinates are persisted immediately
- **JSON storage** - One file per note, easy to sync with Git/Dropbox/OneDrive (default)
- **Optional SQLite backend** - Swap JSON for a single SQLite database via settings (includes tags + checklist)
- **Sync** - **folder** backend (Drive / Dropbox / OneDrive) or **WebDAV**; automatic interval sync or a tray **Sync now** item; last-writer-wins per note by revision with ETag conflict detection, and conflict copies preserved (WebDAV password kept in the Windows credential store)

## Architecture

Clean separation of concerns:

```
Application/    # Orchestration (NoteApplication, NoteEditorContext)
Forms/          # UI only (views: tray, note, list, settings, about)
Components/     # Reusable note-window widgets (header, scrollbar, color picker, checklist, tags)
Controllers/    # Business logic (NoteManager, SettingsController)
Models/         # Data (Note, Settings, Enums)
Storage/        # Abstract persistence (JSON default, SQLite opt-in)
Services/       # Cross-cutting (Autosave, Hotkeys, Theme, Backup, Startup, Migration)
Utils/          # Shared helpers (Window, JSON, Color, Monitor, ISO-8601, Logger)
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
build.bat        REM canonical Win32 Debug build -> src\StickyNotes.exe
build_tests.bat  REM DUnitX unit-test build -> tests\StickyNotes.Tests.exe
```

### Isolated profile (safe smoke testing)

The application normally uses `%APPDATA%\StickyNotes`. To run a throwaway instance that never
touches your real notes, pass a profile directory:

```bat
src\StickyNotes.exe --profile=D:\temp\vnotes-smoke
```

`--profile` redirects the notes, `settings.ini`, the database, `vnotes.log`, `device.id` and the
sync state to that folder, so a smoke test is fully isolated. Diagnostics land in
`<profile>\vnotes.log`.

### Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) builds the app and runs the DUnitX
suite on every push and pull request. Delphi is commercial software that GitHub-hosted
runners do not provide, so the job runs on a **self-hosted Windows runner** labelled
`self-hosted, windows, delphi` with RAD Studio and Virtual-Tree-View installed. Optionally
set the repository variables `DELPHI_ROOT` and `VTV_SRC` to point at the toolchain and
Virtual-Tree-View source on that machine; if unset the build scripts auto-probe.

## Data Location

```
%APPDATA%\StickyNotes\
├── settings.ini
├── vnotes.log          (diagnostics; rotates at ~2 MB)
└── notes\
    ├── 0000000001.json
    └── ...
```

Each note is an independent JSON file - corruption affects only one note, easy to sync.

The backend is selectable via `Storage\Backend` in `settings.ini`: `JSON` (default) or `SQLite`,
which keeps everything in a single `%APPDATA%\StickyNotes\vnotes.db`.

## Hotkeys

| Action | Default | Status |
|--------|---------|--------|
| New Note | `Ctrl+Alt+N` | Implemented (Global) |
| Search Notes | `Ctrl+Alt+F` | Implemented (Global) - opens the Notes List |
| Favorite Note | `Ctrl+F` | Implemented (Note Window) |
| Pin Note | `Ctrl+P` | Implemented (Note Window) |
| Collapse Note | `Ctrl+M` | Implemented (Note Window) |
| Lock Note | `Ctrl+L` | Implemented (Note Window) |
| Toggle Checklist | `Ctrl+K` | Implemented (Note Window) |
| Delete Note | `Ctrl+D` | Implemented (Note Window) |

Configurable in Settings → Hotkeys (Global hotkeys only).

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

Register it in `TStorageResolver.ResolveStorage` (`src/Storage/uStorageResolver.pas`) - no UI changes needed.

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

Phase 7 (cloud sync) has a design analysis: see [docs/PHASE_7_CLOUD_SYNC_DESIGN.md](docs/PHASE_7_CLOUD_SYNC_DESIGN.md).

## License

MIT License