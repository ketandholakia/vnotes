# V-Notes Code Review — 2026-09-17

Scope: the **uncommitted working tree** on top of `554dd97` (`fix(6N)`), i.e. 18 modified
files (+389 / −194) plus the new `src/Services/uServiceInterfaces.pas`. This is the
service-interface (DI) refactor + `System.DateUtils` ISO-8601 consolidation +
event-driven note open/close batch.

## Verification performed in this review

| # | Check | Command | Result |
|---|-------|---------|--------|
| 1 | Main build | `build.bat` (dcc32 36.0, Studio 23.0, Win32 Debug) | **Compile clean** — all units, hints only. Link fails: `Fatal: F2039 Could not create output file 'StickyNotes.exe'` — `StickyNotes.exe` PID **12072** (started 09:32:47) holds the file. |
| 2 | Test project build | `build_tests.bat` | **BUILD SUCCESSFUL** |
| 3 | Test suite **run** | — | **Deliberately not run.** See C3: running the suite writes to live `%APPDATA%\StickyNotes` (documented data-loss incident on 2026-09-10), and the running app currently holds `vnotes.db`. Do not run until C3 is fixed. |
| 4 | ISO-8601 semantics probe | `tools` scratch program, compiled with **both** Studio 23.0 and 21.0 | Identical output on both toolchains — see C1 |
| 5 | Live data inspection | read-only copy of `%APPDATA%\StickyNotes\vnotes.db` + backup ZIP contents | See C1 — the defect is already visible in the user's own data |

---

## Critical

### C1. The ISO-8601 switch silently shifts every legacy timestamp by the local UTC offset — already happened to real data

The working tree replaced the local naive helper with `System.DateUtils`:

```pascal
// before (HEAD, uJsonStorage/uSQLiteStorage/uBackupService)
function DateTimeToISO8601(const ADateTime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', ADateTime);   // naive, second precision
end;
...
Note.CreatedAt := System.DateUtils.ISO8601ToDate(CreatedStr);     // AReturnUTC default = True
```

```pascal
// after (working tree)
Result.AddPair('CreatedAt', TJSONString.Create(System.DateUtils.DateToISO8601(ANote.CreatedAt, False)));
...
Note.CreatedAt := System.DateUtils.ISO8601ToDate(CreatedStr, False);
```

Probe output (Studio 23.0 *and* Studio 21.0 — identical):

```
input                      = 2026-09-17 14:33:25.400
local FormatDateTime       = 2026-09-17T14:33:25          <- what HEAD wrote
DateToISO8601(D,False)     = 2026-09-17T14:33:25.400+05:30 <- what the working tree writes
DateToISO8601(D,True)      = 2026-09-17T14:33:25.400Z

ISO8601ToDate('2026-09-17T14:33:25',          False) -> 20:03:25.000   <- +5:30 SHIFT
ISO8601ToDate('2026-09-17T14:33:25',          True ) -> 14:33:25.000   <- what HEAD did
ISO8601ToDate('2026-09-17T14:33:25.400+05:30',False) -> 14:33:25.400   <- new data: fine
```

`ISO8601ToDate` treats an **offset-less** string as UTC. HEAD wrote offset-less strings
and read them back with `AReturnUTC = True`, so the value round-tripped unchanged. The new
reader passes `False`, so every pre-existing offset-less timestamp is reinterpreted as UTC
and converted to local — on this machine **+5:30** — and then re-written *with* the offset,
making the shift permanent on the next save.

**This has already happened in the user's live data.** Evidence from their own backups:

| Source | note 9 `CreatedAt` |
|---|---|
| `StickyNotes_Backup_20260909_143545.zip` → `notes\0000000009.json` | `2026-09-09T09:09:02` (naive) |
| live `vnotes.db` (read-only copy) | `2026-09-09T14:39:02.000+05:30` |
| `StickyNotes_Backup_20260917_093248.zip` → `notes\0000000009.json` | `2026-09-09T14:39:02…` (offset) |

Delta = **+5:30 exactly** = local UTC offset. The `.000` milliseconds are the fingerprint of
a value that was re-parsed from a second-precision string.

Impact: note timestamps of pre-6N data are inflated by +5:30, permanently. Since the Notes
List sorts `UpdatedAt DESC`, older notes now outrank notes actually edited later; restore
verification (`TimeStampsEqual`) also compares inflated-but-consistent values, so it passes
and hides the problem. `settings.ini` `LastBackupAt` is unaffected (it already used the
offset form in HEAD), but note timestamps in `notes\*.json`, `vnotes.db`, and legacy backup
ZIPs are all affected.

**Fix** — one codec, offset-aware on read. `src/Utils/uIso8601.pas` already exists for
exactly this and is **dead code** (referenced by neither `.dpr`); use it:

```pascal
function StoredISO8601ToDateTime(const AText: string): TDateTime;
var
  S: string;
begin
  S := Trim(AText);
  if S = '' then
  begin
    Result := Now;
    Exit;
  end;
  // ISO8601ToDate treats an offset-less string as UTC. Legacy rows and files are
  // naive LOCAL wall-clock, so request UTC back (True) when there is no offset;
  // otherwise (offset or trailing Z) convert to local (False).
  if (Pos('+', S) > 10) or (Pos('-', S, 11) > 0) or S.EndsWith('Z', True) then
    Result := System.DateUtils.ISO8601ToDate(S, False)
  else
    Result := System.DateUtils.ISO8601ToDate(S, True);
end;
```

Route `uJsonStorage`, `uSQLiteStorage`, `uBackupService` and `uSettings` through it.
Repairing values that are *already* shifted is a separate one-off decision — for note 9 the
true value (`09:09:02`) is recoverable from the 2026-09-09 backup; a `.000` suffix plus a
pre-change date is a workable (not guaranteed) fingerprint for finding the rest.

### C2. `TBackupService.AAppDataPath` defaults to `''` → silent CWD-relative backup path

```pascal
constructor TBackupService.Create(ANoteManager: TNoteManager; ASettings: TSettings;
  const ABackupPath: string; const AAppDataPath: string = '');
...
FileName := TPath.Combine(FAppDataPath, 'vnotes.db');   // TPath.Combine('', 'vnotes.db') = 'vnotes.db'
```

The older derivation (`TPath.GetDirectoryName(ExpandFileName(FBackupPath))`) was removed, so
the default now resolves to a **process-relative** `vnotes.db`. All 7 current call sites pass
4 arguments, so it is latent — but any future 3-argument caller silently backs up/restores
the wrong database. Derive the fallback when the parameter is empty, or make it required.

### C3. Test suite still runs against live `%APPDATA%\StickyNotes` (P1 — still open, data-loss risk)

`tests/Models/TNoteApplicationTests.pas:39` — `TNoteApplication.Create(FTestForm.Handle)`
uses the production `GetAppDataPath`. The 2026-09-10 incident (live `settings.ini` overwritten
with test values) is still reachable, and it is now worse because `vnotes.db` is live too.
`TNoteApplication` already accepts injected services (this batch) — injecting a **base path**
is the missing half. Until then the suite cannot be run safely on a machine with real notes.

---

## Important

### H1. Restoring an older backup re-introduces naive timestamps → another +5:30 each time
`uBackupService.pas:707/711` read note timestamps with `ISO8601ToDate(..., False)`. Backups
from before this change (e.g. `…20260903_061536.zip`, `…20260909_143545.zip`) contain naive
strings, so a restore shifts every note again and persists it. Fixing C1's reader fixes this
path too; until then, treat pre-2026-09-10 backup ZIPs as unsafe to restore.

### H2. Three of the eight new interfaces are declared but never implemented
Implemented: `IAutosaveService`, `IBackupService`, `IHotkeyService`, `IThemeService`,
`IBackupScheduler`. Dead: `IStartupService`, `IStorageMigrationService`,
`IStorageMigrationOrchestrator` — `TStartupService`, `TStorageMigrationService` and
`TStorageMigrationOrchestrator` are still plain classes. Either finish the conversion or drop
the declarations; a declared-but-unimplemented abstraction is worse than none.

Two structural notes on `uServiceInterfaces.pas`:
- it `uses uStorageMigrationService` (for `TMigrationResult`), so the moment
  `TStorageMigrationService` implements its own interface you get a **circular unit
  reference**. Extract the shared types instead.
- it `uses Vcl.Graphics` / `Winapi.Messages` — a cross-cutting contract unit that drags the
  VCL into every consumer.

### H3. UI orchestration moved down into the model layer
`TNoteManager` now owns `RequestOpenAllNotes` / `RequestCloseAllNotes` and fires
UI-directed events; `TTrayForm.OpenAllNotes` / `CloseAllNotes` are one-line delegators.
Behaviour is preserved (`CloseWithoutSaving` also saved via `FormClose`, so this is not a
regression), but two things to note:
- the loop is over **all notes**, each doing a linear `FindNoteForm`, so every restore and
  startup is O(n²) in open windows. Iterating `FNoteForms` was cheaper and correct.
- `TNoteForm.CloseWithoutSaving` is misnamed — `FormClose` saves unconditionally; the flag
  only suppresses the *second* save in `FormDestroy`. Rename or make it real.

### H4. 26 orphaned quarantine databases (624 KB) never cleaned up
`%APPDATA%\StickyNotes\vnotes.db.orphan.<timestamp>` — 26 files, all from 2026-09-06, from
repeated divergent-DB quarantine during Phase 6M testing. The quarantine path creates a new
file on every occurrence and never prunes. Add a retention rule (e.g. keep newest 3) and
consider a one-off cleanup.

### H5. `tests/vnotes.db` (24,576 B) is untracked and **not** gitignored
`git check-ignore` does not match it, so it will be committed on the next `git add -A`. The
`.gitignore` covers `*.dcu` / `*.exe` / `Win32/` but not `*.db`. Also add
`settings.ini.testbak` (the 2026-09-10 incident's residue) and the `backups/` pattern.

### H6. Docs now contradict the code
- `README.md:19` “**JSON storage** — one file per note”, `:29` “SQLite stub”, `:66-70` data
  location shows only `notes\*.json`.
- `docs/ARCHITECTURE.md:113` “uSQLiteStorage.pas (stub only, not functional)”, `:219-220`
  “SQLite stub … all methods return stub/empty results”, `:329` “JSON NOW, SQLITE LATER”.
- Reality (live `settings.ini`): `Backend=SQLite`, `MigrationCompleted=1`,
  `MigrationTimestamp=2026-09-06T15:18:17.653+05:30`; SQLite is authoritative since 6M.
- The `CLAIMS_LEDGER.md` audit covers `DEVELOPMENT_PLAN.md` only — these two files have no
  owner, which is why they drifted. Extend the ledger to them.

### H7. Repo-root junk is committed
`1788159680651_4neem.html` (146,762 B) and `1788159680651_4neem.json` (294,981 B) — 435 KB
of unrelated scraped content at the repo root. Move to `docs/` or delete.

### H8. A 389-line refactor is sitting uncommitted with no phase entry
The repo's convention is one phase + a validation table per change (`DEVELOPMENT_PLAN.md`),
and `554dd97`/`536414d` were each closed out that way. This batch (DI + ISO + event
routing + tightened migration tolerance) has no entry and no test-suite run on record.
Split it into reviewable commits — the timestamp change (C1) should have been its own commit
with a data-compatibility note; it is the kind of change that should never ride along inside
a DI refactor.

---

## Minor / hygiene

- `uHotkeyService.pas(23)` `H2219 Private symbol 'FOnHotkey' declared but never used`.
- `uTrayForm.pas(89)` `H2269` — `WndProc` override is `private`, base is `protected`.
- `uBackupService.pas(241)`, `uJsonUtils.pas(66)`, `StickyNotes.dpr(90)` — `H2077` assigned
  value never used (`SingleInstance`); `uNoteScrollBar.pas(61)` unused `TrackRect`.
- Missing `System.Types` / `System.UITypes` in `uses` blocks (`H2443` in `uWindowUtils`,
  `uNoteForm`) — inline functions not expanded.
- `TAutosaveService.SetDelay` writes `FTimer.Interval` without validating the input and
  without restarting a pending debounce; a `<= 0` value silently disables autosave.
- `src/Utils/uIso8601.pas` is dead code (not in either `.dpr`) — repurpose it per C1 instead
  of leaving a third timestamp helper around.
- `uNoteManager.pas` has no trailing newline.
- `DateToISO8601` is a confusingly-named function to depend on (it returns a *date-time* with
  offset in Delphi 12); wrap it once so the call site reads unambiguously.

---

## What's genuinely good

- The **service-interface extraction is real architecture progress**: `TNoteApplication.Create`
  now takes optional injected services, which is exactly what C3's test-isolation fix needs.
  The property getter/setter boilerplate is mechanical but faithful, and the interface
  contracts match the concrete methods 1:1.
- The **`System.DateUtils` consolidation is the right instinct** — deleting three private
  duplicate helpers (`uJsonStorage`, `uSQLiteStorage`, `uBackupService`) removes a real
  divergence risk. It just needs to be offset-aware on read (C1).
- **`TNoteManager`'s membership guard + `Extract`-before-notify in `DeleteNote`**
  (`SaveNote` refuses notes the manager no longer owns; `Touch` before persist; `PersistNote`
  as the no-Touch write-through) is careful, well-commented work that closes real
  resurrection/ordering bugs.
- **Tightening `TimeStampsEqual` from `0.001` to `1E-7`** is correct now that millisecond
  precision round-trips — but it is only safe *after* C1, because it makes the migration
  verification sensitive to exactly the format asymmetry C1 describes. Land C1 first.
- The build/test scripts self-locate the toolchain and the `%VTV_SRC%` override replaced an
  un-overridable absolute path; the test project compiles clean.
- `.gitignore` correctly keeps `*.dcu` / `*.exe` / `Win32/` out of git — the source tree is
  genuinely clean (the 5 tracked binary-ish files are all intentional resources).

---

## Suggested fix order

1. **C1** — introduce the offset-aware reader (single codec in `uIso8601`), re-point the four
   call sites, then decide on repairing already-shifted rows. Do this *before* touching any
   backup restore.
2. **C3** — inject a base path into `TNoteApplication` for tests. Without it the suite cannot
   be run safely, so nothing below can be verified.
3. **C2** — fix or require `AAppDataPath`.
4. **H1 + tolerance** — only after C1; then re-run the migration tests.
5. **H2 + H3** — finish or drop the dead interfaces; move the open/close loop back to the
   form list and rename `CloseWithoutSaving`.
6. **H5 + H7 + H6** — hygiene batch (gitignore, repo-root junk, README/ARCHITECTURE sync).
7. **H8** — split the uncommitted batch into provenance-clean commits and add the
   `DEVELOPMENT_PLAN.md` entry, per the repo's own convention.

## Where to take the product next

- **Data safety is now the bottleneck, not features.** C1/C3/H1 are all "the app can lose or
  corrupt the user's notes" class issues. A crash/telemetry path (`ILogger` is currently
  `OutputDebugString` only) and a startup integrity check (SQLite `PRAGMA quick_check`
  already exists — surface its result) would pay off more than new note features.
- **Versioned storage schema.** JSON already carries `schemaVersion: 3`; the SQLite schema
  and the timestamp format carry no version. Add one so future format changes are
  detectable rather than silently assumed.
- **Finish the DI story.** Interfaces without a composition root are half a refactor: give
  `TNoteApplication` (or a new `AppBootstrap`) exclusive ownership of construction, and let
  every consumer take an interface. That is what makes C3 and future testing cheap.
- **CI.** `build.bat` / `build_tests.bat` are already self-configuring, so a Windows GitHub
  Action that compiles and runs the suite against a temp `%APPDATA%` is a small step, and it
  is the only durable guard against another C1.
- **Then the README roadmap**: rich text / markdown, reminders, tags UI, plugins, cloud sync.
  None of those are blocked by storage anymore — SQLite is in and working.

---

## Fix log — 2026-09-17 (same day)

### C1 — offset-aware timestamp codec (fixed)

- `src/Utils/uIso8601.pas` is now the single timestamp codec. It was previously
  dead code (a naive helper referenced by neither `.dpr`):
  - `DateTimeToStoredISO8601` — local time, explicit UTC offset, millisecond
    precision. Output format is unchanged from what the working tree emitted.
  - `StoredISO8601ToDateTime` — honours an explicit offset when present, and
    otherwise treats the value as naive **local** wall-clock, which is what
    pre-2026-09-17 builds wrote.
  - `HasExplicitUtcOffset` — detects `+hh:mm`, `-hhmm` and a trailing `Z`.
- All 11 timestamp **reads** re-pointed through `StoredISO8601ToDateTime`
  (`uJsonStorage`, `uSQLiteStorage`, `uBackupService`, `uSettings`). No blind
  `ISO8601ToDate(..., False)` call remains anywhere in `src/`.
- All timestamp **writes** re-pointed through `DateTimeToStoredISO8601`, which
  also removes the two remaining duplicate private helpers (`uSQLiteStorage`,
  `uBackupService`).
- Restores the `Now` fallback for empty/NULL `created_at`/`updated_at` that the
  previous reader change had silently dropped — without it a NULL column would
  have produced `1899-12-30`.
- `uIso8601` registered in both `.dpr` files.
- `tests/Models/TNoteTimestampTests.pas` (new, 6 tests) guards the regression.
  Note for future fixtures: this repo registers tests via `initialization`
  `TDUnitX.RegisterTestFixture(...)`, not RTTI discovery — a fixture without
  that line is silently skipped by the runner.
- Verified with a probe compiled against the shipped unit: `2026-09-09T09:09:02`
  now reads back as `09:09:02`; before the fix it was `14:39:02`.

**Not fixed by C1:** values already shifted before the fix keep their inflated
value. Note 9 in the live database still reads
`2026-09-09T14:39:02.000+05:30`; the true value is recoverable from
`StickyNotes_Backup_20260909_143545.zip`. A `.000` millisecond part on a
pre-change date is a usable (not guaranteed) fingerprint for finding affected
rows.

### C3 — test isolation (fixed)

- `TNoteApplication.Create` gained an optional `ABasePath` parameter in the
  second position. Empty means resolve `%APPDATA%\StickyNotes` exactly as
  before, so the `TTrayForm` production call site is unchanged.
- `TNoteApplicationTests` now runs in a per-test temp sandbox and adds two
  regression guards: `AppDataPath` must equal the injected path, and
  `settings.ini` must be written inside the sandbox.
- `TPhase6LReadinessTests.TestProductionBackendIsJsonInNoteApplication` renamed
  to `TestProductionBackendWiringResolvesSQLiteFromSettings` (the old name said
  JSON while the assertion required SQLite) and rewritten. It no longer moves
  the live `settings.ini` / `vnotes.db` / `notes\` aside; it seeds a sandbox
  that mimics a migrated install instead.
- `.gitignore` now covers `*.db`, `*.db-journal`, `*.db-wal`, `*.db-shm`,
  `*.db.orphan.*` and `*.testbak`; the stray `tests/vnotes.db` was deleted.

### Verification (2026-09-17)

| # | Check | Result |
|---|-------|--------|
| 1 | `build.bat` (Win32 Debug, dcc32 36.0) | **PASS** — clean compile *and* link, exit 0 |
| 2 | `build_tests.bat` | **PASS** — exit 0 |
| 3 | Test suite | **PASS** — 220 found / 220 passed / 0 failed / 0 errored, **with `StickyNotes.exe` running** |
| 4 | Live `%APPDATA%` isolation | **PASS** — `settings.ini` sha256 `3BE18E4B…AE5E9` identical before and after the run; no new files in the live directory |
| 5 | Timestamp codec probe | **PASS** — 12/12 assertions against the shipped unit |

Baseline for comparison: before C3 the suite was 212 found / 211 passed / 1
errored, and the single error was only reachable with the application closed.

### Still open

C2 (`AAppDataPath` defaults to `''`), the note-9 one-off timestamp repair, H2
(three declared-but-unimplemented interfaces), H4 (26 orphaned quarantine
DBs), H6/H7 (README/ARCHITECTURE drift, repo-root junk) and H8 (commit
provenance for the pre-existing uncommitted refactor batch).
