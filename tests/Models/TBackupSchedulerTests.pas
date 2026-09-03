unit TBackupSchedulerTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
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
  // Create old backup (more than retention days old)
  OldFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20230101_120000.zip');
  TFile.WriteAllText(OldFile, 'old backup content');
  TFile.SetLastWriteTime(OldFile, Now - 10);

  // Create recent backup (less than retention days old)
  RecentFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20240101_120000.zip');
  TFile.WriteAllText(RecentFile, 'recent backup content');
  TFile.SetLastWriteTime(RecentFile, Now - 1);

  // Set retention to 7 days
  FSettings.BackupRetentionDays := 7;

  // Trigger backup which should also run cleanup
  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

  // Verify old file was deleted
  Assert.IsFalse(TFile.Exists(OldFile), 'Old backup should be deleted');

  // Verify recent file was preserved
  Assert.IsTrue(TFile.Exists(RecentFile), 'Recent backup should be preserved');
end;

initialization
  TDUnitX.RegisterTestFixture(TBackupSchedulerTestFixture);

end.