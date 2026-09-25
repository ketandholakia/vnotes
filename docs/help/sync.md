# Sync

Sync keeps your notes consistent across machines by exchanging notes through a shared location.
It is **off by default**.

## Setup

1. Tray icon → **Settings… → Sync**.
2. Tick **Enable sync**.
3. Choose a **Backend**:

   | Backend | What to provide | Good for |
   |---|---|---|
   | **Folder (cloud-synced)** | The folder your cloud client already syncs (Drive, Dropbox, OneDrive), or any shared/mounted path | The simplest setup |
   | **WebDAV** | Server URL, user name and password (stored in the Windows Credential Manager) | Nextcloud, ownCloud, and other WebDAV hosts |

4. Set **Auto-sync every (minutes)** (default 15).
5. Press **OK**.

## Running a sync

- **Automatically**, every N minutes, while V-Notes is running.
- **Manually**, from the tray menu → **Sync now**.

The tray tooltip shows progress while a sync runs, and a notification reports the result, e.g.
*"Sync complete: 3 pushed, 1 pulled, 0 conflicts, 0 removed"*. Sync runs off the UI thread, so
the app stays responsive while it works.

## What is synced

| Synced | Device-local (never synced) |
|---|---|
| Title, content | **Window position and size** |
| Colour, favourite, lock, collapsed | |
| Tags and checklist items | |
| Created/updated times, the note's identity | |

Window geometry stays on the machine that owns it — a note moved on your desktop will not fling
the same note across the office PC's screen.

## How conflicts are handled

If the same note is edited on two machines, the conflict is resolved by **revision**: the higher
revision wins overall, and **the losing version is never thrown away** — it is kept as a
**conflict copy** (its title gets a `(conflict from …)` suffix).

To resolve them: tray menu → **Sync conflicts…**. For each copy you can:

- **Keep as normal note** — the copy becomes an ordinary note (both versions stay), or
- **Delete copy** — removes the copy, keeping the other version.

The tray item shows the number of unresolved conflicts, e.g. *Sync conflicts (2)…*.

## Deletions

Deleting a note on one machine removes it on the others the next time they sync — deleted notes
do not come back.

## Security — please read

**Sync does not encrypt your notes.** The remote copy is the same plain JSON as the local one,
so anyone who can read the sync folder (or the WebDAV server) can read your notes. Sync protects
you against *losing* notes, not against someone reading them. End-to-end encryption is a known,
deliberately deferred item — see
[`docs/PHASE_7F_ENCRYPTION_DESIGN.md`](../PHASE_7F_ENCRYPTION_DESIGN.md).

## How it is stored remotely

Objects are written one file per note into a `notes` sub-folder of the sync location:

```
<sync folder>\notes\<globally-unique-id>.json
```

The file name is a globally unique note id (not a local number) precisely so two machines can
never collide. A small `sync-state.json` in your profile records what has been synced, and
`device.id` identifies this installation.

## Limitations

- **WebDAV support is implemented but has not been exercised against a live server in this
  repository.** If you hit a problem, the log (see [Troubleshooting](troubleshooting.md)) records
  what happened — please capture it.
- Sync only runs while V-Notes is running.
- A note cannot be above on another window that is itself always-on-top (a Windows rule).
