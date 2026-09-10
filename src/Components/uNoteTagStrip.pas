unit uNoteTagStrip;

{
  TNoteTagStrip
  =============
  Owner-drawn tag-chip strip with inline add-tag editing.

  Replaces pnlTagsFooter + flwTags + edNewTag + btnAddTag + the
  CreateTagChip / RefreshTagsFooter helpers in uNoteForm.

  The chip pills are drawn directly on the Canvas (no child TPanel / TLabel
  per chip), which avoids the allocation/free churn on every tag change.
  A single child TEdit provides the inline tag-entry field at the right edge;
  it is hidden when the note is locked.

  Layout
  ------
    [chip1][chip2]... [chip-n] | [+ tag input...]

  Each chip shows: "tagname x" (the x is clickable to remove).
  If chips overflow the available width they are horizontally scrolled
  (mousewheel).

  Usage
  -----
    FTagStrip := TNoteTagStrip.CreateStrip(Self);
    FTagStrip.Parent  := Self;
    FTagStrip.Align   := alBottom;
    FTagStrip.Height  := 28;
    FTagStrip.OnTagAdded   := TagAddedHandler;
    FTagStrip.OnTagRemoved := TagRemovedHandler;
    FTagStrip.SetTags(FNote.Tags);
    FTagStrip.Locked  := FNote.Locked;
    FTagStrip.BackColor := myNoteColor;
    FTagStrip.TextColor := clBlack;
}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Types,
  Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Forms;


type
  TNoteTagAddedEvent   = procedure(Sender: TObject; const Tag: string) of object;
  TNoteTagRemovedEvent = procedure(Sender: TObject; const Tag: string; Index: Integer) of object;

  TNoteTagStrip = class(TCustomControl)
  private
    FTags:       TArray<string>;
    FLocked:     Boolean;
    FScrollX:    Integer;
    FHotChip:    Integer;
    FHotRemove:  Boolean;

    FBackColor:  TColor;
    FChipColor:  TColor;
    FTextColor:  TColor;

    FAddEdit:    TEdit;

    FOnTagAdded:   TNoteTagAddedEvent;
    FOnTagRemoved: TNoteTagRemovedEvent;

    procedure AddEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CommitAddEdit;

    function  ChipWidth(AIndex: Integer): Integer;
    procedure ChipRect(AIndex: Integer; out R: TRect; out RemoveR: TRect);
    function  ChipAtPoint(X, Y: Integer; out IsRemove: Boolean): Integer;
    function  TotalChipsWidth: Integer;
    procedure LayoutAddEdit;

    procedure SetLocked(Value: Boolean);
    procedure SetBackColor(Value: TColor);
    procedure SetTextColor(Value: TColor);
    procedure ClampScroll;

  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMMouseWheel(var Message: TWMMouseWheel); message WM_MOUSEWHEEL;

  public
    constructor CreateStrip(AOwner: TComponent);

    procedure SetTags(const ATags: TArray<string>);
    function  GetTags: TArray<string>;
    procedure AddTag(const ATag: string);
    procedure RemoveTagAt(AIndex: Integer);
    procedure ClearTags;

    property Locked:    Boolean read FLocked    write SetLocked;
    property BackColor: TColor  read FBackColor  write SetBackColor;
    property ChipColor: TColor  read FChipColor  write FChipColor;
    property TextColor: TColor  read FTextColor  write SetTextColor;

    property OnTagAdded:   TNoteTagAddedEvent   read FOnTagAdded   write FOnTagAdded;
    property OnTagRemoved: TNoteTagRemovedEvent  read FOnTagRemoved write FOnTagRemoved;
  end;

implementation

const
  TAG_CHIP_H_PAD  = 6;
  TAG_CHIP_V_PAD  = 3;
  TAG_CHIP_RADIUS = 6;
  TAG_REMOVE_W    = 14;
  TAG_EDIT_MIN_W  = 60;
  TAG_EDIT_MAX_W  = 100;
  TAG_CHIP_GAP    = 4;

{ Construction }

constructor TNoteTagStrip.CreateStrip(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTags      := nil;
  FLocked    := False;
  FScrollX   := 0;
  FHotChip   := -1;
  FHotRemove := False;
  FBackColor := clBtnFace;
  FChipColor := clNone;
  FTextColor := clWindowText;

  DoubleBuffered := True;
  Height         := 28;

  FAddEdit              := TEdit.Create(Self);
  FAddEdit.Parent       := Self;
  FAddEdit.BorderStyle  := bsNone;
  FAddEdit.StyleElements := [];
  FAddEdit.TextHint     := '+ tag';
  FAddEdit.Height       := Height - 4;
  FAddEdit.Top          := 2;
  FAddEdit.Font.Name    := 'Segoe UI';
  FAddEdit.Font.Size    := 8;
  FAddEdit.OnKeyDown    := AddEditKeyDown;
  FAddEdit.TabStop      := True;
end;

{ Layout }

function TNoteTagStrip.ChipWidth(AIndex: Integer): Integer;
begin
  Canvas.Font.Name  := 'Segoe UI';
  Canvas.Font.Size  := 8;
  Canvas.Font.Style := [];
  Result := Canvas.TextWidth(FTags[AIndex]) + TAG_CHIP_H_PAD * 2 + TAG_REMOVE_W;
end;

procedure TNoteTagStrip.ChipRect(AIndex: Integer; out R: TRect; out RemoveR: TRect);
var
  I, X, CW: Integer;
begin
  X := -FScrollX;
  for I := 0 to AIndex - 1 do
    X := X + ChipWidth(I) + TAG_CHIP_GAP;
  CW      := ChipWidth(AIndex);
  R       := Rect(X, TAG_CHIP_V_PAD, X + CW, Height - TAG_CHIP_V_PAD);
  RemoveR := Rect(R.Right - TAG_REMOVE_W, R.Top, R.Right, R.Bottom);
end;

function TNoteTagStrip.ChipAtPoint(X, Y: Integer; out IsRemove: Boolean): Integer;
var
  I: Integer;
  R, RR: TRect;
begin
  Result   := -1;
  IsRemove := False;
  for I := 0 to High(FTags) do
  begin
    ChipRect(I, R, RR);
    if PtInRect(R, Point(X, Y)) then
    begin
      Result   := I;
      IsRemove := PtInRect(RR, Point(X, Y));
      Exit;
    end;
  end;
end;

function TNoteTagStrip.TotalChipsWidth: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FTags) do
  begin
    if I > 0 then Inc(Result, TAG_CHIP_GAP);
    Inc(Result, ChipWidth(I));
  end;
end;

procedure TNoteTagStrip.LayoutAddEdit;
var
  Used, Available, EditW: Integer;
begin
  Used := TotalChipsWidth - FScrollX;
  if Length(FTags) > 0 then
    Inc(Used, TAG_CHIP_GAP);
  Available := ClientWidth - Used;
  EditW     := Max(TAG_EDIT_MIN_W, Min(TAG_EDIT_MAX_W, Available));

  FAddEdit.Left        := ClientWidth - EditW - 2;
  FAddEdit.Width       := EditW;
  FAddEdit.Visible     := not FLocked;
  FAddEdit.Color       := FBackColor;
  FAddEdit.Font.Color  := FTextColor;
end;

procedure TNoteTagStrip.ClampScroll;
var
  Overhang: Integer;
begin
  Overhang := TotalChipsWidth - (ClientWidth - TAG_EDIT_MIN_W - TAG_CHIP_GAP);
  if Overhang < 0 then Overhang := 0;
  FScrollX := Max(0, Min(FScrollX, Overhang));
end;

{ Paint }

procedure TNoteTagStrip.Paint;
var
  I: Integer;
  R, RemR, TextR: TRect;
  ChipBg: TColor;
  IsHot: Boolean;
  Tag: string;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  Canvas.Font.Name  := 'Segoe UI';
  Canvas.Font.Size  := 8;
  Canvas.Font.Style := [];

  for I := 0 to High(FTags) do
  begin
    ChipRect(I, R, RemR);
    if R.Right < 0 then Continue;
    if R.Left  > ClientWidth then Break;

    IsHot := (I = FHotChip);
    Tag   := FTags[I];

    if FChipColor = clNone then
      ChipBg := RGB(
        Max(0, GetRValue(ColorToRGB(FBackColor)) - 25),
        Max(0, GetGValue(ColorToRGB(FBackColor)) - 25),
        Max(0, GetBValue(ColorToRGB(FBackColor)) - 25))
    else
      ChipBg := FChipColor;

    if IsHot then
      ChipBg := RGB(
        Min(255, GetRValue(ColorToRGB(ChipBg)) + 20),
        Min(255, GetGValue(ColorToRGB(ChipBg)) + 20),
        Min(255, GetBValue(ColorToRGB(ChipBg)) + 20));

    Canvas.Brush.Color := ChipBg;
    Canvas.Pen.Color   := ChipBg;
    RoundRect(Canvas.Handle, R.Left, R.Top, R.Right, R.Bottom,
              TAG_CHIP_RADIUS * 2, TAG_CHIP_RADIUS * 2);

    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color  := FTextColor;
    TextR := Rect(R.Left + TAG_CHIP_H_PAD, R.Top, R.Right - TAG_REMOVE_W, R.Bottom);
    DrawText(Canvas.Handle, PChar(Tag), -1, TextR,
             DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);

    if not FLocked then
    begin
      if IsHot and FHotRemove then
        Canvas.Font.Color := clRed
      else
        Canvas.Font.Color := FTextColor;
      Canvas.Font.Style := [fsBold];
      DrawText(Canvas.Handle, PChar('x'), -1, RemR,
               DT_CENTER or DT_VCENTER or DT_SINGLELINE);
      Canvas.Font.Style := [];
    end;
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TNoteTagStrip.Resize;
begin
  inherited;
  ClampScroll;
  LayoutAddEdit;
  Invalidate;
end;

{ Mouse }

procedure TNoteTagStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  NewChip: Integer;
  NewRemove: Boolean;
begin
  inherited;
  NewChip := ChipAtPoint(X, Y, NewRemove);
  if (NewChip <> FHotChip) or (NewRemove <> FHotRemove) then
  begin
    FHotChip   := NewChip;
    FHotRemove := NewRemove;
    Invalidate;
  end;
end;

procedure TNoteTagStrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
  IsRemove: Boolean;
begin
  inherited;
  if FLocked then Exit;
  if Button = mbLeft then
  begin
    Idx := ChipAtPoint(X, Y, IsRemove);
    if (Idx >= 0) and IsRemove then
      RemoveTagAt(Idx);
  end;
end;

procedure TNoteTagStrip.CMMouseLeave(var Message: TMessage);
begin
  FHotChip   := -1;
  FHotRemove := False;
  Invalidate;
end;

procedure TNoteTagStrip.WMMouseWheel(var Message: TWMMouseWheel);
begin
  FScrollX := FScrollX - (Message.WheelDelta div 3);
  ClampScroll;
  LayoutAddEdit;
  Invalidate;
  // 0 = handled (a non-zero result would bubble the message to the parent)
  Message.Result := 0;
end;

{ Add edit }

procedure TNoteTagStrip.AddEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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

procedure TNoteTagStrip.CommitAddEdit;
var
  TagText: string;
begin
  TagText := Trim(FAddEdit.Text);
  if TagText = '' then Exit;
  FAddEdit.Text := '';
  AddTag(TagText);
end;

{ Public API }

procedure TNoteTagStrip.SetTags(const ATags: TArray<string>);
begin
  FTags    := System.Copy(ATags);
  FScrollX := 0;
  ClampScroll;
  LayoutAddEdit;
  Invalidate;
end;

function TNoteTagStrip.GetTags: TArray<string>;
begin
  Result := System.Copy(FTags);
end;

procedure TNoteTagStrip.AddTag(const ATag: string);
begin
  SetLength(FTags, Length(FTags) + 1);
  FTags[High(FTags)] := ATag;
  ClampScroll;
  LayoutAddEdit;
  Invalidate;
  if Assigned(FOnTagAdded) then
    FOnTagAdded(Self, ATag);
end;

procedure TNoteTagStrip.RemoveTagAt(AIndex: Integer);
var
  I: Integer;
  RemovedTag: string;
begin
  if (AIndex < 0) or (AIndex > High(FTags)) then Exit;
  RemovedTag := FTags[AIndex];
  for I := AIndex to High(FTags) - 1 do
    FTags[I] := FTags[I + 1];
  SetLength(FTags, Length(FTags) - 1);
  if FHotChip >= Length(FTags) then FHotChip := -1;
  ClampScroll;
  LayoutAddEdit;
  Invalidate;
  if Assigned(FOnTagRemoved) then
    FOnTagRemoved(Self, RemovedTag, AIndex);
end;

procedure TNoteTagStrip.ClearTags;
begin
  FTags    := nil;
  FScrollX := 0;
  LayoutAddEdit;
  Invalidate;
end;

{ Theming }

procedure TNoteTagStrip.SetLocked(Value: Boolean);
begin
  if FLocked = Value then Exit;
  FLocked := Value;
  LayoutAddEdit;
  Invalidate;
end;

procedure TNoteTagStrip.SetBackColor(Value: TColor);
begin
  if FBackColor = Value then Exit;
  FBackColor := Value;
  FAddEdit.Color := Value;
  Invalidate;
end;

procedure TNoteTagStrip.SetTextColor(Value: TColor);
begin
  if FTextColor = Value then Exit;
  FTextColor := Value;
  FAddEdit.Font.Color := Value;
  Invalidate;
end;

end.
