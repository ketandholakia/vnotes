unit TSyncBaselineTests;

// Phase 7G/WP3: baseline correctness tests.
//
// The invariant under test: sync-state advances only for operations that
// actually completed (pushed / pulled / created / verified-unchanged);
// deferred, cancelled or failed work keeps its previous baseline. The
// tombstone journal survives incomplete runs and is never cleared by mere
// observation. All files live in temp sandboxes.

interface

uses
  System.SysUtils, System.Classes, System.Diagnostics, System.IOUtils,
  System.JSON, System.DateUtils, System.Generics.Collections, System.SyncObjs,
  DUnitX.TestFramework,
  uNote, uEnums, uStorage, uJsonStorage, uNoteManager, uServiceInterfaces,
  uSyncEngine, uSyncRunner, uSyncState, uSyncJournal;

type
  // A controllable in-memory ISyncBackend: seeds objects with ETag versions,
  // can fail individual writes (defer), raise on removes (fail) and block the
  // read of one object so tests can interleave main-thread activity.
  TBaselineTestBackend = class(TInterfacedObject, ISyncBackend)
  private
    FNames: TStringList;
    FObjects: TDictionary<string, string>;
    FVersions: TDictionary<string, Integer>;
    FFailWrites: TStringList;
    FFailRemoves: TStringList;
    FRaiseOnListNames: Boolean;
    FBlockName: string;
    FReadEntered: TEvent;
    FReadRelease: TEvent;
    FReadNames: TStringList;
    FWriteCount: Integer;
    FRemoveCount: Integer;
    FListNamesCount: Integer;
    procedure MaybeBlockRead(const AName: string);
  public
    constructor Create;
    destructor Destroy; override;
    // Test controls.
    procedure Put(const AName, APayload: string);
    procedure FailWrite(const AName: string);
    procedure FailRemove(const AName: string);
    procedure BlockReadOf(const AName: string);
    procedure ReleaseReads;
    function WasRead(const AName: string): Boolean;
    function Contains(const AName: string): Boolean;
    function Content(const AName: string): string;
    property RaiseOnListNames: Boolean read FRaiseOnListNames write FRaiseOnListNames;
    property ReadEntered: TEvent read FReadEntered;
    property WriteCount: Integer read FWriteCount;
    property RemoveCount: Integer read FRemoveCount;
    property ListNamesCount: Integer read FListNamesCount;
    // ISyncBackend
    function DisplayName: string;
    function ListNames: TArray<string>;
    function Read(const AName: string): string;
    procedure Write(const AName, AContent: string);
    procedure Remove(const AName: string);
    function SupportsETags: Boolean;
    function ReadWithETag(const AName: string; out AETag: string): string;
    function WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
  end;

  [TestFixture]
  TSyncBaselineTestFixture = class
  private
    FBase: string;
    FLocalPath: string;
    FStatePath: string;
    FJournalPath: string;
    FStorage: INoteStorage;
    FManager: TNoteManager;
    FBackend: TBaselineTestBackend;
    FBackendRef: ISyncBackend;
    FEngine: TSyncEngine;      // non-owning view (see FEngineRef)
    FEngineRef: ISyncService;  // owns the engine's lifetime
    FRunner: TSyncRunner;
    FCompleteCount: Integer;
    FCompleteSuccess: Boolean;
    FCompleteMsg: string;
    procedure HandleComplete(ASuccess: Boolean; const AMessage: string);
    function PumpUntil(AEvent: TEvent; ATimeoutMs: Cardinal): Boolean;
    function MakeNote(const ATitle, AContent: string; ARev: Int64): TNote;
    procedure SeedState(const AGuids: array of string; const ARevs: array of Int64);
    procedure SeedTombstone(const AGuid: string; ARev: Int64);
    function JournalHas(const AGuid: string; out ATombstone: TSyncTombstone): Boolean;
    function StateSyncedRev(const AGuid: string): Int64;
    function ReadText(const APath: string): string;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test] procedure TestRemoteApplyAdvancesBaseline;
    [Test] procedure TestCasFailureKeepsBaseline;
    [Test] procedure TestPushFailureKeepsBaseline;
    [Test] procedure TestPushSuccessAdvancesBaseline;
    [Test] procedure TestCreateFailureKeepsBaseline;
    [Test] procedure TestCreateSuccessAdvancesBaseline;
    [Test] procedure TestDeleteFailureKeepsBaselineAndTombstone;
    [Test] procedure TestDeleteSuccessUpdatesBookkeeping;
    [Test] procedure TestMixedRunKeepsOldBaselineForDeferred;
    [Test] procedure TestCancellationKeepsApprovedPartialProgress;
    [Test] procedure TestStateSaveContainsOnlyCompletedOperations;
    [Test] procedure TestRestartRetriesDeferredWork;
    [Test] procedure TestTombstoneSurvivesIncompleteRun;
    [Test] procedure TestSuccessDoesNotClearUnrelatedTombstone;
    [Test] procedure TestStateSaveFailureIsSurfaced;
  end;

implementation

var
  GTestSeq: Integer = 0;

const
  GX = 'dddddddd-0000-4000-8000-000000000004';
  GY = 'eeeeeeee-0000-4000-8000-000000000005';

function BuildRemotePayload(const AGuid: string; ARev: Int64;
  const ATitle, AContent: string): string;
var
  N: TNote;
  J: TJSONObject;
begin
  N := TNote.Create(1, ATitle, AContent, ncYellow);
  try
    N.Guid := AGuid;
    N.Rev := ARev;
    N.DeviceId := 'remote-device-0000';
    N.CreatedAt := EncodeDate(2026, 9, 28) + EncodeTime(9, 0, 0, 0);
    N.UpdatedAt := N.CreatedAt;
    J := TJsonStorage.NoteToJson(N);
    try
      Result := J.ToJSON;
    finally
      J.Free;
    end;
  finally
    N.Free;
  end;
end;

{ TBaselineTestBackend }

constructor TBaselineTestBackend.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FObjects := TDictionary<string, string>.Create;
  FVersions := TDictionary<string, Integer>.Create;
  FFailWrites := TStringList.Create;
  FFailRemoves := TStringList.Create;
  FReadNames := TStringList.Create;
  FReadEntered := TEvent.Create(nil, False, False, '');
  FReadRelease := TEvent.Create(nil, True, False, '');
end;

destructor TBaselineTestBackend.Destroy;
begin
  FReadEntered.Free;
  FReadRelease.Free;
  FReadNames.Free;
  FFailRemoves.Free;
  FFailWrites.Free;
  FVersions.Free;
  FObjects.Free;
  FNames.Free;
  inherited;
end;

procedure TBaselineTestBackend.Put(const AName, APayload: string);
begin
  if not FObjects.ContainsKey(AName) then
    FNames.Add(AName);
  FObjects.AddOrSetValue(AName, APayload);
  FVersions.AddOrSetValue(AName, 1);
end;

procedure TBaselineTestBackend.FailWrite(const AName: string);
begin
  FFailWrites.Add(AName);
end;

procedure TBaselineTestBackend.FailRemove(const AName: string);
begin
  FFailRemoves.Add(AName);
end;

procedure TBaselineTestBackend.BlockReadOf(const AName: string);
begin
  FBlockName := AName;
end;

procedure TBaselineTestBackend.ReleaseReads;
begin
  FReadRelease.SetEvent;
end;

function TBaselineTestBackend.WasRead(const AName: string): Boolean;
begin
  Result := FReadNames.IndexOf(AName) >= 0;
end;

function TBaselineTestBackend.Contains(const AName: string): Boolean;
begin
  Result := FObjects.ContainsKey(AName);
end;

function TBaselineTestBackend.Content(const AName: string): string;
begin
  if not FObjects.TryGetValue(AName, Result) then
    Result := '';
end;

procedure TBaselineTestBackend.MaybeBlockRead(const AName: string);
begin
  if (FBlockName = '') or (AName <> FBlockName) then Exit;
  if FReadRelease.WaitFor(0) = wrSignaled then Exit;
  FReadEntered.SetEvent;
  FReadRelease.WaitFor(10000); // bounded: a runaway test fails instead of hanging
end;

function TBaselineTestBackend.DisplayName: string;
begin
  Result := 'fake://baseline';
end;

function TBaselineTestBackend.ListNames: TArray<string>;
var
  I: Integer;
begin
  if FRaiseOnListNames then
    raise Exception.Create('injected ListNames failure');
  Inc(FListNamesCount);
  SetLength(Result, FNames.Count);
  for I := 0 to FNames.Count - 1 do
    Result[I] := FNames[I];
end;

function TBaselineTestBackend.Read(const AName: string): string;
begin
  FReadNames.Add(AName);
  MaybeBlockRead(AName);
  Result := Content(AName);
end;

procedure TBaselineTestBackend.Write(const AName, AContent: string);
var
  Version: Integer;
begin
  if not FObjects.ContainsKey(AName) then
    FNames.Add(AName);
  FObjects.AddOrSetValue(AName, AContent);
  Version := 0;
  FVersions.TryGetValue(AName, Version);
  FVersions.AddOrSetValue(AName, Version + 1);
  Inc(FWriteCount);
end;

procedure TBaselineTestBackend.Remove(const AName: string);
var
  Idx: Integer;
begin
  if FFailRemoves.IndexOf(AName) >= 0 then
    raise Exception.Create('injected Remove failure');
  if FObjects.ContainsKey(AName) then
  begin
    FObjects.Remove(AName);
    FVersions.Remove(AName);
    Idx := FNames.IndexOf(AName);
    if Idx >= 0 then
      FNames.Delete(Idx);
  end;
  Inc(FRemoveCount);
end;

function TBaselineTestBackend.SupportsETags: Boolean;
begin
  Result := True;
end;

function TBaselineTestBackend.ReadWithETag(const AName: string; out AETag: string): string;
var
  Version: Integer;
begin
  FReadNames.Add(AName);
  AETag := '';
  if not FObjects.ContainsKey(AName) then
    Exit('');
  Version := FVersions[AName];
  AETag := IntToStr(Version);
  MaybeBlockRead(AName);
  Result := Content(AName);
end;

function TBaselineTestBackend.WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
var
  Current: string;
begin
  Result := False;
  if FFailWrites.IndexOf(AName) >= 0 then
    Exit(False); // simulated optimistic-concurrency failure
  if FObjects.ContainsKey(AName) then
    Current := IntToStr(FVersions[AName])
  else
    Current := '';
  if Current <> AExpectedETag then
    Exit(False);
  Write(AName, AContent);
  Result := True;
end;

{ TSyncBaselineTestFixture }

procedure TSyncBaselineTestFixture.SetUp;
begin
  Inc(GTestSeq);
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Wp3Test_' + IntToStr(TThread.GetTickCount) + '_' + IntToStr(GTestSeq));
  FLocalPath := TPath.Combine(FBase, 'local');
  FStatePath := TPath.Combine(FLocalPath, 'sync-state.json');
  FJournalPath := TPath.Combine(FLocalPath, 'sync-journal.json');
  ForceDirectories(FLocalPath);

  FCompleteCount := 0;
  FCompleteSuccess := False;
  FCompleteMsg := '';

  FStorage := TJsonStorage.Create(FLocalPath);
  FManager := TNoteManager.Create(FStorage);
  FManager.Initialize;
  FBackend := TBaselineTestBackend.Create;
  FBackendRef := FBackend;
  FEngine := TSyncEngine.Create(FManager, FBackendRef, FStatePath);
  FEngineRef := FEngine;
  FEngine.OnComplete := HandleComplete;
  FRunner := TSyncRunner.Create(FEngineRef);
end;

procedure TSyncBaselineTestFixture.TearDown;
begin
  if FEngine <> nil then
    FEngine.Cancel;
  if FBackend <> nil then
    FBackend.ReleaseReads;
  if FRunner <> nil then
    FRunner.WaitForIdle;
  FreeAndNil(FRunner);
  FEngine := nil;
  FEngineRef := nil;
  FBackendRef := nil;
  FBackend := nil;
  FManager.Free;
  FStorage := nil;
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TSyncBaselineTestFixture.HandleComplete(ASuccess: Boolean; const AMessage: string);
begin
  Inc(FCompleteCount);
  FCompleteSuccess := ASuccess;
  FCompleteMsg := AMessage;
end;

function TSyncBaselineTestFixture.PumpUntil(AEvent: TEvent; ATimeoutMs: Cardinal): Boolean;
var
  Stopwatch: TStopwatch;
begin
  Stopwatch := TStopwatch.StartNew;
  repeat
    CheckSynchronize(1);
    if AEvent.WaitFor(0) = wrSignaled then
      Exit(True);
  until Stopwatch.ElapsedMilliseconds >= Int64(ATimeoutMs);
  Result := False;
end;

function TSyncBaselineTestFixture.MakeNote(const ATitle, AContent: string; ARev: Int64): TNote;
begin
  Result := FManager.CreateNote(ATitle, AContent, ncYellow, 10, 10, 300, 200, False);
  Result.Rev := ARev;
  FManager.PersistNote(Result);
end;

procedure TSyncBaselineTestFixture.SeedState(const AGuids: array of string;
  const ARevs: array of Int64);
var
  Map: TDictionary<string, Int64>;
  I: Integer;
begin
  Map := TDictionary<string, Int64>.Create;
  try
    for I := 0 to High(AGuids) do
      Map.AddOrSetValue(AGuids[I], ARevs[I]);
    SaveSyncState(FStatePath, Map);
  finally
    Map.Free;
  end;
end;

procedure TSyncBaselineTestFixture.SeedTombstone(const AGuid: string; ARev: Int64);
var
  J: TSyncJournal;
begin
  J := TSyncJournal.Create(FJournalPath);
  try
    J.Add(AGuid, ARev, Now);
    J.Save;
  finally
    J.Free;
  end;
end;

function TSyncBaselineTestFixture.JournalHas(const AGuid: string;
  out ATombstone: TSyncTombstone): Boolean;
var
  J: TSyncJournal;
begin
  J := TSyncJournal.Create(FJournalPath);
  try
    J.Load;
    Result := J.TryGet(AGuid, ATombstone);
  finally
    J.Free;
  end;
end;

function TSyncBaselineTestFixture.StateSyncedRev(const AGuid: string): Int64;
var
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
  Rev: Int64;
begin
  Result := -1;
  J := TSyncJournal.Create(FJournalPath);
  try
    Map := LoadSyncState(FStatePath, J);
    try
      // Note: TryGetValue would set Rev to 0 for a missing guid; only a
      // successful lookup may replace the -1 "absent" sentinel.
      if Map.TryGetValue(AGuid, Rev) then
        Result := Rev;
    finally
      Map.Free;
    end;
  finally
    J.Free;
  end;
end;

function TSyncBaselineTestFixture.ReadText(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath);
end;

procedure TSyncBaselineTestFixture.TestRemoteApplyAdvancesBaseline;
var
  N: TNote;
begin
  N := MakeNote('A', 'local-v10', 10);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 10, 'A', 'local-v10'));
  SeedState([N.Guid], [10]);

  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 11, 'A', 'remote-v11'));
  Assert.IsTrue(FEngine.SyncNow, 'the run must succeed');
  Assert.AreEqual<Int64>(11, StateSyncedRev(N.Guid),
    'an applied pull must advance the baseline to the applied revision');
  Assert.AreEqual<string>('remote-v11', N.Content);
  Assert.IsTrue(FEngine.LastRunSummary.Succeeded);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Pulled);
  Assert.AreEqual<Integer>(0, FEngine.LastRunSummary.Deferred);
end;

procedure TSyncBaselineTestFixture.TestCasFailureKeepsBaseline;
var
  N: TNote;
begin
  N := MakeNote('B', 'local-v10', 10);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 12, 'B', 'remote-v12'));
  SeedState([N.Guid], [10]);

  FBackend.BlockReadOf(N.Guid);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000), 'worker should reach the blocked read');
  N.Content := 'user-edit';
  FManager.SaveNote(N); // revision 10 -> 11 while the run is in flight
  FBackend.ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<Int64>(10, StateSyncedRev(N.Guid),
    'a rejected CAS must leave the baseline unchanged');
  Assert.AreEqual<string>('user-edit', N.Content);
  Assert.AreEqual<Int64>(11, N.Rev);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Deferred);
end;

procedure TSyncBaselineTestFixture.TestPushFailureKeepsBaseline;
var
  N: TNote;
begin
  N := MakeNote('C', 'user-edit', 2);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 1, 'C', 'old'));
  SeedState([N.Guid], [1]);
  FBackend.FailWrite(N.Guid);

  Assert.IsTrue(FEngine.SyncNow, 'a failed push defers; the run itself completes');
  Assert.AreEqual<Int64>(1, StateSyncedRev(N.Guid),
    'a failed push must not advance the baseline');
  Assert.AreEqual<Integer>(0, FEngine.LastRunSummary.Pushed);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Deferred);
  Assert.IsTrue(Pos('old', FBackend.Content(N.Guid)) > 0, 'the remote keeps its old payload');
end;

procedure TSyncBaselineTestFixture.TestPushSuccessAdvancesBaseline;
var
  N: TNote;
begin
  N := MakeNote('D', 'pushed-v2', 2);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 1, 'D', 'old'));
  SeedState([N.Guid], [1]);

  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Int64>(2, StateSyncedRev(N.Guid),
    'the backend-accepted revision must advance the baseline');
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Pushed);
  Assert.IsTrue(Pos('pushed-v2', FBackend.Content(N.Guid)) > 0);
end;

procedure TSyncBaselineTestFixture.TestCreateFailureKeepsBaseline;
var
  Impostor: TNote;
begin
  FBackend.Put(GX, BuildRemotePayload(GX, 3, 'X', 'remote-x'));
  FBackend.BlockReadOf(GX);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000), 'worker should reach the blocked read');

  // The guid becomes taken while the run is in flight: the guarded create
  // must refuse (defer) instead of materialising a duplicate identity.
  Impostor := FManager.CreateNote('Impostor', 'x', ncYellow, 10, 10, 300, 200, False);
  Impostor.Guid := GX;
  FManager.PersistNote(Impostor);

  FBackend.ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<Int64>(-1, StateSyncedRev(GX),
    'a failed create must not advance the baseline');
  Assert.AreEqual<Integer>(1, FManager.NoteCount, 'no duplicate note may be created');
  Assert.AreEqual<string>('x', Impostor.Content);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Deferred);
end;

procedure TSyncBaselineTestFixture.TestCreateSuccessAdvancesBaseline;
begin
  FBackend.Put(GY, BuildRemotePayload(GY, 3, 'Y', 'remote-y'));

  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Integer>(1, FManager.NoteCount);
  Assert.AreEqual<string>('remote-y', FManager.Notes[0].Content);
  Assert.AreEqual<Int64>(3, StateSyncedRev(GY),
    'a successfully created note must advance the baseline to the applied rev');
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Created);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Pulled);
end;

procedure TSyncBaselineTestFixture.TestDeleteFailureKeepsBaselineAndTombstone;
var
  T: TSyncTombstone;
  StateBytesBefore: string;
begin
  SeedState([GX], [5]);
  SeedTombstone(GX, 5);
  StateBytesBefore := ReadText(FStatePath);
  FBackend.FailRemove(GX);

  Assert.IsFalse(FEngine.SyncNow, 'a failing delete must fail the run');
  Assert.IsTrue(Pos('failed', LowerCase(FCompleteMsg)) > 0, FCompleteMsg);
  Assert.AreEqual<string>(StateBytesBefore, ReadText(FStatePath),
    'a failed run must not write state');
  Assert.AreEqual<Int64>(5, StateSyncedRev(GX), 'the baseline must be unchanged');
  Assert.IsTrue(JournalHas(GX, T), 'the tombstone must be preserved');
  Assert.IsFalse(FEngine.LastRunSummary.Succeeded);
  Assert.IsFalse(FEngine.LastRunSummary.Cancelled);
end;

procedure TSyncBaselineTestFixture.TestDeleteSuccessUpdatesBookkeeping;
begin
  SeedState([GX], [5]);
  FBackend.Put(GX, BuildRemotePayload(GX, 5, 'X', 'remote-x'));

  Assert.IsTrue(FEngine.SyncNow);
  Assert.IsTrue(FEngine.LastRunSummary.Succeeded);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Removed,
    'the propagated deletion must be recorded in the run accounting');
  Assert.AreEqual<Int64>(-1, StateSyncedRev(GX),
    'current-model bookkeeping drops the guid once its deletion is propagated (WP5 revisits)');
  Assert.IsFalse(FBackend.Contains(GX), 'the remote object must be gone');
end;

procedure TSyncBaselineTestFixture.TestMixedRunKeepsOldBaselineForDeferred;
var
  NA, NB, NC: TNote;
begin
  NA := MakeNote('A', 'local-a10', 10);
  FBackend.Put(NA.Guid, BuildRemotePayload(NA.Guid, 11, 'A', 'remote-a11'));
  NB := MakeNote('B', 'local-b10', 10);
  FBackend.Put(NB.Guid, BuildRemotePayload(NB.Guid, 12, 'B', 'remote-b12'));
  NC := MakeNote('C', 'edit-c2', 2);
  FBackend.Put(NC.Guid, BuildRemotePayload(NC.Guid, 1, 'C', 'old-c'));
  SeedState([NA.Guid, NB.Guid, NC.Guid], [10, 10, 1]);

  FBackend.BlockReadOf(NB.Guid);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000), 'worker should reach the blocked read');
  NB.Content := 'user-edit-b';
  FManager.SaveNote(NB);
  FBackend.ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<Int64>(11, StateSyncedRev(NA.Guid), 'A: applied pull -> new revision');
  Assert.AreEqual<Int64>(10, StateSyncedRev(NB.Guid), 'B: deferred -> old revision');
  Assert.AreEqual<Int64>(2, StateSyncedRev(NC.Guid), 'C: applied push -> new revision');
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Pulled);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Pushed);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Deferred);
end;

procedure TSyncBaselineTestFixture.TestCancellationKeepsApprovedPartialProgress;
var
  NA, NB, NC: TNote;
  StateBytesBefore: string;
begin
  NA := MakeNote('A', 'local-a10', 10);
  FBackend.Put(NA.Guid, BuildRemotePayload(NA.Guid, 11, 'A', 'remote-a11'));
  NB := MakeNote('B', 'local-b10', 10);
  FBackend.Put(NB.Guid, BuildRemotePayload(NB.Guid, 12, 'B', 'remote-b12'));
  NC := MakeNote('C', 'local-c1', 1);
  FBackend.Put(NC.Guid, BuildRemotePayload(NC.Guid, 3, 'C', 'remote-c3'));
  SeedState([NA.Guid, NB.Guid, NC.Guid], [10, 10, 1]);
  StateBytesBefore := ReadText(FStatePath);

  FBackend.BlockReadOf(NB.Guid);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000), 'worker should reach the blocked read');
  FEngine.Cancel;
  FBackend.ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<string>('remote-a11', NA.Content, 'A was applied before the cancellation');
  Assert.AreEqual<Int64>(11, NA.Rev);
  Assert.AreEqual<string>('local-b10', NB.Content, 'B must remain unchanged');
  Assert.AreEqual<string>('local-c1', NC.Content, 'no operation may start after cancellation');
  Assert.IsFalse(FBackend.WasRead(NC.Guid), 'C must never be read');
  Assert.AreEqual<string>(StateBytesBefore, ReadText(FStatePath),
    'the approved rule: a cancelled run does not save state');
  Assert.IsTrue(FEngine.LastRunSummary.Cancelled);
  Assert.IsFalse(FEngine.LastRunSummary.Succeeded);
  Assert.IsTrue(Pos('cancel', LowerCase(FCompleteMsg)) > 0, FCompleteMsg);
end;

procedure TSyncBaselineTestFixture.TestStateSaveContainsOnlyCompletedOperations;
var
  NA, NB, NC: TNote;
  StateBytesAfter: string;
begin
  NA := MakeNote('A', 'local-a10', 10);
  FBackend.Put(NA.Guid, BuildRemotePayload(NA.Guid, 11, 'A', 'remote-a11'));
  NB := MakeNote('B', 'edit-b2', 2);
  FBackend.Put(NB.Guid, BuildRemotePayload(NB.Guid, 1, 'B', 'old-b'));
  NC := MakeNote('C', 'local-c12', 12);
  FBackend.Put(NC.Guid, BuildRemotePayload(NC.Guid, 13, 'C', 'remote-c13'));
  SeedState([NA.Guid, NB.Guid, NC.Guid], [10, 1, 12]);
  FBackend.FailWrite(NB.Guid);

  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Int64>(11, StateSyncedRev(NA.Guid), 'applied pull advanced');
  Assert.AreEqual<Int64>(1, StateSyncedRev(NB.Guid), 'deferred push kept the old revision');
  Assert.AreEqual<Int64>(13, StateSyncedRev(NC.Guid), 'applied pull advanced');
  Assert.AreEqual<Integer>(2, FEngine.LastRunSummary.Pulled);
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Deferred);

  // The "failed" part of the mix: a backend exception aborts the run and the
  // saved state must stay byte-identical (a failed operation never advances).
  StateBytesAfter := ReadText(FStatePath);
  FBackend.RaiseOnListNames := True;
  Assert.IsFalse(FEngine.SyncNow, 'a backend exception must fail the run');
  Assert.AreEqual<string>(StateBytesAfter, ReadText(FStatePath),
    'a failed run must not write state');
end;

procedure TSyncBaselineTestFixture.TestRestartRetriesDeferredWork;
var
  N: TNote;
  Engine2: TSyncEngine;
  Engine2Ref: ISyncService;
begin
  N := MakeNote('L', 'local-v1', 1);
  SeedState([N.Guid], [1]);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 5, 'L', 'remote-v5'));

  FBackend.BlockReadOf(N.Guid);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000), 'worker should reach the blocked read');
  N.Content := 'user-edit';
  FManager.SaveNote(N); // revision 1 -> 2
  FBackend.ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<Int64>(1, StateSyncedRev(N.Guid), 'the deferred run kept the old baseline');
  Assert.AreEqual<Integer>(1, FEngine.LastRunSummary.Deferred);

  // Simulate a restart: a fresh engine over the same files must reconsider
  // the deferred guid (the old baseline did not block it).
  Engine2 := TSyncEngine.Create(FManager, FBackendRef, FStatePath);
  Engine2Ref := Engine2;
  try
    Assert.IsTrue(Engine2.SyncNow, 'the restart run must succeed');
    Assert.AreEqual<Int64>(5, StateSyncedRev(N.Guid),
      'the deferred revision is retried and then recorded');
    Assert.AreEqual<Integer>(1, Engine2.LastRunSummary.Pulled);
  finally
    Engine2Ref := nil;
  end;
end;

procedure TSyncBaselineTestFixture.TestTombstoneSurvivesIncompleteRun;
var
  T: TSyncTombstone;
  JournalBytes: string;
begin
  SeedTombstone(GX, 5);
  JournalBytes := ReadText(FJournalPath);

  // 1) A failing run preserves the tombstone (and the file is untouched).
  FBackend.RaiseOnListNames := True;
  Assert.IsFalse(FEngine.SyncNow);
  Assert.IsTrue(JournalHas(GX, T), 'a failed run must preserve the tombstone');
  Assert.AreEqual<string>(JournalBytes, ReadText(FJournalPath),
    'a failed run must not touch the journal file');

  // 2) A cancelled run preserves the tombstone too.
  FBackend.RaiseOnListNames := False;
  FBackend.Put(GY, BuildRemotePayload(GY, 3, 'Y', 'remote-y'));
  FBackend.BlockReadOf(GY);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000), 'worker should reach the blocked read');
  FEngine.Cancel;
  FBackend.ReleaseReads;
  FRunner.WaitForIdle;
  Assert.IsTrue(FEngine.LastRunSummary.Cancelled);
  Assert.IsTrue(JournalHas(GX, T), 'a cancelled run must preserve the tombstone');
end;

procedure TSyncBaselineTestFixture.TestSuccessDoesNotClearUnrelatedTombstone;
var
  T: TSyncTombstone;
begin
  SeedTombstone(GX, 5);
  FBackend.Put(GY, BuildRemotePayload(GY, 3, 'Y', 'remote-y'));

  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Integer>(1, FManager.NoteCount, 'the unrelated note was created');
  Assert.IsTrue(JournalHas(GX, T),
    'a successful unrelated operation must not clear the tombstone (WP5 owns clearing)');
end;

procedure TSyncBaselineTestFixture.TestStateSaveFailureIsSurfaced;
var
  BadStatePath: string;
  Engine2: TSyncEngine;
  Engine2Ref: ISyncService;
  N: TNote;
begin
  // Point the state file into a folder that does not exist: the push succeeds,
  // but the metadata write cannot.
  BadStatePath := TPath.Combine(TPath.Combine(FBase, 'missing-dir'), 'sync-state.json');
  Engine2 := TSyncEngine.Create(FManager, FBackendRef, BadStatePath);
  Engine2Ref := Engine2;
  try
    Engine2.OnComplete := HandleComplete;
    FCompleteCount := 0;
    FCompleteMsg := '';
    N := MakeNote('O', 'push-me', 1);

    Assert.IsFalse(Engine2.SyncNow, 'a metadata save failure must fail the run');
    Assert.IsFalse(Engine2.LastRunSummary.Succeeded,
      'the run must not be reported as fully synchronized');
    Assert.IsFalse(Engine2.LastRunSummary.Cancelled);
    Assert.IsTrue(Pos('failed', LowerCase(FCompleteMsg)) > 0, FCompleteMsg);
    Assert.IsTrue(FBackend.Contains(N.Guid), 'the backend operation itself succeeded');
    Assert.IsFalse(TFile.Exists(BadStatePath), 'no state may be silently written');
    Assert.IsFalse(TFile.Exists(BadStatePath + '.tmp'), 'no temp file may remain');
  finally
    Engine2Ref := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncBaselineTestFixture);

end.
