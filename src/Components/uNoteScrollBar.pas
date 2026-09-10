unit uNoteScrollBar;

{
  TNoteScrollBar
  ==============
  Self-contained custom vertical scrollbar for a TMemo (or any WinControl).

  Replaces pnlCustomScrollbar + pnlThumb + FTimerScroll + MemoContainerResize
  + OnScrollTimer in uNoteForm, and eliminates the fragile "Width+30 push
  native scrollbar off-screen" hack.

  Design
  ------
  - Attach() wires the component to a target TWinControl.
  - A low-frequency 50 ms timer reads GetScrollInfo from the target and
    repaints the thumb whenever the scroll position changes.
  - The thumb is draggable: MouseDown on the thumb enters drag mode;
    MouseMove sends WM_VSCROLL to the target.
  - Click in the track (outside thumb) sends a page-up / page-down.
  - MouseWheel events on the bar are forwarded to the target.

  Usage
  -----
    FScrollBar := TNoteScrollBar.CreateScrollBar(Self);
    FScrollBar.Parent      := Self;
    FScrollBar.Align       := alRight;
    FScrollBar.Width       := 8;
    FScrollBar.TrackColor  := clYellow;      // match note colour
    FScrollBar.ThumbColor  := clOlive;
    FScrollBar.Attach(mmContent);
}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Types,
  Vcl.Controls, Vcl.Graphics, Vcl.ExtCtrls;

type
  TNoteScrollBar = class(TCustomControl)
  private
    FTarget:       TWinControl;
    FTimer:        TTimer;

    FThumbTop:     Integer;
    FThumbHeight:  Integer;
    FThumbVisible: Boolean;

    FDragging:       Boolean;
    FDragStartY:     Integer;
    FDragStartThumb: Integer;
    FDragStartPos:   Integer;
    FLastScrollPos:  Integer;

    FTrackColor: TColor;
    FThumbColor: TColor;

    procedure OnTimer(Sender: TObject);
    procedure UpdateScrollInfo;
    function  TrackRect: TRect;
    function  ThumbRect: TRect;
    procedure ScrollTargetTo(APos: Integer);

  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure WMMouseWheel(var Message: TWMMouseWheel); message WM_MOUSEWHEEL;

  public
    constructor CreateScrollBar(AOwner: TComponent);
    destructor Destroy; override;

    procedure Attach(ATarget: TWinControl);
    procedure Detach;

    property TrackColor: TColor read FTrackColor write FTrackColor;
    property ThumbColor: TColor read FThumbColor write FThumbColor;
  end;

implementation

const
  TIMER_INTERVAL = 50;    // ms — scroll-position poll
  MIN_THUMB_H    = 24;    // minimum thumb height in pixels
  THUMB_MARGIN   = 2;     // inset of thumb from track edge

{ ── construction ─────────────────────────────────────────────────────────── }

constructor TNoteScrollBar.CreateScrollBar(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTarget       := nil;
  FDragging     := False;
  FThumbVisible := False;
  FLastScrollPos := -1;
  FTrackColor   := clBtnFace;
  FThumbColor   := clBtnShadow;

  Width          := 8;
  DoubleBuffered := True;

  FTimer          := TTimer.Create(Self);
  FTimer.Interval := TIMER_INTERVAL;
  FTimer.OnTimer  := OnTimer;
  FTimer.Enabled  := False;
end;

destructor TNoteScrollBar.Destroy;
begin
  FTimer.Free;
  inherited;
end;

{ ── attach / detach ──────────────────────────────────────────────────────── }

procedure TNoteScrollBar.Attach(ATarget: TWinControl);
begin
  FTarget := ATarget;
  FTimer.Enabled := Assigned(FTarget);
  // Hide the native scrollbar on the target to prevent double-bars
  if Assigned(FTarget) and FTarget.HandleAllocated then
    ShowScrollBar(FTarget.Handle, SB_VERT, False);
  UpdateScrollInfo;
  Invalidate;
end;

procedure TNoteScrollBar.Detach;
begin
  FTarget := nil;
  FTimer.Enabled := False;
  FThumbVisible  := False;
  Invalidate;
end;

{ ── scroll info ──────────────────────────────────────────────────────────── }

procedure TNoteScrollBar.UpdateScrollInfo;
var
  SI: TScrollInfo;
  TrackH: Integer;
  PageRatio: Double;
  Range: Integer;
  PosRatio: Double;
begin
  if not Assigned(FTarget) or not FTarget.HandleAllocated then
  begin
    FThumbVisible := False;
    Exit;
  end;

  SI.cbSize := SizeOf(SI);
  SI.fMask  := SIF_ALL;
  if not GetScrollInfo(FTarget.Handle, SB_VERT, SI) then
  begin
    FThumbVisible := False;
    Exit;
  end;

  if (SI.nMax <= 0) or (Integer(SI.nPage) >= SI.nMax) then
  begin
    FThumbVisible := False;
    Exit;
  end;

  TrackH    := ClientHeight - THUMB_MARGIN * 2;
  PageRatio := SI.nPage / (SI.nMax + 1);
  FThumbHeight := Max(MIN_THUMB_H, Round(TrackH * PageRatio));

  Range := SI.nMax - Integer(SI.nPage) + 1;
  if Range <= 0 then Range := 1;
  PosRatio := SI.nPos / Range;
  FThumbTop := THUMB_MARGIN + Round((TrackH - FThumbHeight) * PosRatio);
  FThumbVisible := True;
end;

procedure TNoteScrollBar.OnTimer(Sender: TObject);
var
  SI: TScrollInfo;
begin
  if not Assigned(FTarget) or not FTarget.HandleAllocated then Exit;

  SI.cbSize := SizeOf(SI);
  SI.fMask  := SIF_POS;
  if GetScrollInfo(FTarget.Handle, SB_VERT, SI) then
  begin
    if SI.nPos = FLastScrollPos then Exit; // nothing changed
    FLastScrollPos := SI.nPos;
  end;

  UpdateScrollInfo;
  Invalidate;
end;

{ ── geometry ─────────────────────────────────────────────────────────────── }

function TNoteScrollBar.TrackRect: TRect;
begin
  Result := ClientRect;
end;

function TNoteScrollBar.ThumbRect: TRect;
begin
  Result := Rect(THUMB_MARGIN, FThumbTop,
                 ClientWidth - THUMB_MARGIN, FThumbTop + FThumbHeight);
end;

{ ── paint ────────────────────────────────────────────────────────────────── }

procedure TNoteScrollBar.Paint;
var
  R: TRect;
begin
  Canvas.Brush.Color := FTrackColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  if not FThumbVisible then Exit;

  R := ThumbRect;
  Canvas.Brush.Color := FThumbColor;
  Canvas.Pen.Color   := FThumbColor;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 4, 4);
end;

{ ── scroll target ────────────────────────────────────────────────────────── }

procedure TNoteScrollBar.ScrollTargetTo(APos: Integer);
var
  SI: TScrollInfo;
begin
  if not Assigned(FTarget) or not FTarget.HandleAllocated then Exit;
  SI.cbSize := SizeOf(SI);
  SI.fMask  := SIF_POS;
  SI.nPos   := APos;
  SetScrollInfo(FTarget.Handle, SB_VERT, SI, True);
  // Notify the control it should repaint at the new position
  SendMessage(FTarget.Handle, WM_VSCROLL,
              MakeWParam(SB_THUMBTRACK, APos), 0);
  SendMessage(FTarget.Handle, WM_VSCROLL,
              MakeWParam(SB_THUMBPOSITION, APos), 0);
end;

{ ── mouse ────────────────────────────────────────────────────────────────── }

procedure TNoteScrollBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  SI: TScrollInfo;
begin
  inherited;
  if not Assigned(FTarget) or not FThumbVisible then Exit;

  if (Button = mbLeft) and PtInRect(ThumbRect, Point(X, Y)) then
  begin
    // Start drag
    FDragging       := True;
    FDragStartY     := Y;
    FDragStartThumb := FThumbTop;

    SI.cbSize := SizeOf(SI);
    SI.fMask  := SIF_POS;
    if GetScrollInfo(FTarget.Handle, SB_VERT, SI) then
      FDragStartPos := SI.nPos
    else
      FDragStartPos := 0;

    SetCapture(Handle);
  end
  else if Button = mbLeft then
  begin
    // Page up / down
    if Y < FThumbTop then
      SendMessage(FTarget.Handle, WM_VSCROLL, SB_PAGEUP, 0)
    else
      SendMessage(FTarget.Handle, WM_VSCROLL, SB_PAGEDOWN, 0);
    UpdateScrollInfo;
    Invalidate;
  end;
end;

procedure TNoteScrollBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  DeltaY, TrackH, Range: Integer;
  NewPos: Integer;
  SI: TScrollInfo;
begin
  inherited;
  if not FDragging then Exit;

  DeltaY := Y - FDragStartY;
  TrackH := ClientHeight - THUMB_MARGIN * 2 - FThumbHeight;
  if TrackH <= 0 then Exit;

  SI.cbSize := SizeOf(SI);
  SI.fMask  := SIF_ALL;
  if not GetScrollInfo(FTarget.Handle, SB_VERT, SI) then Exit;

  Range  := SI.nMax - Integer(SI.nPage) + 1;
  NewPos := FDragStartPos + Round(DeltaY / TrackH * Range);
  NewPos := Max(0, Min(NewPos, Range));
  ScrollTargetTo(NewPos);
  UpdateScrollInfo;
  Invalidate;
end;

procedure TNoteScrollBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FDragging then
  begin
    FDragging := False;
    ReleaseCapture;
  end;
end;

procedure TNoteScrollBar.WMMouseWheel(var Message: TWMMouseWheel);
begin
  // Forward wheel to target
  if Assigned(FTarget) and FTarget.HandleAllocated then
    SendMessage(FTarget.Handle, WM_MOUSEWHEEL,
                Message.Keys or (Message.WheelDelta shl 16), 0);
  Message.Result := 1;
end;

end.
