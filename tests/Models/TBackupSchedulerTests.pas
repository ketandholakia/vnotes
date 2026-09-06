unit TBackupSchedulerTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  DUnitX.TestFramework,
  uBackupScheduler, uBackupService, uSettings, uNoteManager, uStorage,
  uJsonStorage, uNote, uEnums;

type
  [TestFixture]
  TBackupSchedulerTestFixture = class
  private
    FBasePath: string;
    FNotesPath: string;
    FBackupPath: string;
    FStorage: INoteStorage;
    FNoteManager: TNoteManager;
    FSettings: TSettings;
    FBackupService: TBackupService;
    FScheduler: TBackupScheduler;
    FBackupCount: Integer;
    procedure OnBackupComplete(ASuccess: Boolean; const AMessage: string);
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDisabledSettingsDoNotStart;
    [Test]
    procedure TestEnabledSettingsStartScheduler;
    [Test]
    procedure TestStopHaltsScheduler;
    [Test]
    procedure TestRefreshWithDisabledStopsRunning;
    [Test]
    procedure TestRefreshWithEnabledRestarts;
    [Test]
    procedure TestRefreshUpdatesIntervalDays;
    [Test]
    procedure TestTickNowRespectsDisabledFlag;
    [Test]
    procedure TestTickNowInvokesBackupWhenEnabled;
    [Test]
    procedure TestBackupRetentionCleanup;
    [Test]
    procedure TestLargeIntervalClamping;
    [Test]
    procedure TestSchedulerRestoresPersistedTimestamp;
    [Test]
    procedure TestSuccessfulBackupUpdatesTimestamp;
    [Test]
    procedure TestFailedBackupDoesNotUpdateTimestamp;
  end;

implementation

procedure TBackupSchedulerTestFixture.OnBackupComplete(ASuccess: Boolean;
  const AMessage: string);
begin
  Inc(FBackupCount);
end;

procedure TBackupSchedulerTestFixture.SetUp;
begin
  FBasePath := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_BackupSchedulerTest_' + IntToStr(TThread.GetTickCount));
  FNotesPath := TPath.Combine(FBasePath, 'notes');
  FBackupPath := TPath.Combine(FBasePath, 'backups');
  ForceDirectories(FNotesPath);
  ForceDirectories(FBackupPath);

  FStorage := TJsonStorage.Create(FBasePath);
  FNoteManager := TNoteManager.Create(FStorage);
  FNoteManager.Initialize;

  FSettings := TSettings.Create;
  FSettings.BackupEnabled := True;
  FSettings.BackupIntervalDays := 1;

  FBackupService := TBackupService.Create(FNoteManager, FSettings, FBackupPath);
  FBackupService.OnComplete := OnBackupComplete;

  FBackupCount := 0;
  FScheduler := TBackupScheduler.Create(FBackupService, FSettings);
end;

procedure TBackupSchedulerTestFixture.TearDown;
begin
  FreeAndNil(FScheduler);
  FreeAndNil(FBackupService);
  FreeAndNil(FSettings);
  FreeAndNil(FNoteManager);
  FStorage := nil;
  if TDirectory.Exists(FBasePath) then
    TDirectory.Delete(FBasePath, True);
end;

procedure TBackupSchedulerTestFixture.TestDisabledSettingsDoNotStart;
begin
  FSettings.BackupEnabled := False;
  FScheduler.Start;
  Assert.IsFalse(FScheduler.IsRunning,
    'Scheduler must NOT run when BackupEnabled is False');
end;

procedure TBackupSchedulerTestFixture.TestEnabledSettingsStartScheduler;
begin
  FSettings.BackupEnabled := True;
  FSettings.BackupIntervalDays := 7;
  FScheduler.Start;
  Assert.IsTrue(FScheduler.IsRunning,
    'Scheduler must run when BackupEnabled is True');
  Assert.AreEqual(7, FScheduler.IntervalDays,
    'Scheduler should pick up the configured interval in days');
end;

procedure TBackupSchedulerTestFixture.TestStopHaltsScheduler;
begin
  FScheduler.Start;
  Assert.IsTrue(FScheduler.IsRunning);
  FScheduler.Stop;
  Assert.IsFalse(FScheduler.IsRunning, 'Stop must halt the running schedule');
end;

procedure TBackupSchedulerTestFixture.TestRefreshWithDisabledStopsRunning;
begin
  FScheduler.Start;
  Assert.IsTrue(FScheduler.IsRunning);
  FSettings.BackupEnabled := False;
  FScheduler.Refresh;
  Assert.IsFalse(FScheduler.IsRunning,
    'Refresh with BackupEnabled=False must stop the schedule');
end;

procedure TBackupSchedulerTestFixture.TestRefreshWithEnabledRestarts;
begin
  FSettings.BackupEnabled := False;
  FScheduler.Start;
  Assert.IsFalse(FScheduler.IsRunning);
  FSettings.BackupEnabled := True;
  FSettings.BackupIntervalDays := 3;
  FScheduler.Refresh;
  Assert.IsTrue(FScheduler.IsRunning,
    'Refresh with BackupEnabled=True must start the schedule');
  Assert.AreEqual(3, FScheduler.IntervalDays);
end;

procedure TBackupSchedulerTestFixture.TestRefreshUpdatesIntervalDays;
begin
  FScheduler.Start;
  Assert.AreEqual(1, FScheduler.IntervalDays);
  FSettings.BackupIntervalDays := 14;
  FScheduler.Refresh;
  Assert.AreEqual(14, FScheduler.IntervalDays,
    'Refresh must pick up the new interval from settings');
  Assert.IsTrue(FScheduler.IsRunning);
end;

procedure TBackupSchedulerTestFixture.TestTickNowRespectsDisabledFlag;
begin
  FSettings.BackupEnabled := False;
  FScheduler.TickNow;
  Assert.AreEqual(0, FBackupCount,
    'TickNow must not run a backup when BackupEnabled is False');
end;

procedure TBackupSchedulerTestFixture.TestTickNowInvokesBackupWhenEnabled;
begin
  FSettings.BackupEnabled := True;
  FScheduler.TickNow;
  Assert.AreEqual(1, FBackupCount,
    'TickNow must trigger exactly one backup when enabled');
  Assert.IsTrue(FScheduler.LastBackupAt > 0,
    'LastBackupAt must be set after a successful tick');
end;

procedure TBackupSchedulerTestFixture.TestBackupRetentionCleanup;
var
  OldFile: string;
  RecentFile: string;
begin
  OldFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20230101_120000.zip');
  TFile.WriteAllText(OldFile, 'old backup content');
  TFile.SetLastWriteTime(OldFile, Now - 10);

  RecentFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20240101_120000.zip');
  TFile.WriteAllText(RecentFile, 'recent backup content');
  TFile.SetLastWriteTime(RecentFile, Now - 1);

  FSettings.BackupRetentionDays := 7;

  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

  Assert.IsFalse(TFile.Exists(OldFile), 'Old backup should be deleted');
  Assert.IsTrue(TFile.Exists(RecentFile), 'Recent backup should be preserved');
end;

procedure TBackupSchedulerTestFixture.TestLargeIntervalClamping;
begin
  FSettings.BackupIntervalDays := 100000;
  FScheduler.Refresh;
  Assert.IsTrue(FScheduler.IsRunning,
    'Scheduler should start even with very large interval (clamped internally)');
  Assert.AreEqual(100000, FScheduler.IntervalDays,
    'IntervalDays setting should be preserved as-is');
end;

procedure TBackupSchedulerTestFixture.TestSchedulerRestoresPersistedTimestamp;
var
  KnownTime: TDateTime;
  LocalSettings: TSettings;
  LocalScheduler: TBackupScheduler;
begin
  KnownTime := EncodeDateTime(2026, 9, 6, 10, 0, 0, 0);
  LocalSettings := TSettings.Create;
  try
    LocalSettings.LastBackupAt := KnownTime;
    LocalScheduler := TBackupScheduler.Create(FBackupService, LocalSettings);
    try
      Assert.AreEqual(Double(KnownTime), Double(LocalScheduler.LastBackupAt), 0.0001,
        'Scheduler must initialize LastBackupAt from persisted settings');
    finally
      LocalScheduler.Free;
    end;
  finally
    LocalSettings.Free;
  end;
end;

procedure TBackupSchedulerTestFixture.TestSuccessfulBackupUpdatesTimestamp;
var
  BeforeTime: TDateTime;
begin
  BeforeTime := Now;
  FSettings.BackupEnabled := True;
  FScheduler.TickNow;
  Assert.IsTrue(FScheduler.LastBackupAt >= BeforeTime,
    'Scheduler LastBackupAt should be updated after successful backup');
  Assert.IsTrue(FSettings.LastBackupAt >= BeforeTime,
    'Settings LastBackupAt should be updated after successful backup');
end;

type
  TFailedBackupServiceStub = class(TBackupService)
  public
    function Backup: Boolean; override;
  end;

function TFailedBackupServiceStub.Backup: Boolean;
begin
  Result := False;
end;

procedure TBackupSchedulerTestFixture.TestFailedBackupDoesNotUpdateTimestamp;
var
  PrevTime: TDateTime;
  BadScheduler: TBackupScheduler;
  FailedService: TBackupService;
begin
  PrevTime := EncodeDateTime(2026, 1, 1, 12, 0, 0, 0);
  FSettings.LastBackupAt := PrevTime;

  FailedService := TFailedBackupServiceStub.Create(FNoteManager, FSettings, FBackupPath);
  try
    BadScheduler := TBackupScheduler.Create(FailedService, FSettings);
    try
      BadScheduler.TickNow;
      Assert.AreEqual(Double(PrevTime), Double(BadScheduler.LastBackupAt), 0.0001,
        'Scheduler LastBackupAt must remain unchanged on failed backup');
      Assert.AreEqual(Double(PrevTime), Double(FSettings.LastBackupAt), 0.0001,
        'Settings LastBackupAt must remain unchanged on failed backup');
    finally
      BadScheduler.Free;
    end;
  finally
    FailedService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBackupSchedulerTestFixture);

end.