# V-Notes Help

User documentation for V-Notes, a lightweight desktop sticky-notes app for Windows.

| Guide | What it covers |
|---|---|
| [Getting started](getting-started.md) | First run, creating notes, the tray icon, the basic workflow |
| [Working with notes](notes.md) | Colours, pin, lock, collapse, favourite, duplicate, delete, properties |
| [Keyboard shortcuts](keyboard-shortcuts.md) | Every global, note-window and Notes-List shortcut |
| [Notes List & search](notes-list-and-search.md) | Finding notes, sorting, tag filter, arranging windows |
| [Settings](settings.md) | Every option in the Settings dialog, tab by tab |
| [Backup & restore](backup-and-restore.md) | Manual and automatic ZIP backups, retention, restoring |
| [Sync](sync.md) | Folder and WebDAV sync, intervals, how conflicts are handled |
| [Troubleshooting](troubleshooting.md) | Hotkeys, diagnostics log, isolated test profile, FAQ |

## At a glance

**Global (work anywhere):**

| Shortcut | Action |
|---|---|
| `Ctrl+Alt+N` | New note |
| `Ctrl+Alt+F` | Open the Notes List with the search box focused |

**Note window:**

| Shortcut | Action |
|---|---|
| `Ctrl+F` | Toggle favourite |
| `Ctrl+P` | Toggle always-on-top (pin) |
| `Ctrl+M` | Toggle collapse |
| `Ctrl+L` | Toggle lock |
| `Ctrl+K` | Toggle checklist |
| `Ctrl+D` | Delete note |
| `Ctrl+Esc` / `Alt+F4` | Close note |

**Tray icon (right-click):** New Note · Open Notes List · Arrange Notes ▸ · Settings… · Backup… · Restore… · Sync now · Sync conflicts… · About · Exit

## Where your data lives

Everything is under `%APPDATA%\StickyNotes\`:

| Item | Purpose |
|---|---|
| `notes\*.json` | Your notes (JSON backend: one file per note) |
| `vnotes.db` | Your notes (SQLite backend: one database) |
| `settings.ini` | All settings |
| `backups\*.zip` | Backups (manual and automatic) |
| `vnotes.log` | Diagnostics log (see [Troubleshooting](troubleshooting.md)) |
| `device.id` | This installation's id (used by sync) |
| `sync-state.json` | Sync bookkeeping (last synced revisions) |

> Tip: you can run a completely throwaway instance that never touches the above, using
> `src\StickyNotes.exe --profile=D:\temp\vnotes-smoke`. See
> [Troubleshooting](troubleshooting.md#testing-without-touching-your-real-notes).
