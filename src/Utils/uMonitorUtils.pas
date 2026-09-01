unit uMonitorUtils;

interface

uses
  Winapi.Windows, System.SysUtils, System.Types, Vcl.Forms;

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
  Result := GetMonitorInfo(AMonitor, @AInfo);
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
  Result := MonitorFromRect(ARect, MONITOR_DEFAULTTONEAREST);
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

end.