unit uStorageMigrationService;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.JSON, System.DateUtils, System.Types,
  uNote, uStorage, uJsonStorage, uSQLiteStorage, uEnums, uILogger;

type
  TMigrationResult = record
    Success: Boolean;
    NotesMigrated: Integer;
    NotesFailed: Integer;
    ErrorMessage: string;
  end;

  TStorageMigrationService = class
  public
    class function MigrateJsonToSQLite(const AAppDataPath: string): TMigrationResult;
  private
    class function VerifyNoteEquivalence(const ASourceNote, ATargetNote: TNote): Boolean;
  end;

implementation

class function TStorageMigrationService.VerifyNoteEquivalence(const ASourceNote, ATargetNote: TNote): Boolean;
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

  // Tighten tolerance from 0.001 to 1E-7 for strict millisecond matching
  if Abs(Double(ASourceNote.CreatedAt) - Double(ATargetNote.CreatedAt)) > 1E-7 then Exit(False);
  if Abs(Double(ASourceNote.UpdatedAt) - Double(ATargetNote.UpdatedAt)) > 1E-7 then Exit(False);

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

class function TStorageMigrationService.MigrateJsonToSQLite(const AAppDataPath: string): TMigrationResult;
var
  NotesPath, DbPath: string;
  SqlStorage: TSQLiteStorage;
  JsonStorage: TJsonStorage;
  ExistingNotes, LoadedNotes, MigratedNotes: TObjectList<TNote>;
  Files: TStringDynArray;
  FileName, JsonText: string;
  JsonVal: TJSONValue;
  Note, SourceNote, TargetNote: TNote;
  I, J: Integer;
  Found: Boolean;
  Logger: ILogger;
begin
  Result.Success := False;
  Result.NotesMigrated := 0;
  Result.NotesFailed := 0;
  Result.ErrorMessage := '';

  Logger := CreateLogger;
  NotesPath := TPath.Combine(AAppDataPath, 'notes');
  DbPath := TPath.Combine(AAppDataPath, 'vnotes.db');

  // Step 1: Destination Safety Check
  if TFile.Exists(DbPath) then
  begin
    SqlStorage := TSQLiteStorage.Create(AAppDataPath);
    try
      SqlStorage.Initialize;
      ExistingNotes := SqlStorage.LoadAllNotes;
      try
        if ExistingNotes.Count > 0 then
        begin
          Result.Success := False;
          Result.NotesMigrated := 0;
          Result.NotesFailed := 0;
          Result.ErrorMessage := 'Destination SQLite database is not empty';
          Logger.Warning('TStorageMigrationService: Migration aborted - destination SQLite database is not empty');
          Exit;
        end;
      finally
        ExistingNotes.Free;
      end;
    finally
      SqlStorage.Finalize;
      SqlStorage.Free;
    end;
  end;

  // Step 2: Source Loading & Strict Validation
  if (not TDirectory.Exists(NotesPath)) or (Length(TDirectory.GetFiles(NotesPath, '*.json')) = 0) then
  begin
    Result.Success := True;
    Result.NotesMigrated := 0;
    Result.NotesFailed := 0;
    Result.ErrorMessage := '';
    Logger.Info('TStorageMigrationService: No JSON notes found to migrate');
    Exit;
  end;

  Files := TDirectory.GetFiles(NotesPath, '*.json');

  // Strict file-by-file JSON validation
  for FileName in Files do
  begin
    try
      JsonText := TFile.ReadAllText(FileName, TEncoding.UTF8);
      JsonVal := TJSONObject.ParseJSONValue(JsonText);
      if (JsonVal = nil) or not (JsonVal is TJSONObject) then
      begin
        if JsonVal <> nil then JsonVal.Free;
        Result.Success := False;
        Result.NotesMigrated := 0;
        Result.NotesFailed := Length(Files);
        Result.ErrorMessage := 'Corrupted or malformed JSON file: ' + TPath.GetFileName(FileName);
        Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
        Exit;
      end;
      JsonVal.Free;
    except
      on E: Exception do
      begin
        Result.Success := False;
        Result.NotesMigrated := 0;
        Result.NotesFailed := Length(Files);
        Result.ErrorMessage := 'Failed to read JSON file ' + TPath.GetFileName(FileName) + ': ' + E.Message;
        Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
        Exit;
      end;
    end;
  end;

  JsonStorage := TJsonStorage.Create(AAppDataPath);
  try
    JsonStorage.Initialize;
    LoadedNotes := JsonStorage.LoadAllNotes;
  finally
    JsonStorage.Free;
  end;

  try
    if LoadedNotes.Count <> Length(Files) then
    begin
      Result.Success := False;
      Result.NotesMigrated := 0;
      Result.NotesFailed := Length(Files) - LoadedNotes.Count;
      Result.ErrorMessage := 'One or more JSON note files failed schema validation or deserialization';
      Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
      Exit;
    end;

    // Step 3: Atomic Batch Import into SQLite
    SqlStorage := TSQLiteStorage.Create(AAppDataPath);
    try
      SqlStorage.Initialize;
      SqlStorage.BeginTransaction;
      try
        for Note in LoadedNotes do
        begin
          if not SqlStorage.SaveNote(Note) then
          begin
            SqlStorage.RollbackTransaction;
            Result.Success := False;
            Result.NotesMigrated := 0;
            Result.NotesFailed := LoadedNotes.Count;
            Result.ErrorMessage := 'Failed to save note ID ' + IntToStr(Note.ID) + ' to SQLite';
            Logger.Error('TStorageMigrationService: Migration aborted during save - ' + Result.ErrorMessage);
            Exit;
          end;
        end;

        // Step 4: Verification
        MigratedNotes := SqlStorage.LoadAllNotes;
        try
          if MigratedNotes.Count <> LoadedNotes.Count then
          begin
            SqlStorage.RollbackTransaction;
            Result.Success := False;
            Result.NotesMigrated := 0;
            Result.NotesFailed := LoadedNotes.Count;
            Result.ErrorMessage := 'Verification failed: Migrated note count mismatch';
            Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
            Exit;
          end;

          for I := 0 to LoadedNotes.Count - 1 do
          begin
            SourceNote := LoadedNotes[I];
            Found := False;
            for J := 0 to MigratedNotes.Count - 1 do
            begin
              TargetNote := MigratedNotes[J];
              if TargetNote.ID = SourceNote.ID then
              begin
                Found := True;
                if not VerifyNoteEquivalence(SourceNote, TargetNote) then
                begin
                  SqlStorage.RollbackTransaction;
                  Result.Success := False;
                  Result.NotesMigrated := 0;
                  Result.NotesFailed := LoadedNotes.Count;
                  Result.ErrorMessage := 'Verification failed for note ID ' + IntToStr(SourceNote.ID);
                  Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
                  Exit;
                end;
                Break;
              end;
            end;

            if not Found then
            begin
              SqlStorage.RollbackTransaction;
              Result.Success := False;
              Result.NotesMigrated := 0;
              Result.NotesFailed := LoadedNotes.Count;
              Result.ErrorMessage := 'Verification failed: Note ID ' + IntToStr(SourceNote.ID) + ' not found in SQLite';
              Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
              Exit;
            end;
          end;

          // Success! Commit transaction
          SqlStorage.CommitTransaction;
          Result.Success := True;
          Result.NotesMigrated := LoadedNotes.Count;
          Result.NotesFailed := 0;
          Result.ErrorMessage := '';
          Logger.Info(Format('TStorageMigrationService: Migration successful (%d notes migrated)', [LoadedNotes.Count]));
        finally
          MigratedNotes.Free;
        end;
      except
        on E: Exception do
        begin
          SqlStorage.RollbackTransaction;
          Result.Success := False;
          Result.NotesMigrated := 0;
          Result.NotesFailed := LoadedNotes.Count;
          Result.ErrorMessage := 'Migration transaction error: ' + E.Message;
          Logger.Error('TStorageMigrationService: Migration aborted - ' + Result.ErrorMessage);
        end;
      end;
    finally
      SqlStorage.Finalize;
      SqlStorage.Free;
    end;
  finally
    LoadedNotes.Free;
  end;
end;

end.
