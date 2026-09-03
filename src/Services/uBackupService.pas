unit uBackupService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  uNoteManager, uSettings, uILogger;

type
  TBackupProgress = procedure(const AMessage: string; AProgress: Integer) of object;
  TBackupComplete = procedure(ASuccess: Boolean; const AMessage: string) of object;

  TBackupService = class
  private
    FNoteManager: TNoteManager;
    FSettings: TSettings;
    FBackupPath: string;
    FOnProgress: TBackupProgress;
    FOnComplete: TBackupComplete;
    function GetBackupFileName: string;
    function CreateBackupZip(const AZipFile: string): Boolean;
    procedure DoRestore(const ABackupFile: string; const ALogger: ILogger);
  public
    constructor Create(ANoteManager: TNoteManager; ASettings: TSettings; const ABackupPath: string);
    destructor Destroy; override;
    procedure Backup;
    procedure Restore(const ABackupFile: string);
    procedure CleanupOldBackups;
    property OnProgress: TBackupProgress read FOnProgress write FOnProgress;
    property OnComplete: TBackupComplete read FOnComplete write FOnComplete;
  end;

implementation

uses
  System.Types, System.JSON, uNote, uEnums;

function GetRelativePath(const ABasePath, AFileName: string): string;
var
  BasePath, FilePath: string;
begin
  BasePath := IncludeTrailingPathDelimiter(ExpandFileName(ABasePath));
  FilePath := ExpandFileName(AFileName);
  if SameText(Copy(FilePath, 1, Length(BasePath)), BasePath) then
    Result := Copy(FilePath, Length(BasePath) + 1, MaxInt)
  else
    Result := FilePath;
end;

function DateTimeToISO8601(const ADateTime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', ADateTime);
end;

{ TBackupService }

constructor TBackupService.Create(ANoteManager: TNoteManager; ASettings: TSettings; const ABackupPath: string);
begin
  inherited Create;
  FNoteManager := ANoteManager;
  FSettings := ASettings;
  FBackupPath := ABackupPath;
  if not TDirectory.Exists(FBackupPath) then
    TDirectory.CreateDirectory(FBackupPath);
end;

destructor TBackupService.Destroy;
begin
  inherited;
end;

function TBackupService.GetBackupFileName: string;
var
  DateStr: string;
begin
  DateStr := FormatDateTime('yyyymmdd_hhnnss', Now);
  Result := TPath.Combine(FBackupPath, 'StickyNotes_Backup_' + DateStr + '.zip');
end;

procedure TBackupService.Backup;
var
  ZipFile: string;
  Success: Boolean;
  Logger: ILogger;
begin
  if Assigned(FOnProgress) then
    FOnProgress('Creating backup...', 0);
  
  Logger := CreateLogger;
  ZipFile := GetBackupFileName;
  Success := CreateBackupZip(ZipFile);
  
  if Success then
  begin
    // Run retention cleanup after successful backup
    CleanupOldBackups;

    if Assigned(FOnComplete) then
      FOnComplete(True, 'Backup created: ' + TPath.GetFileName(ZipFile))
  end
  else
  begin
    if Assigned(FOnComplete) then
      FOnComplete(False, 'Backup failed');
    Logger.Error('Backup: Backup failed - see CreateBackupZip for details');
  end;
end;

function TBackupService.CreateBackupZip(const AZipFile: string): Boolean;
var
  Zip: TZipFile;
  NotesPath: string;
  Files: TStringDynArray;
  FileName: string;
  RelPath: string;
  SettingsFile: string;
  Note: TNote;
  JsonText: string;
  Json: System.JSON.TJSONObject;
  TempDir: string;
  Stream: TStringStream;
  I: Integer;
begin
  Result := False;
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_Backup_' + FormatDateTime('yyyymmdd_hhnnss', Now));
  
  try
    TDirectory.CreateDirectory(TempDir);
    
    // Export notes as JSON files
    NotesPath := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesPath);
    
    if Assigned(FOnProgress) then
      FOnProgress('Exporting notes...', 20);
    
    for I := 0 to FNoteManager.NoteCount - 1 do
    begin
      Note := FNoteManager.Notes[I];
      Json := System.JSON.TJSONObject.Create;
      try
        Json.AddPair('ID', System.JSON.TJSONNumber.Create(Note.ID));
        Json.AddPair('Title', Note.Title);
        Json.AddPair('Content', Note.Content);
        Json.AddPair('Color', System.JSON.TJSONNumber.Create(Ord(Note.Color)));
        Json.AddPair('Left', System.JSON.TJSONNumber.Create(Note.Left));
        Json.AddPair('Top', System.JSON.TJSONNumber.Create(Note.Top));
        Json.AddPair('Width', System.JSON.TJSONNumber.Create(Note.Width));
        Json.AddPair('Height', System.JSON.TJSONNumber.Create(Note.Height));
        Json.AddPair('AlwaysOnTop', System.JSON.TJSONBool.Create(Note.AlwaysOnTop));
        Json.AddPair('Collapsed', System.JSON.TJSONBool.Create(Note.Collapsed));
        Json.AddPair('Locked', System.JSON.TJSONBool.Create(Note.Locked));
        Json.AddPair('CreatedAt', DateTimeToISO8601(Note.CreatedAt));
        Json.AddPair('UpdatedAt', DateTimeToISO8601(Note.UpdatedAt));
        
        JsonText := Json.Format;
        FileName := TPath.Combine(NotesPath, Format('%.10d.json', [Note.ID]));
        TFile.WriteAllText(FileName, JsonText, TEncoding.UTF8);
      finally
        Json.Free;
      end;
    end;
    
    // Export settings
    if Assigned(FOnProgress) then
      FOnProgress('Exporting settings...', 60);
    
    SettingsFile := TPath.Combine(TempDir, 'settings.ini');
    FSettings.SaveToFile(SettingsFile);
    
    // Create ZIP
    if Assigned(FOnProgress) then
      FOnProgress('Creating archive...', 80);
    
    Zip := TZipFile.Create;
    try
      Zip.Open(AZipFile, zmWrite);
      try
        Files := TDirectory.GetFiles(TempDir, '*.*', TSearchOption.soAllDirectories);
        for FileName in Files do
        begin
          RelPath := GetRelativePath(TempDir, FileName);
          Zip.Add(FileName, RelPath);
        end;
      finally
        Zip.Close;
      end;
      Result := True;
    finally
      Zip.Free;
    end;
    
    if Assigned(FOnProgress) then
      FOnProgress('Complete', 100);
    
  finally
    // Cleanup temp directory
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TBackupService.DoRestore(const ABackupFile: string; const ALogger: ILogger);
var
  Zip: TZipFile;
  TempDir: string;
  Files: TStringDynArray;
  FileName: string;
  ExtractPath: string;
  JsonText: string;
  Json: System.JSON.TJSONObject;
  Note: TNote;
  ColorInt: Integer;
  CreatedStr, UpdatedStr: string;
  SettingsFile: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_Restore_' + FormatDateTime('yyyymmdd_hhnnss', Now));
  
  TDirectory.CreateDirectory(TempDir);
  
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(ABackupFile, zmRead);
      try
        Zip.ExtractAll(TempDir);
      finally
        Zip.Close;
      end;
    finally
      Zip.Free;
    end;
    
    if Assigned(FOnProgress) then
      FOnProgress('Restoring notes...', 40);
    
    // Restore notes
    ExtractPath := TPath.Combine(TempDir, 'notes');
    if TDirectory.Exists(ExtractPath) then
    begin
      Files := TDirectory.GetFiles(ExtractPath, '*.json');
      for FileName in Files do
      begin
        try
          JsonText := TFile.ReadAllText(FileName, TEncoding.UTF8);
          Json := System.JSON.TJSONObject.ParseJSONValue(JsonText) as System.JSON.TJSONObject;
          if Json <> nil then
          try
            Note := TNote.Create;
            Note.ID := Json.GetValue<Int64>('ID', 0);
            Note.Title := Json.GetValue<string>('Title', '');
            Note.Content := Json.GetValue<string>('Content', '');
            ColorInt := Json.GetValue<Integer>('Color', Ord(ncYellow));
            Note.Color := TNoteColor(ColorInt);
            Note.Left := Json.GetValue<Integer>('Left', 100);
            Note.Top := Json.GetValue<Integer>('Top', 100);
            Note.Width := Json.GetValue<Integer>('Width', 300);
            Note.Height := Json.GetValue<Integer>('Height', 250);
            Note.AlwaysOnTop := Json.GetValue<Boolean>('AlwaysOnTop', False);
            Note.Collapsed := Json.GetValue<Boolean>('Collapsed', False);
            Note.Locked := Json.GetValue<Boolean>('Locked', False);
            CreatedStr := Json.GetValue<string>('CreatedAt', '');
            UpdatedStr := Json.GetValue<string>('UpdatedAt', '');
            if CreatedStr <> '' then
              Note.CreatedAt := ISO8601ToDate(CreatedStr)
            else
              Note.CreatedAt := Now;
            if UpdatedStr <> '' then
              Note.UpdatedAt := ISO8601ToDate(UpdatedStr)
            else
              Note.UpdatedAt := Now;
            
            if not FNoteManager.AddNote(Note) then
              Note.Free;
          finally
            Json.Free;
          end;
        except
          ALogger.Warning(Format('Restore: Corrupted JSON skipped for file %s', [ExtractFileName(FileName)]));
        end;
      end;
    end;
    
    // Restore settings
    if Assigned(FOnProgress) then
      FOnProgress('Restoring settings...', 80);
    
    SettingsFile := TPath.Combine(TempDir, 'settings.ini');
    if TFile.Exists(SettingsFile) then
      FSettings.LoadFromFile(SettingsFile);
    
    if Assigned(FOnComplete) then
      FOnComplete(True, 'Restore complete');
    
  finally
    // Cleanup
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TBackupService.Restore(const ABackupFile: string);
var
  Logger: ILogger;
begin
  if Assigned(FOnProgress) then
    FOnProgress('Extracting backup...', 0);
  
  Logger := CreateLogger;
  
  try
    DoRestore(ABackupFile, Logger);
  except
    on E: Exception do
    begin
      Logger.Error(Format('Restore: Error during restore: %s', [E.Message]));
      if Assigned(FOnComplete) then
        FOnComplete(False, 'Restore failed: ' + E.Message);
    end;
  end;
end;

procedure TBackupService.CleanupOldBackups;
var
  Logger: ILogger;
  Files: TStringDynArray;
  BackupFile: string;
  FileDate: TDateTime;
  RetentionDate: TDateTime;
  DeletedCount: Integer;
  I: Integer;
  BackupPattern: string;
begin
  Logger := CreateLogger;

  // Skip cleanup if retention is disabled (0)
  if FSettings.BackupRetentionDays <= 0 then
  begin
    Logger.Debug('Backup cleanup: Retention disabled (BackupRetentionDays = 0)');
    Exit;
  end;

  if not TDirectory.Exists(FBackupPath) then
  begin
    Logger.Debug('Backup cleanup: Backup directory does not exist');
    Exit;
  end;

  RetentionDate := Now - FSettings.BackupRetentionDays;
  DeletedCount := 0;

  // Get all files matching the backup pattern
  BackupPattern := 'StickyNotes_Backup_*.zip';
  Files := TDirectory.GetFiles(FBackupPath, BackupPattern);

  for I := 0 to High(Files) do
  begin
    BackupFile := Files[I];
    try
      // Use file modification time for determining eligibility
      FileDate := TFile.GetLastWriteTime(BackupFile);

      // Delete files older than retention date
      if FileDate < RetentionDate then
      begin
        TFile.Delete(BackupFile);
        Inc(DeletedCount);
        Logger.Info(Format('Backup cleanup: Deleted old backup %s', [ExtractFileName(BackupFile)]));
      end;
    except
      on E: Exception do
      begin
        Logger.Warning(Format('Backup cleanup: Failed to delete %s - %s',
          [ExtractFileName(BackupFile), E.Message]));
      end;
    end;
  end;

  Logger.Info(Format('Backup cleanup: Completed. Deleted %d old backups.', [DeletedCount]));
end;

end.