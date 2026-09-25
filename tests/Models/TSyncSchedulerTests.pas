unit TSyncSchedulerTests;

interface

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  uSettings, uServiceInterfaces, uSyncRunner, uSyncScheduler;

type
  // Minimal ISyncService stub that counts SyncNow invocations.
  TStubSyncService = class(TInterfacedObject, ISyncService)
  private
    FSyncCount: Integer;
    FNextResult: Boolean;
    FOnProgress: TSyncProgress;
    FOnComplete: TSyncComplete;
  public
    function IsConfigured: Boolean;
    function SyncNow: Boolean;
    function GetOnProgress: TSyncProgress;
    procedure SetOnProgress(const Value: TSyncProgress);
    function GetOnComplete: TSyncComplete;
    procedure SetOnComplete(const Value: TSyncComplete);
    property SyncCount: Integer read FSyncCount;
    property NextResult: Boolean read FNextResult write FNextResult;
    property OnProgress: TSyncProgress read GetOnProgress write SetOnProgress;
    property OnComplete: TSyncComplete read GetOnComplete write SetOnComplete;
  end;

  [TestFixture]
  TSyncSchedulerTestFixture = class
  public
    [Test]
    procedure TestStartDoesNothingWhenDisabled;
    [Test]
    procedure TestStartArmsWhenEnabled;
    [Test]
    procedure TestTickNowRunsSyncOffThread;
    [Test]
    procedure TestTickNowDoesNothingWhenDisabled;
    [Test]
    procedure TestRefreshStopsWhenDisabled;
    [Test]
    procedure TestRunnerRunsSyncOffThread;
  end;

implementation

{ TStubSyncService }

function TStubSyncService.IsConfigured: Boolean;
begin
  Result := True;
end;

function TStubSyncService.SyncNow: Boolean;
begin
  Inc(FSyncCount);
  Result := FNextResult;
end;

function TStubSyncService.GetOnProgress: TSyncProgress;
begin
  Result := FOnProgress;
end;

procedure TStubSyncService.SetOnProgress(const Value: TSyncProgress);
begin
  FOnProgress := Value;
end;

function TStubSyncService.GetOnComplete: TSyncComplete;
begin
  Result := FOnComplete;
end;

procedure TStubSyncService.SetOnComplete(const Value: TSyncComplete);
begin
  FOnComplete := Value;
end;

{ TSyncSchedulerTestFixture }

procedure TSyncSchedulerTestFixture.TestStartDoesNothingWhenDisabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Runner: TSyncRunner;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Runner := TSyncRunner.Create(Stub);
  Sch := TSyncScheduler.Create(Stub, Runner, S);
  try
    S.SyncEnabled := False;
    Sch.Start;
    Assert.IsFalse(Sch.IsRunning, 'scheduler must not arm when sync is disabled');
  finally
    Sch.Free;
    Runner.Free; // releases the last reference to Stub
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestStartArmsWhenEnabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Runner: TSyncRunner;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Runner := TSyncRunner.Create(Stub);
  Sch := TSyncScheduler.Create(Stub, Runner, S);
  try
    S.SyncEnabled := True;
    S.SyncIntervalMinutes := 5;
    Sch.Start;
    Assert.IsTrue(Sch.IsRunning, 'scheduler should arm when sync is enabled');
    Assert.AreEqual<Integer>(5, Sch.IntervalMinutes);
  finally
    Sch.Free;
    Runner.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestTickNowRunsSyncOffThread;
var
  S: TSettings;
  Stub: TStubSyncService;
  Runner: TSyncRunner;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Runner := TSyncRunner.Create(Stub);
  Sch := TSyncScheduler.Create(Stub, Runner, S);
  try
    S.SyncEnabled := True;
    Stub.NextResult := True;
    Sch.Start;
    Sch.TickNow;
    Assert.IsTrue(Sch.LastSyncAt > 0, 'a tick should record when the run started');
    Sch.WaitForIdle; // let the worker finish
    Assert.AreEqual<Integer>(1, Stub.SyncCount, 'TickNow must run exactly one sync');
  finally
    Sch.Free;
    Runner.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestTickNowDoesNothingWhenDisabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Runner: TSyncRunner;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Runner := TSyncRunner.Create(Stub);
  Sch := TSyncScheduler.Create(Stub, Runner, S);
  try
    S.SyncEnabled := False;
    Sch.TickNow;
    Sch.WaitForIdle;
    Assert.AreEqual<Integer>(0, Stub.SyncCount, 'a disabled scheduler must not sync');
  finally
    Sch.Free;
    Runner.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestRefreshStopsWhenDisabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Runner: TSyncRunner;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Runner := TSyncRunner.Create(Stub);
  Sch := TSyncScheduler.Create(Stub, Runner, S);
  try
    S.SyncEnabled := True;
    Sch.Start;
    Assert.IsTrue(Sch.IsRunning);
    S.SyncEnabled := False;
    Sch.Refresh;
    Assert.IsFalse(Sch.IsRunning, 'disabling sync must stop the schedule');
  finally
    Sch.Free;
    Runner.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestRunnerRunsSyncOffThread;
var
  Stub: TStubSyncService;
  Runner: TSyncRunner;
begin
  Stub := TStubSyncService.Create;
  Runner := TSyncRunner.Create(Stub);
  try
    Stub.NextResult := True;
    Assert.IsFalse(Runner.IsRunning, 'a fresh runner is idle');
    Runner.Start;
    Runner.WaitForIdle;
    Assert.AreEqual<Integer>(1, Stub.SyncCount, 'the runner must invoke SyncNow once');
  finally
    Runner.Free; // releases the only reference to Stub
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncSchedulerTestFixture);

end.
