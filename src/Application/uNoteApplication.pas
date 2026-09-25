unit uNoteApplication;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Winapi.ShlObj,
  System.IOUtils,
  uNote, uNoteManager, uSettings, uSettingsController,
  uAutosaveService, uHotkeyService, uThemeService, uBackupService,
  uBackupScheduler, uServiceInterfaces,
  uStorage, uJsonStorage, uStorageResolver, uStorageMigrationOrchestrator,
  uILogger;

type
  TNoteApplication = class
  private
    FSettingsController: TSettingsController;
    FNoteManager: TNoteManager;
    FAutosaveService: IAutosaveService;
    FHotkeyService: IHotkeyService;
    FThemeService: IThemeService;
    FBackupService: IBackupService;
    FBackupScheduler: IBackupScheduler;
    FStorage: INoteStorage;
    FAppDataPath: string;

    FOnNoteCreated: TNoteEvent;
    FOnNoteChanged: TNoteEvent;
    FOnNoteDeleted: TNoteEvent;
    FOnNoteOpenRequested: TNoteEvent;
    FOnNoteCloseRequested: TNoteEvent;

    function GetAppDataPath: string;
    function GetSettings: TSettings;
    procedure LoadSettings;
  public
    procedure SaveSettings;
    // ABasePath is an isolation seam: supply an explicit directory to keep the
    // instance away from the user's live %APPDATA%\StickyNotes (tests use it),
    // otherwise the production path is resolved as before.
    constructor Create(const AHandle: HWND;
      const ABasePath: string = '';
      const AAutosaveService: IAutosaveService = nil;
      const AHotkeyService: IHotkeyService = nil;
      const AThemeService: IThemeService = nil;
      const ABackupService: IBackupService = nil;
      const ABackupScheduler: IBackupScheduler = nil);
    destructor Destroy; override;
    procedure Initialize;
    procedure Shutdown;
    // Refresh the periodic backup schedule from current settings.
    // Called by the tray form after the user OKs new settings.
    procedure RefreshBackupSchedule;
    // Request to open/close all note windows - fires OnNoteOpenRequested/OnNoteCloseRequested events
    procedure RequestOpenAllNotes;
    procedure RequestCloseAllNotes;

    property NoteManager: TNoteManager read FNoteManager;
    property Settings: TSettings read GetSettings;
    property ThemeService: IThemeService read FThemeService;
    property AutosaveService: IAutosaveService read FAutosaveService;
    property HotkeyService: IHotkeyService read FHotkeyService;
    property BackupService: IBackupService read FBackupService;
    property BackupScheduler: IBackupScheduler read FBackupScheduler;
    property AppDataPath: string read FAppDataPath;

    property OnNoteCreated: TNoteEvent read FOnNoteCreated write FOnNoteCreated;
    property OnNoteChanged: TNoteEvent read FOnNoteChanged write FOnNoteChanged;
    property OnNoteDeleted: TNoteEvent read FOnNoteDeleted write FOnNoteDeleted;
    property OnNoteOpenRequested: TNoteEvent read FOnNoteOpenRequested write FOnNoteOpenRequested;
    property OnNoteCloseRequested: TNoteEvent read FOnNoteCloseRequested write FOnNoteCloseRequested;
  end;

implementation

{ TNoteApplication }

constructor TNoteApplication.Create(const AHandle: HWND;
  const ABasePath: string = '';
  const AAutosaveService: IAutosaveService = nil;
  const AHotkeyService: IHotkeyService = nil;
  const AThemeService: IThemeService = nil;
  const ABackupService: IBackupService = nil;
  const ABackupScheduler: IBackupScheduler = nil);
var
  SettingsIniPath: string;
  AutosaveDelay: Integer;
  BackupPath: string;
  ActualBackupService: IBackupService;
  ActualBackupScheduler: IBackupScheduler;
  ActualAutosaveService: IAutosaveService;
  ActualThemeService: IThemeService;
  ActualHotkeyService: IHotkeyService;
begin
  inherited Create;

  if ABasePath <> '' then
  begin
    // Explicit isolation seam (CODE_REVIEW_2026-09-17 C3): when the caller
    // supplies a base path, never resolve the live user profile.
    FAppDataPath := ABasePath;
    if not TDirectory.Exists(FAppDataPath) then
      TDirectory.CreateDirectory(FAppDataPath);
  end
  else
    FAppDataPath := GetAppDataPath;

  // Route diagnostics to a file so crash / telemetry output is actually
  // captured (ILogger otherwise only writes to OutputDebugString).
  ConfigureLogFile(TPath.Combine(FAppDataPath, 'vnotes.log'));

  SettingsIniPath := TPath.Combine(FAppDataPath, 'settings.ini');
  FSettingsController := TSettingsController.Create(SettingsIniPath);
  FSettingsController.LoadSettings;

  AutosaveDelay := FSettingsController.GetSettings.AutosaveDelay;

  // Create default service implementations if not injected
  if AAutosaveService = nil then
    ActualAutosaveService := TAutosaveService.Create(AutosaveDelay)
  else
    ActualAutosaveService := AAutosaveService;

  if AHotkeyService = nil then
    ActualHotkeyService := THotkeyService.Create(AHandle)
  else
    ActualHotkeyService := AHotkeyService;

  if AThemeService = nil then
    ActualThemeService := TThemeService.Create
  else
    ActualThemeService := AThemeService;

  TStorageMigrationOrchestrator.OrchestrateStorage(FAppDataPath, FSettingsController.GetSettings, SettingsIniPath);
  FStorage := TStorageResolver.ResolveStorage(FAppDataPath, FSettingsController.GetSettings);

  FNoteManager := TNoteManager.Create(FStorage);

  BackupPath := TPath.Combine(FAppDataPath, 'backups');

  if ABackupService = nil then
    ActualBackupService := TBackupService.Create(
      FNoteManager,
      FSettingsController.GetSettings,
      BackupPath,
      FAppDataPath)
  else
    ActualBackupService := ABackupService;

  if ABackupScheduler = nil then
    ActualBackupScheduler := TBackupScheduler.Create(
      ActualBackupService,
      FSettingsController.GetSettings)
  else
    ActualBackupScheduler := ABackupScheduler;

  FAutosaveService := ActualAutosaveService;
  FHotkeyService := ActualHotkeyService;
  FThemeService := ActualThemeService;
  FBackupService := ActualBackupService;
  FBackupScheduler := ActualBackupScheduler;

  FAutosaveService.OnSave := procedure(ANote: TNote)
    begin
      FNoteManager.SaveNote(ANote);
    end;
end;

destructor TNoteApplication.Destroy;
begin
  Shutdown;
  FBackupScheduler := nil;
  FBackupService := nil;
  FNoteManager.Free;
  FHotkeyService := nil;
  FAutosaveService := nil;
  FThemeService := nil;
  FSettingsController.Free;
  inherited;
end;

procedure TNoteApplication.Initialize;
begin
  LoadSettings;
  FThemeService.SetDarkTheme(FSettingsController.GetSettings.DarkTheme);

  FNoteManager.OnNoteCreated := FOnNoteCreated;
  FNoteManager.OnNoteChanged := FOnNoteChanged;
  FNoteManager.OnNoteDeleted := FOnNoteDeleted;
  FNoteManager.OnNoteOpenRequested := FOnNoteOpenRequested;
  FNoteManager.OnNoteCloseRequested := FOnNoteCloseRequested;

  FNoteManager.Initialize;

  // Phase 4C: arm the periodic backup schedule with the loaded settings.
  if FBackupScheduler <> nil then
    FBackupScheduler.Start;
end;

procedure TNoteApplication.Shutdown;
begin
  // Every field is guarded: if the constructor raised partway through
  // (e.g. storage migration failure), Destroy still runs Shutdown, and an
  // unguarded call here crashed with an AV that masked the original error.
  if FBackupScheduler <> nil then
    FBackupScheduler.Stop;
  if FAutosaveService <> nil then
    FAutosaveService.Flush;
  SaveSettings;
  if FNoteManager <> nil then
    FNoteManager.Finalize;
end;

procedure TNoteApplication.RefreshBackupSchedule;
begin
  if FBackupScheduler <> nil then
    FBackupScheduler.Refresh;
end;

procedure TNoteApplication.RequestOpenAllNotes;
begin
  if FNoteManager <> nil then
    FNoteManager.RequestOpenAllNotes;
end;

procedure TNoteApplication.RequestCloseAllNotes;
begin
  if FNoteManager <> nil then
    FNoteManager.RequestCloseAllNotes;
end;

function TNoteApplication.GetAppDataPath: string;
var
  Path: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, CSIDL_APPDATA, 0, SHGFP_TYPE_CURRENT, @Path[0]) = S_OK then
    Result := TPath.Combine(Path, 'StickyNotes')
  else
    Result := TPath.Combine(TPath.GetTempPath, 'StickyNotes');

  if not TDirectory.Exists(Result) then
    TDirectory.CreateDirectory(Result);
end;

function TNoteApplication.GetSettings: TSettings;
begin
  Result := FSettingsController.GetSettings;
end;

procedure TNoteApplication.LoadSettings;
begin
  if FSettingsController = nil then Exit;
  FSettingsController.LoadSettings;
  FSettingsController.ApplyToApplication;
end;

procedure TNoteApplication.SaveSettings;
begin
  if FSettingsController = nil then Exit;
  FSettingsController.SaveSettings;
end;

end.