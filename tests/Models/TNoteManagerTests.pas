unit TNoteManagerTests;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DUnitX.TestFramework,
  uNote, uEnums, uStorage, uJsonStorage, uNoteManager;

type
  [TestFixture]
  TNoteManagerTestFixture = class
  private
    FTempDir: string;
    FManager: TNoteManager;
    FCreatedCount: Integer;
    FDeletedCount: Integer;
    FLastCreated: TNote;
    procedure HandleNoteCreated(const ANote: TNote);
    procedure HandleNoteDeleted(const ANote: TNote);
    function NewManager: TNoteManager;
  public
    [SetUp]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCreateNoteAddsNote;
    [Test]
    procedure TestCreateNoteFiresOnNoteCreatedOnce;
    [Test]
    procedure TestEventReceivesSameObjectAsReturnValue;
    [Test]
    procedure TestMultipleCreatesFireOnceEach;
    [Test]
    procedure TestPreEventInitialization;
    [Test]
    procedure TestThreeArgCreateKeepsDefaults;
    [Test]
    procedure TestFindByID;
    [Test]
    procedure TestFindByIndex;
    [Test]
    procedure TestFindByIDUnknownReturnsNil;
    [Test]
    procedure TestDeleteNoteFiresOnNoteDeletedOnce;
    [Test]
    procedure TestDeleteUnknownNoteReturnsFalse;
    [Test]
    procedure TestAddNoteFiresOnNoteCreatedOnce;
    [Test]
    procedure TestAddDuplicateNoteRejected;
    [Test]
    procedure TestSaveNoteRefusesNoteNotOwnedByManager;
    [Test]
    procedure TestDeleteNoteLeavesNoStorageFile;
    [Test]
    procedure TestManagerImplementsINoteManager;
    [Test]
    procedure TestInterfaceReferenceDoesNotOwnManager;
  end;

implementation

uses
  System.IOUtils;

procedure TNoteManagerTestFixture.Setup;
begin
  FCreatedCount := 0;
  FDeletedCount := 0;
  FLastCreated := nil;
  FManager := NewManager;
end;

procedure TNoteManagerTestFixture.TearDown;
begin
  FManager.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TNoteManagerTestFixture.NewManager: TNoteManager;
var
  Storage: TJsonStorage;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_ManagerTest_' + TGUID.NewGuid.ToString);
  Storage := TJsonStorage.Create(FTempDir);
  Result := TNoteManager.Create(Storage);
  Result.OnNoteCreated := HandleNoteCreated;
  Result.OnNoteDeleted := HandleNoteDeleted;
  Result.Initialize;
end;

procedure TNoteManagerTestFixture.HandleNoteCreated(const ANote: TNote);
begin
  Inc(FCreatedCount);
  FLastCreated := ANote;
end;

procedure TNoteManagerTestFixture.HandleNoteDeleted(const ANote: TNote);
begin
  Inc(FDeletedCount);
end;

procedure TNoteManagerTestFixture.TestCreateNoteAddsNote;
var
  Note: TNote;
begin
  Note := FManager.CreateNote('T', 'C', ncYellow);
  Assert.IsNotNull(Note);
  Assert.AreEqual(1, FManager.NoteCount, 'NoteCount should be 1 after CreateNote');
end;

procedure TNoteManagerTestFixture.TestCreateNoteFiresOnNoteCreatedOnce;
begin
  FManager.CreateNote('T', 'C', ncYellow);
  Assert.AreEqual(1, FCreatedCount, 'OnNoteCreated must fire exactly once');
end;

procedure TNoteManagerTestFixture.TestEventReceivesSameObjectAsReturnValue;
var
  Note: TNote;
begin
  Note := FManager.CreateNote('T', 'C', ncYellow);
  Assert.AreSame(Note, FLastCreated,
    'OnNoteCreated must receive the same object CreateNote returned');
end;

procedure TNoteManagerTestFixture.TestMultipleCreatesFireOnceEach;
var
  I: Integer;
begin
  for I := 1 to 5 do
    FManager.CreateNote('T' + IntToStr(I), 'C', ncYellow);
  Assert.AreEqual(5, FCreatedCount, 'One OnNoteCreated per CreateNote call');
  Assert.AreEqual(5, FManager.NoteCount, 'NoteCount after five creates');
end;

procedure TNoteManagerTestFixture.TestPreEventInitialization;
var
  Note: TNote;
begin
  // Phase 4E: the note must be fully initialized BEFORE OnNoteCreated fires
  // (the event is the single window-creation path).
  Note := FManager.CreateNote('T', 'C', ncBlue, 555, 444, 400, 300, True);
  Assert.AreEqual(555, Note.Left, 'Left must be set before the event');
  Assert.AreEqual(444, Note.Top, 'Top must be set before the event');
  Assert.AreEqual(400, Note.Width, 'Width must be set before the event');
  Assert.AreEqual(300, Note.Height, 'Height must be set before the event');
  Assert.IsTrue(Note.AlwaysOnTop, 'AlwaysOnTop must be set before the event');
  Assert.AreSame(Note, FLastCreated, 'Event still receives the created note');
end;

procedure TNoteManagerTestFixture.TestThreeArgCreateKeepsDefaults;
var
  Note: TNote;
begin
  // Existing 3-argument callers (note context: duplicate / new note menu)
  // must keep the historical TNote defaults.
  Note := FManager.CreateNote('T', 'C', ncGreen);
  Assert.AreEqual(100, Note.Left, 'Default Left');
  Assert.AreEqual(100, Note.Top, 'Default Top');
  Assert.AreEqual(300, Note.Width, 'Default Width');
  Assert.AreEqual(250, Note.Height, 'Default Height');
  Assert.IsFalse(Note.AlwaysOnTop, 'Default AlwaysOnTop');
end;

procedure TNoteManagerTestFixture.TestFindByID;
var
  Note: TNote;
begin
  Note := FManager.CreateNote('T', 'C', ncYellow);
  Assert.AreSame(Note, FManager.FindByID(Note.ID), 'FindByID returns the instance');
end;

procedure TNoteManagerTestFixture.TestFindByIndex;
var
  First, Second: TNote;
begin
  First := FManager.CreateNote('A', 'C', ncYellow);
  Second := FManager.CreateNote('B', 'C', ncYellow);
  Assert.AreSame(First, FManager.FindByIndex(0), 'Index 0 is the first note');
  Assert.AreSame(Second, FManager.FindByIndex(1), 'Index 1 is the second note');
end;

procedure TNoteManagerTestFixture.TestFindByIDUnknownReturnsNil;
begin
  Assert.IsNull(FManager.FindByID(999999), 'Unknown ID must return nil');
end;

procedure TNoteManagerTestFixture.TestDeleteNoteFiresOnNoteDeletedOnce;
var
  Note: TNote;
begin
  Note := FManager.CreateNote('T', 'C', ncYellow);
  Assert.IsTrue(FManager.DeleteNote(Note.ID), 'DeleteNote should succeed');
  Assert.AreEqual(1, FDeletedCount, 'OnNoteDeleted fires exactly once');
  Assert.AreEqual(0, FManager.NoteCount, 'Note removed from the manager');
  Assert.IsNull(FManager.FindByID(Note.ID), 'Deleted note is gone');
end;

procedure TNoteManagerTestFixture.TestDeleteUnknownNoteReturnsFalse;
begin
  Assert.IsFalse(FManager.DeleteNote(424242), 'Deleting an unknown ID returns False');
  Assert.AreEqual(0, FDeletedCount, 'No event for an unknown ID');
end;

procedure TNoteManagerTestFixture.TestAddNoteFiresOnNoteCreatedOnce;
var
  Note: TNote;
begin
  Note := TNote.Create(500, 'Imported', 'C', ncYellow);
  Assert.IsTrue(FManager.AddNote(Note), 'AddNote should succeed');
  Assert.AreEqual(1, FCreatedCount, 'AddNote fires OnNoteCreated once');
  Assert.AreSame(Note, FLastCreated, 'Event receives the added instance');
end;

procedure TNoteManagerTestFixture.TestAddDuplicateNoteRejected;
var
  Note: TNote;
begin
  Note := TNote.Create(501, 'Imported', 'C', ncYellow);
  Assert.IsTrue(FManager.AddNote(Note), 'First AddNote succeeds');
  Assert.IsFalse(FManager.AddNote(Note), 'Re-adding the same ID is rejected');
  Assert.AreEqual(1, FCreatedCount, 'No second OnNoteCreated for a duplicate');
  Assert.AreEqual(1, FManager.NoteCount, 'Note count unchanged by the rejection');
end;

procedure TNoteManagerTestFixture.TestSaveNoteRefusesNoteNotOwnedByManager;
var
  Note: TNote;
begin
  // Regression guard for note resurrection: SaveNote only persists notes
  // the manager owns. The delete flow relies on this - a closing note
  // window saves its (already deleted) note during FormClose, and without
  // the guard the note would be written straight back into storage.
  Note := TNote.Create(888, 'Foreign Note', 'C', ncYellow);
  try
    FManager.SaveNote(Note);
    Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(
      TPath.Combine(FTempDir, 'notes'), '*.json'))),
      'SaveNote must not persist a note the manager does not own');
  finally
    Note.Free;
  end;
end;

procedure TNoteManagerTestFixture.TestDeleteNoteLeavesNoStorageFile;
var
  Note: TNote;
begin
  Note := FManager.CreateNote('T', 'C', ncYellow);
  Assert.IsTrue(FManager.DeleteNote(Note.ID), 'DeleteNote should succeed');
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(
    TPath.Combine(FTempDir, 'notes'), '*.json'))),
    'Deleted note must not remain in storage');
end;

procedure TNoteManagerTestFixture.TestManagerImplementsINoteManager;
var
  Ref: INoteManager;
begin
  Ref := FManager;
  Assert.IsNotNull(Ref, 'TNoteManager must be assignable to INoteManager');
  Assert.AreEqual<Integer>(0, Ref.NoteCount);
end;

procedure TNoteManagerTestFixture.TestInterfaceReferenceDoesNotOwnManager;
var
  Ref: INoteManager;
begin
  Ref := FManager;
  Ref.CreateNote('t', 'c', ncYellow, 10, 20, 300, 200, False);
  Assert.AreEqual<Integer>(1, FManager.NoteCount,
    'creating via the interface must affect the owned instance');

  Ref := nil; // releasing the interface reference must NOT free the manager
  Assert.IsNotNull(FManager,
    'the manager must survive interface release (lifetime is owned explicitly)');
  Assert.AreEqual<Integer>(1, FManager.NoteCount,
    'the manager must remain usable after its interface reference is released');
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteManagerTestFixture);

end.
