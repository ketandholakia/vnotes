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
  VirtualTrees, uNote, uNoteManager, uNoteQuery, System.StrUtils, uEnums;

type
  TNodeKind = (nkGroup, nkNote);
  
  PNoteNodeData = ^TNoteNodeData;
  TNoteNodeData = record
    NodeKind: TNodeKind;
    ColorGroup: TNoteColor;
    Note: TNote;
  end;

type
  TOpenNoteEvent = procedure(ANote: TNote) of object;

  TNotesListForm = class(TForm)
    edSearch: TEdit;
    cbTagFilter: TComboBox;
    vstNotes: TVirtualStringTree;
    btnOpen: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure edSearchChange(Sender: TObject);
    procedure cbTagFilterChange(Sender: TObject);
    procedure vstNotesBeforeCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex; CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
    procedure vstNotesDblClick(Sender: TObject);
    procedure vstNotesFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure vstNotesGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure vstNotesGetNodeDataSize(Sender: TBaseVirtualTree; var NodeDataSize: Integer);
    procedure vstNotesInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure btnOpenClick(Sender: TObject);
  private
    FNoteManager: INoteManager;
    FQuery: INoteQuery;
    FResults: TObjectList<TNote>;  // OwnsObjects = False - references only
    FOnOpenNote: TOpenNoteEvent;
    function SelectedTag: string;
    procedure RefreshTagFilter;
    function SelectedNote: TNote;
    procedure OpenSelected;
  public
    constructor CreateFor(AOwner: TComponent; ANoteManager: INoteManager;
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
  ANoteManager: INoteManager; const AQuery: INoteQuery);
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

procedure TNotesListForm.vstNotesDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TNotesListForm.btnOpenClick(Sender: TObject);
begin
  OpenSelected;
end;

function TNotesListForm.SelectedNote: TNote;
var
  Node: PVirtualNode;
  Data: PNoteNodeData;
begin
  Result := nil;
  Node := vstNotes.GetFirstSelected;
  if Assigned(Node) then
  begin
    Data := vstNotes.GetNodeData(Node);
    if Assigned(Data) and (Data^.NodeKind = nkNote) then
      Result := Data^.Note;
  end;
end;

procedure TNotesListForm.vstNotesBeforeCellPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex; CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
var
  Data: PNoteNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  
  if Data^.NodeKind = nkGroup then
  begin
    case Data^.ColorGroup of
      ncYellow: TargetCanvas.Brush.Color := $00E6FFFF; // Light yellow
      ncGreen:  TargetCanvas.Brush.Color := $00E6FFE6; // Light green
      ncBlue:   TargetCanvas.Brush.Color := $00FFE6E6; // Light blue
      ncPink:   TargetCanvas.Brush.Color := $00FFE6FF; // Light pink
      ncPurple: TargetCanvas.Brush.Color := $00FAE6FF; // Light purple
      ncOrange: TargetCanvas.Brush.Color := $00CCE6FF; // Light orange
      ncGray:   TargetCanvas.Brush.Color := $00F0F0F0; // Light gray
    else
      TargetCanvas.Brush.Color := clWindow;
    end;
    TargetCanvas.FillRect(CellRect);
  end;
end;

procedure TNotesListForm.vstNotesFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  // Nothing to free since TNote is managed by TNoteManager
end;

procedure TNotesListForm.vstNotesGetNodeDataSize(Sender: TBaseVirtualTree; var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TNoteNodeData);
end;

procedure TNotesListForm.vstNotesInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
begin
  // Handled manually during AddChild in RefreshList
end;

procedure TNotesListForm.vstNotesGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  Data: PNoteNodeData;
  Note: TNote;
  ColorName: string;
  Emoji: string;
begin
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  
  if Data^.NodeKind = nkGroup then
  begin
    if Column = 0 then
    begin
      case Data^.ColorGroup of
        ncYellow: ColorName := 'Ideas (Yellow)';
        ncGreen:  ColorName := 'Work (Green)';
        ncBlue:   ColorName := 'Personal (Blue)';
        ncPink:   ColorName := 'Urgent (Pink)';
        ncPurple: ColorName := 'Misc (Purple)';
        ncOrange: ColorName := 'Projects (Orange)';
        ncGray:   ColorName := 'Archive (Gray)';
      else
        ColorName := 'Notes';
      end;
      CellText := Format('📁 %s - %d Notes', [ColorName, Sender.ChildCount[Node]]);
    end
    else
      CellText := '';
    Exit;
  end;
  
  Note := Data^.Note;
  if not Assigned(Note) then Exit;
  
  case Column of
    0: CellText := ' 📌';
    1: 
      if Note.Title = '' then
        CellText := '(untitled)'
      else
        CellText := Note.Title;
    2: CellText := FormatDateTime('dd mmm yyyy', Note.UpdatedAt);
    3: 
      if Note.ChecklistTotalCount > 0 then
        CellText := '✅ Checklist'
      else
        CellText := '📝 Memo';
    4:
      if Length(Note.Tags) > 0 then
        CellText := '[' + String.Join(', ', Note.Tags) + ']'
      else
        CellText := '';
    5:
      begin
        case Note.Color of
          ncYellow: Emoji := '🟨';
          ncGreen:  Emoji := '🟩';
          ncBlue:   Emoji := '🟦';
          ncPink:   Emoji := '🟪'; // pink/purple block
          ncPurple: Emoji := '🟪';
          ncOrange: Emoji := '🟧';
          ncGray:   Emoji := '⬛';
          ncWhite:  Emoji := '⬜';
        else
          Emoji := '';
        end;
        CellText := Emoji;
      end;
  end;
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
  I: Integer;
  Tag: string;
  ColorsPresent: TList<TNoteColor>;
  Color: TNoteColor;
  ParentNode, ChildNode: PVirtualNode;
  Data: PNoteNodeData;
begin
  if (FNoteManager = nil) or (FQuery = nil) then
    Exit;

  RefreshTagFilter;

  Source := TObjectList<TNote>.Create(False);
  try
    for I := 0 to FNoteManager.NoteCount - 1 do
      Source.Add(FNoteManager.Notes[I]);

    Tag := SelectedTag;
    if Tag <> '' then
    begin
      TagResults := FQuery.FilterByTag(Tag, Source);
      try
        Results := FQuery.Search(edSearch.Text, TagResults);
      finally
        TagResults.Free;
      end;
    end
    else
      Results := FQuery.Search(edSearch.Text, Source);
      
    try
      FResults.Clear;
      for Note in Results do
        FResults.Add(Note);
        
      vstNotes.BeginUpdate;
      try
        vstNotes.Clear;
        
        ColorsPresent := TList<TNoteColor>.Create;
        try
          for Note in FResults do
            if not ColorsPresent.Contains(Note.Color) then
              ColorsPresent.Add(Note.Color);
              
          for Color in ColorsPresent do
          begin
            ParentNode := vstNotes.AddChild(nil);
            Data := vstNotes.GetNodeData(ParentNode);
            Data^.NodeKind := nkGroup;
            Data^.ColorGroup := Color;
            Data^.Note := nil;
            
            for Note in FResults do
            begin
              if Note.Color = Color then
              begin
                ChildNode := vstNotes.AddChild(ParentNode);
                Data := vstNotes.GetNodeData(ChildNode);
                Data^.NodeKind := nkNote;
                Data^.Note := Note;
              end;
            end;
          end;
        finally
          ColorsPresent.Free;
        end;
        
        vstNotes.FullExpand;
      finally
        vstNotes.EndUpdate;
      end;
    finally
      Results.Free;
    end;
  finally
    Source.Free;
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