unit uJsonStorage;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.JSON, System.DateUtils, System.Types,
  uStorage, uNote, uEnums, uILogger, uIdentity;

type
  // Raised when a JSON note file carries a schema version that this build
  // cannot safely interpret (future version, negative value, wrong JSON type).
  // The file itself is never modified or deleted when this is raised.
  EJsonSchemaException = class(Exception);

  TJsonStorage = class(TInterfacedObject, INoteStorage)
  private
    const
      // Schema version of the JSON written by this build.
      // v0 = unversioned legacy files.
      // v1 = adds the schemaVersion field itself; no tags/checklistItems.
      // v2 = adds "tags" (string array) and "checklistItems" (array of
      //      {text, done}). Absent on v0/v1 files -> read as empty arrays.
      // v3 = adds "favorite" (boolean). Absent on v0/v1/v2 files, or
      //      wrong-typed, -> read as False (same tolerant policy as the
      //      other boolean flags).
      CURRENT_SCHEMA_VERSION = NoteSchemaVersion;
      // Unversioned (pre-versioning) files are interpreted as schema 0.
      LEGACY_SCHEMA_VERSION = 0;
      SCHEMA_VERSION_FIELD = 'schemaVersion';
  private
    FBasePath: string;
    FNotesPath: string;
    FSettingsPath: string;
    FNextID: Int64;
    FDeviceId: string;
    function GetNoteFileName(AID: Int64): string;
    procedure EnsureDirectories;
    class function TagsToJson(const ATags: TArray<string>): TJSONArray;
    class function ChecklistItemsToJson(const AItems: TArray<TChecklistItem>): TJSONArray;
    // Both readers are defensive by design: an absent field (v0/v1 files),
    // a wrong-typed field, or a malformed element is treated as "no data"
    // for that field/element rather than raising  a damaged tags/checklist
    // block should never make an otherwise-valid note unloadable.
    class function JsonToTags(const AJson: TJSONObject): TArray<string>;
    class function JsonToChecklistItems(const AJson: TJSONObject): TArray<TChecklistItem>;
  public
    constructor Create(const ABasePath: string);
    destructor Destroy; override;
    function SaveNote(const ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function LoadAllNotes: TObjectList<TNote>;
    function GetNextID: Int64;
    procedure Initialize;
    procedure Finalize;

    // Canonical note<->JSON codec, shared with the sync layer so the local
    // storage format and the sync interchange format cannot drift apart.
    class function NoteToJson(const ANote: TNote): TJSONObject;
    class function JsonToNote(const AJson: TJSONObject): TNote;
  end;

implementation

uses
  Winapi.Windows, uIso8601;

{ TJsonStorage }

constructor TJsonStorage.Create(const ABasePath: string);
begin
  inherited Create;
  FBasePath := ABasePath;
  FNotesPath := TPath.Combine(FBasePath, 'notes');
  FSettingsPath := TPath.Combine(FBasePath, 'settings.ini');
  FNextID := 1;
end;

destructor TJsonStorage.Destroy;
begin
  Finalize;
  inherited;
end;

procedure TJsonStorage.EnsureDirectories;
begin
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
  if not TDirectory.Exists(FNotesPath) then
    TDirectory.CreateDirectory(FNotesPath);
end;

procedure TJsonStorage.Initialize;
var
  Files: TStringDynArray;
  FileName: string;
  ID: Int64;
begin
  EnsureDirectories;
  FNextID := 1;
  Files := TDirectory.GetFiles(FNotesPath, '*.json');
  for FileName in Files do
  begin
    ID := StrToInt64Def(TPath.GetFileNameWithoutExtension(FileName), 0);
    if ID >= FNextID then
      FNextID := ID + 1;
  end;
end;

procedure TJsonStorage.Finalize;
begin
  // Nothing to do for JSON storage
end;

function TJsonStorage.GetNoteFileName(AID: Int64): string;
begin
  Result := TPath.Combine(FNotesPath, Format('%.10d.json', [AID]));
end;

function TJsonStorage.GetNextID: Int64;
begin
  Result := FNextID;
  Inc(FNextID);
end;

class function TJsonStorage.NoteToJson(const ANote: TNote): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair(SCHEMA_VERSION_FIELD, TJSONNumber.Create(CURRENT_SCHEMA_VERSION));
  Result.AddPair('ID', TJSONNumber.Create(ANote.ID));
  Result.AddPair('Title', TJSONString.Create(ANote.Title));
  Result.AddPair('Content', TJSONString.Create(ANote.Content));
  Result.AddPair('Color', TJSONNumber.Create(Ord(ANote.Color)));
  Result.AddPair('Left', TJSONNumber.Create(ANote.Left));
  Result.AddPair('Top', TJSONNumber.Create(ANote.Top));
  Result.AddPair('Width', TJSONNumber.Create(ANote.Width));
  Result.AddPair('Height', TJSONNumber.Create(ANote.Height));
  Result.AddPair('AlwaysOnTop', TJSONBool.Create(ANote.AlwaysOnTop));
  Result.AddPair('Collapsed', TJSONBool.Create(ANote.Collapsed));
  Result.AddPair('Locked', TJSONBool.Create(ANote.Locked));
  Result.AddPair('Favorite', TJSONBool.Create(ANote.Favorite));
  Result.AddPair('CreatedAt', TJSONString.Create(DateTimeToStoredISO8601(ANote.CreatedAt)));
  Result.AddPair('UpdatedAt', TJSONString.Create(DateTimeToStoredISO8601(ANote.UpdatedAt)));
  // Phase 7A sync identity (see docs/PHASE_7_CLOUD_SYNC_DESIGN.md).
  Result.AddPair('Guid', TJSONString.Create(ANote.Guid));
  Result.AddPair('Rev', TJSONNumber.Create(ANote.Rev));
  Result.AddPair('DeviceId', TJSONString.Create(ANote.DeviceId));
  Result.AddPair('Deleted', TJSONBool.Create(ANote.Deleted));
  if ANote.DeletedAt <> 0 then
    Result.AddPair('DeletedAt', TJSONString.Create(DateTimeToStoredISO8601(ANote.DeletedAt)));

  Result.AddPair('tags', TagsToJson(ANote.Tags));
  Result.AddPair('checklistItems', ChecklistItemsToJson(ANote.ChecklistItems));
end;

class function TJsonStorage.TagsToJson(const ATags: TArray<string>): TJSONArray;
var
  Tag: string;
begin
  Result := TJSONArray.Create;
  for Tag in ATags do
    Result.Add(Tag);
end;

class function TJsonStorage.ChecklistItemsToJson(const AItems: TArray<TChecklistItem>): TJSONArray;
var
  Item: TChecklistItem;
  ItemJson: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Item in AItems do
  begin
    ItemJson := TJSONObject.Create;
    ItemJson.AddPair('text', TJSONString.Create(Item.Text));
    ItemJson.AddPair('done', TJSONBool.Create(Item.Done));
    Result.AddElement(ItemJson);
  end;
end;

class function TJsonStorage.JsonToTags(const AJson: TJSONObject): TArray<string>;
var
  Val: TJSONValue;
  Arr: TJSONArray;
  Elem: TJSONValue;
  List: TArray<string>;
  Count: Integer;
begin
  Result := nil;
  Val := AJson.GetValue('tags');
  if (Val = nil) or not (Val is TJSONArray) then
    Exit;
  Arr := Val as TJSONArray;
  SetLength(List, Arr.Count);
  Count := 0;
  for Elem in Arr do
  begin
    if Elem is TJSONString then
    begin
      List[Count] := Elem.Value;
      Inc(Count);
    end;
    // Non-string elements are skipped rather than aborting the whole load.
  end;
  SetLength(List, Count);
  Result := List;
end;

class function TJsonStorage.JsonToChecklistItems(const AJson: TJSONObject): TArray<TChecklistItem>;
var
  Val, TextVal, DoneVal: TJSONValue;
  Arr: TJSONArray;
  Elem: TJSONValue;
  ItemObj: TJSONObject;
  List: TArray<TChecklistItem>;
  Count: Integer;
  ItemText: string;
  ItemDone: Boolean;
begin
  Result := nil;
  Val := AJson.GetValue('checklistItems');
  if (Val = nil) or not (Val is TJSONArray) then
    Exit;
  Arr := Val as TJSONArray;
  SetLength(List, Arr.Count);
  Count := 0;
  for Elem in Arr do
  begin
    if not (Elem is TJSONObject) then
      Continue; // Malformed element skipped, rest of the checklist still loads.
    ItemObj := Elem as TJSONObject;

    TextVal := ItemObj.GetValue('text');
    if (TextVal <> nil) and (TextVal is TJSONString) then
      ItemText := TextVal.Value
    else
      ItemText := '';

    DoneVal := ItemObj.GetValue('done');
    ItemDone := (DoneVal <> nil) and (DoneVal is TJSONTrue);

    List[Count] := TChecklistItem.Create(ItemText, ItemDone);
    Inc(Count);
  end;
  SetLength(List, Count);
  Result := List;
end;

class function TJsonStorage.JsonToNote(const AJson: TJSONObject): TNote;
var
  Note: TNote;
  ColorInt: Integer;
  CreatedStr, UpdatedStr: string;
  Val: TJSONValue;
  SchemaVal: TJSONValue;
  SchemaVersion: Int64;
  Logger: ILogger;
begin
  if AJson = nil then
    raise Exception.Create('JsonToNote: AJson is nil');

  // --- Schema version inspection -------------------------------------------
  // Missing schemaVersion       -> legacy (unversioned) format, treated as v0
  //                                and read with the legacy field mapping below.
  // schemaVersion = 1           -> v1: no tags/checklistItems, both default empty.
  // schemaVersion = 2           -> v2: adds tags/checklistItems; no favorite.
  // schemaVersion = 3 (current) -> v3: adds favorite (absent -> False).
  // schemaVersion < 0           -> invalid, reject.
  // schemaVersion > current     -> future format, reject safely (never touched).
  // wrong JSON type             -> invalid metadata, reject safely.
  Logger := CreateLogger;
  SchemaVal := AJson.GetValue(SCHEMA_VERSION_FIELD);
  if SchemaVal = nil then
    Logger.Info('JsonToNote: Unversioned (legacy) JSON detected, interpreting as schema version 0')
  else if SchemaVal is TJSONNumber then
  begin
    SchemaVersion := (SchemaVal as TJSONNumber).AsInt64;
    if SchemaVersion < LEGACY_SCHEMA_VERSION then
      raise EJsonSchemaException.CreateFmt(
        'JsonToNote: Invalid schema version %d (negative versions are not supported)', [SchemaVersion]);
    if SchemaVersion > CURRENT_SCHEMA_VERSION then
      raise EJsonSchemaException.CreateFmt(
        'JsonToNote: Unsupported future schema version %d (this build supports up to %d)',
        [SchemaVersion, CURRENT_SCHEMA_VERSION]);
    // Version 0 stored explicitly is handled identically to legacy/unversioned.
    if SchemaVersion = LEGACY_SCHEMA_VERSION then
      Logger.Info('JsonToNote: Legacy schema version 0 detected, using legacy compatibility reader');
  end
  else
    raise EJsonSchemaException.Create(
      'JsonToNote: Invalid schema version metadata (must be an integer)');

  Note := TNote.Create;
  try
    Val := AJson.GetValue('ID');
    if Val = nil then Val := AJson.GetValue('id');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.ID := (Val as TJSONNumber).AsInt64
    else
      Note.ID := 0;

    Val := AJson.GetValue('Title');
    if Val = nil then Val := AJson.GetValue('title');
    if (Val <> nil) then
    begin
      if Val is TJSONString then
        Note.Title := (Val as TJSONString).Value
      else
        Note.Title := Copy(Val.ToString, 2, Length(Val.ToString) - 2);
    end
    else
      Note.Title := '';

    Val := AJson.GetValue('Content');
    if Val = nil then Val := AJson.GetValue('content');
    if (Val <> nil) then
    begin
      if Val is TJSONString then
        Note.Content := (Val as TJSONString).Value
      else
        Note.Content := Copy(Val.ToString, 2, Length(Val.ToString) - 2);
    end
    else
      Note.Content := '';

    Val := AJson.GetValue('Color');
    if Val = nil then Val := AJson.GetValue('color');
    if (Val <> nil) and (Val is TJSONNumber) then
      ColorInt := (Val as TJSONNumber).AsInt
    else
      ColorInt := Ord(ncYellow);
    Note.Color := TNoteColor(ColorInt);

    Val := AJson.GetValue('Left');
    if Val = nil then Val := AJson.GetValue('left');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Left := (Val as TJSONNumber).AsInt
    else
      Note.Left := 100;

    Val := AJson.GetValue('Top');
    if Val = nil then Val := AJson.GetValue('top');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Top := (Val as TJSONNumber).AsInt
    else
      Note.Top := 100;

    Val := AJson.GetValue('Width');
    if Val = nil then Val := AJson.GetValue('width');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Width := (Val as TJSONNumber).AsInt
    else
      Note.Width := 300;

    Val := AJson.GetValue('Height');
    if Val = nil then Val := AJson.GetValue('height');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Height := (Val as TJSONNumber).AsInt
    else
      Note.Height := 250;

    Val := AJson.GetValue('AlwaysOnTop');
    if Val = nil then Val := AJson.GetValue('always_on_top');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.AlwaysOnTop := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.AlwaysOnTop := False
    else
      Note.AlwaysOnTop := False;

    Val := AJson.GetValue('Collapsed');
    if Val = nil then Val := AJson.GetValue('collapsed');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.Collapsed := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.Collapsed := False
    else
      Note.Collapsed := False;

    Val := AJson.GetValue('Locked');
    if Val = nil then Val := AJson.GetValue('locked');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.Locked := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.Locked := False
    else
      Note.Locked := False;

    // Absent on v0/v1/v2 files (and wrong-typed anywhere) -> False,
    // same tolerant policy as the other boolean flags above.
    Val := AJson.GetValue('Favorite');
    if Val = nil then Val := AJson.GetValue('favorite');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.Favorite := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.Favorite := False
    else
      Note.Favorite := False;

    Val := AJson.GetValue('CreatedAt');
    if Val = nil then Val := AJson.GetValue('created_at');
    CreatedStr := '';
    if (Val <> nil) then
    begin
      if Val is TJSONString then
        CreatedStr := (Val as TJSONString).Value
      else
        CreatedStr := Val.Value;
    end;
    if CreatedStr <> '' then
      Note.CreatedAt := StoredISO8601ToDateTime(CreatedStr, Now)
    else
      Note.CreatedAt := Now;

    Val := AJson.GetValue('UpdatedAt');
    if Val = nil then Val := AJson.GetValue('updated_at');
    UpdatedStr := '';
    if (Val <> nil) then
    begin
      if Val is TJSONString then
        UpdatedStr := (Val as TJSONString).Value
      else
        UpdatedStr := Val.Value;
    end;
    if UpdatedStr <> '' then
      Note.UpdatedAt := StoredISO8601ToDateTime(UpdatedStr, Now)
    else
      Note.UpdatedAt := Now;

    // Phase 7A sync identity. Absent on <= v3 files -> defaults (Guid '' is
    // generated on next save; Rev defaults to 1; Deleted defaults to False).
    Val := AJson.GetValue('Guid');
    if Val = nil then Val := AJson.GetValue('guid');
    if Val is TJSONString then
      Note.Guid := (Val as TJSONString).Value
    else
      Note.Guid := '';

    Val := AJson.GetValue('Rev');
    if Val = nil then Val := AJson.GetValue('rev');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Rev := (Val as TJSONNumber).AsInt64
    else
      Note.Rev := 1;

    Val := AJson.GetValue('DeviceId');
    if Val = nil then Val := AJson.GetValue('deviceId');
    if Val is TJSONString then
      Note.DeviceId := (Val as TJSONString).Value
    else
      Note.DeviceId := '';

    Val := AJson.GetValue('Deleted');
    if Val = nil then Val := AJson.GetValue('deleted');
    Note.Deleted := (Val <> nil) and (Val is TJSONTrue);

    Val := AJson.GetValue('DeletedAt');
    if Val = nil then Val := AJson.GetValue('deletedAt');
    if Val is TJSONString then
      Note.DeletedAt := StoredISO8601ToDateTime((Val as TJSONString).Value, 0)
    else
      Note.DeletedAt := 0;

    // Absent on v0/v1 files (and on any malformed v2 field) -> empty arrays,
    // same "default rather than reject" policy as every field above.
    Note.Tags := JsonToTags(AJson);
    Note.ChecklistItems := JsonToChecklistItems(AJson);

    Result := Note;
  except
    Note.Free;
    raise;
  end;
end;

function TJsonStorage.SaveNote(const ANote: TNote): Boolean;
var
  Json: TJSONObject;
  FileName, TmpFileName: string;
  Stream: TFileStream;
  Writer: TStreamWriter;
  TryCount: Integer;
  Logger: ILogger;
begin
  Result := False;
  TryCount := 0;
  Logger := CreateLogger;

  // Phase 7A: stamp sync identity before serialising. Guid is generated once
  // and then preserved across saves; DeviceId records the last writer.
  if ANote.Guid = '' then
    ANote.Guid := GenerateNoteGuid;
  if FDeviceId = '' then
    FDeviceId := GetOrCreateDeviceId(FBasePath);
  ANote.DeviceId := FDeviceId;

  repeat
    TryCount := TryCount + 1;
    EnsureDirectories;
    Json := NoteToJson(ANote);
    try
      FileName := GetNoteFileName(ANote.ID);
      TmpFileName := FileName + '.tmp';
      Stream := TFileStream.Create(TmpFileName, fmCreate or fmShareDenyWrite);
      try
        Writer := TStreamWriter.Create(Stream, TEncoding.UTF8);
        try
          Writer.Write(Json.ToString);
          Writer.Flush;
        finally
          Writer.Free;
        end;
        Stream.Free;
        // Atomic replace: rename temporary file over the destination
        // Use Win32 MoveFileEx with MOVEFILE_REPLACE_EXISTING
        // This atomically replaces the destination if it exists,
        // and leaves the original untouched if the operation fails
        if not MoveFileEx(PChar(TmpFileName), PChar(FileName), MOVEFILE_REPLACE_EXISTING) then
          RaiseLastOSError;
        Logger.Info(Format('SaveNote: Note ID %d saved successfully', [ANote.ID]));
        Result := True;
      except
        on E: Exception do
        begin
          // Clean up temporary file on failure
          if TFile.Exists(TmpFileName) then
            TFile.Delete(TmpFileName);
          Logger.Error(Format('SaveNote: Error saving Note ID %d: %s', [ANote.ID, E.Message]));
          if TryCount >= 3 then
            Result := False
          else
            Sleep(10);
        end;
      end;
    finally
      Json.Free;
    end;
  until Result or (TryCount > 3);
end;

function TJsonStorage.DeleteNote(const ANoteID: Int64): Boolean;
var
  FileName: string;
begin
  Result := False;
  try
    FileName := GetNoteFileName(ANoteID);
    if TFile.Exists(FileName) then
    begin
      TFile.Delete(FileName);
      Result := True;
    end;
  except
    Result := False;
  end;
end;

function TJsonStorage.LoadAllNotes: TObjectList<TNote>;
var
  Files: TStringDynArray;
  FileName: string;
  JsonText: string;
  Json: TJSONObject;
  Note: TNote;
  Logger: ILogger;
begin
  Result := TObjectList<TNote>.Create(True);
  try
    EnsureDirectories;
    Logger := CreateLogger;
    Files := TDirectory.GetFiles(FNotesPath, '*.json');
    for FileName in Files do
    begin
      try
        JsonText := TFile.ReadAllText(FileName, TEncoding.UTF8);
        Json := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
        if Json <> nil then
        try
          Note := JsonToNote(Json);
          Result.Add(Note);
        finally
          Json.Free;
        end
      except
        on E: EJsonSchemaException do
          // Unsupported/invalid schema version: skip and log, but never
          // modify or delete the original file.
          Logger.Warning(Format('LoadAllNotes: Unsupported or invalid schema in file %s (file preserved): %s', [ExtractFileName(FileName), E.Message]));
        on E: Exception do
          Logger.Warning(Format('LoadAllNotes: Corrupted JSON skipped for file %s: %s', [ExtractFileName(FileName), E.Message]));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.