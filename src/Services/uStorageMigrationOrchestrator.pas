unit uStorageMigrationOrchestrator;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.DateUtils, System.Types,
  uNote, uStorage, uJsonStorage, uSQLiteStorage, uSettings,
  uStorageMigrationService, uILogger;

type
  ESQLiteActivationException = class(Exception);

  TStorageMigrationOrchestrator = class
  public
    class function OrchestrateStorage(const AAppDataPath: string; ASettings: TSettings; const ASettingsPath: string = ''): INoteStorage;
    class function ReconcileInterruptedMigration(const AAppDataPath: string; const ANotesPath: string): Boolean;
    class procedure QuarantineDatabase(const AAppDataPath: string);
  private
    class procedure SaveSettingsIfPathProvided(ASettings: TSettings; const ASettingsPath: string);
    class function VerifyNotesMatch(const AJsonNotes, ASqlNotes: TObjectList<TNote>): Boolean;
    class function VerifyNoteEquivalence(const ASourceNote, ATargetNote: TNote): Boolean;
  end;

implementation

uses
  uStorageResolver;

class procedure TStorageMigrationOrchestrator.SaveSettingsIfPathProvided(ASettings: TSettings; const ASettingsPath: string);
begin
  if (ASettings <> nil) and (ASettingsPath <> '') then
  begin
    try
      ASettings.SaveToFile(ASettingsPath);
    except
      on E: Exception do
      begin
        CreateLogger.Warning('TStorageMigrationOrchestrator: Failed to persist settings after state update: ' + E.Message);
      end;
    end;
  end;
end;

class function TStorageMigrationOrchestrator.VerifyNoteEquivalence(const ASourceNote, ATargetNote: TNote): Boolean;
var
  I: Integer;
begin
  if (ASourceNote = nil) or (ATargetNote = nil) then
    Exit(False);

  if ASourceNote.ID <> ATargetNote.ID then Exit(False);
  if ASourceNote.Title <> ATargetNote.Title then Exit(False);
  if ASourceNote.Content <> ATargetNote.Content then Exit(False);
  if ASourceNote.Color <> ATargetNote.Color then Exit(False);
  if ASourceNote.Left <> ATargetNote.Left then Exit(False);
  if ASourceNote.Top <> ATargetNote.Top then Exit(False);
  if ASourceNote.Width <> ATargetNote.Width then Exit(False);
  if ASourceNote.Height <> ATargetNote.Height then Exit(False);
  if ASourceNote.AlwaysOnTop <> ATargetNote.AlwaysOnTop then Exit(False);
  if ASourceNote.Collapsed <> ATargetNote.Collapsed then Exit(False);
  if ASourceNote.Locked <> ATargetNote.Locked then Exit(False);
  if ASourceNote.Favorite <> ATargetNote.Favorite then Exit(False);

  if Abs(Double(ASourceNote.CreatedAt) - Double(ATargetNote.CreatedAt)) > 0.001 then Exit(False);
  if Abs(Double(ASourceNote.UpdatedAt) - Double(ATargetNote.UpdatedAt)) > 0.001 then Exit(False);

  if Length(ASourceNote.Tags) <> Length(ATargetNote.Tags) then Exit(False);
  for I := 0 to High(ASourceNote.Tags) do
  begin
    if ASourceNote.Tags[I] <> ATargetNote.Tags[I] then Exit(False);
  end;

  if Length(ASourceNote.ChecklistItems) <> Length(ATargetNote.ChecklistItems) then Exit(False);
  for I := 0 to High(ASourceNote.ChecklistItems) do
  begin
    if ASourceNote.ChecklistItems[I].Text <> ATargetNote.ChecklistItems[I].Text then Exit(False);
    if ASourceNote.ChecklistItems[I].Done <> ATargetNote.ChecklistItems[I].Done then Exit(False);
  end;

  Result := True;
end;

class function TStorageMigrationOrchestrator.VerifyNotesMatch(const AJsonNotes, ASqlNotes: TObjectList<TNote>): Boolean;
var
  I, J: Integer;
  SourceNote, TargetNote: TNote;
  Found: Boolean;
begin
  if (AJsonNotes = nil) or (ASqlNotes = nil) then Exit(False);
  if AJsonNotes.Count <> ASqlNotes.Count then Exit(False);

  for I := 0 to AJsonNotes.Count - 1 do
  begin
    SourceNote := AJsonNotes[I];
    Found := False;
    for J := 0 to ASqlNotes.Count - 1 do
    begin
      TargetNote := ASqlNotes[J];
      if TargetNote.ID = SourceNote.ID then
      begin
        Found := True;
        if not VerifyNoteEquivalence(SourceNote, TargetNote) then Exit(False);
        Break;
      end;
    end;
    if not Found then Exit(False);
  end;

  Result := True;
end;

class procedure TStorageMigrationOrchestrator.QuarantineDatabase(const AAppDataPath: string);
var
  DbPath, OrphanPath, TimeStampStr: string;
begin
  DbPath := TPath.Combine(AAppDataPath, 'vnotes.db');
  if not TFile.Exists(DbPath) then Exit;

  DateTimeToString(TimeStampStr, 'yyyyMMdd_hhmmss', Now);
  OrphanPath := TPath.Combine(AAppDataPath, 'vnotes.db.orphan.' + TimeStampStr);

  try
    if TFile.Exists(OrphanPath) then
      TFile.Delete(OrphanPath);
    TFile.Move(DbPath, OrphanPath);

    if TFile.Exists(DbPath + '-wal') then
      TFile.Move(DbPath + '-wal', OrphanPath + '-wal');
    if TFile.Exists(DbPath + '-shm') then
      TFile.Move(DbPath + '-shm', OrphanPath + '-shm');

    CreateLogger.Warning('TStorageMigrationOrchestrator: Existing vnotes.db quarantined to ' + TPath.GetFileName(OrphanPath));
  except
    on E: Exception do
    begin
      CreateLogger.Error('TStorageMigrationOrchestrator: Failed to quarantine database: ' + E.Message);
    end;
  end;
end;

class function TStorageMigrationOrchestrator.ReconcileInterruptedMigration(const AAppDataPath: string; const ANotesPath: string): Boolean;
var
  SqlStorage: TSQLiteStorage;
  JsonStorage: TJsonStorage;
  JsonNotes, SqlNotes: TObjectList<TNote>;
begin
  JsonNotes := nil;
  JsonStorage := TJsonStorage.Create(AAppDataPath);
  try
    try
      JsonStorage.Initialize;
      JsonNotes := JsonStorage.LoadAllNotes;
    except
      on E: Exception do
      begin
        CreateLogger.Warning('TStorageMigrationOrchestrator: Failed loading JSON notes during reconciliation: ' + E.Message);
        Exit(False);
      end;
    end;

    try
      SqlStorage := TSQLiteStorage.Create(AAppDataPath);
      try
        SqlStorage.Initialize;
        SqlNotes := SqlStorage.LoadAllNotes;
        try
          Result := VerifyNotesMatch(JsonNotes, SqlNotes);
        finally
          SqlNotes.Free;
        end;
      finally
        SqlStorage.Finalize;
        SqlStorage.Free;
      end;
    except
      on E: Exception do
      begin
        CreateLogger.Warning('TStorageMigrationOrchestrator: Failed inspecting SQLite database during reconciliation: ' + E.Message);
        Result := False;
      end;
    end;
  finally
    if JsonNotes <> nil then
      JsonNotes.Free;
    JsonStorage.Free;
  end;
end;

class function TStorageMigrationOrchestrator.OrchestrateStorage(const AAppDataPath: string; ASettings: TSettings; const ASettingsPath: string): INoteStorage;
var
  DbPath, NotesPath: string;
  Logger: ILogger;
  SqlStorage: TSQLiteStorage;
  MigRes: TMigrationResult;
  JsonCount: Integer;
  IsFreshInstall: Boolean;
begin
  Logger := CreateLogger;
  DbPath := TPath.Combine(AAppDataPath, 'vnotes.db');
  NotesPath := TPath.Combine(AAppDataPath, 'notes');

  // STATE A: Completed SQLite State
  if (ASettings <> nil) and SameText(ASettings.StorageBackend, 'SQLite') and ASettings.MigrationCompleted then
  begin
    if not TFile.Exists(DbPath) then
    begin
      Logger.Error('TStorageMigrationOrchestrator: Active SQLite storage missing vnotes.db! JSON fallback prohibited.');
      raise ESQLiteActivationException.Create('SQLite database file is missing. Please restore from a backup.');
    end;

    try
      SqlStorage := TSQLiteStorage.Create(AAppDataPath);
      try
        SqlStorage.Initialize; // Validates connection and runs PRAGMA quick_check
      finally
        SqlStorage.Finalize;
        SqlStorage.Free;
      end;
      Result := TStorageResolver.ResolveStorage(AAppDataPath, ASettings);
      Exit;
    except
      on E: Exception do
      begin
        Logger.Error('TStorageMigrationOrchestrator: Active SQLite database corruption or initialization failure: ' + E.Message);
        raise ESQLiteActivationException.Create('SQLite database is corrupt or unopenable: ' + E.Message);
      end;
    end;
  end;

  // STATE B: Unmigrated State (MigrationCompleted = False)

  // Calculate JSON notes count
  JsonCount := 0;
  if TDirectory.Exists(NotesPath) then
    JsonCount := Length(TDirectory.GetFiles(NotesPath, '*.json'));

  // 1. Fresh Installation Check
  // Fresh install occurs if settings.ini file does not exist on disk
  // AND vnotes.db is absent AND no JSON notes exist.
  IsFreshInstall := False;
  if (not TFile.Exists(DbPath)) and (JsonCount = 0) then
  begin
    if (ASettingsPath <> '') and (not TFile.Exists(ASettingsPath)) then
      IsFreshInstall := True
    else if (ASettingsPath = '') and (not TFile.Exists(TPath.Combine(AAppDataPath, 'settings.ini'))) then
      IsFreshInstall := True;
  end;

  if IsFreshInstall then
  begin
    Logger.Info('TStorageMigrationOrchestrator: Fresh installation detected. Activating SQLite storage.');
    SqlStorage := TSQLiteStorage.Create(AAppDataPath);
    try
      SqlStorage.Initialize;
    finally
      SqlStorage.Finalize;
      SqlStorage.Free;
    end;

    if ASettings <> nil then
    begin
      ASettings.StorageBackend := 'SQLite';
      ASettings.MigrationCompleted := True;
      ASettings.MigrationTimestamp := DateToISO8601(Now, False);
      SaveSettingsIfPathProvided(ASettings, ASettingsPath);
    end;

    Result := TStorageResolver.ResolveStorage(AAppDataPath, ASettings);
    Exit;
  end;

  if (not TFile.Exists(DbPath)) and (JsonCount = 0) then
  begin
    // Existing installation configured with JSON, but empty
    if ASettings <> nil then
    begin
      ASettings.StorageBackend := 'SQLite';
      ASettings.MigrationCompleted := True;
      ASettings.MigrationTimestamp := DateToISO8601(Now, False);
      SaveSettingsIfPathProvided(ASettings, ASettingsPath);
    end;
    Result := TStorageResolver.ResolveStorage(AAppDataPath, ASettings);
    Exit;
  end;

  // 2. Interrupted Migration or Existing Database Check
  if TFile.Exists(DbPath) then
  begin
    if ReconcileInterruptedMigration(AAppDataPath, NotesPath) then
    begin
      Logger.Info('TStorageMigrationOrchestrator: Interrupted migration reconciled successfully. Database matches JSON source.');
      if ASettings <> nil then
      begin
        ASettings.StorageBackend := 'SQLite';
        ASettings.MigrationCompleted := True;
        ASettings.MigrationTimestamp := DateToISO8601(Now, False);
        SaveSettingsIfPathProvided(ASettings, ASettingsPath);
      end;

      Result := TStorageResolver.ResolveStorage(AAppDataPath, ASettings);
      Exit;
    end
    else
    begin
      Logger.Warning('TStorageMigrationOrchestrator: Pre-existing vnotes.db does not match JSON notes. Quarantining database.');
      QuarantineDatabase(AAppDataPath);
    end;
  end;

  // 3. Perform JSON -> SQLite Migration
  Logger.Info('TStorageMigrationOrchestrator: Starting JSON -> SQLite migration...');
  MigRes := TStorageMigrationService.MigrateJsonToSQLite(AAppDataPath);

  if MigRes.Success then
  begin
    Logger.Info(Format('TStorageMigrationOrchestrator: Migration succeeded (%d notes migrated).', [MigRes.NotesMigrated]));
    if ASettings <> nil then
    begin
      ASettings.StorageBackend := 'SQLite';
      ASettings.MigrationCompleted := True;
      ASettings.MigrationTimestamp := DateToISO8601(Now, False);
      SaveSettingsIfPathProvided(ASettings, ASettingsPath);
    end;

    Result := TStorageResolver.ResolveStorage(AAppDataPath, ASettings);
  end
  else
  begin
    Logger.Error('TStorageMigrationOrchestrator: Migration failed: ' + MigRes.ErrorMessage + '. Remaining on JSON storage.');
    if ASettings <> nil then
    begin
      ASettings.StorageBackend := 'JSON';
      ASettings.MigrationCompleted := False;
    end;

    Result := TStorageResolver.ResolveStorage(AAppDataPath, ASettings);
  end;
end;

end.
