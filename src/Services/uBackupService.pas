unit uBackupService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  System.Generics.Collections,
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
    procedure CreateManifest(const ATempDir: string; const ALogger: ILogger);
    function ValidateBackupStructure(const ATempDir: string; const ALogger: ILogger): Boolean;
    function CreatePreRestoreBackup(const ALogger: ILogger): string;
    function ValidateRestoredSettings(const ALogger: ILogger): Boolean;
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
  Logger: ILogger;
begin
  Result := False;
  Logger := CreateLogger;
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

    // Create manifest with version info
    if Assigned(FOnProgress) then
      FOnProgress('Creating manifest...', 70);

    CreateManifest(TempDir, Logger);

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
  PreRestoreBackup: string;
  RestoredNotes: TObjectList<TNote>;
  I: Integer;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_Restore_' + FormatDateTime('yyyymmdd_hhnnss', Now));
  PreRestoreBackup := '';
  RestoredNotes := TObjectList<TNote>.Create;

  try
    if not TFile.Exists(ABackupFile) then
    begin
      ALogger.Error(Format('Restore: Backup file not found: %s', [ABackupFile]));
      if Assigned(FOnComplete) then
        FOnComplete(False, 'Backup file not found');
      Exit;
    end;

    // Create pre-restore backup first (before any changes)
    PreRestoreBackup := CreatePreRestoreBackup(ALogger);

    TDirectory.CreateDirectory(TempDir);

    // Extract and validate backup structure atomically in temp directory
    if Assigned(FOnProgress) then
      FOnProgress('Extracting backup...', 10);

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
    except
      on E: Exception do
      begin
        ALogger.Error(Format('Restore: Failed to extract backup archive: %s', [E.Message]));
        if Assigned(FOnComplete) then
          FOnComplete(False, 'Failed to extract backup: ' + E.Message);
        Exit;
      end;
    end;

    // Validate backup structure before attempting restore
    if not ValidateBackupStructure(TempDir, ALogger) then
    begin
      ALogger.Error('Restore: Backup structure validation failed');
      if Assigned(FOnComplete) then
        FOnComplete(False, 'Backup format is incompatible');
      Exit;
    end;

    if Assigned(FOnProgress) then
      FOnProgress('Validating backup contents...', 25);

    // Phase 1: Load all notes from backup to temp list (validate all before applying)
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

            RestoredNotes.Add(Note);
          finally
            Json.Free;
          end;
        except
          on E: Exception do
          begin
            ALogger.Warning(Format('Restore: Corrupted JSON skipped for file %s: %s',
              [ExtractFileName(FileName), E.Message]));
            // Continue reading other files
          end;
        end;
      end;
    end;

    // Phase 2: Clear existing notes and restore from validated temp list
    if Assigned(FOnProgress) then
      FOnProgress('Restoring notes...', 40);

    // Delete all existing notes to make room for restored ones
    for I := FNoteManager.NoteCount - 1 downto 0 do
    begin
      Note := FNoteManager.Notes[I];
      if Note <> nil then
        FNoteManager.DeleteNote(Note.ID);
    end;

    // Add restored notes
    for I := 0 to RestoredNotes.Count - 1 do
    begin
      Note := RestoredNotes[I];
      if not FNoteManager.AddNote(Note) then
      begin
        ALogger.Warning(Format('Restore: Failed to add note ID %d', [Note.ID]));
        Note.Free;
      end;
    end;

    // Phase 3: Restore settings (optional, non-fatal if missing or corrupted)
    if Assigned(FOnProgress) then
      FOnProgress('Restoring settings...', 80);

    SettingsFile := TPath.Combine(TempDir, 'settings.ini');
    if TFile.Exists(SettingsFile) then
    begin
      try
        FSettings.LoadFromFile(SettingsFile);
        if not ValidateRestoredSettings(ALogger) then
        begin
          ALogger.Warning('Restore: Settings validation raised concerns, but restore continues');
        end;
      except
        on E: Exception do
        begin
          ALogger.Warning(Format('Restore: Failed to restore settings: %s - continuing without settings',
            [E.Message]));
        end;
      end;
    end
    else
    begin
      ALogger.Warning('Restore: settings.ini not found in backup - settings not restored');
    end;

    if Assigned(FOnComplete) then
      FOnComplete(True, 'Restore complete');

    ALogger.Info(Format('Restore: Successfully restored %d notes', [RestoredNotes.Count]));

  finally
    // Cleanup
    RestoredNotes.Free;
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

procedure TBackupService.CreateManifest(const ATempDir: string; const ALogger: ILogger);
var
  ManifestFile: string;
  ManifestJson: System.JSON.TJSONObject;
  ManifestText: string;
begin
  ManifestFile := TPath.Combine(ATempDir, 'manifest.json');
  ManifestJson := System.JSON.TJSONObject.Create;
  try
    ManifestJson.AddPair('version', System.JSON.TJSONNumber.Create(1));
    ManifestJson.AddPair('createdAt', DateTimeToISO8601(Now));
    ManifestJson.AddPair('applicationVersion', '5B');

    ManifestText := ManifestJson.Format;
    TFile.WriteAllText(ManifestFile, ManifestText, TEncoding.UTF8);
    ALogger.Debug('Backup: Manifest created with version 1');
  finally
    ManifestJson.Free;
  end;
end;

function TBackupService.ValidateBackupStructure(const ATempDir: string; const ALogger: ILogger): Boolean;
var
  NotesDir: string;
  SettingsFile: string;
  ManifestFile: string;
  ManifestJson: System.JSON.TJSONObject;
  ManifestText: string;
  ManifestVersion: Integer;
begin
  Result := True;

  // Check for manifest
  ManifestFile := TPath.Combine(ATempDir, 'manifest.json');
  if not TFile.Exists(ManifestFile) then
  begin
    ALogger.Warning('Backup: manifest.json not found - backup may be from older version');
    // Old backups without manifest are still accepted for backward compatibility
  end
  else
  begin
    try
      ManifestText := TFile.ReadAllText(ManifestFile, TEncoding.UTF8);
      ManifestJson := System.JSON.TJSONObject.ParseJSONValue(ManifestText) as System.JSON.TJSONObject;
      if ManifestJson <> nil then
      try
        ManifestVersion := ManifestJson.GetValue<Integer>('version', 0);
        if ManifestVersion > 1 then
        begin
          ALogger.Error(Format('Backup: Incompatible version %d (current is 1)', [ManifestVersion]));
          Result := False;
          Exit;
        end;
        ALogger.Debug(Format('Backup: Manifest version %d validated', [ManifestVersion]));
      finally
        ManifestJson.Free;
      end;
    except
      on E: Exception do
      begin
        ALogger.Warning(Format('Backup: Failed to read manifest: %s', [E.Message]));
        // Non-fatal - continue with restore
      end;
    end;
  end;

  // Check for notes directory
  NotesDir := TPath.Combine(ATempDir, 'notes');
  if not TDirectory.Exists(NotesDir) then
  begin
    ALogger.Warning('Backup: notes directory not found - backup may be incomplete');
    // Notes directory may be empty if no notes were backed up, so this is warning only
  end;

  // Settings file is optional, but warn if missing
  SettingsFile := TPath.Combine(ATempDir, 'settings.ini');
  if not TFile.Exists(SettingsFile) then
  begin
    ALogger.Warning('Backup: settings.ini not found - settings will not be restored');
  end;
end;

function TBackupService.CreatePreRestoreBackup(const ALogger: ILogger): string;
var
  PreRestoreFile: string;
  Success: Boolean;
begin
  Result := '';

  if FNoteManager.NoteCount = 0 then
  begin
    ALogger.Debug('Restore: No notes to back up before restore');
    Exit;
  end;

  PreRestoreFile := TPath.Combine(FBackupPath, 'pre_restore_backup_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.zip');

  if Assigned(FOnProgress) then
    FOnProgress('Creating pre-restore backup...', 5);

  Success := CreateBackupZip(PreRestoreFile);

  if Success and TFile.Exists(PreRestoreFile) then
  begin
    Result := PreRestoreFile;
    ALogger.Info(Format('Restore: Pre-restore backup created: %s', [ExtractFileName(PreRestoreFile)]));
  end
  else
  begin
    ALogger.Warning('Restore: Failed to create pre-restore backup');
    Result := '';
  end;
end;

function TBackupService.ValidateRestoredSettings(const ALogger: ILogger): Boolean;
begin
  // Validate that essential settings are reasonable
  Result := True;

  // Settings can be in any valid state - there's no "invalid" value for text settings
  // This is mostly a hook for future validation logic if needed
  ALogger.Debug('Restore: Settings validation passed');
end;

end.
