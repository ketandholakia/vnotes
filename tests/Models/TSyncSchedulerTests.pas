unit TSyncSchedulerTests;

interface

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  uSettings, uServiceInterfaces, uSyncScheduler;

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
    procedure TestTickNowInvokesSyncAndStampsLastSync;
    [Test]
    procedure TestTickNowDoesNothingWhenDisabled;
    [Test]
    procedure TestRefreshStopsWhenDisabled;
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
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Sch := TSyncScheduler.Create(Stub, S);
  try
    S.SyncEnabled := False;
    Sch.Start;
    Assert.IsFalse(Sch.IsRunning, 'scheduler must not arm when sync is disabled');
  finally
    Sch.Free; // releases + frees Stub
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestStartArmsWhenEnabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Sch := TSyncScheduler.Create(Stub, S);
  try
    S.SyncEnabled := True;
    S.SyncIntervalMinutes := 5;
    Sch.Start;
    Assert.IsTrue(Sch.IsRunning, 'scheduler should arm when sync is enabled');
    Assert.AreEqual<Integer>(5, Sch.IntervalMinutes);
  finally
    Sch.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestTickNowInvokesSyncAndStampsLastSync;
var
  S: TSettings;
  Stub: TStubSyncService;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Sch := TSyncScheduler.Create(Stub, S);
  try
    S.SyncEnabled := True;
    Stub.NextResult := True;
    Sch.Start;
    Sch.TickNow;
    Assert.AreEqual<Integer>(1, Stub.SyncCount, 'TickNow must run exactly one sync');
    Assert.IsTrue(Sch.LastSyncAt > 0, 'a successful sync must stamp LastSyncAt');
    Assert.IsFalse(Sch.IsBusy, 'the busy guard must be cleared after a tick');
  finally
    Sch.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestTickNowDoesNothingWhenDisabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Sch := TSyncScheduler.Create(Stub, S);
  try
    S.SyncEnabled := False;
    Sch.TickNow;
    Assert.AreEqual<Integer>(0, Stub.SyncCount, 'a disabled scheduler must not sync');
  finally
    Sch.Free;
    S.Free;
  end;
end;

procedure TSyncSchedulerTestFixture.TestRefreshStopsWhenDisabled;
var
  S: TSettings;
  Stub: TStubSyncService;
  Sch: TSyncScheduler;
begin
  S := TSettings.Create;
  Stub := TStubSyncService.Create;
  Sch := TSyncScheduler.Create(Stub, S);
  try
    S.SyncEnabled := True;
    Sch.Start;
    Assert.IsTrue(Sch.IsRunning);
    S.SyncEnabled := False;
    Sch.Refresh;
    Assert.IsFalse(Sch.IsRunning, 'disabling sync must stop the schedule');
  finally
    Sch.Free;
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncSchedulerTestFixture);

end.
