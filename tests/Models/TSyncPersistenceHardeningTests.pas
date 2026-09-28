unit TSyncPersistenceHardeningTests;

// Phase 7G/WP4: persistence hardening tests for sync-state.json /
// sync-journal.json.
//
// Failure injection uses OS-level semantics only (no production test seam):
// a read-only target makes MoveFileEx replacement fail deterministically
// while the file stays readable; a missing directory makes the temp write
// fail. The suite covers atomic round trips, write/replace failures keeping
// the previous valid file, temp residue handling, the JSON well-formedness
// guard, corrupt-file preservation, migration ordering under write failures,
// the WP3 baseline semantics under the new persistence, and the metadata
// failure / operation success distinction.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections, System.DateUtils,
  DUnitX.TestFramework,
  uNote, uEnums, uStorage, uJsonStorage, uNoteManager, uServiceInterfaces,
  uSyncEngine, uSyncState, uSyncJournal, uAtomicFile;

type
  // A compact in-memory ISyncBackend for the WP3-semantics test.
  THardeningTestBackend = class(TInterfacedObject, ISyncBackend)
  private
    FNames: TStringList;
    FObjects: TDictionary<string, string>;
    FVersions: TDictionary<string, Integer>;
    FFailWrites: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AName, APayload: string);
    procedure FailWrite(const AName: string);
    function Content(const AName: string): string;
    function Contains(const AName: string): Boolean;
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
  TSyncPersistenceHardeningTestFixture = class
  private
    FBase: string;
    FLocalPath: string;
    FStatePath: string;
    FJournalPath: string;
    FStorage: INoteStorage;
    FManager: TNoteManager;
    FBackend: THardeningTestBackend;
    FBackendRef: ISyncBackend;
    FEngine: TSyncEngine;     // non-owning view (see FEngineRef)
    FEngineRef: ISyncService; // owns the engine's lifetime
    FCompleteCount: Integer;
    FCompleteSuccess: Boolean;
    FCompleteMsg: string;
    procedure HandleComplete(ASuccess: Boolean; const AMessage: string);
    function ReadText(const APath: string): string;
    procedure WriteText(const APath, AText: string);
    procedure MakeReadOnly(const APath: string);
    procedure MakeWritable(const APath: string);
    function ExistingTempFiles(const APath: string): TArray<string>;
    function ExpectException(const AProc: TProc): Boolean;
    procedure SeedState(const AGuid: string; ARev: Int64);
    function LoadStateMap: TDictionary<string, Int64>; // caller frees
    function StateSyncedRev(const AGuid: string): Int64;
    function MakeNote(const ATitle, AContent: string; ARev: Int64): TNote;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test] procedure TestStateWriteIsAtomicRoundTrip;
    [Test] procedure TestJournalWriteIsAtomicRoundTrip;
    [Test] procedure TestExistingStateSurvivesWriteFailure;
    [Test] procedure TestExistingJournalSurvivesWriteFailure;
    [Test] procedure TestNoTempFilesAfterSuccess;
    [Test] procedure TestTempCleanupAfterFailure;
    [Test] procedure TestReplacementFailurePreservesTarget;
    [Test] procedure TestJsonGuardRejectsInvalidText;
    [Test] procedure TestCorruptStateNotReset;
    [Test] procedure TestCorruptJournalNotReset;
    [Test] procedure TestMigrationJournalWriteFailureKeepsV1;
    [Test] procedure TestMigrationStateWriteFailureThenRetry;
    [Test] procedure TestMetadataFailureIsDistinguishable;
    [Test] procedure TestMixedRunKeepsWP3BaselineSemantics;
    [Test] procedure TestStaleTempResidueIsCleanedAndNeverLive;
    [Test] procedure TestRepeatedSaveFailSaveCycles;
  end;

implementation

var
  GTestSeq: Integer = 0;

const
  GA = 'aaaaaaaa-0000-4000-8000-000000000001';
  GB = 'bbbbbbbb-0000-4000-8000-000000000002';

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

{ THardeningTestBackend }

constructor THardeningTestBackend.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FObjects := TDictionary<string, string>.Create;
  FVersions := TDictionary<string, Integer>.Create;
  FFailWrites := TStringList.Create;
end;

destructor THardeningTestBackend.Destroy;
begin
  FFailWrites.Free;
  FVersions.Free;
  FObjects.Free;
  FNames.Free;
  inherited;
end;

procedure THardeningTestBackend.Put(const AName, APayload: string);
begin
  if not FObjects.ContainsKey(AName) then
    FNames.Add(AName);
  FObjects.AddOrSetValue(AName, APayload);
  FVersions.AddOrSetValue(AName, 1);
end;

procedure THardeningTestBackend.FailWrite(const AName: string);
begin
  FFailWrites.Add(AName);
end;

function THardeningTestBackend.Content(const AName: string): string;
begin
  if not FObjects.TryGetValue(AName, Result) then
    Result := '';
end;

function THardeningTestBackend.Contains(const AName: string): Boolean;
begin
  Result := FObjects.ContainsKey(AName);
end;

function THardeningTestBackend.DisplayName: string;
begin
  Result := 'fake://hardening';
end;

function THardeningTestBackend.ListNames: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FNames.Count);
  for I := 0 to FNames.Count - 1 do
    Result[I] := FNames[I];
end;

function THardeningTestBackend.Read(const AName: string): string;
begin
  Result := Content(AName);
end;

procedure THardeningTestBackend.Write(const AName, AContent: string);
var
  Version: Integer;
begin
  if not FObjects.ContainsKey(AName) then
    FNames.Add(AName);
  FObjects.AddOrSetValue(AName, AContent);
  Version := 0;
  FVersions.TryGetValue(AName, Version);
  FVersions.AddOrSetValue(AName, Version + 1);
end;

procedure THardeningTestBackend.Remove(const AName: string);
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

function THardeningTestBackend.SupportsETags: Boolean;
begin
  Result := True;
end;

function THardeningTestBackend.ReadWithETag(const AName: string; out AETag: string): string;
begin
  AETag := '';
  if not FObjects.ContainsKey(AName) then
    Exit('');
  AETag := IntToStr(FVersions[AName]);
  Result := Content(AName);
end;

function THardeningTestBackend.WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
var
  Current: string;
begin
  Result := False;
  if FFailWrites.IndexOf(AName) >= 0 then
    Exit(False);
  if FObjects.ContainsKey(AName) then
    Current := IntToStr(FVersions[AName])
  else
    Current := '';
  if Current <> AExpectedETag then
    Exit(False);
  Write(AName, AContent);
  Result := True;
end;

{ TSyncPersistenceHardeningTestFixture }

procedure TSyncPersistenceHardeningTestFixture.SetUp;
begin
  Inc(GTestSeq);
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Wp4Test_' + IntToStr(TThread.GetTickCount) + '_' + IntToStr(GTestSeq));
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
  FBackend := THardeningTestBackend.Create;
  FBackendRef := FBackend;
  FEngine := TSyncEngine.Create(FManager, FBackendRef, FStatePath);
  FEngineRef := FEngine;
  FEngine.OnComplete := HandleComplete;
end;

procedure TSyncPersistenceHardeningTestFixture.TearDown;
begin
  if (FStatePath <> '') and TFile.Exists(FStatePath) then
    MakeWritable(FStatePath);
  if (FJournalPath <> '') and TFile.Exists(FJournalPath) then
    MakeWritable(FJournalPath);
  FEngine := nil;
  FEngineRef := nil;
  FBackendRef := nil;
  FBackend := nil;
  FManager.Free;
  FStorage := nil;
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TSyncPersistenceHardeningTestFixture.HandleComplete(ASuccess: Boolean;
  const AMessage: string);
begin
  Inc(FCompleteCount);
  FCompleteSuccess := ASuccess;
  FCompleteMsg := AMessage;
end;

function TSyncPersistenceHardeningTestFixture.ReadText(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath);
end;

procedure TSyncPersistenceHardeningTestFixture.WriteText(const APath, AText: string);
begin
  TFile.WriteAllText(APath, AText, TEncoding.UTF8);
end;

procedure TSyncPersistenceHardeningTestFixture.MakeReadOnly(const APath: string);
begin
  TFile.SetAttributes(APath, TFile.GetAttributes(APath) + [TFileAttribute.faReadOnly]);
end;

procedure TSyncPersistenceHardeningTestFixture.MakeWritable(const APath: string);
begin
  TFile.SetAttributes(APath, TFile.GetAttributes(APath) - [TFileAttribute.faReadOnly]);
end;

function TSyncPersistenceHardeningTestFixture.ExistingTempFiles(const APath: string): TArray<string>;
begin
  Result := TDirectory.GetFiles(TPath.GetDirectoryName(APath),
    TPath.GetFileName(APath) + '.tmp.*');
end;

function TSyncPersistenceHardeningTestFixture.ExpectException(const AProc: TProc): Boolean;
begin
  Result := False;
  try
    AProc();
  except
    on E: Exception do
      Result := True;
  end;
end;

procedure TSyncPersistenceHardeningTestFixture.SeedState(const AGuid: string; ARev: Int64);
var
  Map: TDictionary<string, Int64>;
begin
  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(AGuid, ARev);
    SaveSyncState(FStatePath, Map);
  finally
    Map.Free;
  end;
end;

function TSyncPersistenceHardeningTestFixture.LoadStateMap: TDictionary<string, Int64>;
var
  J: TSyncJournal;
begin
  J := TSyncJournal.Create(FJournalPath);
  try
    Result := LoadSyncState(FStatePath, J);
  finally
    J.Free;
  end;
end;

function TSyncPersistenceHardeningTestFixture.StateSyncedRev(const AGuid: string): Int64;
var
  Map: TDictionary<string, Int64>;
  Rev: Int64;
begin
  Result := -1;
  Map := LoadStateMap;
  try
    if Map.TryGetValue(AGuid, Rev) then
      Result := Rev;
  finally
    Map.Free;
  end;
end;

function TSyncPersistenceHardeningTestFixture.MakeNote(const ATitle, AContent: string;
  ARev: Int64): TNote;
begin
  Result := FManager.CreateNote(ATitle, AContent, ncYellow, 10, 10, 300, 200, False);
  Result.Rev := ARev;
  FManager.PersistNote(Result);
end;

procedure TSyncPersistenceHardeningTestFixture.TestStateWriteIsAtomicRoundTrip;
var
  Map, Loaded: TDictionary<string, Int64>;
  Rev: Int64;
begin
  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(GA, 12);
    Map.AddOrSetValue(GB, 19);
    SaveSyncState(FStatePath, Map);
  finally
    Map.Free;
  end;

  Loaded := LoadStateMap;
  try
    Assert.AreEqual<Integer>(2, Loaded.Count);
    Assert.IsTrue(Loaded.TryGetValue(GA, Rev));
    Assert.AreEqual<Int64>(12, Rev, 'exact values must round-trip');
    Assert.IsTrue(Loaded.TryGetValue(GB, Rev));
    Assert.AreEqual<Int64>(19, Rev, 'exact values must round-trip');
  finally
    Loaded.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)), 'no temp residue');
end;

procedure TSyncPersistenceHardeningTestFixture.TestJournalWriteIsAtomicRoundTrip;
var
  J: TSyncJournal;
  T: TSyncTombstone;
begin
  J := TSyncJournal.Create(FJournalPath);
  try
    J.Add(GA, 3, Now);
    J.Add(GB, 7, Now);
    J.Save;
  finally
    J.Free;
  end;

  J := TSyncJournal.Create(FJournalPath);
  try
    J.Load;
    Assert.AreEqual<Integer>(2, J.Count);
    Assert.IsTrue(J.TryGet(GA, T));
    Assert.AreEqual<Int64>(3, T.Rev, 'exact tombstones must round-trip');
    Assert.IsTrue(J.TryGet(GB, T));
    Assert.AreEqual<Int64>(7, T.Rev, 'exact tombstones must round-trip');
  finally
    J.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FJournalPath)), 'no temp residue');
end;

procedure TSyncPersistenceHardeningTestFixture.TestExistingStateSurvivesWriteFailure;
var
  Map, Loaded: TDictionary<string, Int64>;
  Rev: Int64;
begin
  SeedState(GA, 12);
  MakeReadOnly(FStatePath);
  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(GA, 99);
    Assert.IsTrue(ExpectException(
      procedure
      begin
        SaveSyncState(FStatePath, Map);
      end), 'the write must fail against a read-only target');
  finally
    Map.Free;
  end;
  MakeWritable(FStatePath);

  Loaded := LoadStateMap;
  try
    Assert.IsTrue(Loaded.TryGetValue(GA, Rev));
    Assert.AreEqual<Int64>(12, Rev, 'the old state must remain readable and unchanged');
  finally
    Loaded.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)), 'no temp residue');
end;

procedure TSyncPersistenceHardeningTestFixture.TestExistingJournalSurvivesWriteFailure;
var
  J: TSyncJournal;
  T: TSyncTombstone;
begin
  J := TSyncJournal.Create(FJournalPath);
  try
    J.Add(GA, 3, Now);
    J.Save;
  finally
    J.Free;
  end;

  J := TSyncJournal.Create(FJournalPath);
  try
    J.Load;
    J.Add(GB, 9, Now);
    MakeReadOnly(FJournalPath);
    Assert.IsTrue(ExpectException(
      procedure
      begin
        J.Save;
      end), 'the journal save must fail against a read-only target');
  finally
    MakeWritable(FJournalPath);
    J.Free;
  end;

  J := TSyncJournal.Create(FJournalPath);
  try
    J.Load;
    Assert.IsTrue(J.TryGet(GA, T), 'the previously saved tombstone must survive');
    Assert.IsFalse(J.TryGet(GB, T), 'the failed addition must not have been persisted');
    Assert.AreEqual<Integer>(1, J.Count);
  finally
    J.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FJournalPath)), 'no temp residue');
end;

procedure TSyncPersistenceHardeningTestFixture.TestNoTempFilesAfterSuccess;
var
  J: TSyncJournal;
begin
  SeedState(GA, 5);
  J := TSyncJournal.Create(FJournalPath);
  try
    J.Add(GA, 5, Now);
    J.Save;
  finally
    J.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)),
    'a successful state write must leave no temp file');
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FJournalPath)),
    'a successful journal write must leave no temp file');
end;

procedure TSyncPersistenceHardeningTestFixture.TestTempCleanupAfterFailure;
var
  Map: TDictionary<string, Int64>;
begin
  SeedState(GA, 12);
  MakeReadOnly(FStatePath);
  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(GA, 99);
    Assert.IsTrue(ExpectException(
      procedure
      begin
        SaveSyncState(FStatePath, Map);
      end));
  finally
    Map.Free;
  end;
  MakeWritable(FStatePath);
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)),
    'a failed write must clean up its temp file where safe');
  Assert.AreEqual<Int64>(12, StateSyncedRev(GA), 'the target must remain valid');
end;

procedure TSyncPersistenceHardeningTestFixture.TestReplacementFailurePreservesTarget;
var
  Map: TDictionary<string, Int64>;
  Before: string;
begin
  SeedState(GA, 12);
  Before := ReadText(FStatePath);
  MakeReadOnly(FStatePath);
  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(GA, 99);
    Assert.IsTrue(ExpectException(
      procedure
      begin
        SaveSyncState(FStatePath, Map);
      end), 'the replacement step must fail');
  finally
    Map.Free;
  end;
  MakeWritable(FStatePath);
  Assert.AreEqual<string>(Before, ReadText(FStatePath),
    'the target must contain the old valid JSON after a replacement failure');
end;

procedure TSyncPersistenceHardeningTestFixture.TestJsonGuardRejectsInvalidText;
begin
  Assert.IsTrue(ExpectException(
    procedure
    begin
      AssureValidJsonText('{ this is not json');
    end), 'the JSON guard must reject invalid text');
  // A well-formed document must pass without raising.
  AssureValidJsonText('{"version":2,"synced":{}}');
end;

procedure TSyncPersistenceHardeningTestFixture.TestCorruptStateNotReset;
var
  Before: string;
  Map: TDictionary<string, Int64>;
  Raised: Boolean;
begin
  WriteText(FStatePath, 'garbage {{{ not json');
  Before := ReadText(FStatePath);
  Raised := False;
  Map := nil;
  try
    Map := LoadStateMap;
  except
    on E: Exception do
      Raised := True;
  end;
  Map.Free;
  Assert.IsTrue(Raised, 'a corrupt state file must surface an error');
  Assert.AreEqual<string>(Before, ReadText(FStatePath), 'the corrupt file must not be reset');
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)), 'no temp residue');
end;

procedure TSyncPersistenceHardeningTestFixture.TestCorruptJournalNotReset;
var
  Before: string;
  J: TSyncJournal;
  Raised: Boolean;
begin
  WriteText(FJournalPath, 'garbage {{{ not json');
  Before := ReadText(FJournalPath);
  Raised := False;
  J := TSyncJournal.Create(FJournalPath);
  try
    try
      J.Load;
    except
      on E: Exception do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'a corrupt journal must surface an error');
    Assert.AreEqual<string>(Before, ReadText(FJournalPath),
      'the corrupt journal must not be reset');
  finally
    J.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FJournalPath)), 'no temp residue');
end;

procedure TSyncPersistenceHardeningTestFixture.TestMigrationJournalWriteFailureKeepsV1;
var
  StateBefore, JournalBefore: string;
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
  Rev: Int64;
  T: TSyncTombstone;
  Raised: Boolean;
  Root: TJSONObject;
begin
  WriteText(FStatePath, '{"synced":{"' + GA + '":12},"deleted":["' + GA + '"]}');
  WriteText(FJournalPath, '{"version":1,"deletions":{}}');
  StateBefore := ReadText(FStatePath);
  JournalBefore := ReadText(FJournalPath);

  MakeReadOnly(FJournalPath);
  Raised := False;
  J := TSyncJournal.Create(FJournalPath);
  try
    Map := nil;
    try
      Map := LoadSyncState(FStatePath, J); // migration: the journal save must fail
    except
      on E: Exception do
        Raised := True;
    end;
    Map.Free;
  finally
    J.Free;
  end;
  MakeWritable(FJournalPath);
  Assert.IsTrue(Raised, 'the journal write failure must surface');

  Assert.AreEqual<string>(StateBefore, ReadText(FStatePath),
    'the v1 state must remain recoverable');
  Assert.AreEqual<string>(JournalBefore, ReadText(FJournalPath),
    'the journal file must be unchanged');
  Assert.IsTrue(Pos(GA, ReadText(FStatePath)) > 0, 'the deleted entry must not be lost');

  // Retry after the failure: the migration completes without duplicates.
  J := TSyncJournal.Create(FJournalPath);
  try
    Map := LoadSyncState(FStatePath, J);
    try
      Assert.IsTrue(Map.TryGetValue(GA, Rev));
      Assert.AreEqual<Int64>(12, Rev);
      Assert.IsTrue(J.TryGet(GA, T), 'the retried migration must persist the tombstone');
      Assert.AreEqual<Int64>(12, T.Rev);
      Assert.AreEqual<Integer>(1, J.Count, 'no duplicate tombstones');
    finally
      Map.Free;
    end;
  finally
    J.Free;
  end;
  Root := TJSONObject.ParseJSONValue(ReadText(FStatePath)) as TJSONObject;
  try
    Assert.AreEqual<Integer>(2, (Root.GetValue('version') as TJSONNumber).AsInt,
      'the retried migration must produce a v2 state');
  finally
    Root.Free;
  end;
end;

procedure TSyncPersistenceHardeningTestFixture.TestMigrationStateWriteFailureThenRetry;
var
  StateBefore: string;
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
  Rev: Int64;
  T: TSyncTombstone;
  Raised: Boolean;
  Root: TJSONObject;
begin
  WriteText(FStatePath, '{"synced":{"' + GA + '":12},"deleted":["' + GA + '"]}');
  StateBefore := ReadText(FStatePath);

  MakeReadOnly(FStatePath);
  Raised := False;
  J := TSyncJournal.Create(FJournalPath);
  try
    Map := nil;
    try
      Map := LoadSyncState(FStatePath, J); // journal ok; the v2 state write must fail
    except
      on E: Exception do
        Raised := True;
    end;
    Map.Free;
  finally
    J.Free;
  end;
  Assert.IsTrue(Raised, 'the state write failure must surface');

  // The journal part of the migration was already persisted (journal-first).
  Assert.IsTrue(TFile.Exists(FJournalPath), 'the migrated journal must exist');
  J := TSyncJournal.Create(FJournalPath);
  try
    J.Load;
    Assert.IsTrue(J.TryGet(GA, T), 'the migrated tombstone must be present');
    Assert.AreEqual<Integer>(1, J.Count);
  finally
    J.Free;
  end;
  MakeWritable(FStatePath);
  Assert.AreEqual<string>(StateBefore, ReadText(FStatePath),
    'the original v1 state must remain recoverable');

  // Retry: no duplicate tombstones, and the state becomes v2.
  J := TSyncJournal.Create(FJournalPath);
  try
    Map := LoadSyncState(FStatePath, J);
    try
      Assert.IsTrue(Map.TryGetValue(GA, Rev));
      Assert.AreEqual<Int64>(12, Rev);
      Assert.AreEqual<Integer>(1, J.Count, 'the retry must not duplicate tombstones');
    finally
      Map.Free;
    end;
  finally
    J.Free;
  end;
  Root := TJSONObject.ParseJSONValue(ReadText(FStatePath)) as TJSONObject;
  try
    Assert.AreEqual<Integer>(2, (Root.GetValue('version') as TJSONNumber).AsInt,
      'the retry must produce a v2 state');
  finally
    Root.Free;
  end;
end;

procedure TSyncPersistenceHardeningTestFixture.TestMetadataFailureIsDistinguishable;
var
  N: TNote;
  StateBefore: string;
  S: TSyncRunSummary;
begin
  N := MakeNote('M', 'push-me', 5);
  SeedState(N.Guid, 5);
  StateBefore := ReadText(FStatePath);
  MakeReadOnly(FStatePath);

  Assert.IsFalse(FEngine.SyncNow, 'the run must report failure');
  Assert.IsTrue(Pos('failed', LowerCase(FCompleteMsg)) > 0, FCompleteMsg);
  S := FEngine.LastRunSummary;
  Assert.IsFalse(S.Succeeded, 'the run must not be reported as fully synchronized');
  Assert.IsFalse(S.Cancelled);
  Assert.IsTrue(S.MetadataFailed,
    'a metadata persistence failure must be distinguishable from an operation failure');
  Assert.AreEqual<Integer>(1, S.Pushed, 'the operation itself had succeeded');

  MakeWritable(FStatePath);
  Assert.AreEqual<string>(StateBefore, ReadText(FStatePath),
    'the previous valid metadata must be preserved');
end;

procedure TSyncPersistenceHardeningTestFixture.TestMixedRunKeepsWP3BaselineSemantics;
var
  NA, NB, NC: TNote;
  Map: TDictionary<string, Int64>;
  S: TSyncRunSummary;
begin
  NA := MakeNote('A', 'local-a10', 10);
  FBackend.Put(NA.Guid, BuildRemotePayload(NA.Guid, 11, 'A', 'remote-a11'));
  NB := MakeNote('B', 'edit-b2', 2);
  FBackend.Put(NB.Guid, BuildRemotePayload(NB.Guid, 1, 'B', 'old-b'));
  FBackend.FailWrite(NB.Guid);
  NC := MakeNote('C', 'local-c12', 12);
  FBackend.Put(NC.Guid, BuildRemotePayload(NC.Guid, 13, 'C', 'remote-c13'));
  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(NA.Guid, 10);
    Map.AddOrSetValue(NB.Guid, 1);
    Map.AddOrSetValue(NC.Guid, 12);
    SaveSyncState(FStatePath, Map);
  finally
    Map.Free;
  end;

  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Int64>(11, StateSyncedRev(NA.Guid), 'applied pull: new revision');
  Assert.AreEqual<Int64>(1, StateSyncedRev(NB.Guid), 'deferred: old revision');
  Assert.AreEqual<Int64>(13, StateSyncedRev(NC.Guid), 'applied pull: new revision');
  S := FEngine.LastRunSummary;
  Assert.IsTrue(S.Succeeded);
  Assert.IsFalse(S.MetadataFailed);
  Assert.AreEqual<Integer>(2, S.Pulled);
  Assert.AreEqual<Integer>(1, S.Deferred);
end;

procedure TSyncPersistenceHardeningTestFixture.TestStaleTempResidueIsCleanedAndNeverLive;
var
  StalePath: string;
  Map: TDictionary<string, Int64>;
  Rev: Int64;
begin
  // Simulate an interruption between temp write and replacement: a stale
  // uniquely named temp file is left next to the target.
  StalePath := FStatePath + '.tmp.99999.1';
  WriteText(StalePath, 'stale garbage from an interrupted write');

  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(GA, 7);
    SaveSyncState(FStatePath, Map);
  finally
    Map.Free;
  end;

  Assert.IsFalse(TFile.Exists(StalePath),
    'a stale temp must be cleaned up on the next write to the same target');
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)));

  Map := LoadStateMap;
  try
    Assert.IsTrue(Map.TryGetValue(GA, Rev));
    Assert.AreEqual<Int64>(7, Rev, 'the stale residue must never be read as live state');
  finally
    Map.Free;
  end;
end;

procedure TSyncPersistenceHardeningTestFixture.TestRepeatedSaveFailSaveCycles;
var
  Map: TDictionary<string, Int64>;
  I: Integer;
  Rev: Int64;
begin
  for I := 1 to 3 do
  begin
    Map := TDictionary<string, Int64>.Create;
    try
      Map.AddOrSetValue(GA, I);
      SaveSyncState(FStatePath, Map); // save (ok)
    finally
      Map.Free;
    end;

    MakeReadOnly(FStatePath);
    Map := TDictionary<string, Int64>.Create;
    try
      Map.AddOrSetValue(GA, 1000 + I);
      Assert.IsTrue(ExpectException(
        procedure
        begin
          SaveSyncState(FStatePath, Map);
        end), 'the forced failure must surface');
    finally
      Map.Free;
    end;
    MakeWritable(FStatePath);
  end;

  Map := TDictionary<string, Int64>.Create;
  try
    Map.AddOrSetValue(GA, 100);
    SaveSyncState(FStatePath, Map); // final save (ok)
  finally
    Map.Free;
  end;

  Map := LoadStateMap;
  try
    Assert.IsTrue(Map.TryGetValue(GA, Rev));
    Assert.AreEqual<Int64>(100, Rev, 'the final valid save must be readable');
  finally
    Map.Free;
  end;
  Assert.AreEqual<Integer>(0, Length(ExistingTempFiles(FStatePath)),
    'no stale temp may be mistaken for live state after the cycles');
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncPersistenceHardeningTestFixture);

end.
