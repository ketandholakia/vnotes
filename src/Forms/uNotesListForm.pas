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
  uNote, uNoteManager, uNoteQuery, System.StrUtils;

type
  TOpenNoteEvent = procedure(ANote: TNote) of object;

  TNotesListForm = class(TForm)
    edSearch: TEdit;
    cbTagFilter: TComboBox;
    lvNotes: TListView;
    btnOpen: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure edSearchChange(Sender: TObject);
    procedure cbTagFilterChange(Sender: TObject);
    procedure lvNotesDblClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
  private
    FNoteManager: TNoteManager;
    FQuery: INoteQuery;
    FResults: TObjectList<TNote>;  // OwnsObjects = False - references only
    FOnOpenNote: TOpenNoteEvent;
    function SelectedTag: string;
    procedure RefreshTagFilter;
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

procedure TNotesListForm.cbTagFilterChange(Sender: TObject);
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

// Phase 6B.2: '' = All Tags, otherwise the exact tag selected in the combo.
// Index 0 is the fixed "All Tags" entry.
function TNotesListForm.SelectedTag: string;
begin
  if (cbTagFilter.ItemIndex > 0) then
    Result := cbTagFilter.Items[cbTagFilter.ItemIndex]
  else
    Result := '';
end;

// Phase 6B.2: rebuild the tag filter options from the query layer's
// DistinctTags. No second tag list is maintained: the combo IS the view.
// The current selection survives refreshes while its tag still exists and
// silently falls back to "All Tags" when the last note using it is gone.
procedure TNotesListForm.RefreshTagFilter;
var
  Source: TObjectList<TNote>;
  Tags: TArray<string>;
  Tag: string;
  Keep: string;
  I: Integer;
begin
  if FNoteManager = nil then
    Exit;

  Keep := SelectedTag;
  Source := TObjectList<TNote>.Create(False);
  try
    for I := 0 to FNoteManager.NoteCount - 1 do
      Source.Add(FNoteManager.Notes[I]);
    Tags := FQuery.DistinctTags(Source);
  finally
    Source.Free;
  end;

  cbTagFilter.OnChange := nil;
  try
    cbTagFilter.Items.BeginUpdate;
    try
      cbTagFilter.Items.Clear;
      cbTagFilter.Items.Add('All Tags');
      for Tag in Tags do
        cbTagFilter.Items.Add(Tag);
      // Restore the previous selection if that tag still exists; otherwise
      // fall back to "All Tags" (last note using a tag gone -> tag gone).
      cbTagFilter.ItemIndex := cbTagFilter.Items.IndexOf(Keep);
      if cbTagFilter.ItemIndex < 0 then
        cbTagFilter.ItemIndex := 0;
    finally
      cbTagFilter.Items.EndUpdate;
    end;
  finally
    cbTagFilter.OnChange := cbTagFilterChange;
  end;
end;

procedure TNotesListForm.RefreshList;
var
  Source: TObjectList<TNote>;
  Results: TObjectList<TNote>;
  TagResults: TObjectList<TNote>;
  Note: TNote;
  Item: TListItem;
  I: Integer;
  Tag: string;
begin
  if (FNoteManager = nil) or (FQuery = nil) then
    Exit;

  // Phase 6B.2: keep the tag filter options in sync with the collection.
  RefreshTagFilter;

  // Snapshot of manager-owned notes: OwnsObjects = False, the manager
  // remains the sole owner throughout.
  Source := TObjectList<TNote>.Create(False);
  try
    for I := 0 to FNoteManager.NoteCount - 1 do
      Source.Add(FNoteManager.Notes[I]);

    // Phase 6B.2: compose tag filter + text search via the query layer.
    // Tag selected -> FilterByTag first, then the existing Search narrows
    // that set. Tag = All -> plain Search, exactly as before. Both paths
    // return query-layer ordered results (UpdatedAt DESC, ID DESC); the UI
    // never re-sorts and never filters by itself.
    Tag := SelectedTag;
    if Tag <> '' then
    begin
      TagResults := FQuery.FilterByTag(Tag, Source);
      try
        Results := FQuery.Search(edSearch.Text, TagResults);
      finally
        TagResults.Free;  // OwnsObjects = False: notes survive
      end;
    end
    else
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

          // Phase 6B.2: tags AND checklist progress render independently -
          // a note carrying both shows both. Phase 6C.2 adds the Favorite
          // star as a fourth subitem. Columns align because every row adds
          // exactly four subitems.
          if Length(Note.Tags) > 0 then
            Item.SubItems.Add(String.Join(', ', Note.Tags))
          else
            Item.SubItems.Add('');
          Item.SubItems.Add(Format('%d/%d',
            [Note.ChecklistDoneCount, Note.ChecklistTotalCount]));
          if Note.Favorite then
            Item.SubItems.Add('★')
          else
            Item.SubItems.Add('');

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