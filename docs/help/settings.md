# Settings

Open the Settings dialog from the tray icon → **Settings…**. It has five tabs and three buttons
(**OK**, **Cancel**, **Apply** — *Apply* saves without closing).

Settings are stored in `%APPDATA%\StickyNotes\settings.ini`.

## General

| Option | Default | Meaning |
|---|---|---|
| **Start with Windows** | Off | Launch V-Notes automatically at sign-in |
| **Confirm before deleting notes** | On | Ask before a note is deleted |
| **Auto-save delay (ms)** | 1000 | How long after you stop typing a note is saved (and after moving/resizing) |
| **Default note size** | 300 × 250 | Size for newly created notes |
| **Default color** | Yellow | Colour for newly created notes |
| **New notes always on top** | Off | New notes start pinned |
| **Enable global hotkeys** | On | Enables `Ctrl+Alt+N` and `Ctrl+Alt+F` |

## Appearance

| Option | Default | Meaning |
|---|---|---|
| **Dark theme** | Off | Windows 10 Dark styling instead of the light theme |
| **Auto-hide Toolbar** | Off | Hides a note's header buttons until you hover over the header |
| **Note Font** | Segoe UI, 10 pt | Font used for note text; **Choose…** picks a different font |

You can also change an individual note's text size on the fly with `Ctrl` + mouse wheel.

## Hotkeys

| Option | Default |
|---|---|
| **New Note** | `Ctrl+Alt+N` |
| **Search Notes** | `Ctrl+Alt+F` |

Enter a combination as text, e.g. `Ctrl+Alt+N` or `Ctrl+Shift+J`. Changes take effect
immediately, and the tray menu updates to show the combinations you have configured. If another
application already owns a combination, V-Notes tells you (see
[Troubleshooting](troubleshooting.md#global-hotkeys-do-not-work)).

## Backup

| Option | Default | Meaning |
|---|---|---|
| **Enable automatic backups** | On | Periodically writes a ZIP backup |
| **Backup interval (days)** | 1 | How often the automatic backup runs |
| **Retention (days, 0 = none)** | 30 | Deletes backups older than this (0 keeps them all) |

See [Backup & restore](backup-and-restore.md).

## Sync

Sync is off until you configure it. See the [Sync guide](sync.md) for setup details.

| Option | Meaning |
|---|---|
| **Enable sync** | Master switch for syncing |
| **Backend** | `Folder (cloud-synced)` or `WebDAV` |
| **Sync folder** | The folder your cloud client (Drive/Dropbox/OneDrive) syncs, or any shared path |
| **WebDAV URL / user / password** | Used when the backend is WebDAV |
| **Auto-sync every (minutes)** | Interval for background sync (default 15) |

The WebDAV password is stored in the **Windows Credential Manager**, never in `settings.ini`.

## Advanced (settings.ini only)

A few settings have no dialog control and must be edited in `settings.ini` directly:

| Section / key | Values | Meaning |
|---|---|---|
| `[Storage] Backend` | `JSON` or `SQLite` | Which storage engine holds your notes |
| `[Storage] MigrationCompleted`, `MigrationTimestamp` | — | Bookkeeping for the storage migration |
| `[General] LastBackupAt` | timestamp | When the last automatic backup ran |

**`[Storage] Backend`** — `JSON` keeps one file per note under `notes\`; `SQLite` keeps
everything in a single `vnotes.db`. New installations are migrated to SQLite automatically on
first run. Change the value and restart V-Notes to switch; existing notes are migrated for you,
so take a [backup](backup-and-restore.md) first if you want a safety net.
