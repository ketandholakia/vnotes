unit uBackupScheduler;

{
  Phase 4C: scheduled (periodic) backup.

  Watches the user's backup settings (BackupEnabled, BackupIntervalDays)
  and periodically asks the existing TBackupService to perform a backup.
  Single timer, single owner: the scheduler is the only component that
  arms the periodic timer, and it guards against concurrent invocations
  via an internal FIsBusy flag.

  Behaviour:
   - Start: arms the timer using the current BackupIntervalDays (if the
     timer is already running, this is a no-op).
   - Stop: disarms the timer.
   - Refresh: re-reads settings and re-arms the timer with the new
     interval (or stops it if backup has been disabled).
   - TickNow: forces an immediate backup tick (used by tests and the
     "Backup Now" tray menu).
}

interface

uses
  System.SysUtils, System.Classes, Vcl.ExtCtrls,
  uBackupService, uSettings, uILogger, uServiceInterfaces;

type
  TBackupScheduler = class(TInterfacedObject, IBackupScheduler)
  private
    FBackupService: IBackupService;
    FSettings: TSettings;
    FTimer: TTimer;
    FIntervalDays: Integer;
    FIsBusy: Boolean;
    FIsRunning: Boolean;
    FLastBackupAt: TDateTime;
    FLogger: ILogger;
    procedure OnTimer(Sender: TObject);
    procedure ApplyInterval;
    function ComputeIntervalMs: Int64;
    function IsOverdue: Boolean;
    function GetIsRunning: Boolean;
    function GetIsBusy: Boolean;
    function GetLastBackupAt: TDateTime;
    function GetIntervalDays: Integer;
  public
    constructor Create(const ABackupService: IBackupService; ASettings: TSettings);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure Refresh;
    procedure TickNow;
    property IsRunning: Boolean read GetIsRunning;
    property IsBusy: Boolean read GetIsBusy;
    property LastBackupAt: TDateTime read GetLastBackupAt;
    property IntervalDays: Integer read GetIntervalDays;
  end;

implementation

const
  MS_PER_DAY: Int64 = 24 * 60 * 60 * 1000;

{ TBackupScheduler }

constructor TBackupScheduler.Create(const ABackupService: IBackupService; ASettings: TSettings);
begin
  inherited Create;
  FBackupService := ABackupService;
  FSettings := ASettings;
  FLogger := CreateLogger;
  FIntervalDays := 0;
  FIsBusy := False;
  FIsRunning := False;
  if FSettings <> nil then
    FLastBackupAt := FSettings.LastBackupAt
  else
    FLastBackupAt := 0;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.OnTimer := OnTimer;
end;

destructor TBackupScheduler.Destroy;
begin
  Stop;
  FTimer.Free;
  inherited;
end;

function TBackupScheduler.ComputeIntervalMs: Int64;
begin
  // Defensive: never let a misconfigured interval (<= 0) collapse the
  // timer to "fire every millisecond" which would peg the UI thread.
  if FIntervalDays <= 0 then
    Result := MS_PER_DAY
  else
    Result := Int64(FIntervalDays) * MS_PER_DAY;
end;

procedure TBackupScheduler.ApplyInterval;
const
  // TTimer.Interval is Cardinal (max ~49.7 days); the old High(Integer)
  // clamp silently shortened configured intervals of 25-30 days.
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

procedure TBackupScheduler.OnTimer(Sender: TObject);
var
  BackupSuccess: Boolean;
  BackupTime: TDateTime;
begin
  if FIsBusy then Exit;
  if not Assigned(FBackupService) then Exit;
  if (FSettings = nil) or (not FSettings.BackupEnabled) then
  begin
    // Settings were turned off between ticks - stop the schedule.
    Stop;
    Exit;
  end;
  FIsBusy := True;
  try
    BackupTime := Now;
    BackupSuccess := FBackupService.Backup;
    if BackupSuccess then
    begin
      FLastBackupAt := BackupTime;
      FSettings.LastBackupAt := FLastBackupAt;
    end;
  finally
    FIsBusy := False;
  end;
  // Re-arm with the current interval (in case it changed since Start).
  ApplyInterval;
  FTimer.Enabled := True;
end;

function TBackupScheduler.IsOverdue: Boolean;
var
  Days: Integer;
begin
  if FSettings = nil then
    Exit(False);
  Days := FSettings.BackupIntervalDays;
  if Days <= 0 then
    Days := 1;
  // TDateTime subtraction yields fractional days.
  if FLastBackupAt <= 0 then
    Result := True // never backed up - run the first backup right away
  else
    Result := (Now - FLastBackupAt) >= Days;
end;

procedure TBackupScheduler.Start;
begin
  if FIsRunning then Exit;
  if (FSettings = nil) then Exit;
  if not FSettings.BackupEnabled then
  begin
    // Backup is disabled, do not arm the schedule.
    FLogger.Debug('BackupScheduler: Start skipped - BackupEnabled is False');
    Exit;
  end;
  FIntervalDays := FSettings.BackupIntervalDays;
  FIsRunning := True;
  // Catch-up: a TTimer does not accumulate across app restarts or system
  // sleep, so a plain re-arm could postpone an overdue backup by a full
  // interval. If the schedule is already due (or has never run), tick
  // now; OnTimer performs the backup and re-arms the timer.
  if IsOverdue then
    OnTimer(nil)
  else
  begin
    ApplyInterval;
    FTimer.Enabled := True;
  end;
  FLogger.Info(Format('BackupScheduler: Started (every %d day(s))',
    [FIntervalDays]));
end;

procedure TBackupScheduler.Stop;
begin
  if not FIsRunning then Exit;
  FTimer.Enabled := False;
  FIsRunning := False;
  FLogger.Debug('BackupScheduler: Stopped');
end;

procedure TBackupScheduler.Refresh;
begin
  // Pull the latest settings values and re-arm (or stop) accordingly.
  if FSettings = nil then Exit;
  if not FSettings.BackupEnabled then
  begin
    Stop;
    Exit;
  end;
  FIntervalDays := FSettings.BackupIntervalDays;
  if FIsRunning then
  begin
    // A settings change can make the schedule overdue (e.g. a shortened
    // interval): catch up immediately instead of waiting a full interval.
    if IsOverdue then
      OnTimer(nil)
    else
      ApplyInterval;
  end
  else
    Start;
end;

procedure TBackupScheduler.TickNow;
begin
  // For tests + manual triggers. Honours the disabled-flag and the
  // busy-guard so this is safe to call from anywhere.
  if FIsBusy then Exit;
  if (FSettings = nil) or (not FSettings.BackupEnabled) then Exit;
  OnTimer(nil);
end;

function TBackupScheduler.GetIsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TBackupScheduler.GetIsBusy: Boolean;
begin
  Result := FIsBusy;
end;

function TBackupScheduler.GetLastBackupAt: TDateTime;
begin
  Result := FLastBackupAt;
end;

function TBackupScheduler.GetIntervalDays: Integer;
begin
  Result := FIntervalDays;
end;

end.