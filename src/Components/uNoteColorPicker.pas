unit uNoteColorPicker;

{
  TNoteColorPicker
  ================
  A lightweight popup that shows all 8 note colors as visual swatches.

  Replaces the plain text "Color" submenu in pmNote.  Call ShowAt() anchored
  to a screen point (typically the Color button's bottom-left corner); the
  popup dismisses itself on selection, Escape, or click-outside (Deactivate).

  Usage
  -----
    FColorPicker := TNoteColorPicker.CreatePicker(Self);
    FColorPicker.SelectedColor   := FNote.Color;
    FColorPicker.OnColorSelected := ColorPickerSelected;

    // In header button-click handler:
    var Pt := ClientToScreen(Point(0, FHeaderBar.Height));
    FColorPicker.ShowAt(Pt.X, Pt.Y);
}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Types,
  Vcl.Controls, Vcl.Graphics, Vcl.Forms,
  uEnums;

type
  TNoteColorSelectedEvent = procedure(Sender: TObject; Color: TNoteColor) of object;

  TNoteColorPickerPopup = class;

  TNoteColorPicker = class(TComponent)
  private
    FPopup:           TNoteColorPickerPopup;
    FSelectedColor:   TNoteColor;
    FOnColorSelected: TNoteColorSelectedEvent;
    procedure PopupColorSelected(Sender: TObject; Color: TNoteColor);
    function GetIsPopupVisible: Boolean;
  public
    constructor CreatePicker(AOwner: TComponent);
    destructor Destroy; override;

    procedure ShowAt(AScreenX, AScreenY: Integer);
    procedure Hide;

    property SelectedColor:   TNoteColor            read FSelectedColor   write FSelectedColor;
    property OnColorSelected: TNoteColorSelectedEvent read FOnColorSelected write FOnColorSelected;
    property IsPopupVisible:  Boolean               read GetIsPopupVisible;
  end;

  /// Internal popup window — not for direct use outside this unit.
  TNoteColorPickerPopup = class(TCustomForm)
  private
    FSelectedColor:   TNoteColor;
    FHotOrdinal:      Integer;    // ordinal of hovered colour, -1 = none
    FOnColorSelected: TNoteColorSelectedEvent;

    procedure SwatchRect(AColor: TNoteColor; out R: TRect);
    function  ColorAtPoint(X, Y: Integer): Integer;  // -1 = none
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;

  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Deactivate; override;

  public
    constructor CreatePopup(AOwner: TComponent);
    property SelectedColor:   TNoteColor             read FSelectedColor   write FSelectedColor;
    property OnColorSelected: TNoteColorSelectedEvent read FOnColorSelected write FOnColorSelected;
  end;

implementation

// ── Unit-scope constants ───────────────────────────────────────────────────
const
  SWATCH_SIZE   = 32;   // pixel size of each colour square
  SWATCH_GAP    = 6;    // gap between swatches
  SWATCH_PADDING       = 8;    // edge SWATCH_PADDING around the strip
  CORNER_RADIUS = 6;    // rounded corner radius for swatches

{ ── TNoteColorPicker ─────────────────────────────────────────────────────── }

constructor TNoteColorPicker.CreatePicker(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedColor := ncYellow;
  FPopup         := TNoteColorPickerPopup.CreatePopup(nil);
  FPopup.OnColorSelected := PopupColorSelected;
end;

destructor TNoteColorPicker.Destroy;
begin
  FPopup.Free;
  inherited;
end;

procedure TNoteColorPicker.ShowAt(AScreenX, AScreenY: Integer);
begin
  FPopup.SelectedColor := FSelectedColor;
  FPopup.Left          := AScreenX;
  FPopup.Top           := AScreenY;
  FPopup.Show;
  FPopup.BringToFront;
  FPopup.SetFocus;
end;

procedure TNoteColorPicker.Hide;
begin
  FPopup.Hide;
end;

function TNoteColorPicker.GetIsPopupVisible: Boolean;
begin
  Result := FPopup.Visible;
end;

procedure TNoteColorPicker.PopupColorSelected(Sender: TObject; Color: TNoteColor);
begin
  FSelectedColor := Color;
  FPopup.Hide;
  if Assigned(FOnColorSelected) then
    FOnColorSelected(Self, Color);
end;

{ ── TNoteColorPickerPopup ────────────────────────────────────────────────── }

constructor TNoteColorPickerPopup.CreatePopup(AOwner: TComponent);
var
  ColorCount, TotalWidth, TotalHeight: Integer;
begin
  inherited CreateNew(AOwner);
  ColorCount   := Ord(High(TNoteColor)) - Ord(Low(TNoteColor)) + 1;
  TotalWidth   := SWATCH_PADDING * 2 + ColorCount * SWATCH_SIZE + (ColorCount - 1) * SWATCH_GAP;
  TotalHeight  := SWATCH_PADDING * 2 + SWATCH_SIZE;

  BorderStyle    := bsNone;
  FormStyle      := fsStayOnTop;
  ClientWidth    := TotalWidth;
  ClientHeight   := TotalHeight;
  Color          := $002D2D2D;
  DoubleBuffered := True;
  KeyPreview     := True;
  FHotOrdinal    := -1;
  FSelectedColor := ncYellow;
end;

procedure TNoteColorPickerPopup.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW;
end;

procedure TNoteColorPickerPopup.SwatchRect(AColor: TNoteColor; out R: TRect);
var
  Idx, X: Integer;
begin
  Idx := Ord(AColor) - Ord(Low(TNoteColor));
  X   := SWATCH_PADDING + Idx * (SWATCH_SIZE + SWATCH_GAP);
  R   := Rect(X, SWATCH_PADDING, X + SWATCH_SIZE, SWATCH_PADDING + SWATCH_SIZE);
end;

function TNoteColorPickerPopup.ColorAtPoint(X, Y: Integer): Integer;
var
  C: TNoteColor;
  R: TRect;
begin
  Result := -1;
  for C := Low(TNoteColor) to High(TNoteColor) do
  begin
    SwatchRect(C, R);
    if PtInRect(R, Point(X, Y)) then
    begin
      Result := Ord(C);
      Exit;
    end;
  end;
end;

procedure TNoteColorPickerPopup.Paint;
var
  C: TNoteColor;
  R, Inner: TRect;
  IsSelected, IsHot: Boolean;
  SwatchColor: TColor;
begin
  Canvas.Brush.Color := Color;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  for C := Low(TNoteColor) to High(TNoteColor) do
  begin
    SwatchRect(C, R);
    IsSelected  := (C = FSelectedColor);
    IsHot       := (Ord(C) = FHotOrdinal);
    SwatchColor := NOTE_COLOR_VALUES[C];

    if IsSelected then
    begin
      // White ring: draw larger, then inset the swatch by 3px
      Canvas.Brush.Color := clWhite;
      Canvas.Pen.Color   := clWhite;
      RoundRect(Canvas.Handle, R.Left, R.Top, R.Right, R.Bottom,
                CORNER_RADIUS * 2, CORNER_RADIUS * 2);
      Inner := Rect(R.Left + 3, R.Top + 3, R.Right - 3, R.Bottom - 3);
    end
    else if IsHot then
    begin
      Canvas.Pen.Color   := clWhite;
      Canvas.Brush.Color := clWhite;
      RoundRect(Canvas.Handle, R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1,
                CORNER_RADIUS * 2, CORNER_RADIUS * 2);
      Inner := R;
    end
    else
      Inner := R;

    Canvas.Brush.Color := SwatchColor;
    Canvas.Pen.Color   := SwatchColor;
    RoundRect(Canvas.Handle, Inner.Left, Inner.Top, Inner.Right, Inner.Bottom,
              CORNER_RADIUS * 2, CORNER_RADIUS * 2);
  end;
end;

procedure TNoteColorPickerPopup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  NewHot: Integer;
begin
  inherited;
  NewHot := ColorAtPoint(X, Y);
  if NewHot <> FHotOrdinal then
  begin
    FHotOrdinal := NewHot;
    Invalidate;
  end;
end;

procedure TNoteColorPickerPopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  inherited;
  if Button = mbLeft then
  begin
    Idx := ColorAtPoint(X, Y);
    if (Idx >= 0) and Assigned(FOnColorSelected) then
      FOnColorSelected(Self, TNoteColor(Idx));
  end;
end;

procedure TNoteColorPickerPopup.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Hide;
    Key := 0;
  end;
  inherited;
end;

procedure TNoteColorPickerPopup.Deactivate;
begin
  inherited;
  Hide;
end;

procedure TNoteColorPickerPopup.CMMouseLeave(var Message: TMessage);
begin
  FHotOrdinal := -1;
  Invalidate;
end;

end.
