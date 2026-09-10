unit uBackupService;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  System.Generics.Collections,
  uNoteManager, uSettings, uILogger;

type
  TBackupProgress = procedure(const AMessage: string; AProgress: Integer) of object;
  TBackupComplete = procedure(ASuccess: Boolean; const AMessage: string) of object;
  // Fired immediately before/after the active storage is swapped during
  // Restore (the note manager is re-initialized, which frees every TNote).
  // The UI must close note windows before the swap and may re-open them
  // after, otherwise open windows keep dangling TNote references.
  TStorageSwapEvent = procedure(Sender: TObject) of object;

  TBackupService = class
  private
    FNoteManager: TNoteManager;
    FSettings: TSettings;
    FBackupPath: string;
    FOnProgress: TBackupProgress;
    FOnComplete: TBackupComplete;
    FOnBeforeStorageSwap: TStorageSwapEvent;
    FOnAfterStorageSwap: TStorageSwapEvent;
    FLastBackupFile: string;
    function CreateBackupZip(const AZipFile: string): Boolean;
    procedure DoRestore(const ABackupFile: string; const ALogger: ILogger);
    procedure CreateManifest(const ATempDir: string; const ALogger: ILogger);
    function ValidateBackupStructure(const ATempDir: string; const ALogger: ILogger): Boolean;
    function CreatePreRestoreBackup(const ALogger: ILogger): string;
    function ValidateRestoredSettings(const ALogger: ILogger): Boolean;
  public
    constructor Create(ANoteManager: TNoteManager; ASettings: TSettings; const ABackupPath: string);
    destructor Destroy; override;
    function Backup: Boolean; virtual;
    procedure Restore(const ABackupFile: string);
    procedure CleanupOldBackups;
    function GetBackupFileName: string;
    class function ValidateSQLiteDatabase(const ADbPath: string; const ALogger: ILogger): Boolean;
    property OnProgress: TBackupProgress read FOnProgress write FOnProgress;
    property OnComplete: TBackupComplete read FOnComplete write FOnComplete;
    property OnBeforeStorageSwap: TStorageSwapEvent read FOnBeforeStorageSwap write FOnBeforeStorageSwap;
    property OnAfterStorageSwap: TStorageSwapEvent read FOnAfterStorageSwap write FOnAfterStorageSwap;
  end;

implementation

uses
  System.Types, System.JSON, uNote, uEnums,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef,
  uSQLiteStorage, uStorageMigrationService;

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

class function TBackupService.ValidateSQLiteDatabase(const ADbPath: string; const ALogger: ILogger): Boolean;
var
  Conn: TFDConnection;
  Query: TFDQuery;
  Res: string;
begin
  Result := False;
  if not TFile.Exists(ADbPath) then Exit;

  try
    Conn := TFDConnection.Create(nil);
    try
      Conn.DriverName := 'SQLite';
      Conn.Params.Values['Database'] := ADbPath;
      Conn.Params.Values['OpenMode'] := 'ReadWrite';
      Conn.Params.Values['Pooled'] := 'False';
      Conn.Open;

      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Conn;
        Query.SQL.Text := 'PRAGMA quick_check;';
        Query.Open;
        if not Query.Eof then
        begin
          Res := Query.Fields[0].AsString;
          if SameText(Res, 'ok') then
            Result := True
          else if ALogger <> nil then
            ALogger.Error('SQLite database validation failed (quick_check): ' + Res);
        end;
      finally
        Query.Free;
      end;
    finally
      Conn.Close;
      Conn.Free;
    end;
  except
    on E: Exception do
    begin
      if ALogger <> nil then
        ALogger.Error('SQLite database validation failed (exception): ' + E.Message);
      Result := False;
    end;
  end;
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
begin
  if FLastBackupFile <> '' then
    Result := FLastBackupFile
  else
  begin
    Result := TPath.Combine(FBackupPath, 'StickyNotes_Backup_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.zip');
  end;
end;

function TBackupService.Backup: Boolean;
var
  ZipFile: string;
  Success: Boolean;
  Logger: ILogger;
begin
  if Assigned(FOnProgress) then
    FOnProgress('Creating backup...', 0);

  Logger := CreateLogger;
  FLastBackupFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.zip');
  ZipFile := FLastBackupFile;
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
  Result := Success;
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
  I: Integer;
  Logger: ILogger;
  TagsArray: System.JSON.TJSONArray;
  ChecklistArray: System.JSON.TJSONArray;
  Tag: string;
  ChecklistItem: TChecklistItem;
  ItemJson: System.JSON.TJSONObject;
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
        Json.AddPair('schemaVersion', System.JSON.TJSONNumber.Create(3));
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
        Json.AddPair('Favorite', System.JSON.TJSONBool.Create(Note.Favorite));
        Json.AddPair('CreatedAt', DateTimeToISO8601(Note.CreatedAt));
        Json.AddPair('UpdatedAt', DateTimeToISO8601(Note.UpdatedAt));

        // Serialize tags
        if Length(Note.Tags) > 0 then
        begin
          TagsArray := System.JSON.TJSONArray.Create;
          try
            for Tag in Note.Tags do
              TagsArray.Add(Tag);
            Json.AddPair('tags', TagsArray);
          except
            TagsArray.Free;
            raise;
          end;
        end
        else
          Json.AddPair('tags', System.JSON.TJSONArray.Create);

        // Serialize checklist items
        if Length(Note.ChecklistItems) > 0 then
        begin
          ChecklistArray := System.JSON.TJSONArray.Create;
          try
            for ChecklistItem in Note.ChecklistItems do
            begin
              ItemJson := System.JSON.TJSONObject.Create;
              ItemJson.AddPair('text', TJSONString.Create(ChecklistItem.Text));
              ItemJson.AddPair('done', TJSONBool.Create(ChecklistItem.Done));
              ChecklistArray.AddElement(ItemJson);
            end;
            Json.AddPair('checklistItems', ChecklistArray);
          except
            ChecklistArray.Free;
            raise;
          end;
        end
        else
          Json.AddPair('checklistItems', System.JSON.TJSONArray.Create);

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

    // Package SQLite database if present in AppData path
    FileName := TPath.Combine(TPath.GetDirectoryName(ExpandFileName(FBackupPath)), 'vnotes.db');
    if TFile.Exists(FileName) then
    begin
      if ValidateSQLiteDatabase(FileName, Logger) then
      begin
        TFile.Copy(FileName, TPath.Combine(TempDir, 'vnotes.db'), True);
        Logger.Info('CreateBackupZip: Included valid vnotes.db in backup archive');
      end
      else
        Logger.Warning('CreateBackupZip: vnotes.db found but quick_check validation failed - omitted from zip');
    end;

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

procedure DeleteDbSidecars(const ADbPath: string);
begin
  if TFile.Exists(ADbPath + '-wal') then
    TFile.Delete(ADbPath + '-wal');
  if TFile.Exists(ADbPath + '-shm') then
    TFile.Delete(ADbPath + '-shm');
  if TFile.Exists(ADbPath + '-journal') then
    TFile.Delete(ADbPath + '-journal');
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
  FavoriteJsonVal: System.JSON.TJSONValue;
  TagsVal, ChecklistVal: System.JSON.TJSONValue;
  TagsArr, ChecklistArr: System.JSON.TJSONArray;
  Elem: System.JSON.TJSONValue;
  Tags: TArray<string>;
  Checklist: TArray<TChecklistItem>;
  ItemObj: System.JSON.TJSONObject;
  TextVal, DoneVal: System.JSON.TJSONValue;
  ItemText: string;
  ItemDone: Boolean;
  TempDbFile: string;
  AppDataPath: string;
  AppDbPath: string;
  BakDbPath: string;
  SqlStorage: TSQLiteStorage;
  SqlNotes: TObjectList<TNote>;
  MigResult: TMigrationResult;
  DbRestored: Boolean;
  IsSQLiteActive: Boolean;
  Val: System.JSON.TJSONValue;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_Restore_' + FormatDateTime('yyyymmdd_hhnnss', Now));
  PreRestoreBackup := '';
  RestoredNotes := TObjectList<TNote>.Create;

  try
    if not TFile.Exists(ABackupFile) then
    begin
      ALogger.Error(Format('Restore: Backup file not found: %s', [ABackupFile]));
      if Assigned(FOnComplete) then
        FOnComplete(False, 'Restore failed: Backup file not found');
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
          FOnComplete(False, 'Restore failed: Failed to extract backup');
        Exit;
      end;
    end;

    // Validate backup structure before attempting restore
    if not ValidateBackupStructure(TempDir, ALogger) then
    begin
      ALogger.Error('Restore: Backup structure validation failed');
      if Assigned(FOnComplete) then
        FOnComplete(False, 'Restore failed: Backup format is incompatible');
      Exit;
    end;

    if Assigned(FOnProgress) then
      FOnProgress('Validating backup contents...', 25);

    DbRestored := False;
    IsSQLiteActive := (FSettings <> nil) and SameText(FSettings.StorageBackend, 'SQLite') and FSettings.MigrationCompleted;

    TempDbFile := TPath.Combine(TempDir, 'vnotes.db');
    AppDataPath := TPath.GetDirectoryName(ExpandFileName(FBackupPath));
    AppDbPath := TPath.Combine(AppDataPath, 'vnotes.db');

    if IsSQLiteActive and TFile.Exists(TempDbFile) then
    begin
      // SQLite Backup Archive: Validate TempDbFile before attempting restore
      if not ValidateSQLiteDatabase(TempDbFile, ALogger) then
      begin
        ALogger.Error('Restore: SQLite database validation failed (quick_check)');
        if Assigned(FOnComplete) then
          FOnComplete(False, 'Restore failed: Corrupted SQLite database in backup');
        Exit;
      end;

      // Load notes from SQLite DB in TempDir
      SqlStorage := TSQLiteStorage.Create(TempDir);
      try
        SqlStorage.Initialize;
        SqlNotes := SqlStorage.LoadAllNotes;
        try
          SqlNotes.OwnsObjects := False;
          for I := 0 to SqlNotes.Count - 1 do
          begin
            RestoredNotes.Add(SqlNotes[I]);
          end;
        finally
          SqlNotes.Free;
        end;
      finally
        SqlStorage.Finalize;
        SqlStorage.Free;
      end;

      // Safely replace AppDbPath with TempDbFile. The swap re-initializes
      // the note manager and frees every TNote it owns, so open note
      // windows must be closed first (OnBeforeStorageSwap) and are
      // re-opened after (OnAfterStorageSwap).
      if FNoteManager <> nil then
      begin
        if Assigned(FOnBeforeStorageSwap) then
          FOnBeforeStorageSwap(Self);
        FNoteManager.Finalize;
      end;
      try
        if TFile.Exists(AppDbPath) then
        begin
          BakDbPath := AppDbPath + '.bak';
          TFile.Copy(AppDbPath, BakDbPath, True);
          try
            DeleteDbSidecars(AppDbPath);
            TFile.Copy(TempDbFile, AppDbPath, True);
            TFile.Delete(BakDbPath);
            DbRestored := True;
          except
            if TFile.Exists(BakDbPath) then
            begin
              DeleteDbSidecars(AppDbPath);
              TFile.Copy(BakDbPath, AppDbPath, True);
              TFile.Delete(BakDbPath);
            end;
            raise;
          end;
        end
        else
        begin
          DeleteDbSidecars(AppDbPath);
          TFile.Copy(TempDbFile, AppDbPath, True);
          DbRestored := True;
        end;
      finally
        if FNoteManager <> nil then
        begin
          try
            FNoteManager.Initialize;
          finally
            // Fire even if Initialize raised, so the closed note windows
            // are re-opened against whatever storage state we ended with
            // (review 2026-09-10 H7).
            if Assigned(FOnAfterStorageSwap) then
              FOnAfterStorageSwap(Self);
          end;
        end;
      end;
    end;

    if (RestoredNotes.Count = 0) and TDirectory.Exists(TempDir) then
    begin
      Files := TDirectory.GetFiles(TempDir, '*.json', TSearchOption.soAllDirectories);
      for FileName in Files do
      begin
        if SameText(ExtractFileName(FileName), 'manifest.json') then
          Continue;

        try
          JsonText := TFile.ReadAllText(FileName, TEncoding.UTF8);
          Json := System.JSON.TJSONObject.ParseJSONValue(JsonText) as System.JSON.TJSONObject;
          if Json <> nil then
          try
            Note := TNote.Create;

            // ID / id
            Val := Json.GetValue('ID');
            if Val = nil then Val := Json.GetValue('id');
            if (Val <> nil) and (Val is TJSONNumber) then
              Note.ID := (Val as TJSONNumber).AsInt64
            else if Val <> nil then
              Note.ID := StrToInt64Def(Val.Value, 0)
            else
              Note.ID := 0;

            // Title / title
            Val := Json.GetValue('Title');
            if Val = nil then Val := Json.GetValue('title');
            if (Val <> nil) and (Val is TJSONString) then
              Note.Title := (Val as TJSONString).Value
            else if Val <> nil then
            begin
              CreatedStr := Val.ToString;
              if (Length(CreatedStr) >= 2) and (CreatedStr[1] = '"') and (CreatedStr[Length(CreatedStr)] = '"') then
                Note.Title := Copy(CreatedStr, 2, Length(CreatedStr) - 2)
              else
                Note.Title := CreatedStr;
            end
            else
              Note.Title := '';

            // Content / content
            Val := Json.GetValue('Content');
            if Val = nil then Val := Json.GetValue('content');
            if (Val <> nil) and (Val is TJSONString) then
              Note.Content := (Val as TJSONString).Value
            else if Val <> nil then
            begin
              CreatedStr := Val.ToString;
              if (Length(CreatedStr) >= 2) and (CreatedStr[1] = '"') and (CreatedStr[Length(CreatedStr)] = '"') then
                Note.Content := Copy(CreatedStr, 2, Length(CreatedStr) - 2)
              else
                Note.Content := CreatedStr;
            end
            else
              Note.Content := '';

            // Color / color
            Val := Json.GetValue('Color');
            if Val = nil then Val := Json.GetValue('color');
            if (Val <> nil) and (Val is TJSONNumber) then
              ColorInt := (Val as TJSONNumber).AsInt
            else
              ColorInt := Ord(ncYellow);
            Note.Color := TNoteColor(ColorInt);

            // Left / left
            Val := Json.GetValue('Left');
            if Val = nil then Val := Json.GetValue('left');
            if (Val <> nil) and (Val is TJSONNumber) then
              Note.Left := (Val as TJSONNumber).AsInt
            else
              Note.Left := 100;

            // Top / top
            Val := Json.GetValue('Top');
            if Val = nil then Val := Json.GetValue('top');
            if (Val <> nil) and (Val is TJSONNumber) then
              Note.Top := (Val as TJSONNumber).AsInt
            else
              Note.Top := 100;

            // Width / width
            Val := Json.GetValue('Width');
            if Val = nil then Val := Json.GetValue('width');
            if (Val <> nil) and (Val is TJSONNumber) then
              Note.Width := (Val as TJSONNumber).AsInt
            else
              Note.Width := 300;

            // Height / height
            Val := Json.GetValue('Height');
            if Val = nil then Val := Json.GetValue('height');
            if (Val <> nil) and (Val is TJSONNumber) then
              Note.Height := (Val as TJSONNumber).AsInt
            else
              Note.Height := 250;

            // AlwaysOnTop / always_on_top
            Val := Json.GetValue('AlwaysOnTop');
            if Val = nil then Val := Json.GetValue('always_on_top');
            Note.AlwaysOnTop := (Val <> nil) and (Val is TJSONTrue);

            // Collapsed / collapsed
            Val := Json.GetValue('Collapsed');
            if Val = nil then Val := Json.GetValue('collapsed');
            Note.Collapsed := (Val <> nil) and (Val is TJSONTrue);

            // Locked / locked
            Val := Json.GetValue('Locked');
            if Val = nil then Val := Json.GetValue('locked');
            Note.Locked := (Val <> nil) and (Val is TJSONTrue);

            // CreatedAt / created_at
            Val := Json.GetValue('CreatedAt');
            if Val = nil then Val := Json.GetValue('created_at');
            CreatedStr := '';
            if Val <> nil then
            begin
              CreatedStr := Val.ToString;
              if (Length(CreatedStr) >= 2) and (CreatedStr[1] = '"') and (CreatedStr[Length(CreatedStr)] = '"') then
                CreatedStr := Copy(CreatedStr, 2, Length(CreatedStr) - 2);
            end;

            // UpdatedAt / updated_at
            Val := Json.GetValue('UpdatedAt');
            if Val = nil then Val := Json.GetValue('updated_at');
            UpdatedStr := '';
            if Val <> nil then
            begin
              UpdatedStr := Val.ToString;
              if (Length(UpdatedStr) >= 2) and (UpdatedStr[1] = '"') and (UpdatedStr[Length(UpdatedStr)] = '"') then
                UpdatedStr := Copy(UpdatedStr, 2, Length(UpdatedStr) - 2);
            end;

            if CreatedStr <> '' then
              Note.CreatedAt := ISO8601ToDate(CreatedStr)
            else
              Note.CreatedAt := Now;
            if UpdatedStr <> '' then
              Note.UpdatedAt := ISO8601ToDate(UpdatedStr)
            else
              Note.UpdatedAt := Now;

            // Favorite / favorite
            Val := Json.GetValue('Favorite');
            if Val = nil then Val := Json.GetValue('favorite');
            Note.Favorite := (Val <> nil) and (Val is TJSONTrue);

            // tags
            TagsVal := Json.GetValue('tags');
            if (TagsVal <> nil) and (TagsVal is TJSONArray) then
            begin
              TagsArr := TagsVal as TJSONArray;
              SetLength(Tags, 0);
              for Elem in TagsArr do
              begin
                if Elem <> nil then
                begin
                  SetLength(Tags, Length(Tags) + 1);
                  CreatedStr := Elem.ToString;
                  if (Length(CreatedStr) >= 2) and (CreatedStr[1] = '"') and (CreatedStr[Length(CreatedStr)] = '"') then
                    Tags[High(Tags)] := Copy(CreatedStr, 2, Length(CreatedStr) - 2)
                  else
                    Tags[High(Tags)] := CreatedStr;
                end;
              end;
              Note.Tags := Tags;
            end
            else
              Note.Tags := nil;

            // checklistItems / checklist
            ChecklistVal := Json.GetValue('checklistItems');
            if ChecklistVal = nil then ChecklistVal := Json.GetValue('checklist');
            if (ChecklistVal <> nil) and (ChecklistVal is TJSONArray) then
            begin
              ChecklistArr := ChecklistVal as TJSONArray;
              SetLength(Checklist, 0);
              for Elem in ChecklistArr do
              begin
                if Elem is TJSONObject then
                begin
                  ItemObj := Elem as TJSONObject;
                  TextVal := ItemObj.GetValue('text');
                  DoneVal := ItemObj.GetValue('done');
                  if TextVal <> nil then
                  begin
                    ItemText := TextVal.ToString;
                    if (Length(ItemText) >= 2) and (ItemText[1] = '"') and (ItemText[Length(ItemText)] = '"') then
                      ItemText := Copy(ItemText, 2, Length(ItemText) - 2);
                  end
                  else
                    ItemText := '';
                  ItemDone := (DoneVal <> nil) and (DoneVal is TJSONTrue);
                  SetLength(Checklist, Length(Checklist) + 1);
                  Checklist[High(Checklist)] := TChecklistItem.Create(ItemText, ItemDone);
                end;
              end;
              Note.ChecklistItems := Checklist;
            end
            else
              Note.ChecklistItems := nil;

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

      // Legacy JSON Backup Restore Compatibility: Migrate JSON notes to vnotes.db in TempDir if SQLite active
      if IsSQLiteActive and (RestoredNotes.Count > 0) then
      begin
        MigResult := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
        if MigResult.Success and ValidateSQLiteDatabase(TempDbFile, ALogger) then
        begin
          if FNoteManager <> nil then
          begin
            if Assigned(FOnBeforeStorageSwap) then
              FOnBeforeStorageSwap(Self);
            FNoteManager.Finalize;
          end;
          try
            if TFile.Exists(AppDbPath) then
            begin
              BakDbPath := AppDbPath + '.bak';
              TFile.Copy(AppDbPath, BakDbPath, True);
              try
                DeleteDbSidecars(AppDbPath);
                TFile.Copy(TempDbFile, AppDbPath, True);
                TFile.Delete(BakDbPath);
                DbRestored := True;
              except
                if TFile.Exists(BakDbPath) then
                begin
                  DeleteDbSidecars(AppDbPath);
                  TFile.Copy(BakDbPath, AppDbPath, True);
                  TFile.Delete(BakDbPath);
                end;
              end;
            end
            else
            begin
              DeleteDbSidecars(AppDbPath);
              TFile.Copy(TempDbFile, AppDbPath, True);
              DbRestored := True;
            end;
          finally
            if FNoteManager <> nil then
            begin
              try
                FNoteManager.Initialize;
              finally
                // Fire even if Initialize raised, so the closed note windows
                // are re-opened against whatever storage state we ended with
                // (review 2026-09-10 H7).
                if Assigned(FOnAfterStorageSwap) then
                  FOnAfterStorageSwap(Self);
              end;
            end;
          end;
        end;
      end;
    end;

    // Phase 2: Clear existing notes and restore from validated temp list (for non-DB restores)
    if not DbRestored then
    begin
      if Assigned(FOnProgress) then
        FOnProgress('Restoring notes...', 40);

      // Delete all existing notes to make room for restored ones
      for I := FNoteManager.NoteCount - 1 downto 0 do
      begin
        Note := FNoteManager.Notes[I];
        if Note <> nil then
          FNoteManager.DeleteNote(Note.ID);
      end;

      // Transfer ownership: note list must not own objects that have been
      // accepted by TNoteManager (which has its own OwnsObjects=True list).
      RestoredNotes.OwnsObjects := False;
      for I := 0 to RestoredNotes.Count - 1 do
      begin
        Note := RestoredNotes[I];
        if not FNoteManager.AddNote(Note) then
        begin
          ALogger.Warning(Format('Restore: Failed to add note ID %d', [Note.ID]));
          Note.Free;
        end;
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
