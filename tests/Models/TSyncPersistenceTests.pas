unit TSyncPersistenceTests;

// Phase 7G/WP2: persistence tests for the tombstone journal (sync-journal.json)
// and the version-2 sync state (sync-state.json), including the v1 -> v2
// migration. All files live in temp sandboxes; nothing touches the live
// %APPDATA%\StickyNotes.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.DateUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  uSyncJournal, uSyncState, uIso8601;

type
  [TestFixture]
  TSyncPersistenceTestFixture = class
  private
    FBase: string;
    FStatePath: string;
    FJournalPath: string;
    function ReadText(const APath: string): string;
    procedure WriteText(const APath, AText: string);
    function NewJournal: TSyncJournal;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTombstoneSurvivesReload;
    [Test]
    procedure TestTombstoneClear;
    [Test]
    procedure TestMultipleTombstones;
    [Test]
    procedure TestStateV2RoundTrip;
    [Test]
    procedure TestV1Migration;
    [Test]
    procedure TestMigrationIdempotence;
    [Test]
    procedure TestCorruptStateIsPreserved;
    [Test]
    procedure TestCorruptJournalIsPreserved;
    [Test]
    procedure TestLoadSavePreservesExistingEntries;
    [Test]
    procedure TestTombstoneRetentionMetadata;
  end;

implementation

var
  GTestSeq: Integer = 0;

const
  GuidA = 'aaaaaaaa-1111-4222-8333-444444444444';
  GuidB = 'bbbbbbbb-1111-4222-8333-444444444444';
  GuidX = 'cccccccc-1111-4222-8333-444444444444'; // deleted, but never in synced

procedure TSyncPersistenceTestFixture.SetUp;
begin
  Inc(GTestSeq);
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Wp2Test_' + IntToStr(TThread.GetTickCount) + '_' + IntToStr(GTestSeq));
  ForceDirectories(FBase);
  FStatePath := TPath.Combine(FBase, 'sync-state.json');
  FJournalPath := TPath.Combine(FBase, 'sync-journal.json');
end;

procedure TSyncPersistenceTestFixture.TearDown;
begin
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

function TSyncPersistenceTestFixture.ReadText(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath);
end;

procedure TSyncPersistenceTestFixture.WriteText(const APath, AText: string);
begin
  TFile.WriteAllText(APath, AText, TEncoding.UTF8);
end;

function TSyncPersistenceTestFixture.NewJournal: TSyncJournal;
begin
  Result := TSyncJournal.Create(FJournalPath);
end;

procedure TSyncPersistenceTestFixture.TestTombstoneSurvivesReload;
var
  J: TSyncJournal;
  T: TSyncTombstone;
  When: TDateTime;
  Root: TJSONValue;
begin
  When := EncodeDate(2026, 9, 28) + EncodeTime(12, 34, 56, 789);
  J := NewJournal;
  try
    J.Add(GuidA, 7, When);
    J.Save;
  finally
    J.Free;
  end;

  // The stored shape is the approved design format (S4.2).
  Root := TJSONObject.ParseJSONValue(ReadText(FJournalPath));
  try
    Assert.IsTrue(Root is TJSONObject, 'the journal must be a JSON object');
    Assert.AreEqual<Integer>(1, ((Root as TJSONObject).GetValue('version') as TJSONNumber).AsInt,
      'journal version must be 1');
    Assert.IsNotNull((Root as TJSONObject).GetValue('deletions') as TJSONObject,
      'the journal must carry a deletions object');
  finally
    Root.Free;
  end;

  J := NewJournal;
  try
    J.Load;
    Assert.IsTrue(J.TryGet(GuidA, T), 'the tombstone must survive a reload');
    Assert.AreEqual<string>(GuidA, T.Guid);
    Assert.AreEqual<Int64>(7, T.Rev);
    Assert.IsTrue(T.DeletedAt > 0, 'DeletedAt must round-trip');
    Assert.AreEqual<string>(DateTimeToStoredISO8601(When), DateTimeToStoredISO8601(T.DeletedAt),
      'the timestamp must round-trip at stored precision');
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestTombstoneClear;
var
  J: TSyncJournal;
  T: TSyncTombstone;
begin
  J := NewJournal;
  try
    J.Add(GuidA, 3, Now);
    J.Save;
  finally
    J.Free;
  end;

  J := NewJournal;
  try
    J.Load;
    Assert.IsTrue(J.TryGet(GuidA, T), 'precondition: the tombstone exists');
    J.Remove(GuidA);
    J.Save;
  finally
    J.Free;
  end;

  J := NewJournal;
  try
    J.Load;
    Assert.IsFalse(J.TryGet(GuidA, T), 'a cleared tombstone must not come back');
    Assert.AreEqual<Integer>(0, J.Count);
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestMultipleTombstones;
var
  J: TSyncJournal;
  T: TSyncTombstone;
  All: TArray<TSyncTombstone>;
begin
  J := NewJournal;
  try
    J.Add(GuidA, 3, Now);
    J.Add(GuidB, 9, Now);
    J.Add(GuidX, 12, Now);
    J.Save;
  finally
    J.Free;
  end;

  J := NewJournal;
  try
    J.Load;
    Assert.AreEqual<Integer>(3, J.Count);
    Assert.IsTrue(J.TryGet(GuidA, T));
    Assert.AreEqual<Int64>(3, T.Rev);
    Assert.IsTrue(J.TryGet(GuidB, T));
    Assert.AreEqual<Int64>(9, T.Rev);
    Assert.IsTrue(J.TryGet(GuidX, T));
    Assert.AreEqual<Int64>(12, T.Rev);
    All := J.Enumerate;
    Assert.AreEqual<Integer>(3, Length(All), 'all tombstones must be enumerable');
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestStateV2RoundTrip;
var
  J: TSyncJournal;
  Map, Loaded: TDictionary<string, Int64>;
  Rev: Int64;
  Root: TJSONValue;
  Before, After: string;
begin
  J := NewJournal;
  try
    Map := TDictionary<string, Int64>.Create;
    try
      Map.AddOrSetValue(GuidA, 12);
      Map.AddOrSetValue(GuidB, 19);
      SaveSyncState(FStatePath, Map);
    finally
      Map.Free;
    end;

    // Stored shape: v2, no deleted list.
    Root := TJSONObject.ParseJSONValue(ReadText(FStatePath));
    try
      Assert.AreEqual<Integer>(2, ((Root as TJSONObject).GetValue('version') as TJSONNumber).AsInt,
        'state version must be 2');
      Assert.IsNull((Root as TJSONObject).GetValue('deleted'),
        'v2 must not carry a deleted list');
    finally
      Root.Free;
    end;

    Before := ReadText(FStatePath);
    Loaded := LoadSyncState(FStatePath, J);
    try
      Assert.AreEqual<Integer>(2, Loaded.Count);
      Assert.IsTrue(Loaded.TryGetValue(GuidA, Rev));
      Assert.AreEqual<Int64>(12, Rev, 'exact values must round-trip');
      Assert.IsTrue(Loaded.TryGetValue(GuidB, Rev));
      Assert.AreEqual<Int64>(19, Rev, 'exact values must round-trip');
    finally
      Loaded.Free;
    end;
    After := ReadText(FStatePath);
    Assert.AreEqual<string>(Before, After,
      'loading a valid v2 file must not rewrite it');
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestV1Migration;
const
  V1 = '{"synced":{"' + GuidA + '":12,"' + GuidB + '":7},' +
       '"deleted":["' + GuidA + '","' + GuidX + '"]}';
var
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
  T: TSyncTombstone;
  Rev: Int64;
  Root, SyncedObj: TJSONObject;
begin
  WriteText(FStatePath, V1);
  J := NewJournal;
  try
    Map := LoadSyncState(FStatePath, J);
    try
      Assert.AreEqual<Integer>(2, Map.Count, 'synchronized revisions must be preserved');
      Assert.IsTrue(Map.TryGetValue(GuidA, Rev));
      Assert.AreEqual<Int64>(12, Rev);
      Assert.IsTrue(Map.TryGetValue(GuidB, Rev));
      Assert.AreEqual<Int64>(7, Rev);

      // The old deleted list became tombstones - nothing was lost.
      Assert.IsTrue(J.TryGet(GuidA, T), 'deleted entry with a synced rev must become a tombstone');
      Assert.AreEqual<Int64>(12, T.Rev, 'the tombstone rev comes from the last synchronized rev');
      Assert.IsTrue(J.TryGet(GuidX, T), 'deleted entry without a synced rev must still be kept');
      Assert.AreEqual<Int64>(0, T.Rev, 'an unknown rev migrates as 0 (unknown)');
      Assert.AreEqual<Integer>(2, J.Count);
    finally
      Map.Free;
    end;
  finally
    J.Free;
  end;

  // The migrated state is v2, has no deleted list, and keeps the synced rev
  // for deleted guids (design S11: deletions are not removals).
  Root := TJSONObject.ParseJSONValue(ReadText(FStatePath)) as TJSONObject;
  try
    Assert.AreEqual<Integer>(2, (Root.GetValue('version') as TJSONNumber).AsInt);
    Assert.IsNull(Root.GetValue('deleted'), 'the deleted list must be gone after migration');
    SyncedObj := Root.GetValue('synced') as TJSONObject;
    Assert.IsNotNull(SyncedObj);
    Assert.IsNotNull(SyncedObj.GetValue(GuidA),
      'a deleted guid must keep its synced revision');
  finally
    Root.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestMigrationIdempotence;
const
  V1 = '{"synced":{"' + GuidA + '":12,"' + GuidB + '":7},' +
       '"deleted":["' + GuidA + '","' + GuidX + '"]}';
var
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
  StateText, JournalText: string;
  Rev: Int64;
begin
  WriteText(FStatePath, V1);
  J := NewJournal;
  try
    Map := LoadSyncState(FStatePath, J); // first migration
    Map.Free;
  finally
    J.Free;
  end;
  StateText := ReadText(FStatePath);
  JournalText := ReadText(FJournalPath);

  J := NewJournal;
  try
    Map := LoadSyncState(FStatePath, J); // second load: already v2
    try
      Assert.AreEqual<Integer>(2, Map.Count);
      Assert.IsTrue(Map.TryGetValue(GuidA, Rev));
      Assert.AreEqual<Int64>(12, Rev, 'synchronized revisions must stay unchanged');
      Assert.AreEqual<Integer>(2, J.Count, 'no duplicate tombstones may be created');
    finally
      Map.Free;
    end;
  finally
    J.Free;
  end;

  Assert.AreEqual<string>(StateText, ReadText(FStatePath), 'the v2 state must be stable');
  Assert.AreEqual<string>(JournalText, ReadText(FJournalPath), 'the journal must be stable');
end;

procedure TSyncPersistenceTestFixture.TestCorruptStateIsPreserved;
var
  J: TSyncJournal;
  Map: TDictionary<string, Int64>;
  Before: string;
  Raised: Boolean;
begin
  WriteText(FStatePath, '{ this is not valid JSON');
  Before := ReadText(FStatePath);
  J := NewJournal;
  try
    Raised := False;
    Map := nil;
    try
      Map := LoadSyncState(FStatePath, J);
      Map.Free;
      Map := nil;
    except
      on E: ESyncStateError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'a corrupt state file must raise, not reset silently');
    Assert.AreEqual<string>(Before, ReadText(FStatePath), 'the original file must be preserved');
    Assert.IsFalse(TFile.Exists(FJournalPath), 'no journal may be written for an unreadable state');
  finally
    J.Free;
  end;

  // An unsupported version fails the same way.
  WriteText(FStatePath, '{"version":99,"synced":{}}');
  J := NewJournal;
  try
    Raised := False;
    Map := nil;
    try
      Map := LoadSyncState(FStatePath, J);
      Map.Free;
      Map := nil;
    except
      on E: ESyncStateError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'an unsupported version must raise');
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestCorruptJournalIsPreserved;
var
  J: TSyncJournal;
  Before: string;
  Raised: Boolean;
begin
  WriteText(FJournalPath, 'not json at all');
  Before := ReadText(FJournalPath);
  J := NewJournal;
  try
    Raised := False;
    try
      J.Load;
    except
      on E: ESyncJournalError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'a corrupt journal must surface an error');

    // It must refuse every path that could overwrite the corrupt file.
    Raised := False;
    try
      J.Save;
    except
      on E: ESyncJournalError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'Save must refuse after a failed Load');

    Raised := False;
    try
      J.Add(GuidA, 1, Now);
    except
      on E: ESyncJournalError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'Add must refuse after a failed Load');

    Assert.AreEqual<string>(Before, ReadText(FJournalPath),
      'the corrupt original must have been left untouched');
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestLoadSavePreservesExistingEntries;
var
  J: TSyncJournal;
  Map, Loaded: TDictionary<string, Int64>;
  Rev: Int64;
  T: TSyncTombstone;
begin
  // Journal: unrelated entries survive a load + Add + Save cycle.
  J := NewJournal;
  try
    J.Add(GuidA, 3, Now);
    J.Add(GuidB, 9, Now);
    J.Save;
  finally
    J.Free;
  end;
  J := NewJournal;
  try
    J.Load;
    J.Add(GuidX, 12, Now);
    J.Save;
  finally
    J.Free;
  end;
  J := NewJournal;
  try
    J.Load;
    Assert.AreEqual<Integer>(3, J.Count, 'an unrelated save must not discard loaded entries');
    Assert.IsTrue(J.TryGet(GuidA, T));
    Assert.AreEqual<Int64>(3, T.Rev);
    Assert.IsTrue(J.TryGet(GuidB, T));
    Assert.AreEqual<Int64>(9, T.Rev);
    Assert.IsTrue(J.TryGet(GuidX, T));
  finally
    J.Free;
  end;

  // State: loading and re-saving must keep every entry.
  J := NewJournal;
  try
    Map := TDictionary<string, Int64>.Create;
    try
      Map.AddOrSetValue(GuidA, 12);
      Map.AddOrSetValue(GuidB, 19);
      SaveSyncState(FStatePath, Map);
    finally
      Map.Free;
    end;
    Loaded := LoadSyncState(FStatePath, J);
    try
      SaveSyncState(FStatePath, Loaded);
    finally
      Loaded.Free;
    end;
    Loaded := LoadSyncState(FStatePath, J);
    try
      Assert.AreEqual<Integer>(2, Loaded.Count, 'state entries must survive a load+save cycle');
      Assert.IsTrue(Loaded.TryGetValue(GuidA, Rev));
      Assert.AreEqual<Int64>(12, Rev);
      Assert.IsTrue(Loaded.TryGetValue(GuidB, Rev));
      Assert.AreEqual<Int64>(19, Rev);
    finally
      Loaded.Free;
    end;
  finally
    J.Free;
  end;
end;

procedure TSyncPersistenceTestFixture.TestTombstoneRetentionMetadata;
var
  T: TSyncTombstone;
  PointInTime: TDateTime;
begin
  PointInTime := EncodeDate(2026, 9, 28) + EncodeTime(15, 0, 0, 0);
  T.Guid := GuidA;
  T.Rev := 5;

  T.DeletedAt := PointInTime - 89;
  Assert.IsFalse(IsTombstoneExpired(T, PointInTime), '89 days: still within retention');
  T.DeletedAt := PointInTime - 91;
  Assert.IsTrue(IsTombstoneExpired(T, PointInTime), '91 days: past retention');
  T.DeletedAt := PointInTime - 90;
  Assert.IsTrue(IsTombstoneExpired(T, PointInTime), 'exactly 90 days: at the boundary');
  T.DeletedAt := 0;
  Assert.IsFalse(IsTombstoneExpired(T, PointInTime), 'an unknown deletion time never expires');

  // The window is parameterised for future GC policy work.
  T.DeletedAt := PointInTime - 45;
  Assert.IsTrue(IsTombstoneExpired(T, PointInTime, 30), 'a 30-day window must honour the override');
  Assert.IsFalse(IsTombstoneExpired(T, PointInTime, 60), 'a 60-day window must keep it');

  // Nothing above garbage-collects anything: the retention helper is a pure
  // calculation (GC is deliberately deferred, design S4.3).
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncPersistenceTestFixture);

end.
