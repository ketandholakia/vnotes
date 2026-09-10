unit uNoteHeaderBar;

{
  TNoteHeaderBar
  ==============
  Owner-drawn, borderless header strip for a note window.

  Layout (left → right):
    [drag zone ...... | Fav | Color | Pin | Collapse | Lock | Checklist | Close]

  Usage
  -----
    FHeaderBar := TNoteHeaderBar.CreateNote(Self, TWindowUtils.GetCaptionHeight);
    FHeaderBar.Parent := Self;
    FHeaderBar.Align  := alTop;
    FHeaderBar.OnButtonClick := HeaderButtonClicked;
    FHeaderBar.SetButtonChecked(nhbPin, FNote.AlwaysOnTop);
    FHeaderBar.SetButtonEnabled(nhbPin, not FNote.Locked);
    FHeaderBar.BackColor := myNoteColor;
    FHeaderBar.IconColor := clBlack;
}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Types,
  Vcl.Controls, Vcl.Graphics;

type
  TNoteHeaderButton = (
    nhbFavorite,    // leftmost button
    nhbColor,
    nhbPin,
    nhbCollapse,
    nhbLock,
    nhbChecklist,
    nhbClose        // rightmost
  );

  TNoteHeaderButtonEvent = procedure(Sender: TObject; Button: TNoteHeaderButton) of object;

  TNoteHeaderBar = class(TCustomControl)
  private
    FButtonSize: Integer;
    FButtonEnabled: array[TNoteHeaderButton] of Boolean;
    FButtonChecked: array[TNoteHeaderButton] of Boolean;
    FHotIndex:     Integer;   // ordinal of hovered button, -1 = none
    FPressedIndex: Integer;
    FTrackingMouse: Boolean;

    FBackColor:    TColor;
    FIconColor:    TColor;
    FHotColor:     TColor;
    FPressedColor: TColor;

    FOnButtonClick: TNoteHeaderButtonEvent;

    function  ButtonRect(ABtn: TNoteHeaderButton): TRect;
    function  ButtonAtPoint(X, Y: Integer): Integer; // ordinal, -1 = none
    function  ButtonIcon(ABtn: TNoteHeaderButton): string;
    function  BlendColor(AFg, ABg: TColor; AAlpha: Byte): TColor;
    procedure DeriveHotPressed;
    procedure SetBackColor(Value: TColor);
    procedure SetIconColor(Value: TColor);

  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;

  public
    constructor CreateNote(AOwner: TComponent; AButtonSize: Integer = 32);

    procedure SetButtonEnabled(ABtn: TNoteHeaderButton; AEnabled: Boolean);
    procedure SetButtonChecked(ABtn: TNoteHeaderButton; AChecked: Boolean);
    function  IsButtonEnabled(ABtn: TNoteHeaderButton): Boolean;
    function  IsButtonChecked(ABtn: TNoteHeaderButton): Boolean;

    /// Returns the left portion of the header suitable for WM_NCLBUTTONDOWN drag.
    function DragZone: TRect;

    property ButtonSize: Integer  read FButtonSize;
    property BackColor:  TColor   read FBackColor   write SetBackColor;
    property IconColor:  TColor   read FIconColor   write SetIconColor;
    property HotColor:   TColor   read FHotColor    write FHotColor;
    property PressedColor: TColor read FPressedColor write FPressedColor;
    property OnButtonClick: TNoteHeaderButtonEvent read FOnButtonClick write FOnButtonClick;
  end;

implementation

// ── Unit-scope constants ───────────────────────────────────────────────────
// Segoe MDL2 Assets codepoints — same glyphs the original TSpeedButtons used
const
  ICON_CLOSE     = #$E8BB;
  ICON_CHECKLIST = #$E73E;
  ICON_LOCK_OFF  = #$E785;
  ICON_LOCK_ON   = #$E72E;
  ICON_COLLAPSE  = #$E738;
  ICON_EXPAND    = #$E73F;
  ICON_PIN       = #$E718;
  ICON_COLOR     = #$E2B1;
  ICON_FAV_OFF   = #$E113;
  ICON_FAV_ON    = #$E734;
  BTN_COUNT      = 7;   // number of TNoteHeaderButton values

{ ── Helpers ──────────────────────────────────────────────────────────────── }

function TNoteHeaderBar.BlendColor(AFg, ABg: TColor; AAlpha: Byte): TColor;
var
  F, B: DWORD;
  A, IA: Integer;
begin
  F  := ColorToRGB(AFg);
  B  := ColorToRGB(ABg);
  A  := AAlpha;
  IA := 255 - A;
  Result := RGB(
    (GetRValue(F) * A + GetRValue(B) * IA) div 255,
    (GetGValue(F) * A + GetGValue(B) * IA) div 255,
    (GetBValue(F) * A + GetBValue(B) * IA) div 255);
end;

procedure TNoteHeaderBar.DeriveHotPressed;
var
  Lum: Integer;
  C: DWORD;
begin
  // Blend the hover/pressed state toward white on dark backgrounds and
  // toward black on light ones, otherwise the hot state is invisible on
  // White/Yellow notes (review 2026-09-10, minor).
  C   := ColorToRGB(FBackColor);
  Lum := (GetRValue(C) * 77 + GetGValue(C) * 150 + GetBValue(C) * 29) div 256;
  if Lum >= 128 then
  begin
    FHotColor     := BlendColor(clBlack, FBackColor, 45);
    FPressedColor := BlendColor(clBlack, FBackColor, 90);
  end
  else
  begin
    FHotColor     := BlendColor(clWhite, FBackColor, 60);
    FPressedColor := BlendColor(clBlack, FBackColor, 40);
  end;
end;

{ ── Construction ─────────────────────────────────────────────────────────── }

constructor TNoteHeaderBar.CreateNote(AOwner: TComponent; AButtonSize: Integer);
var
  B: TNoteHeaderButton;
begin
  inherited Create(AOwner);
  FButtonSize    := AButtonSize;
  FHotIndex      := -1;
  FPressedIndex  := -1;
  FTrackingMouse := False;
  FBackColor     := clBtnFace;
  FIconColor     := clWindowText;
  DeriveHotPressed;

  for B := Low(TNoteHeaderButton) to High(TNoteHeaderButton) do
  begin
    FButtonEnabled[B] := True;
    FButtonChecked[B] := False;
  end;

  Height         := AButtonSize;
  DoubleBuffered := True;
end;

{ ── Geometry ─────────────────────────────────────────────────────────────── }

function TNoteHeaderBar.ButtonRect(ABtn: TNoteHeaderButton): TRect;
// Buttons packed right-to-left in enum ordinal order.
// nhbClose (Ord = 6) is at the far right; nhbFavorite (Ord = 0) is leftmost button.
var
  RightOffset: Integer;
begin
  // Distance from the right edge for this button's left side
  RightOffset := (Ord(High(TNoteHeaderButton)) - Ord(ABtn)) * FButtonSize;
  Result := Rect(
    ClientWidth - FButtonSize - RightOffset,
    (ClientHeight - FButtonSize) div 2,
    ClientWidth - RightOffset,
    (ClientHeight - FButtonSize) div 2 + FButtonSize);
end;

function TNoteHeaderBar.DragZone: TRect;
begin
  Result := Rect(0, 0, ClientWidth - BTN_COUNT * FButtonSize, ClientHeight);
end;

function TNoteHeaderBar.ButtonAtPoint(X, Y: Integer): Integer;
var
  B: TNoteHeaderButton;
begin
  Result := -1;
  for B := Low(TNoteHeaderButton) to High(TNoteHeaderButton) do
    if PtInRect(ButtonRect(B), Point(X, Y)) then
    begin
      if FButtonEnabled[B] then
        Result := Ord(B);
      Exit;
    end;
end;

{ ── Icons ────────────────────────────────────────────────────────────────── }

function TNoteHeaderBar.ButtonIcon(ABtn: TNoteHeaderButton): string;
begin
  case ABtn of
    nhbClose:     Result := ICON_CLOSE;
    nhbChecklist: Result := ICON_CHECKLIST;
    nhbLock:      if FButtonChecked[ABtn] then Result := ICON_LOCK_ON
                  else                         Result := ICON_LOCK_OFF;
    nhbCollapse:  if FButtonChecked[ABtn] then Result := ICON_EXPAND
                  else                         Result := ICON_COLLAPSE;
    nhbPin:       Result := ICON_PIN;
    nhbColor:     Result := ICON_COLOR;
    nhbFavorite:  if FButtonChecked[ABtn] then Result := ICON_FAV_ON
                  else                         Result := ICON_FAV_OFF;
  else
    Result := '?';
  end;
end;

{ ── Paint ────────────────────────────────────────────────────────────────── }

procedure TNoteHeaderBar.Paint;
var
  B: TNoteHeaderButton;
  R: TRect;
  BgColor: TColor;
  BtnOrd: Integer;
  IconStr: string;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  Canvas.Font.Name  := 'Segoe MDL2 Assets';
  // Scale the glyph font with the (DPI-scaled) button size; a fixed 12 pt
  // shrinks relative to the buttons at 150%+ (review 2026-09-10, minor).
  // ButtonSize was seeded from GetCaptionHeight, 32 px at 96 DPI.
  Canvas.Font.Size  := Max(9, MulDiv(12, FButtonSize, 32));
  Canvas.Font.Style := [];

  for B := Low(TNoteHeaderButton) to High(TNoteHeaderButton) do
  begin
    R      := ButtonRect(B);
    BtnOrd := Ord(B);

    if not FButtonEnabled[B] then
      BgColor := FBackColor
    else if BtnOrd = FPressedIndex then
      BgColor := FPressedColor
    else if BtnOrd = FHotIndex then
      BgColor := FHotColor
    else
      BgColor := FBackColor;

    Canvas.Brush.Color := BgColor;
    Canvas.FillRect(R);

    if FButtonEnabled[B] then
      Canvas.Font.Color := FIconColor
    else
      Canvas.Font.Color := BlendColor(FIconColor, FBackColor, 100);

    Canvas.Brush.Style := bsClear;
    IconStr := ButtonIcon(B);
    DrawText(Canvas.Handle, PChar(IconStr), -1, R,
             DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    Canvas.Brush.Style := bsSolid;
  end;
end;

{ ── Mouse ────────────────────────────────────────────────────────────────── }

procedure TNoteHeaderBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  NewHot: Integer;
  TME: TTrackMouseEvent;
begin
  inherited;
  NewHot := ButtonAtPoint(X, Y);
  if NewHot <> FHotIndex then
  begin
    FHotIndex := NewHot;
    Invalidate;
  end;

  if not FTrackingMouse then
  begin
    FTrackingMouse       := True;
    TME.cbSize           := SizeOf(TME);
    TME.dwFlags          := TME_LEAVE;
    TME.hwndTrack        := Handle;
    TME.dwHoverTime      := 0;
    TrackMouseEvent(TME);
  end;
end;

procedure TNoteHeaderBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
  begin
    FPressedIndex := ButtonAtPoint(X, Y);
    if FPressedIndex >= 0 then
      Invalidate;
  end;
end;

procedure TNoteHeaderBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  inherited;
  if (Button = mbLeft) and (FPressedIndex >= 0) then
  begin
    Idx := ButtonAtPoint(X, Y);
    if (Idx = FPressedIndex) and Assigned(FOnButtonClick) then
      FOnButtonClick(Self, TNoteHeaderButton(FPressedIndex));
    FPressedIndex := -1;
    Invalidate;
  end;
end;

procedure TNoteHeaderBar.CMMouseLeave(var Message: TMessage);
begin
  FHotIndex      := -1;
  FPressedIndex  := -1;
  FTrackingMouse := False;
  Invalidate;
end;

procedure TNoteHeaderBar.WMNCHitTest(var Message: TWMNCHitTest);
var
  P: TPoint;
begin
  inherited;
  P := ScreenToClient(Point(Message.XPos, Message.YPos));
  if PtInRect(DragZone, P) then
    Message.Result := HTTRANSPARENT;
end;

{ ── Public state ─────────────────────────────────────────────────────────── }

procedure TNoteHeaderBar.SetButtonEnabled(ABtn: TNoteHeaderButton; AEnabled: Boolean);
begin
  if FButtonEnabled[ABtn] = AEnabled then Exit;
  FButtonEnabled[ABtn] := AEnabled;
  Invalidate;
end;

procedure TNoteHeaderBar.SetButtonChecked(ABtn: TNoteHeaderButton; AChecked: Boolean);
begin
  if FButtonChecked[ABtn] = AChecked then Exit;
  FButtonChecked[ABtn] := AChecked;
  Invalidate;
end;

function TNoteHeaderBar.IsButtonEnabled(ABtn: TNoteHeaderButton): Boolean;
begin
  Result := FButtonEnabled[ABtn];
end;

function TNoteHeaderBar.IsButtonChecked(ABtn: TNoteHeaderButton): Boolean;
begin
  Result := FButtonChecked[ABtn];
end;

procedure TNoteHeaderBar.SetBackColor(Value: TColor);
begin
  if FBackColor = Value then Exit;
  FBackColor := Value;
  DeriveHotPressed;
  Invalidate;
end;

procedure TNoteHeaderBar.SetIconColor(Value: TColor);
begin
  if FIconColor = Value then Exit;
  FIconColor := Value;
  Invalidate;
end;

end.
