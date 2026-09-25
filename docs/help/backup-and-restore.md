# Backup & restore

Backups are ZIP files containing your notes, your settings and (when using the SQLite backend)
the database. They are written to:

```
%APPDATA%\StickyNotes\backups\
```

## Making a backup

Tray icon → **Backup…**. V-Notes writes a new ZIP into the `backups` folder and reports the
result when it finishes.

## Automatic backups

Configure them in **Settings → Backup**:

| Option | Default |
|---|---|
| Enable automatic backups | On |
| Backup interval (days) | 1 |
| Retention (days, 0 = none) | 30 |

The scheduler runs while V-Notes is running and takes a backup when the interval has elapsed.
Backups older than the retention period are deleted automatically (set retention to `0` to keep
everything).

> Because V-Notes is a tray app, automatic backups only happen while it is running. If your
> machine sleeps/shuts down regularly, take a manual backup now and then as well.

## Restoring

Tray icon → **Restore…**, and pick a `.zip` from the `backups` folder (the file dialog opens
there by default).

> **Restoring replaces your current notes with the contents of the backup.** Anything created
> after that backup was taken is lost. Take a fresh backup first if you are unsure.

V-Notes validates the backup before applying it, and works with both storage backends (a JSON
backup restores into a JSON profile and vice versa).

## What a backup contains

- Every note, with its content, colour, position, flags, tags and checklist items.
- Your `settings.ini`.
- The `vnotes.db` database when the SQLite backend is in use.
- A manifest describing the backup, so a damaged or foreign file can be rejected.

## Recovering without a backup

Because the JSON backend stores one plain file per note under `%APPDATA%\StickyNotes\notes\`,
you can also copy those `.json` files by hand to move notes between machines. With the SQLite
backend, copy `vnotes.db` instead.
