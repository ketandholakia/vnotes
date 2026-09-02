{
  Phase 4C additions:
    - IsRectOnAnyWorkArea / EnsureRectVisible: pure helpers that take a
      list of work-area rects and return whether a given rect is visible
      on any of them, or a clamped version when it is not. Pure
      (Win32-free) so the clamping math can be unit-tested.

  Phase 4C also adds a Screen-backed convenience overload used by
  TNoteForm to validate and clamp restored note positions.
}

unit uMonitorUtils;

interface

uses
  Winapi.Windows, Winapi.MultiMon, System.SysUtils, System.Types, Vcl.Forms;

type
  TMonitorUtils = class
  public
    class function GetMonitorFromWindow(AHandle: HWND): HMONITOR;
    class function GetMonitorRect(AMonitor: HMONITOR): TRect;
    class function GetMonitorWorkArea(AMonitor: HMONITOR): TRect;
    class function GetMonitorCount: Integer;
    class function GetPrimaryMonitor: HMONITOR;
    class function GetMonitorInfo(AMonitor: HMONITOR; out AInfo: TMonitorInfo): Boolean;
    class procedure ConstrainToMonitor(var ARect: TRect; AMonitor: HMONITOR = 0; AUseWorkArea: Boolean = True);
    class function GetMonitorAtPoint(const APoint: TPoint): HMONITOR;
    class function GetMonitorAtRect(const ARect: TRect): HMONITOR;
    class procedure CenterRectOnMonitor(var ARect: TRect; AMonitor: HMONITOR = 0);
    class function IsRectOnScreen(const ARect: TRect): Boolean;
    class function GetNearestMonitor(const ARect: TRect): HMONITOR;

    // Phase 4C: pure, testable helpers for note-position clamping.
    // ARect is treated as a normal Top/Left/Width/Height rectangle.
    // AWorkAreas is a list of monitor work-area rectangles (in the same
    // coordinate space as ARect).
    //
    // IsRectOnAnyWorkArea returns True iff ARect overlaps any of the
    // supplied work areas.
    //
    // EnsureRectVisible returns a rect that is guaranteed to overlap at
    // least one work area. If ARect is already visible on any monitor
    // it is returned unchanged; otherwise it is moved (preserving size)
    // so that its top-left sits inside the nearest work area.
    class function IsRectOnAnyWorkArea(const ARect: TRect;
      const AWorkAreas: array of TRect): Boolean;
    class function EnsureRectVisible(const ARect: TRect;
      const AWorkAreas: array of TRect): TRect;

    // Phase 4C: Screen-backed convenience wrapper used by TNoteForm.
    // Returns True if the note rect overlaps any monitor's work area.
    // Out parameter AAdjustedRect is either the original rect (if
    // already visible) or a clamped version (if not).
    class function EnsureNoteRectVisible(const ARect: TRect;
      out AAdjustedRect: TRect): Boolean;
  end;

implementation

{ TMonitorUtils }

class function TMonitorUtils.GetMonitorFromWindow(AHandle: HWND): HMONITOR;
begin
  Result := MonitorFromWindow(AHandle, MONITOR_DEFAULTTONEAREST);
end;

class function TMonitorUtils.GetMonitorRect(AMonitor: HMONITOR): TRect;
var
  MI: TMonitorInfo;
begin
  if GetMonitorInfo(AMonitor, MI) then
    Result := MI.rcMonitor
  else
    Result := Rect(0, 0, Screen.Width, Screen.Height);
end;

class function TMonitorUtils.GetMonitorWorkArea(AMonitor: HMONITOR): TRect;
var
  MI: TMonitorInfo;
begin
  if GetMonitorInfo(AMonitor, MI) then
    Result := MI.rcWork
  else
    Result := Rect(0, 0, Screen.Width, Screen.Height);
end;

class function TMonitorUtils.GetMonitorCount: Integer;
begin
  Result := Screen.MonitorCount;
end;

class function TMonitorUtils.GetPrimaryMonitor: HMONITOR;
begin
  Result := MonitorFromPoint(Point(0, 0), MONITOR_DEFAULTTOPRIMARY);
end;

class function TMonitorUtils.GetMonitorInfo(AMonitor: HMONITOR; out AInfo: TMonitorInfo): Boolean;
begin
  AInfo.cbSize := SizeOf(TMonitorInfo);
  // Qualify with the unit: an unqualified call would recurse into this
  // class method instead of the Win32 API of the same name.
  Result := Winapi.MultiMon.GetMonitorInfo(AMonitor, @AInfo);
end;

class procedure TMonitorUtils.ConstrainToMonitor(var ARect: TRect; AMonitor: HMONITOR; AUseWorkArea: Boolean);
var
  MonitorRect: TRect;
  Width, Height: Integer;
begin
  if AMonitor = 0 then
    AMonitor := GetMonitorFromWindow(0);
  
  if AUseWorkArea then
    MonitorRect := GetMonitorWorkArea(AMonitor)
  else
    MonitorRect := GetMonitorRect(AMonitor);
  
  Width := ARect.Width;
  Height := ARect.Height;
  
  // Constrain left
  if ARect.Left < MonitorRect.Left then
    ARect.Left := MonitorRect.Left;
  if ARect.Right > MonitorRect.Right then
    ARect.Left := MonitorRect.Right - Width;
  
  // Constrain top
  if ARect.Top < MonitorRect.Top then
    ARect.Top := MonitorRect.Top;
  if ARect.Bottom > MonitorRect.Bottom then
    ARect.Top := MonitorRect.Bottom - Height;
  
  ARect.Right := ARect.Left + Width;
  ARect.Bottom := ARect.Top + Height;
end;

class function TMonitorUtils.GetMonitorAtPoint(const APoint: TPoint): HMONITOR;
begin
  Result := MonitorFromPoint(APoint, MONITOR_DEFAULTTONEAREST);
end;

class function TMonitorUtils.GetMonitorAtRect(const ARect: TRect): HMONITOR;
begin
  // MonitorFromRect expects a PRect (pointer to rect), so pass @ARect.
  Result := MonitorFromRect(@ARect, MONITOR_DEFAULTTONEAREST);
end;

class procedure TMonitorUtils.CenterRectOnMonitor(var ARect: TRect; AMonitor: HMONITOR);
var
  MonitorRect: TRect;
  Width, Height: Integer;
begin
  if AMonitor = 0 then
    AMonitor := GetPrimaryMonitor;
  
  MonitorRect := GetMonitorWorkArea(AMonitor);
  Width := ARect.Width;
  Height := ARect.Height;
  
  ARect.Left := MonitorRect.Left + (MonitorRect.Width - Width) div 2;
  ARect.Top := MonitorRect.Top + (MonitorRect.Height - Height) div 2;
  ARect.Right := ARect.Left + Width;
  ARect.Bottom := ARect.Top + Height;
end;

class function TMonitorUtils.IsRectOnScreen(const ARect: TRect): Boolean;
var
  I: Integer;
  MonitorRect: TRect;
begin
  Result := False;
  for I := 0 to Screen.MonitorCount - 1 do
  begin
    MonitorRect := Screen.Monitors[I].BoundsRect;
    if (ARect.Right > MonitorRect.Left) and (ARect.Left < MonitorRect.Right) and
       (ARect.Bottom > MonitorRect.Top) and (ARect.Top < MonitorRect.Bottom) then
      Exit(True);
  end;
end;

class function TMonitorUtils.GetNearestMonitor(const ARect: TRect): HMONITOR;
var
  Center: TPoint;
begin
  Center := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
  Result := MonitorFromPoint(Center, MONITOR_DEFAULTTONEAREST);
end;

class function TMonitorUtils.IsRectOnAnyWorkArea(const ARect: TRect;
  const AWorkAreas: array of TRect): Boolean;
var
  I: Integer;
  R: TRect;
begin
  Result := False;
  for I := Low(AWorkAreas) to High(AWorkAreas) do
  begin
    R := AWorkAreas[I];
    // Standard two-rect overlap test: ARect overlaps R iff both axes
    // overlap. Touching edges do not count as overlapping.
    if (ARect.Right > R.Left) and (ARect.Left < R.Right) and
       (ARect.Bottom > R.Top) and (ARect.Top < R.Bottom) then
      Exit(True);
  end;
end;

class function TMonitorUtils.EnsureRectVisible(const ARect: TRect;
  const AWorkAreas: array of TRect): TRect;

  function SqDist(const APoint: TPoint; const R: TRect): Int64;
  var
    DX, DY: Int64;
  begin
    // Squared distance from the rect's centre to the work area.
    DX := APoint.X - ((R.Left + R.Right) div 2);
    DY := APoint.Y - ((R.Top + R.Bottom) div 2);
    Result := DX * DX + DY * DY;
  end;

var
  I, BestIdx: Integer;
  Center: TPoint;
  BestDist: Int64;
  R: TRect;
begin
  Result := ARect;
  // Preserve size by snapshotting now and restoring at the end.
  if IsRectOnAnyWorkArea(ARect, AWorkAreas) then Exit;

  if Length(AWorkAreas) = 0 then
  begin
    // No monitor info at all - leave the rect alone rather than
    // inventing coordinates.
    Exit;
  end;

  // Pick the work area whose centre is closest to the note's centre.
  Center := Point((ARect.Left + ARect.Right) div 2,
                  (ARect.Top + ARect.Bottom) div 2);
  BestIdx := Low(AWorkAreas);
  BestDist := SqDist(Center, AWorkAreas[BestIdx]);
  for I := Low(AWorkAreas) + 1 to High(AWorkAreas) do
  begin
    R := AWorkAreas[I];
    if SqDist(Center, R) < BestDist then
    begin
      BestIdx := I;
      BestDist := SqDist(Center, R);
    end;
  end;
  R := AWorkAreas[BestIdx];

  // Move the rect so its top-left sits inside the chosen work area,
  // preserving the original width and height. The clamp keeps the
  // top-left inside the work area horizontally; if the rect is taller
  // or wider than the work area we still anchor to the top-left and
  // let the bottom/right extend (rare for sticky-note-sized rects).
  Result.Left := R.Left + 8;
  Result.Top := R.Top + 8;
  Result.Right := Result.Left + ARect.Width;
  Result.Bottom := Result.Top + ARect.Height;
end;

class function TMonitorUtils.EnsureNoteRectVisible(const ARect: TRect;
  out AAdjustedRect: TRect): Boolean;
var
  WorkAreas: array of TRect;
  I: Integer;
begin
  // Collect work areas from VCL Screen; fall back to a single whole-Screen
  // rectangle if there are no monitors (e.g. during early startup).
  if Screen.MonitorCount = 0 then
  begin
    SetLength(WorkAreas, 1);
    WorkAreas[0] := Rect(0, 0, Screen.Width, Screen.Height);
  end
  else
  begin
    SetLength(WorkAreas, Screen.MonitorCount);
    for I := 0 to Screen.MonitorCount - 1 do
      WorkAreas[I] := Screen.Monitors[I].WorkareaRect;
  end;
  Result := IsRectOnAnyWorkArea(ARect, WorkAreas);
  if Result then
    AAdjustedRect := ARect
  else
    AAdjustedRect := EnsureRectVisible(ARect, WorkAreas);
end;

end.