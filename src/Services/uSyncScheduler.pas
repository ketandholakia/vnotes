unit uSyncScheduler;

{
  Phase 7D: scheduled (interval) sync - mirrors TBackupScheduler.

  A single timer owns periodic sync. The scheduler is the only component that
  arms it, and an internal FIsBusy flag prevents overlapping runs.

  Behaviour:
   - Start:   arms the timer with the current SyncIntervalMinutes (no-op if
              already running, or if sync is disabled).
   - Stop:    disarms the timer.
   - Refresh: re-reads settings and re-arms (or stops).
   - TickNow: forces an immediate tick (tests / manual triggers).

  Note: SyncNow runs synchronously on the main thread. For the folder backend
  that is a fast filesystem pass; a future networked backend should move the
  work off the UI thread.
}

interface

uses
  System.SysUtils, System.Classes, Vcl.ExtCtrls,
  uSettings, uILogger, uServiceInterfaces;

type
  TSyncScheduler = class(TInterfacedObject, ISyncScheduler)
  private
    FSyncService: ISyncService;
    FSettings: TSettings;
    FTimer: TTimer;
    FIntervalMinutes: Integer;
    FIsBusy: Boolean;
    FIsRunning: Boolean;
    FLastSyncAt: TDateTime;
    FLogger: ILogger;
    procedure OnTimer(Sender: TObject);
    procedure ApplyInterval;
    function ComputeIntervalMs: Int64;
    function GetIsRunning: Boolean;
    function GetIsBusy: Boolean;
    function GetLastSyncAt: TDateTime;
    function GetIntervalMinutes: Integer;
  public
    constructor Create(const ASyncService: ISyncService; ASettings: TSettings);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure Refresh;
    procedure TickNow;
    property IsRunning: Boolean read GetIsRunning;
    property IsBusy: Boolean read GetIsBusy;
    property LastSyncAt: TDateTime read GetLastSyncAt;
    property IntervalMinutes: Integer read GetIntervalMinutes;
  end;

implementation

const
  MS_PER_MINUTE: Int64 = 60 * 1000;
  DEFAULT_INTERVAL_MINUTES = 15;

{ TSyncScheduler }

constructor TSyncScheduler.Create(const ASyncService: ISyncService; ASettings: TSettings);
begin
  inherited Create;
  FSyncService := ASyncService;
  FSettings := ASettings;
  FLogger := CreateLogger;
  FIntervalMinutes := 0;
  FIsBusy := False;
  FIsRunning := False;
  FLastSyncAt := 0;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.OnTimer := OnTimer;
end;

destructor TSyncScheduler.Destroy;
begin
  Stop;
  FTimer.Free;
  inherited;
end;

function TSyncScheduler.ComputeIntervalMs: Int64;
begin
  // Defensive: never let a misconfigured interval (<= 0) collapse the timer.
  if FIntervalMinutes <= 0 then
    Result := Int64(DEFAULT_INTERVAL_MINUTES) * MS_PER_MINUTE
  else
    Result := Int64(FIntervalMinutes) * MS_PER_MINUTE;
end;

procedure TSyncScheduler.ApplyInterval;
const
  MAX_TIMER_INTERVAL = High(Cardinal);
var
  Computed: Int64;
begin
  FTimer.Enabled := False;
  Computed := ComputeIntervalMs;
  if Computed > MAX_TIMER_INTERVAL then
    Computed := MAX_TIMER_INTERVAL;
  FTimer.Interval := Computed;
end;

procedure TSyncScheduler.OnTimer(Sender: TObject);
var
  Success: Boolean;
begin
  if FIsBusy then Exit;
  if not Assigned(FSyncService) then Exit;
  if (FSettings = nil) or (not FSettings.SyncEnabled) then
  begin
    Stop; // settings were turned off between ticks
    Exit;
  end;

  FIsBusy := True;
  try
    Success := FSyncService.SyncNow;
    if Success then
      FLastSyncAt := Now;
  finally
    FIsBusy := False;
  end;

  // Re-arm with the current interval (in case it changed since Start).
  ApplyInterval;
  FTimer.Enabled := True;
end;

procedure TSyncScheduler.Start;
begin
  if FIsRunning then Exit;
  if FSettings = nil then Exit;
  if not FSettings.SyncEnabled then
  begin
    FLogger.Debug('SyncScheduler: Start skipped - SyncEnabled is False');
    Exit;
  end;
  FIntervalMinutes := FSettings.SyncIntervalMinutes;
  FIsRunning := True;
  ApplyInterval;
  FTimer.Enabled := True;
  FLogger.Info(Format('SyncScheduler: Started (every %d minute(s))', [FIntervalMinutes]));
end;

procedure TSyncScheduler.Stop;
begin
  if not FIsRunning then Exit;
  FTimer.Enabled := False;
  FIsRunning := False;
  FLogger.Debug('SyncScheduler: Stopped');
end;

procedure TSyncScheduler.Refresh;
begin
  if FSettings = nil then Exit;
  if not FSettings.SyncEnabled then
  begin
    Stop;
    Exit;
  end;
  FIntervalMinutes := FSettings.SyncIntervalMinutes;
  if FIsRunning then
    ApplyInterval
  else
    Start;
end;

procedure TSyncScheduler.TickNow;
begin
  if FIsBusy then Exit;
  if (FSettings = nil) or (not FSettings.SyncEnabled) then Exit;
  OnTimer(nil);
end;

function TSyncScheduler.GetIsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TSyncScheduler.GetIsBusy: Boolean;
begin
  Result := FIsBusy;
end;

function TSyncScheduler.GetLastSyncAt: TDateTime;
begin
  Result := FLastSyncAt;
end;

function TSyncScheduler.GetIntervalMinutes: Integer;
begin
  Result := FIntervalMinutes;
end;

end.
