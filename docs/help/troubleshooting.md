# Troubleshooting

## The diagnostics log

V-Notes writes a log to:

```
%APPDATA%\StickyNotes\vnotes.log
```

It records startup (storage backend and schema version, database integrity check, note count and
load time), hotkey registration, backups and sync. Example:

```
[2026-09-25 12:23:26.999][INFO] SQLite schema initialised at v5 (...)
[2026-09-25 12:23:27.010][INFO] SQLite integrity check passed (quick_check: ok)
[2026-09-25 12:23:27.012][INFO] Note load: 2 note(s) in 3 ms
[2026-09-25 12:23:27.030][INFO] Hotkey registered: "Ctrl+Alt+N" (ID 32768, hwnd 1234567, mod 3, key 78)
```

The file rotates once at ~2 MB (`vnotes.log.1`). When reporting a problem, include the
relevant lines.

## Global hotkeys do not work

1. **Is V-Notes running?** Hotkeys are app hotkeys — if the tray icon is gone, nothing responds.
   Start V-Notes again.
2. **Are hotkeys enabled?** **Settings → General → Enable global hotkeys**.
3. **Is another application using that combination?** When registration fails, V-Notes shows a
   warning and logs `Hotkey registration failed: … (winerr 1409)`. Change the combination in
   **Settings → Hotkeys** (for example to `Ctrl+Shift+J`) and try again.
4. **After changing hotkeys,** the tray menu should show the new combination.

## The tray menu shows the wrong shortcut

It shows whatever is configured in **Settings → Hotkeys**. If it looks stale, reopen the Settings
dialog and press **OK**, or restart V-Notes.

## A pinned note does not stay on top

- Check the **pin icon** on the note — it changes appearance when active, so you can see at a
  glance whether the note is actually pinned (`Ctrl+P` toggles).
- A **locked** note ignores the pin action. Unlock it first (`Ctrl+L`).
- Notes cannot stay above a window that is *itself* always-on-top — Task Manager, some media
  players, screen recorders and launch tools, or exclusive full-screen games. Always-on-top
  windows are ordered among themselves by Windows.
- After changing this behaviour, restart V-Notes so the new build is loaded.

## Notes are missing

- Check which storage backend is in use: **JSON** keeps files in
  `%APPDATA%\StickyNotes\notes\`, **SQLite** keeps one file `%APPDATA%\StickyNotes\vnotes.db`.
  Look in the one matching `[Storage] Backend` in `settings.ini`.
- If a monitor was disconnected, notes that would have been off-screen are pulled back into the
  visible work area — look there rather than at the old coordinates.
- Restore from the newest `.zip` in `%APPDATA%\StickyNotes\backups\` (tray → **Restore…**).

## Nothing is syncing

- Sync must be configured: **Settings → Sync → Enable sync**, with a folder (or a WebDAV URL)
  set. If it is not configured, the tray's **Sync now** item reports "not configured".
- Sync only runs while V-Notes is running.
- Run **Sync now** and read the notification, then check the log for `Sync:` lines.

## Conflicts keep appearing

Two machines are editing the same note. Open **Sync conflicts…** from the tray to review them,
then **Keep as normal note** or **Delete copy**. Editing the note on one machine at a time avoids
most conflicts.

## Starting a second copy just exits

That is intended: V-Notes is single-instance. Launching it again signals the running copy
(which surfaces the Notes List) and the new process exits.

## Testing without touching your real notes

Run a throwaway instance with its own profile:

```
src\StickyNotes.exe --profile=D:\temp\vnotes-smoke
```

Everything — notes, `settings.ini`, the database, the log, `device.id` and sync state — is
redirected into that folder, so your real `%APPDATA%\StickyNotes` is untouched. Delete the folder
when you are done.

You can pre-seed settings in that profile first, e.g. to test sync without clicking anything:

```ini
[Sync]
Enabled=1
BackendType=folder
Folder=D:\temp\sync-target
IntervalMinutes=1
```

## Switching storage backend

Set `[Storage] Backend` in `settings.ini` to `JSON` or `SQLite` and restart. Existing notes are
migrated automatically (progress and integrity checks are logged). Take a backup first.

## Reporting a problem

Include:

1. What you did and what happened.
2. The relevant lines from `%APPDATA%\StickyNotes\vnotes.log`.
3. Your Windows version and whether the storage backend is JSON or SQLite.
