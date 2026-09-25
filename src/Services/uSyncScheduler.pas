unit uSyncScheduler;

{
  Phase 7D/7E: scheduled (interval) sync - mirrors TBackupScheduler.

  A single timer owns periodic sync. Runs are executed through a TSyncRunner so
  the I/O happens off the UI thread; the busy state is the runner's, which also
  prevents overlapping runs.

  Behaviour:
   - Start:   arms the timer with the current SyncIntervalMinutes (no-op if
              already running, or if sync is disabled).
   - Stop:    disarms the timer.
   - Refresh: re-reads settings and re-arms (or stops).
   - TickNow: forces an immediate tick (tests / manual triggers).

  LastSyncAt records when the most recent run was started.
}

interface

uses
  System.SysUtils, System.Classes, Vcl.ExtCtrls,
  uSettings, uILogger, uServiceInterfaces, uSyncRunner;

type
  TSyncScheduler = class(TInterfacedObject, ISyncScheduler)
  private
    FSyncService: ISyncService;
    FRunner: TSyncRunner;
    FSettings: TSettings;
    FTimer: TTimer;
    FIntervalMinutes: Integer;
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
    constructor Create(const ASyncService: ISyncService; const ARunner: TSyncRunner;
      ASettings: TSettings);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure Refresh;
    procedure TickNow;
    // Blocks until the current run (if any) has finished. For tests/diagnostics.
    procedure WaitForIdle;
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

constructor TSyncScheduler.Create(const ASyncService: ISyncService;
  const ARunner: TSyncRunner; ASettings: TSettings);
begin
  inherited Create;
  FSyncService := ASyncService;
  FRunner := ARunner;
  FSettings := ASettings;
  FLogger := CreateLogger;
  FIntervalMinutes := 0;
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
begin
  if (FSettings = nil) or (not FSettings.SyncEnabled) then
  begin
    Stop; // settings were turned off between ticks
    Exit;
  end;
  if FRunner <> nil then
  begin
    if FRunner.IsRunning then Exit; // never overlap
    FLastSyncAt := Now;
    FRunner.Start;
  end
  else if FSyncService <> nil then
  begin
    FLastSyncAt := Now;
    FSyncService.SyncNow;
  end;
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
  if (FSettings = nil) or (not FSettings.SyncEnabled) then Exit;
  if FRunner <> nil then
  begin
    if FRunner.IsRunning then Exit;
    FLastSyncAt := Now;
    FRunner.Start;
  end
  else if FSyncService <> nil then
  begin
    FLastSyncAt := Now;
    FSyncService.SyncNow;
  end;
end;

procedure TSyncScheduler.WaitForIdle;
begin
  if FRunner <> nil then
    FRunner.WaitForIdle;
end;

function TSyncScheduler.GetIsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TSyncScheduler.GetIsBusy: Boolean;
begin
  Result := (FRunner <> nil) and FRunner.IsRunning;
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
