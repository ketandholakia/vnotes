unit uStorage;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uNote;

const
  // Version of the persisted note payload, shared by every backend:
  //   - JSON writes it per note as `schemaVersion`
  //   - SQLite records it once per database as `PRAGMA user_version`
  // v0 = unversioned legacy; v1 = schemaVersion field; v2 = tags +
  // checklist; v3 = favorite; v4 = sync identity (guid, rev, deviceId,
  // deleted, deletedAt) - current.
  NoteSchemaVersion = 4;

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

implementation

end.
