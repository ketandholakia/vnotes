# Getting started

## Installing

V-Notes is a single executable — there is no installer.

1. Copy `StickyNotes.exe` anywhere you like (e.g. `C:\Program Files\V-Notes\`).
2. Run it. It starts **minimised to the system tray** — look for the note icon in the
   notification area (possibly behind the `^` chevron).
3. On first run it creates `%APPDATA%\StickyNotes\` and one empty note.

To have it start with Windows: tray icon → **Settings… → General → Start with Windows**.

## The tray icon

The tray icon is the app's control centre. **Left-click** it to open the Notes List;
**right-click** it for the menu:

| Menu item | What it does |
|---|---|
| **New Note** | Creates a note (`Ctrl+Alt+N`) |
| **Open Notes List** | Opens the searchable list of all notes (`Ctrl+Alt+F`) |
| **Arrange Notes ▸** | Cascade / Grid / By Color / By Tag — tidies open note windows |
| **Settings…** | The Settings dialog |
| **Backup…** | Creates a ZIP backup now |
| **Restore…** | Restores from a backup file |
| **Sync now** | Runs a sync immediately (only present when sync is configured) |
| **Sync conflicts…** | Reviews conflict copies created by sync (only when there are any) |
| **About** | Version information |
| **Exit** | Quits V-Notes |

> Closing a note window does **not** quit the app — the tray icon stays until you choose **Exit**.

## Creating and editing notes

- **New note:** `Ctrl+Alt+N`, or tray → **New Note**.
- **Edit:** just click into the note and type. Notes auto-save about a second after you
  stop typing (the delay is configurable in Settings).
- **Move:** drag the note by its header bar.
- **Resize:** drag any edge or corner (native Windows behaviour).
- **Close:** the close button in the header, `Ctrl+Esc`, or `Alt+F4`.

Because notes are plain files, nothing is "committed" — a note is saved as soon as it changes.

## Where to go next

- [Working with notes](notes.md) — what the header buttons do.
- [Keyboard shortcuts](keyboard-shortcuts.md) — full reference.
- [Settings](settings.md) — theme, fonts, autosave delay, hotkeys, backups, sync.
