unit TSyncReconcileTests;

// Phase 7G/WP5: T1-T9 reconcile behavior tests (design S7).
//
// Two test devices (independent storage + sync-state + journal) share one
// folder-sync store. Each device's backend is wrapped in a counting decorator
// that counts backend writes, can fail one named write once, and can throw on
// the next write (T8/T9). All syncs run inline on the main thread, so no
// worker pumping is needed. Temp sandboxes only.
//
// This unit is written BEFORE the WP5 rewrite so the pre-fix failures of T1,
// T2, T4, T6, T7 (and T3, T5, T9) are demonstrated against the old engine.

interface

uses
  System.SysUtils, System.Classes, System.Hash, System.IOUtils, System.JSON,
  System.DateUtils, System.Generics.Collections,
  DUnitX.TestFramework,
  uNote, uEnums, uStorage, uJsonStorage, uNoteManager, uServiceInterfaces,
  uFolderSyncBackend, uSyncEngine, uSyncState, uSyncJournal, uAtomicFile;

type
  // Shared write accounting + failure injection across both devices.
  TWriteCounter = class
  private
    FFailOnce: TStringList;
  public
    WriteSuccesses: Integer;
    WriteAttempts: Integer;
    RemoveCalls: Integer;
    RaiseOnNextWrite: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure ResetStats;
    procedure FailNextWriteOnce(const AName: string);
    function PopFailOnce(const AName: string): Boolean;
    property Writes: Integer read WriteSuccesses;
    property Attempts: Integer read WriteAttempts;
  end;

  TCountingBackend = class(TInterfacedObject, ISyncBackend)
  private
    FInner: TFolderSyncBackend;
    FCounter: TWriteCounter;
  public
    constructor Create(const ARootPath: string; const ACounter: TWriteCounter);
    destructor Destroy; override;
    function DisplayName: string;
    function ListNames: TArray<string>;
    function Read(const AName: string): string;
    procedure Write(const AName, AContent: string);
    procedure Remove(const AName: string);
    function SupportsETags: Boolean;
    function ReadWithETag(const AName: string; out AETag: string): string;
    function WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
  end;

  TTestDevice = class
  public
    Name: string;
    DeviceTag: string;
    BasePath: string;
    Storage: INoteStorage;
    Manager: TNoteManager;
    Backend: TCountingBackend;
    BackendRef: ISyncBackend;
    Engine: TSyncEngine;
    EngineRef: ISyncService;
    constructor Create(const AName, ADeviceTag, ABasePath, ASharedRoot: string;
      const ACounter: TWriteCounter);
    destructor Destroy; override;
  end;

  [TestFixture]
  TSyncReconcileTestFixture = class
  private
    FBase: string;
    FShared: string;
    FCounter: TWriteCounter;
    FDeviceA: TTestDevice;
    FDeviceB: TTestDevice;
    FLastCompleteOk: Boolean;
    FLastCompleteMsg: string;
    procedure CreateDevices;
    procedure HandleComplete(ASuccess: Boolean; const AMessage: string);
    function NewNote(const AD: TTestDevice; const ATitle, AContent: string): TNote;
    procedure EditNote(const AD: TTestDevice; const ANote: TNote; const AContent: string);
    procedure DeleteWithJournal(const AD: TTestDevice; const ANote: TNote);
    procedure SyncD(const AD: TTestDevice);
    function FindNote(const AD: TTestDevice; const AGuid: string): TNote;
    function NoteCount(const AD: TTestDevice): Integer;
    function HasContent(const AD: TTestDevice; const AContent: string): Boolean;
    function RemoteNames: TArray<string>;
    function RemoteNameList: string;
    function NotesDir: string;
    function RemoteText(const AName: string): string;
    function RemoteNote(const AName: string): TNote; // caller frees
    function RemoteLiveCount: Integer;
    function RemoteTombstoneCount: Integer;
    function CopiesFor(const AOrigGuid: string): Integer;
    function ExpectedCopyGuid(const AOrigGuid, ALoserDeviceId: string; ALoserRev: Int64): string;
    procedure MakeCommonNote(out AGA: string);
    procedure WriteStateFile(const AD: TTestDevice; const AEntries: TDictionary<string, Int64>);
    function RunDeletionScenario(const ACount: Integer): Boolean;
    function StateRevOf(const AD: TTestDevice; const AGuid: string): Int64;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test] procedure TestT1LostUpdateOrderABAB;
    [Test] procedure TestT1LostUpdateOrderBABA;
    [Test] procedure TestT2EqualRevConflictConverges;
    [Test] procedure TestT3OrderIndependence;
    [Test] procedure TestT4DeletePropagation;
    [Test] procedure TestT5EditBeatsDelete;
    [Test] procedure TestT6PullDeleteBeforeNextSync;
    [Test] procedure TestT7AbsenceNeverDeletes;
    [Test] procedure TestT8FailedRunKeepsStateIdentical;
    [Test] procedure TestT9DeterministicCopyIdentity;
    [Test] procedure TestEmptyRemoteRepushesWithoutDeleting;
    [Test] procedure TestDeletionThreshold25NoWarning;
    [Test] procedure TestDeletionThreshold26Warns;
  end;

implementation

var
  GTestSeq: Integer = 0;

const
  DevTagA = 'a-device-000000000001';
  DevTagB = 'b-device-000000000002';

function BuildLivePayload(const AGuid: string; ARev: Int64;
  const ATitle, AContent, ADeviceId: string): string;
var
  N: TNote;
  J: TJSONObject;
begin
  N := TNote.Create(1, ATitle, AContent, ncYellow);
  try
    N.Guid := AGuid;
    N.Rev := ARev;
    N.DeviceId := ADeviceId;
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

function BuildTombstonePayload(const AGuid: string; ARev: Int64;
  ADeletedAt: TDateTime): string;
var
  N: TNote;
  J: TJSONObject;
begin
  N := TNote.Create(1, '', '', ncYellow);
  try
    N.Guid := AGuid;
    N.Rev := ARev;
    N.DeviceId := DevTagB;
    N.Deleted := True;
    N.DeletedAt := ADeletedAt;
    N.CreatedAt := ADeletedAt;
    N.UpdatedAt := ADeletedAt;
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

{ TWriteCounter }

constructor TWriteCounter.Create;
begin
  inherited Create;
  FFailOnce := TStringList.Create;
end;

destructor TWriteCounter.Destroy;
begin
  FFailOnce.Free;
  inherited;
end;

procedure TWriteCounter.ResetStats;
begin
  WriteSuccesses := 0;
  WriteAttempts := 0;
  RemoveCalls := 0;
end;

procedure TWriteCounter.FailNextWriteOnce(const AName: string);
begin
  FFailOnce.Add(AName);
end;

function TWriteCounter.PopFailOnce(const AName: string): Boolean;
var
  Idx: Integer;
begin
  Idx := FFailOnce.IndexOf(AName);
  Result := Idx >= 0;
  if Result then
    FFailOnce.Delete(Idx);
end;

{ TCountingBackend }

constructor TCountingBackend.Create(const ARootPath: string; const ACounter: TWriteCounter);
begin
  inherited Create;
  FInner := TFolderSyncBackend.Create(ARootPath);
  FCounter := ACounter;
end;

destructor TCountingBackend.Destroy;
begin
  FInner.Free;
  inherited;
end;

function TCountingBackend.DisplayName: string;
begin
  Result := FInner.DisplayName;
end;

function TCountingBackend.ListNames: TArray<string>;
begin
  Result := FInner.ListNames;
end;

function TCountingBackend.Read(const AName: string): string;
begin
  Result := FInner.Read(AName);
end;

procedure TCountingBackend.Write(const AName, AContent: string);
begin
  Inc(FCounter.WriteAttempts);
  if FCounter.RaiseOnNextWrite then
  begin
    FCounter.RaiseOnNextWrite := False;
    raise Exception.Create('injected backend write failure');
  end;
  FInner.Write(AName, AContent);
  Inc(FCounter.WriteSuccesses);
end;

procedure TCountingBackend.Remove(const AName: string);
begin
  Inc(FCounter.RemoveCalls);
  FInner.Remove(AName);
end;

function TCountingBackend.SupportsETags: Boolean;
begin
  Result := FInner.SupportsETags;
end;

function TCountingBackend.ReadWithETag(const AName: string; out AETag: string): string;
begin
  Result := FInner.ReadWithETag(AName, AETag);
end;

function TCountingBackend.WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
begin
  Inc(FCounter.WriteAttempts);
  if FCounter.RaiseOnNextWrite then
  begin
    FCounter.RaiseOnNextWrite := False;
    raise Exception.Create('injected backend write failure');
  end;
  if FCounter.PopFailOnce(AName) then
    Exit(False); // simulated optimistic-concurrency failure, one shot
  Result := FInner.WriteIfMatch(AName, AContent, AExpectedETag);
  if Result then
    Inc(FCounter.WriteSuccesses);
end;

{ TTestDevice }

constructor TTestDevice.Create(const AName, ADeviceTag, ABasePath, ASharedRoot: string;
  const ACounter: TWriteCounter);
begin
  inherited Create;
  Name := AName;
  DeviceTag := ADeviceTag;
  BasePath := ABasePath;
  ForceDirectories(BasePath);
  // Deterministic device identity: the storage stamps this tag on every save.
  TFile.WriteAllText(TPath.Combine(BasePath, 'device.id'), ADeviceTag, TEncoding.ASCII);
  Storage := TJsonStorage.Create(BasePath);
  Manager := TNoteManager.Create(Storage);
  Manager.Initialize;
  Backend := TCountingBackend.Create(ASharedRoot, ACounter);
  BackendRef := Backend;
  Engine := TSyncEngine.Create(Manager, BackendRef,
    TPath.Combine(BasePath, 'sync-state.json'));
  EngineRef := Engine;
end;

destructor TTestDevice.Destroy;
begin
  Engine := nil;
  EngineRef := nil;
  BackendRef := nil;
  Backend := nil;
  Manager.Free;
  Storage := nil;
  inherited;
end;

{ TSyncReconcileTestFixture }

procedure TSyncReconcileTestFixture.SetUp;
begin
  Inc(GTestSeq);
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Wp5Test_' + IntToStr(TThread.GetTickCount) + '_' + IntToStr(GTestSeq));
  FShared := TPath.Combine(FBase, 'shared-remote');
  ForceDirectories(FBase);
  ForceDirectories(FShared);
  ForceDirectories(TPath.Combine(FShared, 'notes')); // TFolderSyncBackend's object dir
  FCounter := TWriteCounter.Create;
  FLastCompleteOk := True;
  FLastCompleteMsg := '';
  CreateDevices;
end;

procedure TSyncReconcileTestFixture.CreateDevices;
begin
  FDeviceA := TTestDevice.Create('A', DevTagA, TPath.Combine(FBase, 'devA'), FShared, FCounter);
  FDeviceB := TTestDevice.Create('B', DevTagB, TPath.Combine(FBase, 'devB'), FShared, FCounter);
  FDeviceA.Engine.OnComplete := HandleComplete;
  FDeviceB.Engine.OnComplete := HandleComplete;
end;

procedure TSyncReconcileTestFixture.TearDown;
begin
  FDeviceA.Free;
  FDeviceB.Free;
  FCounter.Free;
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TSyncReconcileTestFixture.HandleComplete(ASuccess: Boolean; const AMessage: string);
begin
  FLastCompleteOk := ASuccess;
  FLastCompleteMsg := AMessage;
end;

function TSyncReconcileTestFixture.NewNote(const AD: TTestDevice;
  const ATitle, AContent: string): TNote;
begin
  Result := AD.Manager.CreateNote(ATitle, AContent, ncYellow, 10, 10, 300, 200, False);
  AD.Manager.PersistNote(Result); // stamps the deterministic device tag
end;

procedure TSyncReconcileTestFixture.EditNote(const AD: TTestDevice; const ANote: TNote;
  const AContent: string);
begin
  ANote.Content := AContent;
  AD.Manager.SaveNote(ANote);
end;

procedure TSyncReconcileTestFixture.DeleteWithJournal(const AD: TTestDevice; const ANote: TNote);
begin
  // Mirrors the application flow: the journal records the deletion the moment
  // it actually happens (TNoteApplication.OnNoteDeleted -> RecordLocalDeletion).
  AD.Engine.RecordLocalDeletion(ANote.Guid, ANote.Rev);
  Assert.IsTrue(AD.Manager.DeleteNote(ANote.ID), 'the local delete must succeed');
end;

procedure TSyncReconcileTestFixture.SyncD(const AD: TTestDevice);
begin
  Assert.IsTrue(AD.Engine.SyncNow, AD.Name + ': the sync must succeed (msg: ' + FLastCompleteMsg + ')');
end;

function TSyncReconcileTestFixture.FindNote(const AD: TTestDevice; const AGuid: string): TNote;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to AD.Manager.NoteCount - 1 do
    if AD.Manager.Notes[I].Guid = AGuid then
      Exit(AD.Manager.Notes[I]);
end;

function TSyncReconcileTestFixture.NoteCount(const AD: TTestDevice): Integer;
begin
  Result := AD.Manager.NoteCount;
end;

function TSyncReconcileTestFixture.HasContent(const AD: TTestDevice;
  const AContent: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to AD.Manager.NoteCount - 1 do
    if AD.Manager.Notes[I].Content = AContent then
      Exit(True);
end;

function TSyncReconcileTestFixture.RemoteNameList: string;
var
  Names: TArray<string>;
  Name: string;
begin
  Result := '';
  Names := RemoteNames;
  for Name in Names do
    Result := Result + TPath.GetFileName(Name) + ' ';
end;

function TSyncReconcileTestFixture.NotesDir: string;
begin
  // TFolderSyncBackend stores objects one-per-file under <root>\notes.
  Result := TPath.Combine(FShared, 'notes');
end;

function TSyncReconcileTestFixture.RemoteNames: TArray<string>;
begin
  if not TDirectory.Exists(NotesDir) then
    Exit(nil);
  Result := TDirectory.GetFiles(NotesDir, '*.json');
end;

function TSyncReconcileTestFixture.RemoteText(const AName: string): string;
begin
  Result := TFile.ReadAllText(TPath.Combine(NotesDir, AName));
end;

function TSyncReconcileTestFixture.RemoteNote(const AName: string): TNote;
var
  Root: TJSONValue;
begin
  Result := nil;
  Root := TJSONObject.ParseJSONValue(RemoteText(AName));
  if Root is TJSONObject then
    Result := TJsonStorage.JsonToNote(Root as TJSONObject);
  Root.Free;
end;

function TSyncReconcileTestFixture.RemoteLiveCount: Integer;
var
  Names: TArray<string>;
  Name: string;
  N: TNote;
begin
  Result := 0;
  Names := RemoteNames;
  for Name in Names do
  begin
    N := RemoteNote(TPath.GetFileName(Name));
    try
      if (N <> nil) and (not N.Deleted) then
        Inc(Result);
    finally
      N.Free;
    end;
  end;
end;

function TSyncReconcileTestFixture.RemoteTombstoneCount: Integer;
var
  Names: TArray<string>;
  Name: string;
  N: TNote;
begin
  Result := 0;
  Names := RemoteNames;
  for Name in Names do
  begin
    N := RemoteNote(TPath.GetFileName(Name));
    try
      if (N <> nil) and N.Deleted then
        Inc(Result);
    finally
      N.Free;
    end;
  end;
end;

function TSyncReconcileTestFixture.CopiesFor(const AOrigGuid: string): Integer;
var
  Guids: TStringList;
  I: Integer;
  N: TNote;
  Name: string;
  Names: TArray<string>;
begin
  // Distinct conflict-copy guids across device A, device B and the remote.
  Guids := TStringList.Create;
  try
    for I := 0 to FDeviceA.Manager.NoteCount - 1 do
      if FDeviceA.Manager.Notes[I].ConflictOf = AOrigGuid then
        if Guids.IndexOf(FDeviceA.Manager.Notes[I].Guid) < 0 then
          Guids.Add(FDeviceA.Manager.Notes[I].Guid);
    for I := 0 to FDeviceB.Manager.NoteCount - 1 do
      if FDeviceB.Manager.Notes[I].ConflictOf = AOrigGuid then
        if Guids.IndexOf(FDeviceB.Manager.Notes[I].Guid) < 0 then
          Guids.Add(FDeviceB.Manager.Notes[I].Guid);
    Names := RemoteNames;
    for Name in Names do
    begin
      N := RemoteNote(TPath.GetFileName(Name));
      try
        if (N <> nil) and (N.ConflictOf = AOrigGuid) then
          if Guids.IndexOf(N.Guid) < 0 then
            Guids.Add(N.Guid);
      finally
        N.Free;
      end;
    end;
    Result := Guids.Count;
  finally
    Guids.Free;
  end;
end;

function TSyncReconcileTestFixture.ExpectedCopyGuid(const AOrigGuid, ALoserDeviceId: string;
  ALoserRev: Int64): string;
var
  Hash: string;
begin
  Hash := LowerCase(THashSHA2.GetHashString(AOrigGuid + '|' + ALoserDeviceId + '|' +
    IntToStr(ALoserRev)));
  Result := Copy(Hash, 1, 8) + '-' + Copy(Hash, 9, 4) + '-' + Copy(Hash, 13, 4) +
    '-' + Copy(Hash, 17, 4) + '-' + Copy(Hash, 21, 12);
end;

procedure TSyncReconcileTestFixture.MakeCommonNote(out AGA: string);
var
  N: TNote;
begin
  // A creates the note and publishes it; B pulls it: common state rev 1.
  N := NewNote(FDeviceA, 'X', 'common');
  AGA := N.Guid;
  SyncD(FDeviceA);
  SyncD(FDeviceB);
  Assert.IsTrue(FindNote(FDeviceB, AGA) <> nil, 'the common note must exist on B');
  FCounter.ResetStats;
end;

procedure TSyncReconcileTestFixture.WriteStateFile(const AD: TTestDevice;
  const AEntries: TDictionary<string, Int64>);
var
  J: TSyncJournal;
begin
  J := TSyncJournal.Create(TPath.Combine(AD.BasePath, 'sync-journal.json'));
  try
    SaveSyncState(TPath.Combine(AD.BasePath, 'sync-state.json'), AEntries);
  finally
    J.Free;
  end;
end;

procedure TSyncReconcileTestFixture.TestT1LostUpdateOrderABAB;
var
  GA: string;
  NA: TNote;
  ExpectedCopy: string;
begin
  MakeCommonNote(GA);

  // A: one content edit (rev 2). B: three content edits (rev 4).
  EditNote(FDeviceA, FindNote(FDeviceA, GA), 'A-edit');
  NA := FindNote(FDeviceB, GA);
  EditNote(FDeviceB, NA, 'B-edit-1');
  EditNote(FDeviceB, NA, 'B-edit-2');
  EditNote(FDeviceB, NA, 'B-edit-3');

  // Interleaving: A, B, A.
  SyncD(FDeviceA);
  SyncD(FDeviceB);
  SyncD(FDeviceA);

  // Both texts survive: B's final edit live (higher rev won), A's edit as the
  // single deterministic conflict copy.
  Assert.IsTrue(HasContent(FDeviceA, 'B-edit-3'), 'A must hold B''s final text');
  Assert.IsTrue(HasContent(FDeviceA, 'A-edit'), 'A''s text must survive on A (as the copy)');
  Assert.IsTrue(HasContent(FDeviceB, 'B-edit-3'), 'B must hold its final text');
  Assert.IsTrue(HasContent(FDeviceB, 'A-edit'), 'A''s text must survive on B (as the copy)');
  ExpectedCopy := ExpectedCopyGuid(GA, DevTagA, 2);
  Assert.AreEqual<Integer>(1, CopiesFor(GA), 'exactly one conflict copy may exist');
  Assert.IsTrue(FindNote(FDeviceA, ExpectedCopy) <> nil,
    'the copy must have the deterministic identity for the (A, rev 2) loser');
  Assert.AreEqual<Int64>(5, FindNote(FDeviceA, GA).Rev, 'the winner must be published at max+1');
  Assert.AreEqual<Int64>(5, FindNote(FDeviceB, GA).Rev, 'both sides must end at the same rev');
  Assert.AreEqual<Int64>(2, FindNote(FDeviceA, ExpectedCopy).Rev, 'the copy keeps the loser rev');
end;

procedure TSyncReconcileTestFixture.TestT1LostUpdateOrderBABA;
var
  GA: string;
  NA: TNote;
  ExpectedCopy: string;
begin
  MakeCommonNote(GA);

  EditNote(FDeviceA, FindNote(FDeviceA, GA), 'A-edit');
  NA := FindNote(FDeviceB, GA);
  EditNote(FDeviceB, NA, 'B-edit-1');
  EditNote(FDeviceB, NA, 'B-edit-2');
  EditNote(FDeviceB, NA, 'B-edit-3');

  // Interleaving: B, A, B.
  SyncD(FDeviceB);
  SyncD(FDeviceA);
  SyncD(FDeviceB);

  Assert.IsTrue(HasContent(FDeviceA, 'B-edit-3'), 'A must hold B''s final text');
  Assert.IsTrue(HasContent(FDeviceA, 'A-edit'), 'A''s text must survive on A (as the copy)');
  Assert.IsTrue(HasContent(FDeviceB, 'A-edit'), 'A''s text must survive on B (as the copy)');
  ExpectedCopy := ExpectedCopyGuid(GA, DevTagA, 2);
  Assert.AreEqual<Integer>(1, CopiesFor(GA), 'exactly one conflict copy may exist');
  Assert.IsTrue(FindNote(FDeviceB, ExpectedCopy) <> nil,
    'the copy identity must be the same deterministic value in the mirrored order');
  Assert.AreEqual<Int64>(FindNote(FDeviceA, GA).Rev, FindNote(FDeviceB, GA).Rev,
    'both sides must end at the same rev');
  Assert.AreEqual<string>('B-edit-3', FindNote(FDeviceA, GA).Content);
end;

procedure TSyncReconcileTestFixture.TestT2EqualRevConflictConverges;
var
  GA: string;
  WritesAfterR3: Integer;
  ExpectedCopy: string;
  W1, W2, W3, W4, W5: Integer;
begin
  MakeCommonNote(GA);

  // Equal-rev conflict: both edit once from the common rev (rev 2 each).
  EditNote(FDeviceA, FindNote(FDeviceA, GA), 'A-edit');
  EditNote(FDeviceB, FindNote(FDeviceB, GA), 'B-edit');

  // Alternate A, B, A, B, A.
  SyncD(FDeviceA); // A publishes its edit (only-local-changed)
  W1 := FCounter.Writes;
  SyncD(FDeviceB); // B resolves: winner by deviceId -> publish @3 + copy
  W2 := FCounter.Writes;
  SyncD(FDeviceA); // A pulls the resolved winner + the copy
  W3 := FCounter.Writes;

  WritesAfterR3 := W3;
  SyncD(FDeviceB); // round 4
  W4 := FCounter.Writes;
  SyncD(FDeviceA); // round 5
  W5 := FCounter.Writes;
  Assert.AreEqual<Integer>(WritesAfterR3, FCounter.Writes,
    Format('the last two rounds must produce zero backend writes (per round: %d,%d,%d,%d,%d; copies: %d; A[X:%d "%s"] B[X:%d "%s"] remote(%d)=%s)',
      [W1, W2, W3, W4, W5, CopiesFor(GA),
       FindNote(FDeviceA, GA).Rev, FindNote(FDeviceA, GA).Content,
       FindNote(FDeviceB, GA).Rev, FindNote(FDeviceB, GA).Content,
       Length(RemoteNames), RemoteNameList]));

  // Exactly one conflict copy, stable counts, same final revocation.
  ExpectedCopy := ExpectedCopyGuid(GA, DevTagA, 2);
  Assert.AreEqual<Integer>(1, CopiesFor(GA), 'exactly one conflict copy in the system');
  Assert.IsTrue(FindNote(FDeviceA, ExpectedCopy) <> nil, 'copy on A (deterministic guid)');
  Assert.IsTrue(FindNote(FDeviceB, ExpectedCopy) <> nil, 'copy on B (deterministic guid)');
  Assert.AreEqual<Integer>(2, NoteCount(FDeviceA), 'stable note count on A');
  Assert.AreEqual<Integer>(2, NoteCount(FDeviceB), 'stable note count on B');
  Assert.AreEqual<Integer>(2, Length(RemoteNames), 'stable object count on the remote');
  Assert.AreEqual<Int64>(FindNote(FDeviceA, GA).Rev, FindNote(FDeviceB, GA).Rev,
    'both sides must hold the winner at the same final rev');
  Assert.AreEqual<Int64>(FindNote(FDeviceA, GA).Rev, 3, 'the winner was published at max+1');
  Assert.AreEqual<string>('B-edit', FindNote(FDeviceA, GA).Content,
    'the deviceId tie-break must pick B on both sides');
end;

procedure TSyncReconcileTestFixture.TestT3OrderIndependence;
var
  GA: string;
  WritesAfterR3: Integer;
  ExpectedCopy: string;
  W1, W2, W3, W4, W5: Integer;
begin
  MakeCommonNote(GA);

  EditNote(FDeviceA, FindNote(FDeviceA, GA), 'A-edit');
  EditNote(FDeviceB, FindNote(FDeviceB, GA), 'B-edit');

  // T2 with B syncing first: alternate B, A, B, A, B.
  SyncD(FDeviceB);
  W1 := FCounter.Writes;
  SyncD(FDeviceA);
  W2 := FCounter.Writes;
  SyncD(FDeviceB);
  W3 := FCounter.Writes;

  WritesAfterR3 := W3;
  SyncD(FDeviceA);
  W4 := FCounter.Writes;
  SyncD(FDeviceB);
  W5 := FCounter.Writes;
  Assert.AreEqual<Integer>(WritesAfterR3, FCounter.Writes,
    Format('the last two rounds must produce zero backend writes (per round: %d,%d,%d,%d,%d; copies: %d; A[X:%d "%s"] B[X:%d "%s"] remote(%d)=%s)',
      [W1, W2, W3, W4, W5, CopiesFor(GA),
       FindNote(FDeviceA, GA).Rev, FindNote(FDeviceA, GA).Content,
       FindNote(FDeviceB, GA).Rev, FindNote(FDeviceB, GA).Content,
       Length(RemoteNames), RemoteNameList]));

  // Same final logical state as T2: winner content live on both sides, the
  // loser preserved under the identical deterministic copy identity.
  ExpectedCopy := ExpectedCopyGuid(GA, DevTagA, 2);
  Assert.AreEqual<Integer>(1, CopiesFor(GA), 'exactly one conflict copy in the system');
  Assert.IsTrue(FindNote(FDeviceA, ExpectedCopy) <> nil, 'copy on A with the T2 identity');
  Assert.IsTrue(FindNote(FDeviceB, ExpectedCopy) <> nil, 'copy on B with the T2 identity');
  Assert.AreEqual<string>('B-edit', FindNote(FDeviceA, GA).Content);
  Assert.AreEqual<string>('B-edit', FindNote(FDeviceB, GA).Content);
  Assert.AreEqual<Int64>(FindNote(FDeviceA, GA).Rev, FindNote(FDeviceB, GA).Rev,
    'both sides must end at the same rev');
  Assert.AreEqual<Integer>(2, NoteCount(FDeviceA), 'stable note count on A');
  Assert.AreEqual<Integer>(2, NoteCount(FDeviceB), 'stable note count on B');
  Assert.AreEqual<Integer>(2, Length(RemoteNames), 'stable object count on the remote');
end;

procedure TSyncReconcileTestFixture.TestT4DeletePropagation;
var
  GA: string;
  WritesAfterStable: Integer;
  Tomb: TNote;
begin
  MakeCommonNote(GA);

  // A deletes (journal + local delete), then syncs; B syncs.
  DeleteWithJournal(FDeviceA, FindNote(FDeviceA, GA));
  SyncD(FDeviceA);
  SyncD(FDeviceB);

  Assert.IsTrue(FindNote(FDeviceB, GA) = nil, 'the note must be gone on B');
  Assert.AreEqual<Integer>(0, NoteCount(FDeviceB));
  Assert.AreEqual<Integer>(1, RemoteTombstoneCount, 'a tombstone must exist on the remote');
  Tomb := RemoteNote(GA + '.json');
  try
    Assert.IsTrue(Tomb <> nil, 'the tombstone must parse');
    Assert.IsTrue(Tomb.Deleted, 'the remote object must be a tombstone');
    Assert.AreEqual<Int64>(2, Tomb.Rev, 'the tombstone carries rev = old rev + 1');
    Assert.IsTrue(Tomb.DeletedAt > 0, 'the tombstone carries DeletedAt');
  finally
    Tomb.Free;
  end;

  // Stable afterwards; nothing is physically removed; no resurrection on A.
  WritesAfterStable := FCounter.Writes;
  SyncD(FDeviceA);
  SyncD(FDeviceB);
  Assert.AreEqual<Integer>(WritesAfterStable, FCounter.Writes, 'must be stable');
  Assert.AreEqual<Integer>(1, RemoteTombstoneCount, 'the tombstone must survive');
  Assert.IsTrue(FindNote(FDeviceA, GA) = nil, 'no resurrection on A');
  Assert.IsTrue(FindNote(FDeviceB, GA) = nil, 'no resurrection on B');
  Assert.AreEqual<Integer>(0, FCounter.RemoveCalls, 'the engine must never physically remove objects');
end;

procedure TSyncReconcileTestFixture.TestT5EditBeatsDelete;
var
  GA: string;
begin
  MakeCommonNote(GA);

  // A deletes and publishes the tombstone.
  DeleteWithJournal(FDeviceA, FindNote(FDeviceA, GA));
  SyncD(FDeviceA);
  Assert.AreEqual<Integer>(1, RemoteTombstoneCount, 'precondition: tombstone on the remote');

  // B edits before learning of the deletion; the edit must win.
  EditNote(FDeviceB, FindNote(FDeviceB, GA), 'B-edit');
  SyncD(FDeviceB);
  SyncD(FDeviceA);

  Assert.IsTrue(FindNote(FDeviceA, GA) <> nil, 'the note must be live again on A');
  Assert.AreEqual<string>('B-edit', FindNote(FDeviceA, GA).Content, 'A must see B''s edit');
  Assert.AreEqual<Int64>(3, FindNote(FDeviceA, GA).Rev, 'published at max(revL, revT) + 1');
  Assert.AreEqual<Int64>(3, FindNote(FDeviceB, GA).Rev, 'both sides end at the same rev');
  Assert.AreEqual<Integer>(0, RemoteTombstoneCount, 'the tombstone was superseded');
  Assert.AreEqual<Integer>(1, RemoteLiveCount, 'the live note is on the remote again');
  Assert.AreEqual<Integer>(0, CopiesFor(GA), 'edit-beats-delete is not a conflict: no copy');
end;

procedure TSyncReconcileTestFixture.TestT6PullDeleteBeforeNextSync;
var
  GA: string;
  WritesAfterStable: Integer;
begin
  // A creates and publishes; B pulls it in a successful run.
  MakeCommonNote(GA);

  // B deletes before its next sync.
  DeleteWithJournal(FDeviceB, FindNote(FDeviceB, GA));
  SyncD(FDeviceB);
  SyncD(FDeviceA);

  Assert.IsTrue(FindNote(FDeviceB, GA) = nil, 'the note must not come back on B');
  Assert.IsTrue(FindNote(FDeviceA, GA) = nil, 'the deletion must propagate to A');
  Assert.AreEqual<Integer>(1, RemoteTombstoneCount, 'a tombstone must exist on the remote');

  WritesAfterStable := FCounter.Writes;
  SyncD(FDeviceB);
  SyncD(FDeviceA);
  Assert.AreEqual<Integer>(WritesAfterStable, FCounter.Writes, 'must be stable');
  Assert.IsTrue(FindNote(FDeviceB, GA) = nil, 'no resurrection on B');
end;

procedure TSyncReconcileTestFixture.TestT7AbsenceNeverDeletes;
var
  I: Integer;
  N: TNote;
  RemoteBefore: TDictionary<string, string>;
  Names: TArray<string>;
  Name: string;
  Map, LoadedMap: TDictionary<string, Int64>;
  StateText: string;
  J: TSyncJournal;
begin
  // Remote: five notes (published by A). B's profile: sync-state seeded from a
  // previous life, local store empty.
  RemoteBefore := TDictionary<string, string>.Create;
  Map := TDictionary<string, Int64>.Create;
  J := nil;
  try
    for I := 1 to 5 do
    begin
      N := NewNote(FDeviceA, 'N' + IntToStr(I), 'content-' + IntToStr(I));
      SyncD(FDeviceA);
      Map.AddOrSetValue(N.Guid, N.Rev);
      RemoteBefore.AddOrSetValue(N.Guid + '.json', RemoteText(N.Guid + '.json'));
    end;
    Assert.AreEqual<Integer>(5, Length(RemoteNames), 'precondition: five remote notes');

    // Seed B's surviving sync-state (as if the local store was lost).
    WriteStateFile(FDeviceB, Map);
    J := TSyncJournal.Create(TPath.Combine(FDeviceB.BasePath, 'sync-journal.json'));
    LoadedMap := LoadSyncState(TPath.Combine(FDeviceB.BasePath, 'sync-state.json'), J);
    try
      Assert.AreEqual<Integer>(5, LoadedMap.Count, 'precondition: the seeded baseline must load');
    finally
      LoadedMap.Free;
    end;
    J.Free;
    J := nil;
    FCounter.ResetStats;

    // B syncs with an empty local store: nothing may be deleted remotely.
    SyncD(FDeviceB);

    Assert.AreEqual<Integer>(0, FCounter.WriteAttempts,
      'an empty local store must not write to the remote at all');
    Assert.AreEqual<Integer>(0, FCounter.RemoveCalls, 'nothing may be removed');
    Names := RemoteNames;
    Assert.AreEqual<Integer>(5, Length(Names), 'all remote objects must survive');
    for Name in Names do
      Assert.AreEqual<string>(RemoteBefore[TPath.GetFileName(Name)],
        RemoteText(TPath.GetFileName(Name)), 'remote objects must be byte-unchanged');
    Assert.AreEqual<Integer>(5, NoteCount(FDeviceB), 'B must pull all notes back');
    StateText := TFile.ReadAllText(TPath.Combine(FDeviceB.BasePath, 'sync-state.json'));
    Assert.IsTrue(Pos('"version":2', StateText) > 0, 'the baseline must stay healthy');
  finally
    J.Free;
    Map.Free;
    RemoteBefore.Free;
  end;
end;

procedure TSyncReconcileTestFixture.TestT8FailedRunKeepsStateIdentical;
var
  N: TNote;
  StatePath: string;
  Before: string;
begin
  N := NewNote(FDeviceA, 'T8', 'v1');
  SyncD(FDeviceA); // publishes rev 1 and writes the state file
  EditNote(FDeviceA, N, 'v2'); // a pending push for the next run

  StatePath := TPath.Combine(FDeviceA.BasePath, 'sync-state.json');
  Before := TFile.ReadAllText(StatePath);

  FCounter.RaiseOnNextWrite := True;
  Assert.IsFalse(FDeviceA.Engine.SyncNow, 'the run must report failure');
  Assert.AreEqual<string>(Before, TFile.ReadAllText(StatePath),
    'a failed run must leave sync-state.json byte-identical');

  // The next normal run reconciles.
  SyncD(FDeviceA);
  Assert.AreEqual<Int64>(2, StateRevOf(FDeviceA, N.Guid), 'the retried push must be recorded');
end;

procedure TSyncReconcileTestFixture.TestT9DeterministicCopyIdentity;
var
  GA: string;
  ExpectedCopy: string;
  WritesAfterStable: Integer;
begin
  MakeCommonNote(GA);

  EditNote(FDeviceA, FindNote(FDeviceA, GA), 'A-edit');
  EditNote(FDeviceB, FindNote(FDeviceB, GA), 'B-edit');

  // The copy push is suppressed once: the identity must still be deterministic
  // and the retry path must converge on the same single copy guid.
  ExpectedCopy := ExpectedCopyGuid(GA, DevTagA, 2);
  FCounter.FailNextWriteOnce(ExpectedCopy);

  SyncD(FDeviceA); // A publishes its edit
  SyncD(FDeviceB); // B resolves the conflict; its copy push fails once
  SyncD(FDeviceA); // A pulls the winner
  SyncD(FDeviceB); // B retries the copy push
  SyncD(FDeviceA); // A pulls the copy

  Assert.AreEqual<Integer>(1, CopiesFor(GA), 'no duplicate identities may exist');
  Assert.IsTrue(FindNote(FDeviceA, ExpectedCopy) <> nil,
    'the copy must carry the independent deterministic identity');
  Assert.IsTrue(FindNote(FDeviceB, ExpectedCopy) <> nil, 'the same identity on B');
  Assert.IsTrue(TFile.Exists(TPath.Combine(NotesDir, ExpectedCopy + '.json')),
    'the single copy object must exist on the remote');

  WritesAfterStable := FCounter.Writes;
  SyncD(FDeviceB);
  SyncD(FDeviceA);
  Assert.AreEqual<Integer>(WritesAfterStable, FCounter.Writes,
    'the system must be converged once the copy exists');
end;

procedure TSyncReconcileTestFixture.TestEmptyRemoteRepushesWithoutDeleting;
var
  N1, N2: TNote;
  Names: TArray<string>;
  Name: string;
begin
  N1 := NewNote(FDeviceA, 'R1', 'one');
  N2 := NewNote(FDeviceA, 'R2', 'two');
  SyncD(FDeviceA);
  Assert.AreEqual<Integer>(2, Length(RemoteNames), 'precondition: both notes published');

  // The remote store is emptied (outside the app): absence must never delete.
  for Name in RemoteNames do
    TFile.Delete(Name);
  FCounter.ResetStats;

  SyncD(FDeviceA);

  Assert.AreEqual<Integer>(2, NoteCount(FDeviceA), 'no local note may be deleted');
  Assert.AreEqual<Integer>(0, FCounter.RemoveCalls, 'nothing may be removed');
  Assert.AreEqual<Integer>(2, Length(RemoteNames), 'the notes must be republished');
  Assert.IsTrue(TFile.Exists(TPath.Combine(NotesDir, N1.Guid + '.json')), 'N1 republished');
  Assert.IsTrue(TFile.Exists(TPath.Combine(NotesDir, N2.Guid + '.json')), 'N2 republished');
end;

procedure TSyncReconcileTestFixture.TestDeletionThreshold25NoWarning;
begin
  Assert.IsFalse(RunDeletionScenario(25), '25 deletions must stay below the warning threshold');
end;

procedure TSyncReconcileTestFixture.TestDeletionThreshold26Warns;
begin
  Assert.IsTrue(RunDeletionScenario(26), '26 deletions must trigger the warn-only threshold note');
end;

// Shared helper for the deletion-threshold scenarios: N remote tombstones are
// applied to N unchanged local notes; returns True when the completion message
// carries the threshold warning.
function TSyncReconcileTestFixture.RunDeletionScenario(const ACount: Integer): Boolean;
var
  I: Integer;
  N: TNote;
  Map: TDictionary<string, Int64>;
begin
  Map := TDictionary<string, Int64>.Create;
  try
    for I := 1 to ACount do
    begin
      N := NewNote(FDeviceA, 'D' + IntToStr(I), 'body-' + IntToStr(I));
      Map.AddOrSetValue(N.Guid, 1);
      WriteTextAtomic(TPath.Combine(NotesDir, N.Guid + '.json'),
        BuildTombstonePayload(N.Guid, 2, EncodeDate(2026, 9, 28) + EncodeTime(10, 0, 0, 0)));
    end;
    WriteStateFile(FDeviceA, Map);
    FCounter.ResetStats;

    SyncD(FDeviceA);

    Assert.AreEqual<Integer>(0, NoteCount(FDeviceA), 'all deletions must be applied');
    Result := Pos('threshold', LowerCase(FLastCompleteMsg)) > 0;
  finally
    Map.Free;
  end;
end;

// Reads the recorded baseline rev for a guid from the device's sync-state.
function TSyncReconcileTestFixture.StateRevOf(const AD: TTestDevice; const AGuid: string): Int64;
var
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
begin
  Result := -1;
  J := TSyncJournal.Create(TPath.Combine(AD.BasePath, 'sync-journal.json'));
  try
    Map := LoadSyncState(TPath.Combine(AD.BasePath, 'sync-state.json'), J);
    try
      Map.TryGetValue(AGuid, Result);
    finally
      Map.Free;
    end;
  finally
    J.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncReconcileTestFixture);

end.
