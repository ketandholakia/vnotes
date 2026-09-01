unit uSQLiteStorage;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  uStorage, uNote;

type
  TSQLiteStorage = class(TInterfacedObject, INoteStorage)
  private
    FBasePath: string;
    FDatabasePath: string;
    FConnection: TObject; // TFDConnection placeholder
    FNextID: Int64;
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

{ TSQLiteStorage }

constructor TSQLiteStorage.Create(const ABasePath: string);
begin
  inherited Create;
  FBasePath := ABasePath;
  FDatabasePath := System.IOUtils.TPath.Combine(FBasePath, 'notes.db');
  FNextID := 1;
end;

destructor TSQLiteStorage.Destroy;
begin
  Finalize;
  inherited;
end;

procedure TSQLiteStorage.Initialize;
begin
  // TODO: Initialize SQLite database
  // Create tables if not exist:
  // CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, content TEXT, color INTEGER,
  //   left INTEGER, top INTEGER, width INTEGER, height INTEGER,
  //   always_on_top INTEGER, collapsed INTEGER, locked INTEGER,
  //   created_at TEXT, updated_at TEXT);
  // CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
  // SELECT MAX(id) + 1 FROM notes for FNextID
end;

procedure TSQLiteStorage.Finalize;
begin
  // TODO: Close database connection
end;

function TSQLiteStorage.GetNextID: Int64;
begin
  Result := FNextID;
  Inc(FNextID);
end;

function TSQLiteStorage.SaveNote(const ANote: TNote): Boolean;
begin
  // TODO: INSERT OR REPLACE INTO notes ...
  Result := False;
end;

function TSQLiteStorage.DeleteNote(const ANoteID: Int64): Boolean;
begin
  // TODO: DELETE FROM notes WHERE id = ?
  Result := False;
end;

function TSQLiteStorage.LoadAllNotes: TObjectList<TNote>;
begin
  // TODO: SELECT * FROM notes
  Result := TObjectList<TNote>.Create(True);
end;

end.