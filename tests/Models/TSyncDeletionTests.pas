unit TSyncDeletionTests;

// Phase 7G/WP2: end-to-end tests for tombstone creation through the real
// deletion pathway - TNoteApplication (sandboxed) wires
// TNoteManager.DeleteNote -> OnNoteDeleted -> journal. Every profile is a temp
// sandbox; nothing touches the live %APPDATA%\StickyNotes.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  FireDAC.Comp.Client, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef, FireDAC.Stan.ExprFuncs,
  FireDAC.Phys.SQLiteWrapper.Stat,
  DUnitX.TestFramework,
  uNote, uEnums, uSettings, uNoteApplication, uSyncJournal;

type
  [TestFixture]
  TSyncDeletionTestFixture = class
  private
    FBase: string;
    FProfile: string;
    FRemote: string;
    FApp: TNoteApplication;
    function JournalPath: string;
    procedure WriteSyncSettings;
    function LoadJournal: TSyncJournal; // caller frees
    function TryGetTombstone(const AGuid: string; out ATombstone: TSyncTombstone): Boolean;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDeleteCreatesTombstone;
    [Test]
    procedure TestDeleteFailureDoesNotCreateTombstone;
    [Test]
    procedure TestDuplicateDeletionKeepsSingleTombstone;
  end;

implementation

var
  GTestSeq: Integer = 0;

// Test seam: abort every future DELETE on the notes table at the SQLite level,
// so TNoteManager.DeleteNote hits a genuine storage failure (the app performs
// its delete on the same database, on its own connection).
function FailNoteDeletes(const AProfileDir: string): Boolean;
var
  Conn: TFDConnection;
begin
  Result := False;
  Conn := TFDConnection.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := TPath.Combine(AProfileDir, 'vnotes.db');
    Conn.Params.Values['OpenMode'] := 'ReadWrite';
    Conn.Params.Values['LockingMode'] := 'Normal';
    Conn.Params.Values['ForeignKeys'] := 'On';
    Conn.Params.Values['Pooled'] := 'False';
    Conn.Connected := True;
    try
      Conn.ExecSQL('CREATE TRIGGER wp2_fail_delete BEFORE DELETE ON notes ' +
        'BEGIN SELECT RAISE(ABORT, ''wp2 injected delete failure''); END');
      Result := True;
    finally
      Conn.Connected := False;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TSyncDeletionTestFixture.SetUp;
begin
  Inc(GTestSeq);
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Wp2DelTest_' + IntToStr(TThread.GetTickCount) + '_' + IntToStr(GTestSeq));
  FProfile := TPath.Combine(FBase, 'deviceA');
  FRemote := TPath.Combine(FBase, 'remote');
  ForceDirectories(FProfile);
  ForceDirectories(FRemote);
  WriteSyncSettings;
  FApp := TNoteApplication.Create(0, FProfile);
end;

procedure TSyncDeletionTestFixture.TearDown;
begin
  FreeAndNil(FApp);
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TSyncDeletionTestFixture.WriteSyncSettings;
var
  S: TSettings;
begin
  S := TSettings.Create;
  try
    S.SyncEnabled := True;
    S.SyncBackendType := 'folder';
    S.SyncFolder := FRemote;
    S.SyncWebDavUrl := '';
    S.SyncIntervalMinutes := 15;
    S.SaveToFile(TPath.Combine(FProfile, 'settings.ini'));
  finally
    S.Free;
  end;
end;

function TSyncDeletionTestFixture.JournalPath: string;
begin
  Result := TPath.Combine(FProfile, 'sync-journal.json');
end;

function TSyncDeletionTestFixture.LoadJournal: TSyncJournal;
begin
  Result := TSyncJournal.Create(JournalPath);
  Result.Load;
end;

function TSyncDeletionTestFixture.TryGetTombstone(const AGuid: string;
  out ATombstone: TSyncTombstone): Boolean;
var
  J: TSyncJournal;
begin
  J := LoadJournal;
  try
    Result := J.TryGet(AGuid, ATombstone);
  finally
    J.Free;
  end;
end;

procedure TSyncDeletionTestFixture.TestDeleteCreatesTombstone;
var
  N: TNote;
  Guid: string;
  RevAtDelete: Int64;
  T: TSyncTombstone;
  Root: TJSONValue;
begin
  N := FApp.NoteManager.CreateNote('Doomed', 'body', ncYellow, 10, 10, 300, 200, False);
  N.Content := 'edited';
  FApp.NoteManager.SaveNote(N); // revision 2 - the tombstone must record the real rev
  Guid := N.Guid;
  RevAtDelete := N.Rev;
  Assert.IsTrue(Guid <> '', 'the note must have a guid before deletion');
  Assert.AreEqual<Int64>(2, RevAtDelete, 'precondition: the note was saved once');

  Assert.IsTrue(FApp.NoteManager.DeleteNote(N.ID), 'the deletion must succeed');
  Assert.AreEqual<Integer>(0, FApp.NoteManager.NoteCount, 'the note must be gone');

  Assert.IsTrue(TryGetTombstone(Guid, T), 'the deletion must be recorded as a tombstone');
  Assert.AreEqual<string>(Guid, T.Guid, 'the tombstone guid must match the deleted note');
  Assert.AreEqual<Int64>(RevAtDelete, T.Rev, 'the tombstone must preserve the deleted revision');
  Assert.IsTrue(T.DeletedAt > 0, 'DeletedAt must be set');
  Assert.IsTrue(Abs(Now - T.DeletedAt) < 0.01, 'DeletedAt must be the deletion moment');

  // The on-disk shape is the approved design format (S4.2): version + deletions.
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(JournalPath));
  try
    Assert.IsTrue(Root is TJSONObject, 'the journal must be a JSON object');
    Assert.AreEqual<Integer>(1, ((Root as TJSONObject).GetValue('version') as TJSONNumber).AsInt);
    Assert.IsNotNull((Root as TJSONObject).GetValue('deletions') as TJSONObject,
      'the journal must carry a deletions object');
  finally
    Root.Free;
  end;
end;

procedure TSyncDeletionTestFixture.TestDeleteFailureDoesNotCreateTombstone;
var
  N: TNote;
  Guid: string;
  T: TSyncTombstone;
begin
  N := FApp.NoteManager.CreateNote('Kept', 'body', ncYellow, 10, 10, 300, 200, False);
  Guid := N.Guid;
  Assert.IsTrue(Guid <> '', 'the note must have a guid');

  // Make the actual storage-level delete fail: a SQLite trigger aborts every
  // DELETE on the notes table, so the manager's delete hits a real error.
  Assert.IsTrue(FailNoteDeletes(FProfile), 'the failure injection must succeed');

  Assert.IsFalse(FApp.NoteManager.DeleteNote(N.ID), 'the deletion must fail');
  Assert.AreEqual<Integer>(1, FApp.NoteManager.NoteCount, 'the note must remain');
  Assert.IsFalse(TryGetTombstone(Guid, T), 'a failed deletion must not create a tombstone');
  Assert.IsFalse(TFile.Exists(JournalPath), 'a failed deletion must not even create a journal file');
end;

procedure TSyncDeletionTestFixture.TestDuplicateDeletionKeepsSingleTombstone;
var
  N: TNote;
  Guid: string;
  T: TSyncTombstone;
  J: TSyncJournal;
  JournalText: string;
begin
  N := FApp.NoteManager.CreateNote('Once', 'body', ncYellow, 10, 10, 300, 200, False);
  FApp.NoteManager.SaveNote(N);
  Guid := N.Guid;
  Assert.IsTrue(FApp.NoteManager.DeleteNote(N.ID), 'the first deletion must succeed');

  J := LoadJournal;
  try
    Assert.AreEqual<Integer>(1, J.Count, 'exactly one tombstone may exist');
    Assert.IsTrue(J.TryGet(Guid, T));
    Assert.AreEqual<Int64>(2, T.Rev, 'the recorded revision must be deterministic');
  finally
    J.Free;
  end;

  // A repeated deletion attempt through the same lifecycle finds no note and
  // must not touch the journal at all.
  JournalText := TFile.ReadAllText(JournalPath);
  Assert.IsFalse(FApp.NoteManager.DeleteNote(N.ID), 'a repeated deletion attempt must be a no-op');
  Assert.AreEqual<string>(JournalText, TFile.ReadAllText(JournalPath),
    'a repeated deletion attempt must not rewrite the journal');
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncDeletionTestFixture);

end.
