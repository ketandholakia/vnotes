unit uNoteManager;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uNote, uStorage, uEnums;

type
  TNoteEvent = procedure(const ANote: TNote) of object;

  TNoteManager = class
  private
    FStorage: INoteStorage;
    FNotes: TObjectList<TNote>;
    FOnNoteCreated: TNoteEvent;
    FOnNoteChanged: TNoteEvent;
    FOnNoteDeleted: TNoteEvent;
    function GetNoteCount: Integer;
    function GetNote(Index: Integer): TNote;
  public
    constructor Create(const AStorage: INoteStorage);
    destructor Destroy; override;
    procedure Initialize;
    procedure Finalize;
    function CreateNote(const ATitle, AContent: string; AColor: TNoteColor = ncYellow): TNote;
    function AddNote(ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function FindByID(const ANoteID: Int64): TNote;
    function FindByIndex(const AIndex: Integer): TNote;
    procedure SaveNote(const ANote: TNote);
    procedure LoadNotes;
    procedure OpenAllNotes;
    procedure CloseAllNotes;
    property NoteCount: Integer read GetNoteCount;
    property Notes[Index: Integer]: TNote read GetNote; default;
    property OnNoteCreated: TNoteEvent read FOnNoteCreated write FOnNoteCreated;
    property OnNoteChanged: TNoteEvent read FOnNoteChanged write FOnNoteChanged;
    property OnNoteDeleted: TNoteEvent read FOnNoteDeleted write FOnNoteDeleted;
  end;

implementation

{ TNoteManager }

constructor TNoteManager.Create(const AStorage: INoteStorage);
begin
  inherited Create;
  FStorage := AStorage;
  FNotes := TObjectList<TNote>.Create(True);
end;

destructor TNoteManager.Destroy;
begin
  Finalize;
  FNotes.Free;
  inherited;
end;

procedure TNoteManager.Initialize;
begin
  FStorage.Initialize;
  LoadNotes;
end;

procedure TNoteManager.Finalize;
begin
  FStorage.Finalize;
  FNotes.Clear;
end;

function TNoteManager.GetNoteCount: Integer;
begin
  Result := FNotes.Count;
end;

function TNoteManager.GetNote(Index: Integer): TNote;
begin
  if (Index >= 0) and (Index < FNotes.Count) then
    Result := FNotes[Index]
  else
    Result := nil;
end;

function TNoteManager.CreateNote(const ATitle, AContent: string; AColor: TNoteColor = ncYellow): TNote;
begin
  Result := TNote.Create(FStorage.GetNextID, ATitle, AContent, AColor);
  FNotes.Add(Result);
  SaveNote(Result);
  if Assigned(FOnNoteCreated) then
    FOnNoteCreated(Result);
end;

function TNoteManager.AddNote(ANote: TNote): Boolean;
begin
  // Public way to import/restore an existing TNote instance without callers
  // reaching into the private FNotes list directly (e.g. from TBackupService).
  Result := False;
  if ANote = nil then Exit;
  if FindByID(ANote.ID) <> nil then Exit; // already present, caller should free it

  FNotes.Add(ANote);
  SaveNote(ANote); // persists via storage and fires OnNoteChanged
  if Assigned(FOnNoteCreated) then
    FOnNoteCreated(ANote);
  Result := True;
end;

function TNoteManager.DeleteNote(const ANoteID: Int64): Boolean;
var
  Note: TNote;
  Index: Integer;
begin
  Result := False;
  Note := FindByID(ANoteID);
  if Note = nil then Exit;
  
  Index := FNotes.IndexOf(Note);
  if Index < 0 then Exit;
  
  if FStorage.DeleteNote(ANoteID) then
  begin
    FNotes.Delete(Index);
    if Assigned(FOnNoteDeleted) then
      FOnNoteDeleted(Note);
    Result := True;
  end;
end;

function TNoteManager.FindByID(const ANoteID: Int64): TNote;
var
  Note: TNote;
begin
  Result := nil;
  for Note in FNotes do
    if Note.ID = ANoteID then
      Exit(Note);
end;

function TNoteManager.FindByIndex(const AIndex: Integer): TNote;
begin
  if (AIndex >= 0) and (AIndex < FNotes.Count) then
    Result := FNotes[AIndex]
  else
    Result := nil;
end;

procedure TNoteManager.SaveNote(const ANote: TNote);
begin
  if FStorage.SaveNote(ANote) then
  begin
    ANote.Touch;
    if Assigned(FOnNoteChanged) then
      FOnNoteChanged(ANote);
  end;
end;

procedure TNoteManager.LoadNotes;
var
  LoadedNotes: TObjectList<TNote>;
  Note: TNote;
begin
  FNotes.Clear;
  LoadedNotes := FStorage.LoadAllNotes;
  try
    for Note in LoadedNotes do
      FNotes.Add(Note);
    LoadedNotes.OwnsObjects := False; // Don't free notes, we own them now
  finally
    LoadedNotes.Free;
  end;
end;

procedure TNoteManager.OpenAllNotes;
var
  Note: TNote;
begin
  // This will be implemented when forms are created
  // For now, just a placeholder for the controller to use
  for Note in FNotes do
  begin
    // Open note form for each note
  end;
end;

procedure TNoteManager.CloseAllNotes;
begin
  // Close all open note forms
  // Implemented in controller
end;

end.