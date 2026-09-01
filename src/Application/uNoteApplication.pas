unit uNoteApplication;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Winapi.ShlObj,
  System.IOUtils,
  uNote, uNoteManager, uSettings, uSettingsController,
  uAutosaveService, uHotkeyService, uThemeService, uBackupService,
  uStorage, uJsonStorage;

type
  TNoteApplication = class
  private
    FSettingsController: TSettingsController;
    FNoteManager: TNoteManager;
    FAutosaveService: TAutosaveService;
    FHotkeyService: THotkeyService;
    FThemeService: TThemeService;
    FBackupService: TBackupService;
    FStorage: INoteStorage;
    FAppDataPath: string;

    FOnNoteCreated: TNoteEvent;
    FOnNoteChanged: TNoteEvent;
    FOnNoteDeleted: TNoteEvent;

    function GetAppDataPath: string;
    function GetSettings: TSettings;
    procedure LoadSettings;
  public
    procedure SaveSettings;
    constructor Create(const AHandle: HWND);
    destructor Destroy; override;
    procedure Initialize;
    procedure Shutdown;

    property NoteManager: TNoteManager read FNoteManager;
    property Settings: TSettings read GetSettings;
    property ThemeService: TThemeService read FThemeService;
    property AutosaveService: TAutosaveService read FAutosaveService;
    property HotkeyService: THotkeyService read FHotkeyService;
    property BackupService: TBackupService read FBackupService;
    property AppDataPath: string read FAppDataPath;

    property OnNoteCreated: TNoteEvent read FOnNoteCreated write FOnNoteCreated;
    property OnNoteChanged: TNoteEvent read FOnNoteChanged write FOnNoteChanged;
    property OnNoteDeleted: TNoteEvent read FOnNoteDeleted write FOnNoteDeleted;
  end;

implementation

{ TNoteApplication }

constructor TNoteApplication.Create(const AHandle: HWND);
begin
  inherited Create;
  FAppDataPath := GetAppDataPath;

  FSettingsController := TSettingsController.Create(
    TPath.Combine(FAppDataPath, 'settings.ini'));

  FThemeService := TThemeService.Create;
  FAutosaveService := TAutosaveService.Create(
    FSettingsController.GetSettings.AutosaveDelay);
  FHotkeyService := THotkeyService.Create(AHandle);

  FStorage := TJsonStorage.Create(FAppDataPath);

  FNoteManager := TNoteManager.Create(FStorage);

  FBackupService := TBackupService.Create(
    FNoteManager,
    FSettingsController.GetSettings,
    TPath.Combine(FAppDataPath, 'backups'));

  FAutosaveService.OnSave := procedure(ANote: TNote)
    begin
      FNoteManager.SaveNote(ANote);
    end;
end;

destructor TNoteApplication.Destroy;
begin
  Shutdown;
  FBackupService.Free;
  FNoteManager.Free;
  FHotkeyService.Free;
  FAutosaveService.Free;
  FThemeService.Free;
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

  FNoteManager.Initialize;
end;

procedure TNoteApplication.Shutdown;
begin
  FAutosaveService.Flush;
  SaveSettings;
  FNoteManager.Finalize;
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
  FSettingsController.LoadSettings;
  FSettingsController.ApplyToApplication;
end;

procedure TNoteApplication.SaveSettings;
begin
  FSettingsController.SaveSettings;
end;

end.