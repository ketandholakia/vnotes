unit uSettings;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles,
  uEnums;

type
  TSettings = class
  private
    FAutoStart: Boolean;
    FConfirmDelete: Boolean;
    FAutosaveDelay: Integer; // milliseconds
    FDefaultColor: TNoteColor;
    FDefaultWidth: Integer;
    FDefaultHeight: Integer;
    FDefaultAlwaysOnTop: Boolean;
    FEnableHotkeys: Boolean;
    FBackupEnabled: Boolean;
    FBackupIntervalDays: Integer;
    FBackupRetentionDays: Integer;
    FDarkTheme: Boolean;
    FAutoHideToolbar: Boolean;
    FFontName: string;
    FFontSize: Integer;
    FHotkeyNewNote: string;
    FHotkeySearch: string;
    FLastBackupAt: TDateTime;
    FStorageBackend: string;
    FMigrationCompleted: Boolean;
    FMigrationTimestamp: string;
    FSyncEnabled: Boolean;
    FSyncFolder: string;
    procedure SetDefaults;
  public
    constructor Create;
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    procedure Assign(Source: TSettings);
    property AutoStart: Boolean read FAutoStart write FAutoStart;
    property ConfirmDelete: Boolean read FConfirmDelete write FConfirmDelete;
    property AutosaveDelay: Integer read FAutosaveDelay write FAutosaveDelay;
    property DefaultColor: TNoteColor read FDefaultColor write FDefaultColor;
    property DefaultWidth: Integer read FDefaultWidth write FDefaultWidth;
    property DefaultHeight: Integer read FDefaultHeight write FDefaultHeight;
    property DefaultAlwaysOnTop: Boolean read FDefaultAlwaysOnTop write FDefaultAlwaysOnTop;
    property EnableHotkeys: Boolean read FEnableHotkeys write FEnableHotkeys;
    property BackupEnabled: Boolean read FBackupEnabled write FBackupEnabled;
    property BackupIntervalDays: Integer read FBackupIntervalDays write FBackupIntervalDays;
    property BackupRetentionDays: Integer read FBackupRetentionDays write FBackupRetentionDays;
    property DarkTheme: Boolean read FDarkTheme write FDarkTheme;
    property AutoHideToolbar: Boolean read FAutoHideToolbar write FAutoHideToolbar;
    property FontName: string read FFontName write FFontName;
    property FontSize: Integer read FFontSize write FFontSize;
    property HotkeyNewNote: string read FHotkeyNewNote write FHotkeyNewNote;
    property HotkeySearch: string read FHotkeySearch write FHotkeySearch;
    property LastBackupAt: TDateTime read FLastBackupAt write FLastBackupAt;
    property StorageBackend: string read FStorageBackend write FStorageBackend;
    property MigrationCompleted: Boolean read FMigrationCompleted write FMigrationCompleted;
    property MigrationTimestamp: string read FMigrationTimestamp write FMigrationTimestamp;
    // Phase 7B: cloud/file sync (folder backend). Empty folder = not configured.
    property SyncEnabled: Boolean read FSyncEnabled write FSyncEnabled;
    property SyncFolder: string read FSyncFolder write FSyncFolder;
  end;

implementation

uses
  System.DateUtils, uILogger, uIso8601;

{ TSettings }

constructor TSettings.Create;
begin
  inherited;
  SetDefaults;
end;

procedure TSettings.SetDefaults;
begin
  FAutoStart := False;
  FConfirmDelete := True;
  FAutosaveDelay := 1000; // 1 second
  FDefaultColor := ncYellow;
  FDefaultWidth := 300;
  FDefaultHeight := 250;
  FDefaultAlwaysOnTop := False;
  FEnableHotkeys := True;
  FBackupEnabled := True;
  FBackupIntervalDays := 1;
  FBackupRetentionDays := 30;
  FDarkTheme := False;
  FAutoHideToolbar := False;
  FFontName := 'Segoe UI';
  FFontSize := 10;
  FHotkeyNewNote := 'Ctrl+Alt+N';
  FHotkeySearch := 'Ctrl+Alt+F';
  FLastBackupAt := 0;
  FStorageBackend := 'JSON';
  FMigrationCompleted := False;
  FMigrationTimestamp := '';
  FSyncEnabled := False;
  FSyncFolder := '';
end;

procedure TSettings.LoadFromFile(const AFileName: string);
var
  Ini: TIniFile;
  LastBackupStr: string;
  Logger: ILogger;
begin
  SetDefaults;
  if not FileExists(AFileName) then Exit;
  Ini := TIniFile.Create(AFileName);
  try
    FAutoStart := Ini.ReadBool('General', 'AutoStart', FAutoStart);
    FConfirmDelete := Ini.ReadBool('General', 'ConfirmDelete', FConfirmDelete);
    FAutosaveDelay := Ini.ReadInteger('General', 'AutosaveDelay', FAutosaveDelay);
    FDefaultColor := TNoteColor(Ini.ReadInteger('General', 'DefaultColor', Ord(FDefaultColor)));
    FDefaultWidth := Ini.ReadInteger('General', 'DefaultWidth', FDefaultWidth);
    FDefaultHeight := Ini.ReadInteger('General', 'DefaultHeight', FDefaultHeight);
    FDefaultAlwaysOnTop := Ini.ReadBool('General', 'DefaultAlwaysOnTop', FDefaultAlwaysOnTop);
    FEnableHotkeys := Ini.ReadBool('General', 'EnableHotkeys', FEnableHotkeys);
    FBackupEnabled := Ini.ReadBool('Backup', 'Enabled', FBackupEnabled);
    FBackupIntervalDays := Ini.ReadInteger('Backup', 'IntervalDays', FBackupIntervalDays);
    FBackupRetentionDays := Ini.ReadInteger('Backup', 'RetentionDays', FBackupRetentionDays);
    FDarkTheme := Ini.ReadBool('Appearance', 'DarkTheme', FDarkTheme);
    FAutoHideToolbar := Ini.ReadBool('Appearance', 'AutoHideToolbar', FAutoHideToolbar);
    FFontName := Ini.ReadString('Appearance', 'FontName', FFontName);
    FFontSize := Ini.ReadInteger('Appearance', 'FontSize', FFontSize);
    FHotkeyNewNote := Ini.ReadString('Hotkeys', 'NewNote', FHotkeyNewNote);
    FHotkeySearch := Ini.ReadString('Hotkeys', 'Search', FHotkeySearch);

    FStorageBackend := Ini.ReadString('Storage', 'Backend', FStorageBackend);
    FMigrationCompleted := Ini.ReadBool('Storage', 'MigrationCompleted', FMigrationCompleted);
    FMigrationTimestamp := Ini.ReadString('Storage', 'MigrationTimestamp', FMigrationTimestamp);

    FSyncEnabled := Ini.ReadBool('Sync', 'Enabled', FSyncEnabled);
    FSyncFolder := Ini.ReadString('Sync', 'Folder', FSyncFolder);

    LastBackupStr := Ini.ReadString('Backup', 'LastBackupAt', '');
    // Tolerant read: accepts the current offset-bearing format and the legacy
    // offset-less one (CODE_REVIEW_2026-09-17 C1). 0 keeps the previous
    // "never backed up" behaviour for empty or unparseable values.
    FLastBackupAt := StoredISO8601ToDateTime(LastBackupStr, 0);
    if (LastBackupStr <> '') and (FLastBackupAt <= 0) then
    begin
      Logger := CreateLogger;
      Logger.Warning('Settings: Failed to parse LastBackupAt timestamp "' + LastBackupStr + '"');
    end;
  finally
    Ini.Free;
  end;
end;

procedure TSettings.SaveToFile(const AFileName: string);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(AFileName);
  try
    Ini.WriteBool('General', 'AutoStart', FAutoStart);
    Ini.WriteBool('General', 'ConfirmDelete', FConfirmDelete);
    Ini.WriteInteger('General', 'AutosaveDelay', FAutosaveDelay);
    Ini.WriteInteger('General', 'DefaultColor', Ord(FDefaultColor));
    Ini.WriteInteger('General', 'DefaultWidth', FDefaultWidth);
    Ini.WriteInteger('General', 'DefaultHeight', FDefaultHeight);
    Ini.WriteBool('General', 'DefaultAlwaysOnTop', FDefaultAlwaysOnTop);
    Ini.WriteBool('General', 'EnableHotkeys', FEnableHotkeys);
    Ini.WriteBool('Backup', 'Enabled', FBackupEnabled);
    Ini.WriteInteger('Backup', 'IntervalDays', FBackupIntervalDays);
    Ini.WriteInteger('Backup', 'RetentionDays', FBackupRetentionDays);
    if FLastBackupAt > 0 then
      Ini.WriteString('Backup', 'LastBackupAt', DateTimeToStoredISO8601(FLastBackupAt))
    else
      Ini.WriteString('Backup', 'LastBackupAt', '');
    Ini.WriteBool('Appearance', 'DarkTheme', FDarkTheme);
    Ini.WriteBool('Appearance', 'AutoHideToolbar', FAutoHideToolbar);
    Ini.WriteString('Appearance', 'FontName', FFontName);
    Ini.WriteInteger('Appearance', 'FontSize', FFontSize);
    Ini.WriteString('Hotkeys', 'NewNote', FHotkeyNewNote);
    Ini.WriteString('Hotkeys', 'Search', FHotkeySearch);

    Ini.WriteString('Storage', 'Backend', FStorageBackend);
    Ini.WriteBool('Storage', 'MigrationCompleted', FMigrationCompleted);
    Ini.WriteString('Storage', 'MigrationTimestamp', FMigrationTimestamp);
    Ini.WriteBool('Sync', 'Enabled', FSyncEnabled);
    Ini.WriteString('Sync', 'Folder', FSyncFolder);
  finally
    Ini.Free;
  end;
end;

procedure TSettings.Assign(Source: TSettings);
begin
  if Source = nil then Exit;
  FAutoStart := Source.FAutoStart;
  FConfirmDelete := Source.FConfirmDelete;
  FAutosaveDelay := Source.FAutosaveDelay;
  FDefaultColor := Source.FDefaultColor;
  FDefaultWidth := Source.FDefaultWidth;
  FDefaultHeight := Source.FDefaultHeight;
  FDefaultAlwaysOnTop := Source.FDefaultAlwaysOnTop;
  FEnableHotkeys := Source.FEnableHotkeys;
  FBackupEnabled := Source.FBackupEnabled;
  FBackupIntervalDays := Source.FBackupIntervalDays;
  FBackupRetentionDays := Source.FBackupRetentionDays;
  FDarkTheme := Source.FDarkTheme;
  FAutoHideToolbar := Source.FAutoHideToolbar;
  FFontName := Source.FFontName;
  FFontSize := Source.FFontSize;
  FHotkeyNewNote := Source.FHotkeyNewNote;
  FHotkeySearch := Source.FHotkeySearch;
  FLastBackupAt := Source.FLastBackupAt;
  FStorageBackend := Source.FStorageBackend;
  FMigrationCompleted := Source.FMigrationCompleted;
  FMigrationTimestamp := Source.FMigrationTimestamp;
  FSyncEnabled := Source.FSyncEnabled;
  FSyncFolder := Source.FSyncFolder;
end;

end.