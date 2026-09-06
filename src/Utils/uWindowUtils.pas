unit uWindowUtils;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.Dwmapi, System.SysUtils, System.Types, System.Classes,
  System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Themes;

const
  RESIZE_BORDER = 8;
  CAPTION_HEIGHT = 32;

  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
  DWMWCP_ROUND = 2;

type
  TWindowUtils = class
  public
    class procedure EnableBorderlessWindow(AForm: TForm);
    class procedure EnableRoundedCorners(AForm: TForm);
    class procedure HandleNCHitTest(AForm: TForm; var Message: TWMNCHitTest);
    class procedure HandleNCCalcSize(AForm: TForm; var Message: TWMNCCalcSize);
    class procedure HandleNCPaint(AForm: TForm; var Message: TWMNCPaint);
    class function GetResizeBorderSize: Integer;
    class function GetCaptionHeight: Integer;
  end;

  // 6E.2 resize fix: the note's client area is fully covered by windowed
  // child controls (memo, header/footer panels, checklist items...), so a
  // real mouse at a window edge hits a CHILD whose WM_NCHITTEST yields
  // HTCLIENT - the form's own edge hit test is never consulted. This hook
  // wraps each descendant control's WindowProc and answers HTTRANSPARENT
  // when the cursor is inside the resize band, making the system fall
  // through to the form (whose WM_NCHITTEST then returns the HT* codes and
  // DefWindowProc runs the native modal size loop). Controls are tracked
  // per instance and detach cleanly on destruction.
  TEdgeHitTestHook = class(TComponent)
  private class var
    FHooks: TDictionary<TWinControl, TEdgeHitTestHook>;
  private
    FControl: TWinControl;
    FForm: TCustomForm;
    FOrigProc: TWndMethod;
    procedure HookProc(var Message: TMessage);
    class constructor Create;
    class destructor Destroy;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    class procedure Install(AForm: TCustomForm);
    class procedure InstallControl(AForm: TCustomForm; AControl: TWinControl);
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
  // Runtime VCL styles install TFormStyleHook, which intercepts WM_NCHITTEST
  // for forms still participating in styled non-client rendering and forces
  // HTCLIENT. That silently defeats every custom HT* hit test (and even the
  // native WS_THICKFRAME sizing border), so resizing never engages. Dropping
  // seBorder opts the form out of the styled non-client hook.
  // Dropping seClient allows the custom FrameColor to paint the margins.
  AForm.StyleElements := AForm.StyleElements - [seBorder, seClient];
end;

class procedure TWindowUtils.EnableRoundedCorners(AForm: TForm);
var
  Preference: Integer;
begin
  Preference := DWMWCP_ROUND;
  DwmSetWindowAttribute(AForm.Handle, DWMWA_WINDOW_CORNER_PREFERENCE, @Preference, SizeOf(Preference));
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

  // Check resize borders FIRST: the caption check below used to run before
  // them, so the 32px caption strip swallowed the whole top edge (including
  // the top corners) and HTTOP/HTTOPLEFT/HTTOPRIGHT could never be returned.
  // Corners take precedence over edges.
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
  else if (ClientPoint.Y >= 0) and (ClientPoint.Y < CAPTION_HEIGHT) then
  begin
    // Caption area (top strip) for dragging, only where no resize border
    // matched. NOTE: the note header has its own real buttons
    // (close/color/pin/collapse/lock) drawn as child controls, which
    // intercept their own clicks before WM_NCHITTEST for the parent form is
    // ever consulted. Treating this whole strip as HTCAPTION (rather than
    // carving out HTCLOSE/HTMINBUTTON zones that don't line up with the
    // actual button positions) avoids clicks in the gaps between buttons
    // being misread as a system close/minimize.
    CaptionRect := Rect(0, 0, AForm.ClientWidth, CAPTION_HEIGHT);
    if PtInRect(CaptionRect, ClientPoint) then
      HitTest := HTCAPTION
    else
      HitTest := HTCLIENT;
  end
  else
    HitTest := HTCLIENT;

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

{ TEdgeHitTestHook }

class constructor TEdgeHitTestHook.Create;
begin
  inherited;
  FHooks := TDictionary<TWinControl, TEdgeHitTestHook>.Create;
end;

class destructor TEdgeHitTestHook.Destroy;
var
  Pair: TPair<TWinControl, TEdgeHitTestHook>;
begin
  for Pair in FHooks do
  begin
    if Pair.Value.FControl <> nil then
    begin
      if Pair.Value.FControl.HandleAllocated then
        Pair.Value.FControl.WindowProc := Pair.Value.FOrigProc;
      Pair.Value.FControl := nil;
    end;
  end;
  FHooks.Free;
  inherited;
end;

procedure TEdgeHitTestHook.HookProc(var Message: TMessage);
var
  P: TPoint;
begin
  if (Message.Msg = WM_NCHITTEST) and (FForm <> nil) and (FControl <> nil) then
  begin
    P := FForm.ScreenToClient(Point(
      SmallInt(LongRec(Message.LParam).Lo),
      SmallInt(LongRec(Message.LParam).Hi)));
    // Inside the resize band: let the point fall through to the form, whose
    // own WM_NCHITTEST handler turns it into an HT* sizing code. NOTE: the
    // form takes precedence (header drag stays custom outside the band).
    if (P.X < RESIZE_BORDER) or (P.X >= FForm.ClientWidth - RESIZE_BORDER) or
       (P.Y < RESIZE_BORDER) or (P.Y >= FForm.ClientHeight - RESIZE_BORDER) then
    begin
      Message.Result := HTTRANSPARENT;
      Exit;
    end;
  end;
  if Assigned(FOrigProc) then
    FOrigProc(Message);
end;

procedure TEdgeHitTestHook.Notification(AComponent: TComponent; Operation: TOperation);
var
  Key: TWinControl;
  Found: Boolean;
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FControl) then
  begin
    if FControl.HandleAllocated then
      FControl.WindowProc := FOrigProc;
    FControl := nil;
    Key := nil;
    Found := False;
    for Key in FHooks.Keys do
      if FHooks[Key] = Self then
      begin
        Found := True;
        Break;
      end;
    if Found then
      FHooks.Remove(Key);
    Free;
  end;
end;

class procedure TEdgeHitTestHook.InstallControl(AForm: TCustomForm; AControl: TWinControl);
var
  Hook: TEdgeHitTestHook;
  I: Integer;
  Child: TControl;
begin
  if (AControl = nil) or (AControl = AForm) or FHooks.ContainsKey(AControl) then
    Exit;
  Hook := TEdgeHitTestHook.Create(nil);
  Hook.FControl := AControl;
  Hook.FForm := AForm;
  Hook.FOrigProc := AControl.WindowProc;
  AControl.FreeNotification(Hook);
  AControl.WindowProc := Hook.HookProc;
  FHooks.Add(AControl, Hook);
  // Hook any existing windowed descendants too.
  for I := 0 to AControl.ControlCount - 1 do
  begin
    Child := AControl.Controls[I];
    if Child is TWinControl then
      InstallControl(AForm, TWinControl(Child));
  end;
end;

class procedure TEdgeHitTestHook.Install(AForm: TCustomForm);
var
  I: Integer;
begin
  if AForm = nil then
    Exit;
  for I := 0 to AForm.ControlCount - 1 do
    if AForm.Controls[I] is TWinControl then
      InstallControl(AForm, TWinControl(AForm.Controls[I]));
end;

end.