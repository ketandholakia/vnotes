unit uWindowUtils;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Types, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics;

const
  RESIZE_BORDER = 8;
  CAPTION_HEIGHT = 32;

type
  TWindowUtils = class
  public
    class procedure EnableBorderlessWindow(AForm: TForm);
    class procedure HandleNCHitTest(AForm: TForm; var Message: TWMNCHitTest);
    class procedure HandleNCCalcSize(AForm: TForm; var Message: TWMNCCalcSize);
    class procedure HandleNCPaint(AForm: TForm; var Message: TWMNCPaint);
    class function GetResizeBorderSize: Integer;
    class function GetCaptionHeight: Integer;
  end;

  TWindowDragHelper = class
  private
    FForm: TForm;
    FDragMode: Boolean;
    FDragOffset: TPoint;
    procedure MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  public
    constructor Create(AForm: TForm);
    destructor Destroy; override;
  end;

implementation

{ TWindowUtils }

class procedure TWindowUtils.EnableBorderlessWindow(AForm: TForm);
begin
  AForm.BorderStyle := bsNone;
  AForm.DoubleBuffered := True;
  AForm.AlphaBlend := False;
  AForm.KeyPreview := True;
  AForm.Position := poDesigned;
end;

class function TWindowUtils.GetResizeBorderSize: Integer;
begin
  Result := RESIZE_BORDER;
end;

class function TWindowUtils.GetCaptionHeight: Integer;
begin
  Result := CAPTION_HEIGHT;
end;

class procedure TWindowUtils.HandleNCHitTest(AForm: TForm; var Message: TWMNCHitTest);
var
  ClientPoint: TPoint;
  HitTest: Integer;
  CaptionRect: TRect;
  LeftBorder, RightBorder, TopBorder, BottomBorder: Boolean;
begin
  ClientPoint := AForm.ScreenToClient(Point(Message.XPos, Message.YPos));
  
  // Check if in caption area (top area for dragging).
  // NOTE: the note header has its own real buttons (close/color/pin/collapse/
  // lock) drawn as child controls, which intercept their own clicks before
  // WM_NCHITTEST for the parent form is ever consulted. Treating this whole
  // strip as HTCAPTION (rather than carving out HTCLOSE/HTMINBUTTON zones
  // that don't line up with the actual button positions) avoids clicks in
  // the gaps between buttons being misread as a system close/minimize.
  CaptionRect := Rect(0, 0, AForm.ClientWidth, CAPTION_HEIGHT);
  if PtInRect(CaptionRect, ClientPoint) then
    HitTest := HTCAPTION
  else
  begin
    // Check resize borders
    LeftBorder := ClientPoint.X < RESIZE_BORDER;
    RightBorder := ClientPoint.X > AForm.ClientWidth - RESIZE_BORDER;
    TopBorder := ClientPoint.Y < RESIZE_BORDER;
    BottomBorder := ClientPoint.Y > AForm.ClientHeight - RESIZE_BORDER;
    
    if TopBorder and LeftBorder then
      HitTest := HTTOPLEFT
    else if TopBorder and RightBorder then
      HitTest := HTTOPRIGHT
    else if BottomBorder and LeftBorder then
      HitTest := HTBOTTOMLEFT
    else if BottomBorder and RightBorder then
      HitTest := HTBOTTOMRIGHT
    else if LeftBorder then
      HitTest := HTLEFT
    else if RightBorder then
      HitTest := HTRIGHT
    else if TopBorder then
      HitTest := HTTOP
    else if BottomBorder then
      HitTest := HTBOTTOM
    else
      HitTest := HTCLIENT;
  end;
  
  Message.Result := HitTest;
end;

class procedure TWindowUtils.HandleNCCalcSize(AForm: TForm; var Message: TWMNCCalcSize);
begin
  // No custom non-client area calculation needed for borderless
  // Windows handles it automatically when we return HT* from NCHitTest
end;

class procedure TWindowUtils.HandleNCPaint(AForm: TForm; var Message: TWMNCPaint);
var
  DC: HDC;
  R: TRect;
  Brush: HBRUSH;
  Color: TColor;
begin
  // Paint custom border for borderless window
  DC := GetWindowDC(AForm.Handle);
  try
    GetWindowRect(AForm.Handle, R);
    OffsetRect(R, -R.Left, -R.Top);
    
    if AForm.Brush.Style <> bsClear then
      Color := AForm.Brush.Color
    else
      Color := clWindow;
    
    Brush := CreateSolidBrush(ColorToRGB(Color));
    try
      FrameRect(DC, R, Brush);
    finally
      DeleteObject(Brush);
    end;
  finally
    ReleaseDC(AForm.Handle, DC);
  end;
end;

{ TWindowDragHelper }

constructor TWindowDragHelper.Create(AForm: TForm);
begin
  inherited Create;
  FForm := AForm;
  FDragMode := False;
  FForm.OnMouseDown := MouseDown;
  FForm.OnMouseMove := MouseMove;
  FForm.OnMouseUp := MouseUp;
end;

destructor TWindowDragHelper.Destroy;
begin
  FForm.OnMouseDown := nil;
  FForm.OnMouseMove := nil;
  FForm.OnMouseUp := nil;
  inherited;
end;

procedure TWindowDragHelper.MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (Y < CAPTION_HEIGHT) then
  begin
    FDragMode := True;
    FDragOffset := Point(X, Y);
  end;
end;

procedure TWindowDragHelper.MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FDragMode and (ssLeft in Shift) then
  begin
    FForm.Left := FForm.Left + (X - FDragOffset.X);
    FForm.Top := FForm.Top + (Y - FDragOffset.Y);
  end;
end;

procedure TWindowDragHelper.MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDragMode := False;
end;

end.