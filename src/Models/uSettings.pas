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
    FDarkTheme: Boolean;
    FHotkeyNewNote: string;
    FHotkeySearch: string;
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
    property DarkTheme: Boolean read FDarkTheme write FDarkTheme;
    property HotkeyNewNote: string read FHotkeyNewNote write FHotkeyNewNote;
    property HotkeySearch: string read FHotkeySearch write FHotkeySearch;
  end;

implementation

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
  FDarkTheme := False;
  FHotkeyNewNote := 'Ctrl+Alt+N';
  FHotkeySearch := 'Ctrl+Alt+F';
end;

procedure TSettings.LoadFromFile(const AFileName: string);
var
  Ini: TIniFile;
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
    FDarkTheme := Ini.ReadBool('Appearance', 'DarkTheme', FDarkTheme);
    FHotkeyNewNote := Ini.ReadString('Hotkeys', 'NewNote', FHotkeyNewNote);
    FHotkeySearch := Ini.ReadString('Hotkeys', 'Search', FHotkeySearch);
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
    Ini.WriteBool('Appearance', 'DarkTheme', FDarkTheme);
    Ini.WriteString('Hotkeys', 'NewNote', FHotkeyNewNote);
    Ini.WriteString('Hotkeys', 'Search', FHotkeySearch);
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
  FDarkTheme := Source.FDarkTheme;
  FHotkeyNewNote := Source.FHotkeyNewNote;
  FHotkeySearch := Source.FHotkeySearch;
end;

end.