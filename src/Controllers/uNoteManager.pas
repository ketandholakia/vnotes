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
    // Optional geometry/on-top parameters exist so the note is FULLY
    // initialized before OnNoteCreated fires (the event fires synchronously
    // inside this method, and TTrayForm creates the note window there).
    // Defaults mirror TNote.Create so existing 3-argument callers are
    // unchanged. Callers pass user settings here; the manager stays
    // settings-agnostic.
    function CreateNote(const ATitle, AContent: string; AColor: TNoteColor = ncYellow;
      ALeft: Integer = 100; ATop: Integer = 100; AWidth: Integer = 300;
      AHeight: Integer = 250; AAlwaysOnTop: Boolean = False): TNote;
    function AddNote(ANote: TNote): Boolean;
    function DeleteNote(const ANoteID: Int64): Boolean;
    function FindByID(const ANoteID: Int64): TNote;
    function FindByIndex(const AIndex: Integer): TNote;
    procedure SaveNote(const ANote: TNote);
    // Write-through to storage without Touch. Used by SaveNote (after
    // Touch) and by CreateNote/AddNote so created, imported and restored
    // notes keep their original timestamps; also public for geometry-only
    // persistence (window arrange) that must not bump UpdatedAt.
    procedure PersistNote(const ANote: TNote);
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

function TNoteManager.CreateNote(const ATitle, AContent: string; AColor: TNoteColor;
  ALeft, ATop, AWidth, AHeight: Integer; AAlwaysOnTop: Boolean): TNote;
begin
  Result := TNote.Create(FStorage.GetNextID, ATitle, AContent, AColor);
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.AlwaysOnTop := AAlwaysOnTop;
  FNotes.Add(Result);
  PersistNote(Result);
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
  // Persists via storage and fires OnNoteChanged; PersistNote (not SaveNote)
  // so an imported/restored note keeps its original UpdatedAt.
  PersistNote(ANote);
  if Assigned(FOnNoteCreated) then
    FOnNoteCreated(ANote);
  Result := True;
end;

function TNoteManager.DeleteNote(const ANoteID: Int64): Boolean;
var
  Note: TNote;
begin
  Result := False;
  Note := FindByID(ANoteID);
  if Note = nil then Exit;

  if FStorage.DeleteNote(ANoteID) then
  begin
    // Take the note out of the owned list WITHOUT freeing it yet (Extract
    // transfers the object out; Delete would free it), so OnNoteDeleted
    // handlers still receive a valid object - TTrayForm closes the note
    // window from inside this event. The old order (notify first, remove
    // after) let the closing window's FormClose save the note straight
    // back into storage, resurrecting the just-deleted note.
    FNotes.Extract(Note);
    try
      if Assigned(FOnNoteDeleted) then
        FOnNoteDeleted(Note);
    finally
      Note.Free;
    end;
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
  // Membership guard: never persist a note the manager no longer owns.
  // This is what stops a closing note window (FormClose saves
  // unconditionally) from resurrecting a note that was just deleted; it
  // also makes a late autosave of a deleted note a harmless no-op.
  if (ANote = nil) or (FNotes.IndexOf(ANote) < 0) then
    Exit;

  // Touch BEFORE persisting so the stored UpdatedAt is the timestamp of
  // this save; the old order (save, then Touch) wrote the previous save's
  // timestamp to disk, so memory and storage disagreed between saves.
  ANote.Touch;

  PersistNote(ANote);
end;

procedure TNoteManager.PersistNote(const ANote: TNote);
begin
  if FStorage.SaveNote(ANote) then
  begin
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