unit uJsonStorage;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.JSON, System.DateUtils, System.Types,
  uStorage, uNote, uEnums, uILogger;

type
  TJsonStorage = class(TInterfacedObject, INoteStorage)
  private
    FBasePath: string;
    FNotesPath: string;
    FSettingsPath: string;
    FNextID: Int64;
    function GetNoteFileName(AID: Int64): string;
    procedure EnsureDirectories;
    function NoteToJson(const ANote: TNote): TJSONObject;
    function JsonToNote(const AJson: TJSONObject): TNote;
  public
    constructor Create(const ABasePath: string);
    destructor Destroy; override;
    function SaveNote(const ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function LoadAllNotes: TObjectList<TNote>;
    function GetNextID: Int64;
    procedure Initialize;
    procedure Finalize;
  end;

implementation

uses
  Winapi.Windows;

function DateTimeToISO8601(const ADateTime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', ADateTime);
end;

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

function TJsonStorage.NoteToJson(const ANote: TNote): TJSONObject;
begin
  Result := TJSONObject.Create;
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
  Result.AddPair('CreatedAt', TJSONString.Create(DateTimeToISO8601(ANote.CreatedAt)));
  Result.AddPair('UpdatedAt', TJSONString.Create(DateTimeToISO8601(ANote.UpdatedAt)));
end;

function TJsonStorage.JsonToNote(const AJson: TJSONObject): TNote;
var
  Note: TNote;
  ColorInt: Integer;
  CreatedStr, UpdatedStr: string;
  Val: TJSONValue;
begin
  if AJson = nil then
    raise Exception.Create('JsonToNote: AJson is nil');

  Note := TNote.Create;
  try
    Val := AJson.GetValue('ID');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.ID := (Val as TJSONNumber).AsInt64
    else
      Note.ID := 0;

    Val := AJson.GetValue('Title');
    if (Val <> nil) then
      Note.Title := Copy(Val.ToString, 2, Length(Val.ToString) - 2)
    else
      Note.Title := '';

    Val := AJson.GetValue('Content');
    if (Val <> nil) then
      Note.Content := Copy(Val.ToString, 2, Length(Val.ToString) - 2)
    else
      Note.Content := '';
      
    Val := AJson.GetValue('Color');
    if (Val <> nil) and (Val is TJSONNumber) then
      ColorInt := (Val as TJSONNumber).AsInt
    else
      ColorInt := Ord(ncYellow);
    Note.Color := TNoteColor(ColorInt);
    
    Val := AJson.GetValue('Left');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Left := (Val as TJSONNumber).AsInt
    else
      Note.Left := 100;
      
    Val := AJson.GetValue('Top');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Top := (Val as TJSONNumber).AsInt
    else
      Note.Top := 100;
      
    Val := AJson.GetValue('Width');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Width := (Val as TJSONNumber).AsInt
    else
      Note.Width := 300;
      
    Val := AJson.GetValue('Height');
    if (Val <> nil) and (Val is TJSONNumber) then
      Note.Height := (Val as TJSONNumber).AsInt
    else
      Note.Height := 250;
      
    Val := AJson.GetValue('AlwaysOnTop');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.AlwaysOnTop := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.AlwaysOnTop := False
    else
      Note.AlwaysOnTop := False;
      
    Val := AJson.GetValue('Collapsed');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.Collapsed := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.Collapsed := False
    else
      Note.Collapsed := False;
      
    Val := AJson.GetValue('Locked');
    if (Val <> nil) and (Val is TJSONTrue) then
      Note.Locked := True
    else if (Val <> nil) and (Val is TJSONFalse) then
      Note.Locked := False
    else
      Note.Locked := False;
      
    Val := AJson.GetValue('CreatedAt');
    CreatedStr := '';
    if (Val <> nil) then
      CreatedStr := Val.Value;
    if CreatedStr <> '' then
      Note.CreatedAt := System.DateUtils.ISO8601ToDate(CreatedStr)
    else
      Note.CreatedAt := Now;
      
    Val := AJson.GetValue('UpdatedAt');
    UpdatedStr := '';
    if (Val <> nil) then
      UpdatedStr := Val.Value;
    if UpdatedStr <> '' then
      Note.UpdatedAt := System.DateUtils.ISO8601ToDate(UpdatedStr)
    else
      Note.UpdatedAt := Now;
      
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
        Logger.Info(Format('SaveNote: Note ID % saved successfully', [ANote.ID]));
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