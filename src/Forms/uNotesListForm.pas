unit uNotesListForm;
{
  Phase 4B - note list + in-memory search window.

  Ownership contract:
  - This form does NOT own TNote objects. TNoteManager is the single owner.
  - FResults and the temporary lists inside RefreshList hold references only
    and are always created with OwnsObjects := False.
  - ListView items keep a TNote pointer in .Data for selection/display only.
  - Closing the form hides it (caHide); it never frees notes.
  - Search runs purely in memory via INoteQuery: it never saves, mutates or
    reorders the underlying notes, and never touches persistence.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls,
  uNote, uNoteManager, uNoteQuery;

type
  TOpenNoteEvent = procedure(ANote: TNote) of object;

  TNotesListForm = class(TForm)
    edSearch: TEdit;
    lvNotes: TListView;
    btnOpen: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure edSearchChange(Sender: TObject);
    procedure lvNotesDblClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
  private
    FNoteManager: TNoteManager;
    FQuery: INoteQuery;
    FResults: TObjectList<TNote>;  // OwnsObjects = False - references only
    FOnOpenNote: TOpenNoteEvent;
    function SelectedNote: TNote;
    procedure OpenSelected;
  public
    constructor CreateFor(AOwner: TComponent; ANoteManager: TNoteManager;
      const AQuery: INoteQuery);
    // Re-runs the current search against the note manager's notes.
    // Public so TTrayForm can resync the (open) list on note create/delete.
    procedure RefreshList;
    // Focus + select-all the search edit (used by the Ctrl+Alt+F hotkey).
    procedure FocusSearch;
    property OnOpenNote: TOpenNoteEvent read FOnOpenNote write FOnOpenNote;
  end;

var
  NotesListForm: TNotesListForm;

implementation

{$R *.dfm}

{ TNotesListForm }

constructor TNotesListForm.CreateFor(AOwner: TComponent;
  ANoteManager: TNoteManager; const AQuery: INoteQuery);
begin
  // inherited Create loads the dfm and fires FormCreate; the manager/query
  // fields are assigned afterwards, before RefreshList is ever called.
  inherited Create(AOwner);
  FNoteManager := ANoteManager;
  FQuery := AQuery;
end;

procedure TNotesListForm.FormCreate(Sender: TObject);
begin
  // References only - the notes stay owned by TNoteManager.
  FResults := TObjectList<TNote>.Create(False);
end;

procedure TNotesListForm.FormDestroy(Sender: TObject);
begin
  FResults.Free;  // OwnsObjects = False: this never frees any TNote
end;

procedure TNotesListForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Hide instead of freeing: the form is owned by TTrayForm and reused.
  Action := caHide;
end;

procedure TNotesListForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    Close
  else if Key = VK_RETURN then
    OpenSelected;
end;

procedure TNotesListForm.edSearchChange(Sender: TObject);
begin
  RefreshList;
end;

procedure TNotesListForm.lvNotesDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TNotesListForm.btnOpenClick(Sender: TObject);
begin
  OpenSelected;
end;

function TNotesListForm.SelectedNote: TNote;
begin
  if lvNotes.Selected <> nil then
    Result := TNote(lvNotes.Selected.Data)
  else
    Result := nil;
end;

procedure TNotesListForm.OpenSelected;
var
  Note: TNote;
begin
  Note := SelectedNote;
  if (Note <> nil) and Assigned(FOnOpenNote) then
    FOnOpenNote(Note);  // receiver (TTrayForm) owns the note + form lifecycle
end;

procedure TNotesListForm.RefreshList;
var
  Source: TObjectList<TNote>;
  Results: TObjectList<TNote>;
  Note: TNote;
  Item: TListItem;
  I: Integer;
begin
  if (FNoteManager = nil) or (FQuery = nil) then
    Exit;

  // Snapshot of manager-owned notes: OwnsObjects = False, the manager
  // remains the sole owner throughout.
  Source := TObjectList<TNote>.Create(False);
  try
    for I := 0 to FNoteManager.NoteCount - 1 do
      Source.Add(FNoteManager.Notes[I]);

    Results := FQuery.Search(edSearch.Text, Source);
    try
      FResults.Clear;
      lvNotes.Items.BeginUpdate;
      try
        lvNotes.Items.Clear;
        for Note in Results do
        begin
          FResults.Add(Note);
          Item := lvNotes.Items.Add;
          if Note.Title = '' then
            Item.Caption := '(untitled)'
          else
            Item.Caption := Note.Title;
          Item.SubItems.Add(FormatDateTime('yyyy-mm-dd hh:nn', Note.UpdatedAt));
          Item.Data := Pointer(Note);  // display-only reference, NOT owned
        end;
      finally
        lvNotes.Items.EndUpdate;
      end;
    finally
      Results.Free;  // OwnsObjects = False: notes survive
    end;
  finally
    Source.Free;     // OwnsObjects = False: notes survive
  end;
end;

procedure TNotesListForm.FocusSearch;
begin
  if edSearch.CanFocus then
  begin
    edSearch.SetFocus;
    edSearch.SelectAll;
  end;
end;

end.