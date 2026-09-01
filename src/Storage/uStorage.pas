unit uStorage;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uNote;

type
  INoteStorage = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function SaveNote(const ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function LoadAllNotes: TObjectList<TNote>;
    function GetNextID: Int64;
    procedure Initialize;
    procedure Finalize;
  end;

  TStorageFactory = class
  public
    class function CreateStorage(const AStorageType: string; const ABasePath: string): INoteStorage;
  end;

implementation

uses
  uJsonStorage, uSQLiteStorage;

{ TStorageFactory }

class function TStorageFactory.CreateStorage(const AStorageType: string; const ABasePath: string): INoteStorage;
begin
  if SameText(AStorageType, 'JSON') then
    Result := TJsonStorage.Create(ABasePath)
  else if SameText(AStorageType, 'SQLITE') then
    Result := TSQLiteStorage.Create(ABasePath)
  else
    Result := TJsonStorage.Create(ABasePath); // Default to JSON
end;

end.