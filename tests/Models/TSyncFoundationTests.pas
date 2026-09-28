unit TSyncFoundationTests;

// Phase 7G/WP1: tests for the snapshot + compare-and-set sync foundation.
//
// These tests prove the WP1 safety properties before WP5 changes the reconcile
// algorithm:
//   * the worker runs from an immutable main-thread snapshot and survives the
//     user deleting notes mid-run (no live TNote references),
//   * CAS applies only when guid + expected Rev still match; stale snapshots
//     are deferred and never overwrite a concurrent local edit,
//   * a cancelled run stops, mutates nothing further and writes no state,
//   * SyncNow is non-reentrant and WaitForIdle returns only after the worker
//     terminated with all marshalled callbacks delivered.
//
// Threading notes: worker runs marshal their mutations back to the main
// thread (TMainInvoker -> TThread.Synchronize), so the test thread must
// service that queue while it waits - PumpUntil/CheckSynchronize below. Never
// Sleep-poll: every wait is event-driven with a bounded timeout.

interface

uses
  System.SysUtils, System.Classes, System.Diagnostics, System.IOUtils,
  System.JSON, System.DateUtils, System.Generics.Collections, System.SyncObjs,
  DUnitX.TestFramework,
  uNote, uEnums, uStorage, uJsonStorage, uNoteManager, uServiceInterfaces,
  uSyncEngine, uSyncRunner;

type
  // A controllable in-memory ISyncBackend. It counts backend writes and can
  // block the Read of one specific object on an event, which lets a test edit
  // or delete notes on the main thread while the worker is mid-run.
  TFakeSyncBackend = class(TInterfacedObject, ISyncBackend)
  private
    FNames: TStringList;                      // insertion order of object names
    FObjects: TDictionary<string, string>;    // name -> payload
    FVersions: TDictionary<string, Integer>;  // name -> etag version
    FReadNames: TStringList;                  // every name actually read
    FBlockName: string;
    FReadEntered: TEvent;
    FReadRelease: TEvent;
    FWriteCount: Integer;
    FListNamesCount: Integer;
    procedure MaybeBlockRead(const AName: string);
    function GetObject(const AName: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    // Test controls (not part of ISyncBackend).
    procedure Put(const AName, APayload: string);
    procedure SetBlockOnRead(const AName: string);
    procedure ReleaseReads;
    function WasRead(const AName: string): Boolean;
    property ReadEntered: TEvent read FReadEntered;
    property WriteCount: Integer read FWriteCount;
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
  TSyncFoundationTestFixture = class
  private
    FBase: string;
    FLocalPath: string;
    FStatePath: string;
    FStorage: INoteStorage;
    FManager: TNoteManager;
    FBackend: TFakeSyncBackend;   // non-owning view (see FBackendRef)
    FBackendRef: ISyncBackend;   // owns the fake backend's lifetime
    FEngine: TSyncEngine;        // non-owning view (see FEngineRef)
    FEngineRef: ISyncService;    // owns the engine's lifetime
    FRunner: TSyncRunner;
    FCompleteCount: Integer;
    FCompleteSuccess: Boolean;
    FCompleteMsg: string;
    FLastProgress: string;
    procedure HandleComplete(ASuccess: Boolean; const AMessage: string);
    procedure HandleProgress(const AMessage: string; AProgress: Integer);
    // Waits for AEvent while keeping the main-thread synchronize queue
    // serviced (the worker can only reach its next step after its marshalled
    // requests were processed).
    function PumpUntil(AEvent: TEvent; ATimeoutMs: Cardinal): Boolean;
    // Reads the recorded baseline rev for a guid from sync-state.json;
    // -1 when the file or the entry is absent.
    function StateSyncedRev(const AGuid: string): Int64;
    // Loads a note fresh from disk storage by local ID (caller frees).
    function ReloadNote(const AID: Int64): TNote;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestWorkerSurvivesNoteDeletedMidRun;
    [Test]
    procedure TestCasAppliesMutation;
    [Test]
    procedure TestCasRejectsStaleSnapshot;
    [Test]
    procedure TestCasDoesNotResurrectDeletedNote;
    [Test]
    procedure TestLocalEditDuringSyncIsNotOverwritten;
    [Test]
    procedure TestCancellationStopsTheRun;
    [Test]
    procedure TestSecondSyncNowIsIgnoredWhileRunning;
    [Test]
    procedure TestCancelThenWaitForIdleTerminates;
  end;

implementation

var
  GTestSeq: Integer = 0;

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

{ TFakeSyncBackend }

constructor TFakeSyncBackend.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FObjects := TDictionary<string, string>.Create;
  FVersions := TDictionary<string, Integer>.Create;
  FReadNames := TStringList.Create;
  // FReadRelease is manual-reset: once released, later reads never block again.
  FReadEntered := TEvent.Create(nil, False, False, '');
  FReadRelease := TEvent.Create(nil, True, False, '');
end;

destructor TFakeSyncBackend.Destroy;
begin
  FReadEntered.Free;
  FReadRelease.Free;
  FReadNames.Free;
  FVersions.Free;
  FObjects.Free;
  FNames.Free;
  inherited;
end;

procedure TFakeSyncBackend.Put(const AName, APayload: string);
begin
  if not FObjects.ContainsKey(AName) then
    FNames.Add(AName);
  FObjects.AddOrSetValue(AName, APayload);
  FVersions.AddOrSetValue(AName, 1);
end;

procedure TFakeSyncBackend.SetBlockOnRead(const AName: string);
begin
  FBlockName := AName;
end;

procedure TFakeSyncBackend.ReleaseReads;
begin
  FReadRelease.SetEvent;
end;

function TFakeSyncBackend.WasRead(const AName: string): Boolean;
begin
  Result := FReadNames.IndexOf(AName) >= 0;
end;

procedure TFakeSyncBackend.MaybeBlockRead(const AName: string);
begin
  if (FBlockName = '') or (AName <> FBlockName) then Exit;
  if FReadRelease.WaitFor(0) = wrSignaled then Exit; // already released
  FReadEntered.SetEvent;
  // Bounded wait: a runaway test fails with a timeout instead of hanging the
  // whole suite (teardown releases the event unconditionally).
  FReadRelease.WaitFor(10000);
end;

function TFakeSyncBackend.GetObject(const AName: string): string;
begin
  if not FObjects.TryGetValue(AName, Result) then
    Result := '';
end;

function TFakeSyncBackend.DisplayName: string;
begin
  Result := 'fake://backend';
end;

function TFakeSyncBackend.ListNames: TArray<string>;
var
  I: Integer;
begin
  Inc(FListNamesCount);
  SetLength(Result, FNames.Count);
  for I := 0 to FNames.Count - 1 do
    Result[I] := FNames[I];
end;

function TFakeSyncBackend.Read(const AName: string): string;
begin
  FReadNames.Add(AName);
  MaybeBlockRead(AName);
  Result := GetObject(AName);
end;

procedure TFakeSyncBackend.Write(const AName, AContent: string);
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

procedure TFakeSyncBackend.Remove(const AName: string);
var
  Idx: Integer;
begin
  if FObjects.ContainsKey(AName) then
  begin
    FObjects.Remove(AName);
    FVersions.Remove(AName);
    Idx := FNames.IndexOf(AName);
    if Idx >= 0 then
      FNames.Delete(Idx);
  end;
end;

function TFakeSyncBackend.SupportsETags: Boolean;
begin
  Result := True;
end;

function TFakeSyncBackend.ReadWithETag(const AName: string; out AETag: string): string;
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
  Result := GetObject(AName);
end;

function TFakeSyncBackend.WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
var
  Current: string;
begin
  Result := False;
  if FObjects.ContainsKey(AName) then
    Current := IntToStr(FVersions[AName])
  else
    Current := '';
  if Current <> AExpectedETag then
    Exit(False); // precondition failed - object left untouched
  Write(AName, AContent);
  Result := True;
end;

{ TSyncFoundationTestFixture }

procedure TSyncFoundationTestFixture.SetUp;
begin
  Inc(GTestSeq);
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Wp1Test_' + IntToStr(TThread.GetTickCount) + '_' + IntToStr(GTestSeq));
  FLocalPath := TPath.Combine(FBase, 'local');
  FStatePath := TPath.Combine(FLocalPath, 'sync-state.json');
  ForceDirectories(FLocalPath);

  FCompleteCount := 0;
  FCompleteSuccess := False;
  FCompleteMsg := '';
  FLastProgress := '';

  FStorage := TJsonStorage.Create(FLocalPath);
  FManager := TNoteManager.Create(FStorage);
  FManager.Initialize;
  FBackend := TFakeSyncBackend.Create;
  FBackendRef := FBackend;
  FEngine := TSyncEngine.Create(FManager, FBackendRef, FStatePath);
  FEngineRef := FEngine; // the owning reference (engine is refcounted)
  FEngine.OnComplete := HandleComplete;
  FEngine.OnProgress := HandleProgress;
  FRunner := TSyncRunner.Create(FEngineRef);
end;

procedure TSyncFoundationTestFixture.TearDown;
begin
  // Stop any worker before application-owned objects go away (same order the
  // application uses in TNoteApplication.Shutdown).
  if FEngine <> nil then
    FEngine.Cancel;
  if FBackend <> nil then
    FBackend.ReleaseReads; // never leave a blocked worker behind
  if FRunner <> nil then
    FRunner.WaitForIdle;
  FreeAndNil(FRunner);
  FEngine := nil;
  FEngineRef := nil; // releases and destroys the engine (and its backend ref)
  FBackendRef := nil; // releases and destroys the fake backend
  FBackend := nil;
  FManager.Free;
  FStorage := nil;
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TSyncFoundationTestFixture.HandleComplete(ASuccess: Boolean; const AMessage: string);
begin
  Inc(FCompleteCount);
  FCompleteSuccess := ASuccess;
  FCompleteMsg := AMessage;
end;

procedure TSyncFoundationTestFixture.HandleProgress(const AMessage: string; AProgress: Integer);
begin
  FLastProgress := AMessage;
end;

function TSyncFoundationTestFixture.PumpUntil(AEvent: TEvent; ATimeoutMs: Cardinal): Boolean;
var
  Stopwatch: TStopwatch;
begin
  Stopwatch := TStopwatch.StartNew;
  repeat
    // Service the worker's marshalled requests while we wait: it can only
    // reach its next step after its main-thread dispatches were processed.
    CheckSynchronize(1);
    if AEvent.WaitFor(0) = wrSignaled then
      Exit(True);
  until Stopwatch.ElapsedMilliseconds >= Int64(ATimeoutMs);
  Result := False;
end;

function TSyncFoundationTestFixture.StateSyncedRev(const AGuid: string): Int64;
var
  Root: TJSONValue;
  Obj, SyncedObj: TJSONObject;
  Val: TJSONValue;
begin
  Result := -1;
  if not TFile.Exists(FStatePath) then Exit;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(FStatePath));
  try
    if not (Root is TJSONObject) then Exit;
    Obj := Root as TJSONObject;
    Val := Obj.GetValue('synced');
    if not (Val is TJSONObject) then Exit;
    SyncedObj := Val as TJSONObject;
    Val := SyncedObj.GetValue(AGuid);
    if Val is TJSONNumber then
      Result := (Val as TJSONNumber).AsInt64;
  finally
    Root.Free;
  end;
end;

function TSyncFoundationTestFixture.ReloadNote(const AID: Int64): TNote;
var
  Storage: INoteStorage;
  Notes: TObjectList<TNote>;
  I: Integer;
begin
  Result := nil;
  Storage := TJsonStorage.Create(FLocalPath);
  Notes := Storage.LoadAllNotes;
  try
    for I := 0 to Notes.Count - 1 do
      if Notes[I].ID = AID then
      begin
        Result := Notes.Extract(Notes[I]);
        Break;
      end;
  finally
    Notes.Free;
  end;
end;

procedure TSyncFoundationTestFixture.TestWorkerSurvivesNoteDeletedMidRun;
var
  N: TNote;
begin
  // A note that the reconcile will want to pull (remote is newer)...
  N := FManager.CreateNote('Live', 'local-v1', ncYellow, 10, 10, 300, 200, False);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 2, 'Live', 'remote-v2'));
  FBackend.SetBlockOnRead(N.Guid);

  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000),
    'the worker should reach the blocked read');

  // ...is deleted (and its TNote freed) while the worker is mid-run. This
  // would be a use-after-free if the worker still held a live note reference;
  // snapshot-only workers simply defer the now-missing note.
  Assert.IsTrue(FManager.DeleteNote(N.ID), 'deleting the note should succeed');
  (FBackend).ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<Integer>(1, FCompleteCount);
  Assert.IsTrue(FCompleteSuccess, 'the run must complete safely: ' + FCompleteMsg);
  Assert.IsTrue(Pos('deferred', FCompleteMsg) > 0,
    'the skipped note must be reported as deferred: ' + FCompleteMsg);
  Assert.AreEqual<Integer>(0, FManager.NoteCount, 'the deleted note must stay deleted');
  Assert.AreEqual<Integer>(0, (FBackend).WriteCount,
    'nothing may be written to the remote for a locally deleted note');
end;

procedure TSyncFoundationTestFixture.TestCasAppliesMutation;
var
  N, Reloaded: TNote;
  Res: TSyncApplyResult;
begin
  N := FManager.CreateNote('Cas', 'before', ncYellow, 10, 10, 300, 200, False);
  Res := FEngine.TryApplyNoteCAS(N.Guid, N.Rev,
    procedure(Note: TNote)
    begin
      Note.Content := 'applied';
      FManager.PersistNote(Note);
    end);
  Assert.IsTrue(Res = TSyncApplyResult.arApplied, 'a matching revision must apply');
  Assert.AreEqual<string>('applied', N.Content);

  Reloaded := ReloadNote(N.ID);
  try
    Assert.IsNotNull(Reloaded, 'the note must still load from disk');
    Assert.AreEqual<string>('applied', Reloaded.Content, 'the mutation must be persisted');
    Assert.AreEqual<Int64>(N.Rev, Reloaded.Rev, 'the revision must be preserved as set');
  finally
    Reloaded.Free;
  end;
end;

procedure TSyncFoundationTestFixture.TestCasRejectsStaleSnapshot;
var
  N: TNote;
  Applied: Boolean;
  Res: TSyncApplyResult;
begin
  N := FManager.CreateNote('Cas', 'v1', ncYellow, 10, 10, 300, 200, False);
  // The user edits the note after the (notional) snapshot was taken:
  // revision 1 -> 2.
  N.Content := 'user edit';
  FManager.SaveNote(N);

  Applied := False;
  Res := FEngine.TryApplyNoteCAS(N.Guid, 1,
    procedure(Note: TNote)
    begin
      Applied := True;
      Note.Content := 'stale write';
    end);
  Assert.IsFalse(Applied, 'the mutation closure must not run on a stale snapshot');
  Assert.IsTrue(Res = TSyncApplyResult.arDeferred, 'a stale snapshot must defer, not apply');
  Assert.AreEqual<string>('user edit', N.Content, 'the concurrent user edit must remain untouched');
  Assert.AreEqual<Int64>(2, N.Rev);
  // Run-level baseline handling for deferrals is asserted in
  // TestLocalEditDuringSyncIsNotOverwritten (a state file only exists there).
end;

procedure TSyncFoundationTestFixture.TestCasDoesNotResurrectDeletedNote;
var
  N, N2: TNote;
  Guid: string;
  Rev: Int64;
  Mutated, Created: Boolean;
  Res: TSyncApplyResult;
begin
  N := FManager.CreateNote('Gone', 'x', ncYellow, 10, 10, 300, 200, False);
  Guid := N.Guid;
  Rev := N.Rev;
  Assert.IsTrue(FManager.DeleteNote(N.ID), 'deleting the note should succeed');

  Mutated := False;
  Res := FEngine.TryApplyNoteCAS(Guid, Rev,
    procedure(Note: TNote)
    begin
      Mutated := True;
    end);
  Assert.IsFalse(Mutated, 'a mutation for a deleted note must not run');
  Assert.IsTrue(Res = TSyncApplyResult.arNotFound, 'a deleted note must report not-found');
  Assert.AreEqual<Integer>(0, FManager.NoteCount, 'the deleted note must not be recreated');

  // The create-guard path (used when materialising pulled notes) must refuse
  // an existing guid instead of creating a duplicate identity.
  N2 := FManager.CreateNote('Guard', 'x', ncYellow, 10, 10, 300, 200, False);
  Created := False;
  Res := FEngine.TryCreateNoteCAS(N2.Guid,
    procedure
    begin
      Created := True;
    end);
  Assert.IsFalse(Created, 'a create must not run when its guard guid already exists');
  Assert.IsTrue(Res = TSyncApplyResult.arDeferred, 'the guarded create must defer');
  Assert.AreEqual<Integer>(1, FManager.NoteCount);
end;

procedure TSyncFoundationTestFixture.TestLocalEditDuringSyncIsNotOverwritten;
var
  N, P: TNote;
begin
  // N: the worker plans a stale pull (remote rev 5 vs local rev 1); the user
  // edits it while the run is in flight.
  N := FManager.CreateNote('Edited', 'local-v1', ncYellow, 10, 10, 300, 200, False);
  FBackend.Put(N.Guid, BuildRemotePayload(N.Guid, 5, 'Edited', 'remote-v5'));
  // P: a fresh local note the run will push in the same pass.
  P := FManager.CreateNote('Pushed', 'push-me', ncYellow, 20, 20, 300, 200, False);

  FBackend.SetBlockOnRead(N.Guid);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000),
    'the worker should reach the blocked read');

  // The user edit lands mid-run: revision 1 -> 2.
  N.Content := 'user edit';
  FManager.SaveNote(N);

  (FBackend).ReleaseReads;
  FRunner.WaitForIdle;

  // The stale pull must be rejected; the user's edit survives.
  Assert.AreEqual<string>('user edit', N.Content,
    'a stale pull must never overwrite a newer local edit');
  Assert.AreEqual<Int64>(2, N.Rev);

  Assert.AreEqual<Integer>(1, FCompleteCount);
  Assert.IsTrue(FCompleteSuccess, 'the run completes with a deferral: ' + FCompleteMsg);
  Assert.IsTrue(Pos('deferred', FCompleteMsg) > 0,
    'a partial run must say so: ' + FCompleteMsg);
  Assert.AreEqual<Integer>(1, (FBackend).WriteCount,
    'exactly the pushed note may be written');

  // The baseline records only completed work: the pushed note keeps its
  // pushed rev; the deferred note must not advance.
  Assert.AreEqual<Int64>(1, StateSyncedRev(P.Guid), 'the pushed note keeps its pushed rev');
  Assert.AreEqual<Int64>(-1, StateSyncedRev(N.Guid),
    'a deferred note must not advance the baseline');

  // And a later run can reconcile the new revision (current rev-based
  // semantics; WP5 revisits conflict handling on top of this foundation).
  Assert.IsTrue(FEngine.SyncNow, 'the next run must reconcile the new revision');
  Assert.AreEqual<Int64>(5, StateSyncedRev(N.Guid),
    'the second run must process N against the latest revisions');
end;

procedure TSyncFoundationTestFixture.TestCancellationStopsTheRun;
var
  N1, N2, N3: TNote;
begin
  N1 := FManager.CreateNote('C1', 'local-1', ncYellow, 10, 10, 300, 200, False);
  FBackend.Put(N1.Guid, BuildRemotePayload(N1.Guid, 3, 'C1', 'remote-1'));
  N2 := FManager.CreateNote('C2', 'local-2', ncYellow, 20, 20, 300, 200, False);
  FBackend.Put(N2.Guid, BuildRemotePayload(N2.Guid, 3, 'C2', 'remote-2'));
  N3 := FManager.CreateNote('C3', 'local-3', ncYellow, 30, 30, 300, 200, False);
  FBackend.Put(N3.Guid, BuildRemotePayload(N3.Guid, 3, 'C3', 'remote-3'));

  // The run pulls N1, then blocks on N2's read - giving us a deterministic
  // window to cancel mid-run.
  FBackend.SetBlockOnRead(N2.Guid);
  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000),
    'the worker should reach the blocked read on N2');

  FEngine.Cancel;
  (FBackend).ReleaseReads;
  FRunner.WaitForIdle;

  Assert.AreEqual<Integer>(1, FCompleteCount);
  Assert.IsFalse(FCompleteSuccess, 'a cancelled run must not report success');
  Assert.IsTrue(Pos('cancel', LowerCase(FCompleteMsg)) > 0,
    'the cancellation must be reported distinctly: ' + FCompleteMsg);
  Assert.AreEqual<string>('remote-1', N1.Content, 'N1 was pulled before the cancellation');
  Assert.AreEqual<string>('local-2', N2.Content, 'a cancelled run must not mutate N2');
  Assert.AreEqual<string>('local-3', N3.Content, 'a cancelled run must not reach N3');
  Assert.IsFalse((FBackend).WasRead(N3.Guid),
    'processing must stop before reading N3');
  Assert.IsFalse(TFile.Exists(FStatePath), 'a cancelled run must not write sync state');
  Assert.AreEqual<Integer>(0, (FBackend).WriteCount);
end;

procedure TSyncFoundationTestFixture.TestSecondSyncNowIsIgnoredWhileRunning;
var
  N1: TNote;
begin
  N1 := FManager.CreateNote('G1', 'local', ncYellow, 10, 10, 300, 200, False);
  FBackend.Put(N1.Guid, BuildRemotePayload(N1.Guid, 3, 'G1', 'remote'));
  FBackend.SetBlockOnRead(N1.Guid);

  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000),
    'the worker should reach the blocked read');
  Assert.AreEqual<Integer>(1, (FBackend).ListNamesCount);

  // A second SyncNow while the first run is active must be a no-op: no second
  // worker, no duplicate backend traffic.
  Assert.IsFalse(FEngine.SyncNow, 'a second SyncNow must be ignored while a run is active');
  Assert.AreEqual<Integer>(1, (FBackend).ListNamesCount,
    'the rejected call must not start another run');
  Assert.IsTrue(FRunner.IsRunning, 'the original worker must still be the only run');

  (FBackend).ReleaseReads;
  FRunner.WaitForIdle;
  Assert.AreEqual<Integer>(1, FCompleteCount, 'exactly one run may complete');
end;

procedure TSyncFoundationTestFixture.TestCancelThenWaitForIdleTerminates;
var
  N1: TNote;
begin
  N1 := FManager.CreateNote('H1', 'local', ncYellow, 10, 10, 300, 200, False);
  FBackend.Put(N1.Guid, BuildRemotePayload(N1.Guid, 3, 'H1', 'remote'));
  FBackend.SetBlockOnRead(N1.Guid);

  FRunner.Start;
  Assert.IsTrue(PumpUntil(FBackend.ReadEntered, 5000),
    'the worker should reach the blocked read');

  FEngine.Cancel;
  (FBackend).ReleaseReads;
  FRunner.WaitForIdle; // must keep pumping the queue until the worker is done

  Assert.IsFalse(FRunner.IsRunning,
    'WaitForIdle must only return after the worker has terminated');
  Assert.AreEqual<Integer>(1, FCompleteCount,
    'the final marshalled callback must have been delivered');
  Assert.IsTrue(Pos('cancel', LowerCase(FCompleteMsg)) > 0, FCompleteMsg);
  Assert.IsFalse(CheckSynchronize(0),
    'no marshalled callbacks may remain queued after WaitForIdle');

  // The application-side teardown that follows WaitForIdle in Shutdown:
  // nothing may touch the note store afterwards.
  FManager.Finalize;
  Assert.AreEqual<Integer>(1, FCompleteCount, 'no late callback may fire after shutdown');
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncFoundationTestFixture);

end.
