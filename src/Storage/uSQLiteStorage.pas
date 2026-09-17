unit uSQLiteStorage;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.DateUtils,
  FireDAC.Comp.Client, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef, FireDAC.Stan.ExprFuncs, FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.VCLUI.Wait, FireDAC.Comp.UI, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet,
  uStorage, uNote, uEnums, uILogger, uIso8601;

type
  TSQLiteStorage = class(TInterfacedObject, INoteStorage)
  private
    FBasePath: string;
    FDatabasePath: string;
    FConnection: TFDConnection;
    FNextID: Int64;
    FLogger: ILogger;
    procedure EnsureDirectories;
    procedure InitDatabaseSchema;
    procedure LoadTagsForNote(const ANote: TNote);
    procedure LoadChecklistForNote(const ANote: TNote);
    procedure SaveTagsForNote(const ANote: TNote);
    procedure SaveChecklistForNote(const ANote: TNote);
  public
    constructor Create(const ABasePath: string);
    destructor Destroy; override;
    function SaveNote(const ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function LoadAllNotes: TObjectList<TNote>;
    function GetNextID: Int64;
    procedure Initialize;
    procedure Finalize;
    procedure BeginTransaction;
    procedure CommitTransaction;
    procedure RollbackTransaction;
    function IsInTransaction: Boolean;
  end;

implementation

{ TSQLiteStorage }

constructor TSQLiteStorage.Create(const ABasePath: string);
begin
  inherited Create;
  FBasePath := ABasePath;
  FDatabasePath := TPath.Combine(FBasePath, 'vnotes.db');
  FNextID := 1;
  FLogger := CreateLogger;
end;

destructor TSQLiteStorage.Destroy;
begin
  Finalize;
  inherited;
end;

procedure TSQLiteStorage.EnsureDirectories;
begin
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
end;

procedure TSQLiteStorage.InitDatabaseSchema;
begin
  if FConnection = nil then Exit;

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS notes (' +
    '  id INTEGER PRIMARY KEY,' +
    '  title TEXT,' +
    '  content TEXT,' +
    '  color INTEGER,' +
    '  left_pos INTEGER,' +
    '  top_pos INTEGER,' +
    '  width INTEGER,' +
    '  height INTEGER,' +
    '  always_on_top INTEGER,' +
    '  collapsed INTEGER,' +
    '  locked INTEGER,' +
    '  favorite INTEGER,' +
    '  created_at TEXT,' +
    '  updated_at TEXT' +
    ');'
  );

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS note_tags (' +
    '  note_id INTEGER,' +
    '  tag_order INTEGER,' +
    '  tag_text TEXT,' +
    '  PRIMARY KEY (note_id, tag_order),' +
    '  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE' +
    ');'
  );

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS note_checklist_items (' +
    '  note_id INTEGER,' +
    '  item_order INTEGER,' +
    '  item_text TEXT,' +
    '  done INTEGER,' +
    '  PRIMARY KEY (note_id, item_order),' +
    '  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE' +
    ');'
  );

  FConnection.ExecSQL('PRAGMA user_version = 1;');
end;

procedure TSQLiteStorage.Initialize;
var
  Query: TFDQuery;
begin
  EnsureDirectories;
  if FConnection = nil then
  begin
    FConnection := TFDConnection.Create(nil);
    FConnection.DriverName := 'SQLite';
    FConnection.Params.Values['Database'] := FDatabasePath;
    FConnection.Params.Values['OpenMode'] := 'ReadWriteCreate';
    FConnection.Params.Values['LockingMode'] := 'Normal';
    FConnection.Params.Values['ForeignKeys'] := 'On';
    FConnection.Params.Values['Pooled'] := 'False';
    FConnection.Open;

    InitDatabaseSchema;
  end;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT COALESCE(MAX(id), 0) + 1 FROM notes';
    Query.Open;
    FNextID := Query.Fields[0].AsLargeInt;
    if FNextID < 1 then
      FNextID := 1;
  finally
    Query.Free;
  end;
end;

procedure TSQLiteStorage.Finalize;
begin
  if FConnection <> nil then
  begin
    if FConnection.Connected then
      FConnection.Close;
    FreeAndNil(FConnection);
  end;
end;

function TSQLiteStorage.GetNextID: Int64;
begin
  Result := FNextID;
  Inc(FNextID);
end;

procedure TSQLiteStorage.LoadTagsForNote(const ANote: TNote);
var
  Query: TFDQuery;
  TagsList: TList<string>;
begin
  Query := TFDQuery.Create(nil);
  TagsList := TList<string>.Create;
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT tag_text FROM note_tags WHERE note_id = :id ORDER BY tag_order ASC';
    Query.ParamByName('id').AsLargeInt := ANote.ID;
    Query.Open;
    while not Query.Eof do
    begin
      TagsList.Add(Query.Fields[0].AsString);
      Query.Next;
    end;
    ANote.Tags := TagsList.ToArray;
  finally
    TagsList.Free;
    Query.Free;
  end;
end;

procedure TSQLiteStorage.LoadChecklistForNote(const ANote: TNote);
var
  Query: TFDQuery;
  ItemsList: TList<TChecklistItem>;
  ItemText: string;
  ItemDone: Boolean;
begin
  Query := TFDQuery.Create(nil);
  ItemsList := TList<TChecklistItem>.Create;
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT item_text, done FROM note_checklist_items WHERE note_id = :id ORDER BY item_order ASC';
    Query.ParamByName('id').AsLargeInt := ANote.ID;
    Query.Open;
    while not Query.Eof do
    begin
      ItemText := Query.FieldByName('item_text').AsString;
      ItemDone := Query.FieldByName('done').AsInteger <> 0;
      ItemsList.Add(TChecklistItem.Create(ItemText, ItemDone));
      Query.Next;
    end;
    ANote.ChecklistItems := ItemsList.ToArray;
  finally
    ItemsList.Free;
    Query.Free;
  end;
end;

function TSQLiteStorage.LoadAllNotes: TObjectList<TNote>;
var
  Query: TFDQuery;
  Note: TNote;
begin
  Result := TObjectList<TNote>.Create(True);
  if FConnection = nil then
    Initialize;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT * FROM notes ORDER BY id ASC';
    Query.Open;
    while not Query.Eof do
    begin
      Note := TNote.Create;
      try
        Note.ID := Query.FieldByName('id').AsLargeInt;
        Note.Title := Query.FieldByName('title').AsString;
        Note.Content := Query.FieldByName('content').AsString;
        Note.Color := TNoteColor(Query.FieldByName('color').AsInteger);
        Note.Left := Query.FieldByName('left_pos').AsInteger;
        Note.Top := Query.FieldByName('top_pos').AsInteger;
        Note.Width := Query.FieldByName('width').AsInteger;
        Note.Height := Query.FieldByName('height').AsInteger;
        Note.AlwaysOnTop := Query.FieldByName('always_on_top').AsInteger <> 0;
        Note.Collapsed := Query.FieldByName('collapsed').AsInteger <> 0;
        Note.Locked := Query.FieldByName('locked').AsInteger <> 0;
        Note.Favorite := Query.FieldByName('favorite').AsInteger <> 0;
        // Tolerant read: legacy rows hold offset-less local wall-clock, current
        // rows hold an explicit offset (CODE_REVIEW_2026-09-17 C1).
        Note.CreatedAt := StoredISO8601ToDateTime(Query.FieldByName('created_at').AsString, Now);
        Note.UpdatedAt := StoredISO8601ToDateTime(Query.FieldByName('updated_at').AsString, Now);

        LoadTagsForNote(Note);
        LoadChecklistForNote(Note);

        Result.Add(Note);
      except
        Note.Free;
        raise;
      end;
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

procedure TSQLiteStorage.SaveTagsForNote(const ANote: TNote);
var
  Query: TFDQuery;
  I: Integer;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'DELETE FROM note_tags WHERE note_id = :id';
    Query.ParamByName('id').AsLargeInt := ANote.ID;
    Query.ExecSQL;

    if Length(ANote.Tags) > 0 then
    begin
      Query.SQL.Text := 'INSERT INTO note_tags (note_id, tag_order, tag_text) VALUES (:id, :order, :text)';
      for I := 0 to High(ANote.Tags) do
      begin
        Query.ParamByName('id').AsLargeInt := ANote.ID;
        Query.ParamByName('order').AsInteger := I;
        Query.ParamByName('text').AsString := ANote.Tags[I];
        Query.ExecSQL;
      end;
    end;
  finally
    Query.Free;
  end;
end;

procedure TSQLiteStorage.SaveChecklistForNote(const ANote: TNote);
var
  Query: TFDQuery;
  I: Integer;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'DELETE FROM note_checklist_items WHERE note_id = :id';
    Query.ParamByName('id').AsLargeInt := ANote.ID;
    Query.ExecSQL;

    if Length(ANote.ChecklistItems) > 0 then
    begin
      Query.SQL.Text := 'INSERT INTO note_checklist_items (note_id, item_order, item_text, done) VALUES (:id, :order, :text, :done)';
      for I := 0 to High(ANote.ChecklistItems) do
      begin
        Query.ParamByName('id').AsLargeInt := ANote.ID;
        Query.ParamByName('order').AsInteger := I;
        Query.ParamByName('text').AsString := ANote.ChecklistItems[I].Text;
        Query.ParamByName('done').AsInteger := Ord(ANote.ChecklistItems[I].Done);
        Query.ExecSQL;
      end;
    end;
  finally
    Query.Free;
  end;
end;

procedure TSQLiteStorage.BeginTransaction;
begin
  if FConnection = nil then Initialize;
  if not FConnection.InTransaction then
    FConnection.StartTransaction;
end;

procedure TSQLiteStorage.CommitTransaction;
begin
  if (FConnection <> nil) and FConnection.InTransaction then
    FConnection.Commit;
end;

procedure TSQLiteStorage.RollbackTransaction;
begin
  if (FConnection <> nil) and FConnection.InTransaction then
    FConnection.Rollback;
end;

function TSQLiteStorage.IsInTransaction: Boolean;
begin
  Result := (FConnection <> nil) and FConnection.InTransaction;
end;

function TSQLiteStorage.SaveNote(const ANote: TNote): Boolean;
var
  Query: TFDQuery;
  WillCommit: Boolean;
begin
  Result := False;
  if ANote = nil then Exit;
  if FConnection = nil then Initialize;

  WillCommit := not FConnection.InTransaction;
  if WillCommit then
    FConnection.StartTransaction;
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'INSERT INTO notes (' +
        '  id, title, content, color, left_pos, top_pos, width, height, ' +
        '  always_on_top, collapsed, locked, favorite, created_at, updated_at' +
        ') VALUES (' +
        '  :id, :title, :content, :color, :left_pos, :top_pos, :width, :height, ' +
        '  :always_on_top, :collapsed, :locked, :favorite, :created_at, :updated_at' +
        ') ON CONFLICT(id) DO UPDATE SET ' +
        '  title = excluded.title, ' +
        '  content = excluded.content, ' +
        '  color = excluded.color, ' +
        '  left_pos = excluded.left_pos, ' +
        '  top_pos = excluded.top_pos, ' +
        '  width = excluded.width, ' +
        '  height = excluded.height, ' +
        '  always_on_top = excluded.always_on_top, ' +
        '  collapsed = excluded.collapsed, ' +
        '  locked = excluded.locked, ' +
        '  favorite = excluded.favorite, ' +
        '  created_at = excluded.created_at, ' +
        '  updated_at = excluded.updated_at';

      Query.ParamByName('id').AsLargeInt := ANote.ID;
      Query.ParamByName('title').AsString := ANote.Title;
      Query.ParamByName('content').AsString := ANote.Content;
      Query.ParamByName('color').AsInteger := Ord(ANote.Color);
      Query.ParamByName('left_pos').AsInteger := ANote.Left;
      Query.ParamByName('top_pos').AsInteger := ANote.Top;
      Query.ParamByName('width').AsInteger := ANote.Width;
      Query.ParamByName('height').AsInteger := ANote.Height;
      Query.ParamByName('always_on_top').AsInteger := Ord(ANote.AlwaysOnTop);
      Query.ParamByName('collapsed').AsInteger := Ord(ANote.Collapsed);
      Query.ParamByName('locked').AsInteger := Ord(ANote.Locked);
      Query.ParamByName('favorite').AsInteger := Ord(ANote.Favorite);
      Query.ParamByName('created_at').AsString := DateTimeToStoredISO8601(ANote.CreatedAt);
      Query.ParamByName('updated_at').AsString := DateTimeToStoredISO8601(ANote.UpdatedAt);

      Query.ExecSQL;

      SaveTagsForNote(ANote);
      SaveChecklistForNote(ANote);

      if ANote.ID >= FNextID then
        FNextID := ANote.ID + 1;
    finally
      Query.Free;
    end;

    if WillCommit then
      FConnection.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      if WillCommit and FConnection.InTransaction then
        FConnection.Rollback;
      FLogger.Error('TSQLiteStorage.SaveNote failed for ID ' + IntToStr(ANote.ID) + ': ' + E.Message);
      Result := False;
    end;
  end;
end;

function TSQLiteStorage.DeleteNote(const ANoteID: Int64): Boolean;
var
  Query: TFDQuery;
  WillCommit: Boolean;
begin
  if FConnection = nil then Initialize;

  WillCommit := not FConnection.InTransaction;
  if WillCommit then
    FConnection.StartTransaction;
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text := 'DELETE FROM notes WHERE id = :id';
      Query.ParamByName('id').AsLargeInt := ANoteID;
      Query.ExecSQL;
    finally
      Query.Free;
    end;

    if WillCommit then
      FConnection.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      if WillCommit and FConnection.InTransaction then
        FConnection.Rollback;
      FLogger.Error('TSQLiteStorage.DeleteNote failed for ID ' + IntToStr(ANoteID) + ': ' + E.Message);
      Result := False;
    end;
  end;
end;

end.