unit uNoteChecklistPanel;

{
  TNoteChecklistPanel
  ===================
  Scrollable checklist panel with inline editing and strike-through on done items.

  Replaces pnlChecklist, pnlChecklistItems, pnlAddChecklist, edAddChecklist,
  btnAddChecklist, and all the RefreshChecklistPanel / ChecklistItemToggle /
  ChecklistItemTextChange helpers in uNoteForm.

  Each row is a TNoteChecklistRow:
    [drawn checkbox] [TEdit for item text]
  Rows update in-place on toggle or text-change (no full rebuild).
  The Add-item edit is pinned at the bottom of the panel.

  Usage
  -----
    FChecklist := TNoteChecklistPanel.CreatePanel(Self);
    FChecklist.Parent  := Self;
    FChecklist.Align   := alClient;
    FChecklist.Locked  := FNote.Locked;
    FChecklist.SetItems(FNote.ChecklistItems);
    FChecklist.OnItemToggled      := ChecklistToggled;
    FChecklist.OnItemTextChanged  := ChecklistTextChanged;
    FChecklist.OnItemAdded        := ChecklistItemAdded;
    FChecklist.OnItemRemoved      := ChecklistItemRemoved;
    FChecklist.BackColor := myContentColor;
    FChecklist.TextColor := clBlack;
}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Types,
  Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls, Vcl.Forms, Vcl.ExtCtrls,
  uNote;

const
  CL_CHECK_SIZE   = 16;
  CL_ROW_HEIGHT   = 26;
  CL_CHECK_MARGIN = 4;
  CL_ADD_ROW_H    = 26;
  CL_SIDE_MARGIN  = 8;
  CL_MIN_EDIT_W   = 24;

type
  TChecklistItemEvent   = procedure(Sender: TObject; Index: Integer) of object;
  TChecklistToggleEvent = procedure(Sender: TObject; Index: Integer; Done: Boolean) of object;
  TChecklistTextEvent   = procedure(Sender: TObject; Index: Integer; const Text: string) of object;
  TChecklistAddEvent    = procedure(Sender: TObject; const Text: string) of object;

  TNoteChecklistPanel = class;

  TNoteChecklistRow = class(TCustomControl)
  private
    FIndex:      Integer;
    FDone:       Boolean;
    FText:       string;
    FLocked:     Boolean;
    FBackColor:  TColor;
    FTextColor:  TColor;
    FCheckColor: TColor;
    FDoneColor:  TColor;
    FHotCheck:   Boolean;

    FEdit:       TEdit;
    FOwnerPanel: TNoteChecklistPanel;

    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function  CheckBoxRect: TRect;

  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMRelease(var Message: TMessage); message CM_RELEASE;

  public
    constructor CreateRow(AOwner: TNoteChecklistPanel; AIndex: Integer;
                          const AText: string; ADone: Boolean;
                          ABackColor, ATextColor, ACheckColor, ADoneColor: TColor);
    procedure UpdateRow(AIndex: Integer; const AText: string; ADone: Boolean);
    procedure ApplyColors(ABack, AText, ACheck, ADone: TColor);
    procedure SetLocked(Value: Boolean);

    property RowIndex: Integer read FIndex;
    property Done:     Boolean read FDone;
    property RowText:  string  read FText;
  end;

  TNoteChecklistPanel = class(TScrollingWinControl)
  private
    FRows:     TArray<TNoteChecklistRow>;
    FAddEdit:  TEdit;
    FLocked:   Boolean;

    FBackColor:  TColor;
    FTextColor:  TColor;
    FCheckColor: TColor;
    FDoneColor:  TColor;

    FOnItemToggled:     TChecklistToggleEvent;
    FOnItemTextChanged: TChecklistTextEvent;
    FOnItemAdded:       TChecklistAddEvent;
    FOnItemRemoved:     TChecklistItemEvent;

    procedure AddEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CommitAddEdit;
    procedure RebuildLayout;
    procedure SetLocked(Value: Boolean);

  public
    procedure RowToggled(ARow: TNoteChecklistRow);
    procedure RowTextChanged(ARow: TNoteChecklistRow; const AText: string);
    procedure RemoveRow(AIndex: Integer);

  public
    constructor CreatePanel(AOwner: TComponent);

    procedure SetItems(const AItems: TArray<TChecklistItem>);
    function  ItemCount: Integer;

    property Locked:     Boolean read FLocked     write SetLocked;
    property BackColor:  TColor  read FBackColor   write FBackColor;
    property TextColor:  TColor  read FTextColor   write FTextColor;
    property CheckColor: TColor  read FCheckColor  write FCheckColor;
    property DoneColor:  TColor  read FDoneColor   write FDoneColor;

    property OnItemToggled:     TChecklistToggleEvent read FOnItemToggled     write FOnItemToggled;
    property OnItemTextChanged: TChecklistTextEvent   read FOnItemTextChanged write FOnItemTextChanged;
    property OnItemAdded:       TChecklistAddEvent    read FOnItemAdded       write FOnItemAdded;
    property OnItemRemoved:     TChecklistItemEvent   read FOnItemRemoved     write FOnItemRemoved;
  end;

implementation

{ TNoteChecklistRow }

constructor TNoteChecklistRow.CreateRow(AOwner: TNoteChecklistPanel; AIndex: Integer;
                                        const AText: string; ADone: Boolean;
                                        ABackColor, ATextColor, ACheckColor, ADoneColor: TColor);
begin
  inherited Create(AOwner);
  FOwnerPanel := AOwner;
  FIndex      := AIndex;
  FDone       := ADone;
  FText       := AText;
  FLocked     := False;
  FBackColor  := ABackColor;
  FTextColor  := ATextColor;
  FCheckColor := ACheckColor;
  FDoneColor  := ADoneColor;
  FHotCheck   := False;

  Parent         := AOwner;
  Height         := CL_ROW_HEIGHT;
  Align          := alTop;
  DoubleBuffered := True;
  Color          := ABackColor;

  FEdit              := TEdit.Create(Self);
  FEdit.Parent       := Self;
  FEdit.BorderStyle  := bsNone;
  FEdit.Text         := AText;
  FEdit.Font.Name    := 'Segoe UI';
  FEdit.Font.Size    := 9;
  FEdit.Left         := CL_CHECK_SIZE + CL_CHECK_MARGIN * 2;
  FEdit.Top          := (CL_ROW_HEIGHT - FEdit.Height) div 2;
  // Width is maintained in Resize; the akRight anchor is deliberately NOT
  // used: its rule is captured against the row's default creation width,
  // which made the edit overhang the row permanently (review 2026-09-10 H2).
  FEdit.Width        := Max(CL_MIN_EDIT_W, ClientWidth - FEdit.Left - CL_SIDE_MARGIN);
  FEdit.Color        := ABackColor;
  FEdit.Font.Color   := ATextColor;
  FEdit.OnChange     := EditChange;
  FEdit.OnKeyDown    := EditKeyDown;
  FEdit.ReadOnly     := False;
end;

procedure TNoteChecklistRow.UpdateRow(AIndex: Integer; const AText: string; ADone: Boolean);
begin
  FIndex := AIndex;
  if FText <> AText then
  begin
    FText := AText;
    if FEdit.Text <> AText then
      FEdit.Text := AText;
  end;
  if FDone <> ADone then
  begin
    FDone := ADone;
    FEdit.Font.Color := IfThen(FDone, FDoneColor, FTextColor);
    Invalidate;
  end;
end;

procedure TNoteChecklistRow.ApplyColors(ABack, AText, ACheck, ADone: TColor);
begin
  FBackColor  := ABack;
  FTextColor  := AText;
  FCheckColor := ACheck;
  FDoneColor  := ADone;
  Color              := ABack;
  FEdit.Color        := ABack;
  FEdit.Font.Color   := IfThen(FDone, ADone, AText);
  Invalidate;
end;

procedure TNoteChecklistRow.SetLocked(Value: Boolean);
begin
  FLocked        := Value;
  FEdit.ReadOnly := Value;
end;

function TNoteChecklistRow.CheckBoxRect: TRect;
begin
  Result := Rect(CL_CHECK_MARGIN,
                 (Height - CL_CHECK_SIZE) div 2,
                 CL_CHECK_MARGIN + CL_CHECK_SIZE,
                 (Height - CL_CHECK_SIZE) div 2 + CL_CHECK_SIZE);
end;

procedure TNoteChecklistRow.Paint;
var
  CR: TRect;
  CX, CY, StrikeY: Integer;
  EditR: TRect;
  BorderColor: TColor;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  CR := CheckBoxRect;

  // Checkbox outline
  if FHotCheck and not FLocked then
    BorderColor := FCheckColor
  else
    BorderColor := RGB(
      Min(255, GetRValue(ColorToRGB(FCheckColor)) + 40),
      Min(255, GetGValue(ColorToRGB(FCheckColor)) + 40),
      Min(255, GetBValue(ColorToRGB(FCheckColor)) + 40));

  Canvas.Pen.Color   := BorderColor;
  Canvas.Pen.Width   := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.RoundRect(CR.Left, CR.Top, CR.Right, CR.Bottom, 4, 4);

  if FDone then
  begin
    // Draw checkmark tick
    Canvas.Pen.Color := FCheckColor;
    Canvas.Pen.Width := 2;
    CX := CR.Left + 3;
    CY := CR.Top + CR.Height div 2;
    Canvas.MoveTo(CX, CY);
    Canvas.LineTo(CX + 3, CY + 4);
    Canvas.LineTo(CR.Right - 3, CR.Top + 4);
    Canvas.Pen.Width := 1;

    // Strike-through the edit
    EditR   := Rect(FEdit.Left, FEdit.Top, FEdit.Left + FEdit.Width, FEdit.Top + FEdit.Height);
    StrikeY := EditR.Top + EditR.Height div 2;
    Canvas.Pen.Color := FTextColor;
    Canvas.Pen.Width := 1;
    Canvas.MoveTo(EditR.Left, StrikeY);
    Canvas.LineTo(EditR.Right, StrikeY);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TNoteChecklistRow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  NewHot: Boolean;
begin
  inherited;
  NewHot := PtInRect(CheckBoxRect, Point(X, Y));
  if NewHot <> FHotCheck then
  begin
    FHotCheck := NewHot;
    if NewHot then Cursor := crHandPoint
    else            Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TNoteChecklistRow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FLocked then Exit;
  if (Button = mbLeft) and PtInRect(CheckBoxRect, Point(X, Y)) then
    FOwnerPanel.RowToggled(Self);
end;

procedure TNoteChecklistRow.CMMouseLeave(var Message: TMessage);
begin
  FHotCheck := False;
  Cursor    := crDefault;
  Invalidate;
end;

procedure TNoteChecklistRow.Resize;
begin
  inherited;
  if FEdit <> nil then
    FEdit.Width := Max(CL_MIN_EDIT_W, ClientWidth - FEdit.Left - CL_SIDE_MARGIN);
end;

procedure TNoteChecklistRow.CMRelease(var Message: TMessage);
begin
  // Deferred self-destruction: RemoveRow posts CM_RELEASE because it can be
  // reached from this row's own EditKeyDown (Ctrl+Delete), while the TEdit
  // is still mid-WM_KEYDOWN. Freeing synchronously there would let VCL
  // continue message processing on freed memory (review 2026-09-10 H1).
  Free;
end;

procedure TNoteChecklistRow.EditChange(Sender: TObject);
begin
  FText := FEdit.Text;
  FOwnerPanel.RowTextChanged(Self, FText);
end;

procedure TNoteChecklistRow.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (ssCtrl in Shift) and not FLocked then
  begin
    FOwnerPanel.RemoveRow(FIndex);
    Key := 0;
  end;
end;

{ TNoteChecklistPanel }

constructor TNoteChecklistPanel.CreatePanel(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRows       := nil;
  FLocked     := False;
  FBackColor  := clWindow;
  FTextColor  := clWindowText;
  FCheckColor := clWindowText;
  FDoneColor  := clGray;

  DoubleBuffered := True;
  AutoScroll     := True;
  Color          := FBackColor;

  FAddEdit              := TEdit.Create(Self);
  FAddEdit.Parent       := Self;
  FAddEdit.BorderStyle  := bsNone;
  FAddEdit.TextHint     := '+ Add item...';
  FAddEdit.Font.Name    := 'Segoe UI';
  FAddEdit.Font.Size    := 9;
  FAddEdit.Height       := CL_ADD_ROW_H;
  FAddEdit.Left         := CL_SIDE_MARGIN;
  FAddEdit.OnKeyDown    := AddEditKeyDown;
  FAddEdit.Color        := FBackColor;
end;

procedure TNoteChecklistPanel.RebuildLayout;
var
  I, TotalH: Integer;
begin
  TotalH           := Length(FRows) * CL_ROW_HEIGHT;
  FAddEdit.Top     := TotalH;
  FAddEdit.Width   := ClientWidth - CL_SIDE_MARGIN * 2;
  FAddEdit.Visible := not FLocked;

  for I := 0 to High(FRows) do
    FRows[I].Width := ClientWidth;
end;

procedure TNoteChecklistPanel.SetItems(const AItems: TArray<TChecklistItem>);
var
  I, NeedMore, HaveMore: Integer;
begin
  NeedMore := Length(AItems) - Length(FRows);
  HaveMore := Length(FRows) - Length(AItems);

  // Create new rows
  if NeedMore > 0 then
  begin
    SetLength(FRows, Length(AItems));
    for I := Length(AItems) - NeedMore to High(AItems) do
    begin
      FRows[I] := TNoteChecklistRow.CreateRow(
        Self, I, AItems[I].Text, AItems[I].Done,
        FBackColor, FTextColor, FCheckColor, FDoneColor);
      FRows[I].Width := ClientWidth;
      FRows[I].SetLocked(FLocked);
    end;
  end;

  // Destroy surplus rows
  if HaveMore > 0 then
  begin
    for I := Length(AItems) to High(FRows) do
      FRows[I].Free;
    SetLength(FRows, Length(AItems));
  end;

  // Update existing rows in-place
  for I := 0 to Min(High(AItems), High(FRows)) do
    FRows[I].UpdateRow(I, AItems[I].Text, AItems[I].Done);

  RebuildLayout;
  Invalidate;
end;

procedure TNoteChecklistPanel.SetLocked(Value: Boolean);
var
  Row: TNoteChecklistRow;
begin
  if FLocked = Value then Exit;
  FLocked := Value;
  for Row in FRows do
    Row.SetLocked(Value);
  FAddEdit.Visible := not Value;
end;

function TNoteChecklistPanel.ItemCount: Integer;
begin
  Result := Length(FRows);
end;

procedure TNoteChecklistPanel.RowToggled(ARow: TNoteChecklistRow);
begin
  if Assigned(FOnItemToggled) then
    FOnItemToggled(Self, ARow.RowIndex, not ARow.Done);
end;

procedure TNoteChecklistPanel.RowTextChanged(ARow: TNoteChecklistRow; const AText: string);
begin
  if Assigned(FOnItemTextChanged) then
    FOnItemTextChanged(Self, ARow.RowIndex, AText);
end;

procedure TNoteChecklistPanel.RemoveRow(AIndex: Integer);
var
  I: Integer;
  Row: TNoteChecklistRow;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then Exit;
  Row := FRows[AIndex];

  // Shift the surviving rows left and re-index BEFORE the dying row leaves
  // the array, so no code can reach it through FRows afterwards.
  for I := AIndex to High(FRows) - 1 do
  begin
    FRows[I] := FRows[I + 1];
    FRows[I].UpdateRow(I, FRows[I].RowText, FRows[I].Done);
  end;
  SetLength(FRows, Length(FRows) - 1);
  RebuildLayout;
  if Assigned(FOnItemRemoved) then
    FOnItemRemoved(Self, AIndex);

  // Defer destruction (review 2026-09-10 H1): RemoveRow is reached from the
  // row's own EditKeyDown (Ctrl+Delete), so its TEdit is mid-WM_KEYDOWN and
  // a synchronous Free would continue VCL message processing on freed
  // memory. CM_RELEASE destroys the row after the message handler returns.
  if Row.HandleAllocated then
    PostMessage(Row.Handle, CM_RELEASE, 0, 0)
  else
    Row.Free;
end;

procedure TNoteChecklistPanel.AddEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    CommitAddEdit;
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    FAddEdit.Text := '';
    Key := 0;
  end;
end;

procedure TNoteChecklistPanel.CommitAddEdit;
var
  ItemText: string;
begin
  ItemText := Trim(FAddEdit.Text);
  if ItemText = '' then Exit;
  FAddEdit.Text := '';
  if Assigned(FOnItemAdded) then
    FOnItemAdded(Self, ItemText);
end;

end.
