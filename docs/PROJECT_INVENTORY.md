# StickyNotes – Project Inventory

> Generated automatically from the source tree (`.dpr`, `.dproj`, unit sources) on **2026‑08‑31**.

---

## 1. Project Files

| File | Path | Notes |
|------|------|-------|
| **StickyNotes.dpr** | `src\StickyNotes.dpr` | Main program entry point. |
| **StickyNotes.dproj** | `src\StickyNotes.dproj` | MSBuild project (Delphi / RAD Studio). |
| **\*.groupproj** | *none* | No project group file present. |

---

## 2. Compiler / Tool‑chain Information

| Item | Value |
|------|-------|
| **ProjectVersion (from .dproj)** | `17.0`  → RAD Studio 10.3 Rio (Delphi 27). |
| **Target Platform** | `Win32` (only). |
| **Build Configurations** | `Debug` • `Release` |
| **Debug Output Directories** | `.\Win32\Debug` (EXE, DCUs, packages) |
| **Release Output Directories** | `.\Win32\Release` (EXE, DCUs, packages) |
| **rsvars.bat locations** | `C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat`  <br> `C:\Program Files (x86)\Embarcadero\Studio\23.0\Bin\rsvars.bat` |
| **MSBuild Targets Import** | `$(BDS)\Bin\CodeGear.Delphi.Targets` (standard Delphi targets). |

---
## 3. Unit Catalogue (one‑line responsibility & classification)

| Unit (file) | Responsibility (≈1 line) | Classification | VCL Form? |
|-------------|--------------------------|----------------|-----------|
| `Forms\uTrayForm.pas` | Hidden tray‑icon host; creates services, storage, note manager, and spawns note windows. | **form** | ✅ |
| `Forms\uNoteForm.pas` | Borderless sticky‑note window (title, content, colour, pin, collapse, lock). | **form** | ✅ |
| `Forms\uSettingsForm.pas` | Modal dialog for all user preferences (autosave, hot‑keys, theme, backup, autostart). | **form** | ✅ |
| `Forms\uAboutForm.pas` | Simple “About” dialog with version / licence info. | **form** | ✅ |
| `Models\uNote.pas` | `TNote` entity – properties, cloning, bounds, timestamps, colour conversion. | **model** | |
| `Models\uSettings.pas` | `TSettings` – INI‑file persisted user options (autostart, theme, hot‑keys, backup, defaults). | **model** | |
| `Models\uEnums.pas` | Enumerations (`TNoteColor`, `TStorageType`) + colour‑name/value helpers. | **model** | |
| `Controllers\uNoteManager.pas` | Central note repository – load/save/create/delete, fires events, owns `INoteStorage`. | **logic / controller** | |
| `Controllers\uTrayController.pas` | Independent tray‑icon/menu component (not used by default UI). | **logic / controller** | |
| `Controllers\uSettingsController.pas` | Loads/saves `TSettings` from `settings.ini`; applies theme & autostart. | **logic / controller** | |
| `Storage\uStorage.pas` | `INoteStorage` interface + `TStorageFactory` (JSON / SQLite selector). | **storage (interface)** | |
| `Storage\uJsonStorage.pas` | JSON file‑per‑note implementation ( `%APPDATA%\StickyNotes\notes\####.json` ). | **storage** | |
| `Storage\uSQLiteStorage.pas` | Stub SQLite implementation (not functional). | **storage** | |
| `Services\uAutosaveService.pas` | Debounced timer that forwards a pending note to `OnSave` callback. | **service / logic** | |
| `Services\uHotkeyService.pas` | Registers/unregisters global hot‑keys (Ctrl+Alt+N, Ctrl+Alt+F …) via `RegisterHotKey`. | **service** | |
| `Services\uStartupService.pas` | Reads/writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` for autostart. | **service** | |
| `Services\uThemeService.pas` | Supplies colour palettes for light/dark themes and switches VCL styles. | **service** | |
| `Services\uBackupService.pas` | Zips `notes\*.json` + `settings.ini` into timestamped `.zip` under `backups\`; restores from zip. | **service / storage** | |
| `Utils\uWindowUtils.pas` | Borderless‑window hit‑test, resize‑border, drag‑helper for note forms. | **utils** | |
| `Utils\uJsonUtils.pas` | Thin wrappers around `System.JSON` for load/save/path queries. | **utils** | |
| `Utils\uIso8601.pas` | `DateTimeToISO8601` helper (used by JSON storage). | **utils** | |
| `Utils\uColorUtils.pas` | Lighten/darken, contrast, hex↔color, blend, brightness, complementary helpers. | **utils** | |
| `Utils\uMonitorUtils.pas` | Multi‑monitor geometry helpers (constrain, center, work‑area). | **utils** | |

> **Untestable units** – the four VCL form units (`uTrayForm`, `uNoteForm`, `uSettingsForm`, `uAboutForm`) are flagged ✅ above; they require a UI test harness.
---

## 4. Rough **uses** Dependency Map  

```
StickyNotes.dpr
 ├─ Vcl.Forms, Vcl.Themes, Vcl.Styles, Winapi.Windows, System.SysUtils
 ├─ Forms\uTrayForm
 │    ├─ uNote, uNoteManager, uSettings, uTrayController, uSettingsController
 │    ├─ uAutosaveService, uHotkeyService, uThemeService, uBackupService
 │    ├─ uStorage, uNoteForm
 │    └─ (implementation) uSettingsForm, uAboutForm, uJsonStorage, System.IOUtils
 ├─ Forms\uNoteForm
 │    ├─ uNote, uAutosaveService, uThemeService, uSettings, uWindowUtils
 │    └─ (dfm) VCL controls
 ├─ Forms\uSettingsForm
 │    ├─ uSettings, uThemeService, uHotkeyService, uStartupService
 │    └─ (dfm) VCL controls
 ├─ Forms\uAboutForm
 │    └─ (dfm) VCL controls
 ├─ Models\uNote ← uEnums
 ├─ Models\uSettings ← uEnums
 ├─ Models\uEnums
 ├─ Controllers\uNoteManager ← uNote, uStorage, uEnums
 ├─ Controllers\uTrayController ← uNoteManager, uSettings
 ├─ Controllers\uSettingsController ← uSettings, uStartupService, Vcl.Themes
 ├─ Storage\uStorage ← uNote
 │    └─ (implementation) uJsonStorage, uSQLiteStorage
 ├─ Storage\uJsonStorage ← uStorage, uNote, uEnums, System.IOUtils, System.JSON
 ├─ Storage\uSQLiteStorage ← uStorage, uNote, System.IOUtils
 ├─ Services\uAutosaveService ← uNote
 ├─ Services\uHotkeyService ← uSettings
 ├─ Services\uStartupService ← Winapi.ShlObj, Winapi.KnownFolders, System.Win.Registry
 ├─ Services\uThemeService ← uEnums, Vcl.Themes
 ├─ Services\uBackupService ← uNoteManager, uSettings, uNote, uEnums, System.Zip, System.IOUtils
 ├─ Utils\uWindowUtils ← Winapi.*, Vcl.Forms, Vcl.Controls, Vcl.Graphics
 ├─ Utils\uJsonUtils ← System.JSON, System.IOUtils
 ├─ Utils\uIso8601 ← System.DateUtils
 ├─ Utils\uColorUtils ← uEnums, Vcl.Graphics, Winapi.Windows
 └─ Utils\uMonitorUtils ← Winapi.Windows, Vcl.Forms
```

*Arrows point from the **consumer** to the **provider** (i.e. “uses”).  The graph is intentionally coarse – it captures the architectural layers (Forms → Controllers/Services → Models/Storage/Utils).*
---

## 5. Persistence Layer – Where Note JSON Files Live  

| Aspect | Detail |
|--------|--------|
| **Base directory resolution** | `TTrayForm.GetAppDataPath` (in `uTrayForm.pas`) calls `SHGetFolderPath(CSIDL_APPDATA)` → `%APPDATA%\StickyNotes`. Fallback to `%TEMP%\StickyNotes`. |
| **Notes folder** | `<BasePath>\notes\` – created by `TJsonStorage.EnsureDirectories`. |
| **Note file naming** | `<BasePath>\notes\`**`%.10d.json`** (zero‑padded 10‑digit numeric ID, e.g. `0000000001.json`). |
| **Settings file** | `<BasePath>\settings.ini` (handled by `TSettingsController` → `TSettings.LoadFromFile/SaveToFile`). |
| **Backup folder** | `<BasePath>\backups\` – created by `TBackupService` constructor. |
| **Backup file naming** | `StickyNotes_Backup_YYYYMMDD_HHMMSS.zip` (timestamped). |
| **Backup contents** | `notes\*.json` + `settings.ini` (zipped via `System.Zip.TZipFile`). |
| **Restore** | Unzips to a temporary folder, re‑imports each JSON via `TNoteManager.AddNote`, then loads `settings.ini` into `TSettings`. |
| **Hard‑coded paths** | None – everything derived from `SHGetFolderPath(CSIDL_APPDATA)` / `TPath.GetTempPath`. |
---

## 6. Tool‑chain Verification  

| Path | Exists? |
|------|---------|
| `C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat` | ✅ |
| `C:\Program Files (x86)\Embarcadero\Studio\23.0\Bin\rsvars.bat` | ✅ |

Both RAD Studio 10.4 (21.0) and 11 Alexandria (23.0) are installed; the project’s `ProjectVersion = 17.0` matches the 10.3 Rio toolset, but either `rsvars.bat` can be used to set up the environment.

---

## 7. Quick‑Start Build Commands (for reference)

```bat
REM Choose the desired RAD Studio version
call "C:\Program Files (x86)\Embarcadero\Studio\21.0\Bin\rsvars.bat"
REM or
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\Bin\rsvars.bat"

msbuild src\StickyNotes.dproj /p:Config=Release /p:Platform=Win32
```

Output EXE will appear under `src\Win32\Release\StickyNotes.exe`.

---

*End of inventory.*