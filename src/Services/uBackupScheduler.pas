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
  uBackupService, uSettings, uILogger;

type
  TBackupScheduler = class
  private
    FBackupService: TBackupService;
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
  public
    constructor Create(ABackupService: TBackupService; ASettings: TSettings);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    // Re-reads settings (BackupEnabled, BackupIntervalDays) and applies
    // them to the current schedule. Call after the user accepts new
    // settings in TSettingsForm.
    procedure Refresh;
    // Forces an immediate backup tick. If a previous tick is still busy
    // the call is a no-op so we cannot stack multiple backups.
    procedure TickNow;
    property IsRunning: Boolean read FIsRunning;
    property IsBusy: Boolean read FIsBusy;
    property LastBackupAt: TDateTime read FLastBackupAt;
    property IntervalDays: Integer read FIntervalDays;
  end;

implementation

const
  MS_PER_DAY: Int64 = 24 * 60 * 60 * 1000;

{ TBackupScheduler }

constructor TBackupScheduler.Create(ABackupService: TBackupService; ASettings: TSettings);
begin
  inherited Create;
  FBackupService := ABackupService;
  FSettings := ASettings;
  FLogger := CreateLogger;
  FIntervalDays := 0;
  FIsBusy := False;
  FIsRunning := False;
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
begin
  FTimer.Enabled := False;
  FTimer.Interval := ComputeIntervalMs;
end;

procedure TBackupScheduler.OnTimer(Sender: TObject);
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
    FLastBackupAt := Now;
    FBackupService.Backup;
  finally
    FIsBusy := False;
  end;
  // Re-arm with the current interval (in case it changed since Start).
  ApplyInterval;
  FTimer.Enabled := True;
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
  ApplyInterval;
  FTimer.Enabled := True;
  FIsRunning := True;
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
    ApplyInterval
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

end.