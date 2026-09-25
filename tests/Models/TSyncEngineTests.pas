unit TSyncEngineTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.DateUtils,
  DUnitX.TestFramework,
  uNote, uEnums, uStorage, uJsonStorage, uNoteManager, uServiceInterfaces,
  uFolderSyncBackend, uSyncEngine;

type
  [TestFixture]
  TSyncEngineTestFixture = class
  private
    FBase: string;
    FLocalPath: string;
    FRemotePath: string;
    FStatePath: string;
    FStorage: INoteStorage;
    FManager: TNoteManager;
    FBackend: ISyncBackend;
    FEngine: TSyncEngine;
    function RemoteNoteFile(const AGuid: string): string;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPushLocalOnlyNote;
    [Test]
    procedure TestPullRemoteOnlyNote;
    [Test]
    procedure TestRemoteNewerRevisionWins;
    [Test]
    procedure TestLocalNewerRevisionWins;
    [Test]
    procedure TestConflictProducesExtraCopy;
    [Test]
    procedure TestLocalDeletionIsPropagatedAndNotResurrected;
  end;

implementation

function BuildPayload(const AGuid: string; ARev: Int64; const ATitle, AContent: string): string;
var
  N: TNote;
  J: TJSONObject;
begin
  N := TNote.Create(1, ATitle, AContent, ncYellow);
  try
    N.Guid := AGuid;
    N.Rev := ARev;
    N.DeviceId := 'remote-device-1234';
    N.CreatedAt := EncodeDate(2026, 9, 25) + EncodeTime(12, 0, 0, 0);
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

procedure WriteRemote(const ARoot, AGuid, APayload: string);
var
  Dir: string;
begin
  Dir := TPath.Combine(ARoot, 'notes');
  ForceDirectories(Dir);
  TFile.WriteAllText(TPath.Combine(Dir, AGuid + '.json'), APayload, TEncoding.UTF8);
end;

procedure TSyncEngineTestFixture.SetUp;
begin
  FBase := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SyncTest_' + IntToStr(TThread.GetTickCount));
  FLocalPath := TPath.Combine(FBase, 'local');
  FRemotePath := TPath.Combine(FBase, 'remote');
  FStatePath := TPath.Combine(FLocalPath, 'sync-state.json');
  ForceDirectories(FLocalPath);
  ForceDirectories(FRemotePath);

  FStorage := TJsonStorage.Create(FLocalPath);
  FManager := TNoteManager.Create(FStorage);
  FManager.Initialize;
  FBackend := TFolderSyncBackend.Create(FRemotePath);
  FEngine := TSyncEngine.Create(FManager, FBackend, FStatePath);
end;

procedure TSyncEngineTestFixture.TearDown;
begin
  FEngine.Free;   // releases its ISyncBackend reference
  FManager.Free;  // releases its INoteStorage reference
  FBackend := nil;
  FStorage := nil;
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

function TSyncEngineTestFixture.RemoteNoteFile(const AGuid: string): string;
begin
  Result := TPath.Combine(TPath.Combine(FRemotePath, 'notes'), AGuid + '.json');
end;

procedure TSyncEngineTestFixture.TestPushLocalOnlyNote;
var
  N: TNote;
begin
  N := FManager.CreateNote('Local', 'Body', ncYellow, 10, 10, 300, 200, False);
  Assert.IsTrue(FEngine.SyncNow, 'sync should succeed');
  Assert.IsTrue(N.Guid <> '', 'local note should have a guid after sync');
  Assert.IsTrue(TFile.Exists(RemoteNoteFile(N.Guid)), 'local note should be pushed to remote');
end;

procedure TSyncEngineTestFixture.TestPullRemoteOnlyNote;
const
  Guid = 'aaaaaaaa-1111-2222-3333-444444444444';
begin
  WriteRemote(FRemotePath, Guid, BuildPayload(Guid, 3, 'From remote', 'Remote body'));
  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Integer>(1, FManager.NoteCount, 'remote note should be pulled locally');
  Assert.AreEqual<string>('From remote', FManager.Notes[0].Title);
  Assert.AreEqual<string>(Guid, FManager.Notes[0].Guid);
end;

procedure TSyncEngineTestFixture.TestRemoteNewerRevisionWins;
var
  N: TNote;
begin
  N := FManager.CreateNote('Local', 'Local body', ncYellow, 10, 10, 300, 200, False);
  N.Guid := 'bbbbbbbb-1111-2222-3333-444444444444';
  N.Rev := 1;
  FManager.PersistNote(N);

  WriteRemote(FRemotePath, N.Guid, BuildPayload(N.Guid, 9, 'Remote', 'Remote wins'));
  Assert.IsTrue(FEngine.SyncNow);

  Assert.AreEqual<string>('Remote wins', FManager.Notes[0].Content,
    'the higher remote revision must win');
end;

procedure TSyncEngineTestFixture.TestLocalNewerRevisionWins;
var
  N: TNote;
  RemoteText: string;
begin
  N := FManager.CreateNote('Local', 'Local wins', ncYellow, 10, 10, 300, 200, False);
  N.Guid := 'cccccccc-1111-2222-3333-444444444444';
  N.Rev := 8;
  FManager.PersistNote(N);

  WriteRemote(FRemotePath, N.Guid, BuildPayload(N.Guid, 2, 'Remote', 'stale'));
  Assert.IsTrue(FEngine.SyncNow);

  RemoteText := TFile.ReadAllText(RemoteNoteFile(N.Guid));
  Assert.IsTrue(RemoteText.Contains('Local wins'),
    'the higher local revision must overwrite the remote');
end;

procedure TSyncEngineTestFixture.TestConflictProducesExtraCopy;
var
  N: TNote;
begin
  N := FManager.CreateNote('Local', 'Local version', ncYellow, 10, 10, 300, 200, False);
  N.Guid := 'dddddddd-1111-2222-3333-444444444444';
  N.Rev := 4;
  FManager.PersistNote(N);

  // Same guid, same rev, different content -> conflict.
  WriteRemote(FRemotePath, N.Guid, BuildPayload(N.Guid, 4, 'Remote', 'Remote version'));
  Assert.IsTrue(FEngine.SyncNow);

  Assert.AreEqual<Integer>(2, FManager.NoteCount,
    'a conflicting remote edit must be preserved as a conflict copy, not lost');
end;

procedure TSyncEngineTestFixture.TestLocalDeletionIsPropagatedAndNotResurrected;
var
  N: TNote;
  Guid: string;
begin
  N := FManager.CreateNote('Doomed', 'x', ncYellow, 10, 10, 300, 200, False);
  Assert.IsTrue(FEngine.SyncNow);
  Guid := N.Guid;
  Assert.IsTrue(TFile.Exists(RemoteNoteFile(Guid)), 'note should be on remote before delete');

  Assert.IsTrue(FManager.DeleteNote(N.ID), 'local delete should succeed');
  Assert.IsTrue(FEngine.SyncNow, 'second sync should succeed');
  Assert.IsFalse(TFile.Exists(RemoteNoteFile(Guid)), 'deletion must be propagated to remote');

  // A further sync must not resurrect the deleted note from the remote.
  Assert.IsTrue(FEngine.SyncNow);
  Assert.AreEqual<Integer>(0, FManager.NoteCount, 'deleted note must not be resurrected');
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncEngineTestFixture);

end.
