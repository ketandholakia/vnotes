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

implementation

end.
