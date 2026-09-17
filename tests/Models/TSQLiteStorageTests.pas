unit TSQLiteStorageTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.DateUtils,
  DUnitX.TestFramework, uSQLiteStorage, uJsonStorage, uNote, uEnums, uILogger;

type
  [TestFixture]
  TSQLiteStorageTestFixture = class
  public
    [Test]
    procedure TestDatabaseCreation;
    [Test]
    procedure TestEmptyDatabaseReturnsZeroNotes;
    [Test]
    procedure TestSaveLoadNote;
    [Test]
    procedure TestSaveLoadAllScalarFields;
    [Test]
    procedure TestSaveLoadTagsAndOrder;
    [Test]
    procedure TestSaveLoadChecklistItemsOrderAndDoneState;
    [Test]
    procedure TestSaveLoadFavorite;
    [Test]
    procedure TestSaveLoadTimestamps;
    [Test]
    procedure TestSaveLoadPositionAndSize;
    [Test]
    procedure TestUpdateExistingNote;
    [Test]
    procedure TestDeleteNote;
    [Test]
    procedure TestDeleteNonexistentNoteBehavesSafely;
    [Test]
    procedure TestMultipleNotesAndNextID;
    [Test]
    procedure TestReopenDatabasePreservesPersistence;
    [Test]
    procedure TestJsonAndSQLiteSemanticEquivalence;
    [Test]
    procedure TestOuterTransactionCommit;
    [Test]
    procedure TestOuterTransactionRollback;
    [Test]
    procedure TestSaveNoteDoesNotRollbackOuterTransactionOnFailure;
  end;

implementation

procedure TSQLiteStorageTestFixture.TestDatabaseCreation;
var
  Storage: TSQLiteStorage;
  TempDir, DbFile: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_DbCreation_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    DbFile := TPath.Combine(TempDir, 'vnotes.db');
    Assert.IsTrue(TFile.Exists(DbFile), 'SQLite database file should exist after initialization');
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestEmptyDatabaseReturnsZeroNotes;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Empty_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(0, Notes.Count, 'Empty database should return zero notes');
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadNote;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_SaveLoad_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'SQLite Title', 'SQLite Content', ncGreen);
    try
      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should return True');
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count, 'Should load 1 note');
      Assert.AreEqual<Int64>(1, Notes[0].ID);
      Assert.AreEqual<string>('SQLite Title', Notes[0].Title);
      Assert.AreEqual<string>('SQLite Content', Notes[0].Content);
      Assert.AreEqual<TNoteColor>(ncGreen, Notes[0].Color);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadAllScalarFields;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Scalars_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(10, 'Full Note', 'Full Content', ncPurple);
    try
      Note.AlwaysOnTop := True;
      Note.Collapsed := True;
      Note.Locked := True;
      Note.Favorite := True;
      Note.Left := 150;
      Note.Top := 250;
      Note.Width := 400;
      Note.Height := 350;
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      Assert.AreEqual<Int64>(10, Notes[0].ID);
      Assert.AreEqual<string>('Full Note', Notes[0].Title);
      Assert.AreEqual<string>('Full Content', Notes[0].Content);
      Assert.AreEqual<TNoteColor>(ncPurple, Notes[0].Color);
      Assert.IsTrue(Notes[0].AlwaysOnTop);
      Assert.IsTrue(Notes[0].Collapsed);
      Assert.IsTrue(Notes[0].Locked);
      Assert.IsTrue(Notes[0].Favorite);
      Assert.AreEqual(150, Notes[0].Left);
      Assert.AreEqual(250, Notes[0].Top);
      Assert.AreEqual(400, Notes[0].Width);
      Assert.AreEqual(350, Notes[0].Height);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadTagsAndOrder;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Tags_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'Tags Note', 'Content', ncYellow);
    try
      Note.AddTag('alpha');
      Note.AddTag('beta');
      Note.AddTag('gamma');
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      Assert.AreEqual(3, Length(Notes[0].Tags));
      Assert.AreEqual('alpha', Notes[0].Tags[0]);
      Assert.AreEqual('beta', Notes[0].Tags[1]);
      Assert.AreEqual('gamma', Notes[0].Tags[2]);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadChecklistItemsOrderAndDoneState;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Checklist_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'Checklist Note', 'Content', ncYellow);
    try
      Note.AddChecklistItem('Task 1', False);
      Note.AddChecklistItem('Task 2', True);
      Note.AddChecklistItem('Task 3', False);
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      Assert.AreEqual(3, Length(Notes[0].ChecklistItems));

      Assert.AreEqual('Task 1', Notes[0].ChecklistItems[0].Text);
      Assert.IsFalse(Notes[0].ChecklistItems[0].Done);

      Assert.AreEqual('Task 2', Notes[0].ChecklistItems[1].Text);
      Assert.IsTrue(Notes[0].ChecklistItems[1].Done);

      Assert.AreEqual('Task 3', Notes[0].ChecklistItems[2].Text);
      Assert.IsFalse(Notes[0].ChecklistItems[2].Done);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadFavorite;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Favorite_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'Fav Note', 'Content', ncYellow);
    try
      Note.ToggleFavorite;
      Assert.IsTrue(Note.Favorite);
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      Assert.IsTrue(Notes[0].Favorite);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadTimestamps;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
  KnownCreated, KnownUpdated: TDateTime;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Timestamps_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    KnownCreated := EncodeDateTime(2026, 9, 1, 10, 0, 0, 0);
    KnownUpdated := EncodeDateTime(2026, 9, 6, 12, 0, 0, 0);
    Note := TNote.Create(1, 'Time Note', 'Content', ncYellow);
    try
      Note.CreatedAt := KnownCreated;
      Note.UpdatedAt := KnownUpdated;
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      // Tighten precision from 0.001 to 1E-7 for strict millisecond matching
      Assert.AreEqual(Double(KnownCreated), Double(Notes[0].CreatedAt), 1E-7);
      Assert.AreEqual(Double(KnownUpdated), Double(Notes[0].UpdatedAt), 1E-7);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveLoadPositionAndSize;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Pos_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'Pos Note', 'Content', ncYellow);
    try
      Note.Left := 320;
      Note.Top := 240;
      Note.Width := 500;
      Note.Height := 400;
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      Assert.AreEqual(320, Notes[0].Left);
      Assert.AreEqual(240, Notes[0].Top);
      Assert.AreEqual(500, Notes[0].Width);
      Assert.AreEqual(400, Notes[0].Height);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestUpdateExistingNote;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Update_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'Initial Title', 'Initial Content', ncYellow);
    try
      Note.AddTag('tag1');
      Note.AddChecklistItem('item1');
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    // Update the same note ID
    Note := TNote.Create(1, 'Updated Title', 'Updated Content', ncBlue);
    try
      Note.AddTag('tag2');
      Note.AddChecklistItem('item2_a');
      Note.AddChecklistItem('item2_b', True);
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count, 'Should still contain exactly 1 note');
      Assert.AreEqual<string>('Updated Title', Notes[0].Title);
      Assert.AreEqual<string>('Updated Content', Notes[0].Content);
      Assert.AreEqual<TNoteColor>(ncBlue, Notes[0].Color);

      Assert.AreEqual(1, Length(Notes[0].Tags));
      Assert.AreEqual('tag2', Notes[0].Tags[0]);

      Assert.AreEqual(2, Length(Notes[0].ChecklistItems));
      Assert.AreEqual('item2_a', Notes[0].ChecklistItems[0].Text);
      Assert.AreEqual('item2_b', Notes[0].ChecklistItems[1].Text);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestDeleteNote;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Delete_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(5, 'Delete Target', 'Content', ncPink);
    try
      Note.AddTag('delete_me');
      Note.AddChecklistItem('delete_item');
      Assert.IsTrue(Storage.SaveNote(Note));
    finally
      Note.Free;
    end;

    Assert.IsTrue(Storage.DeleteNote(5), 'DeleteNote should return True');

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(0, Notes.Count, 'Note count should be 0 after delete');
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestDeleteNonexistentNoteBehavesSafely;
var
  Storage: TSQLiteStorage;
  TempDir: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_DelNonExistent_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Assert.IsTrue(Storage.DeleteNote(99999), 'Deleting non-existent note should return True safely');
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestMultipleNotesAndNextID;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  N1, N2: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_MultiNextID_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Assert.AreEqual<Int64>(1, Storage.GetNextID);

    N1 := TNote.Create(1, 'First', '1', ncYellow);
    N2 := TNote.Create(2, 'Second', '2', ncGreen);
    try
      Storage.SaveNote(N1);
      Storage.SaveNote(N2);
    finally
      N1.Free;
      N2.Free;
    end;

    Assert.AreEqual<Int64>(3, Storage.GetNextID);

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(2, Notes.Count);
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestReopenDatabasePreservesPersistence;
var
  Storage1, Storage2: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_Reopen_' + IntToStr(TThread.GetTickCount));
  Storage1 := TSQLiteStorage.Create(TempDir);
  try
    Storage1.Initialize;
    Note := TNote.Create(100, 'Reopen Test', 'Reopen Content', ncOrange);
    try
      Note.AddTag('persistent');
      Note.AddChecklistItem('survives restart');
      Note.ToggleFavorite;
      Storage1.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    Storage1.Free;
  end;

  Storage2 := TSQLiteStorage.Create(TempDir);
  try
    Storage2.Initialize;
    Assert.AreEqual<Int64>(101, Storage2.GetNextID, 'GetNextID after reopen should be max ID + 1');

    Notes := Storage2.LoadAllNotes;
    try
      Assert.AreEqual(1, Notes.Count);
      Assert.AreEqual<Int64>(100, Notes[0].ID);
      Assert.AreEqual<string>('Reopen Test', Notes[0].Title);
      Assert.AreEqual<string>('Reopen Content', Notes[0].Content);
      Assert.IsTrue(Notes[0].Favorite);
      Assert.AreEqual(1, Length(Notes[0].Tags));
      Assert.AreEqual('persistent', Notes[0].Tags[0]);
      Assert.AreEqual(1, Length(Notes[0].ChecklistItems));
      Assert.AreEqual('survives restart', Notes[0].ChecklistItems[0].Text);
    finally
      Notes.Free;
    end;
  finally
    Storage2.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestJsonAndSQLiteSemanticEquivalence;
var
  SqlStorage: TSQLiteStorage;
  JsonStorage: TJsonStorage;
  TempDirSql, TempDirJson: string;
  OriginalNote: TNote;
  SqlNotes, JsonNotes: TObjectList<TNote>;
  SqlNote, JsonNote: TNote;
begin
  TempDirSql := TPath.Combine(TPath.GetTempPath, 'StickyNotes_Equiv_SQL_' + IntToStr(TThread.GetTickCount));
  TempDirJson := TPath.Combine(TPath.GetTempPath, 'StickyNotes_Equiv_JSON_' + IntToStr(TThread.GetTickCount));

  SqlStorage := TSQLiteStorage.Create(TempDirSql);
  JsonStorage := TJsonStorage.Create(TempDirJson);
  try
    SqlStorage.Initialize;
    JsonStorage.Initialize;

    OriginalNote := TNote.Create(42, 'Equivalence Title', 'Equivalence Content', ncPink);
    try
      OriginalNote.Left := 200;
      OriginalNote.Top := 300;
      OriginalNote.Width := 450;
      OriginalNote.Height := 350;
      OriginalNote.AlwaysOnTop := True;
      OriginalNote.Collapsed := False;
      OriginalNote.Locked := True;
      OriginalNote.ToggleFavorite;
      OriginalNote.AddTag('tagA');
      OriginalNote.AddTag('tagB');
      OriginalNote.AddChecklistItem('CheckA', True);
      OriginalNote.AddChecklistItem('CheckB', False);

      SqlStorage.SaveNote(OriginalNote);
      JsonStorage.SaveNote(OriginalNote);
    finally
      OriginalNote.Free;
    end;

    SqlNotes := SqlStorage.LoadAllNotes;
    JsonNotes := JsonStorage.LoadAllNotes;
    try
      Assert.AreEqual(1, SqlNotes.Count);
      Assert.AreEqual(1, JsonNotes.Count);

      SqlNote := SqlNotes[0];
      JsonNote := JsonNotes[0];

      Assert.AreEqual(JsonNote.ID, SqlNote.ID);
      Assert.AreEqual(JsonNote.Title, SqlNote.Title);
      Assert.AreEqual(JsonNote.Content, SqlNote.Content);
      Assert.AreEqual<TNoteColor>(JsonNote.Color, SqlNote.Color);
      Assert.AreEqual(JsonNote.Left, SqlNote.Left);
      Assert.AreEqual(JsonNote.Top, SqlNote.Top);
      Assert.AreEqual(JsonNote.Width, SqlNote.Width);
      Assert.AreEqual(JsonNote.Height, SqlNote.Height);
      Assert.AreEqual(JsonNote.AlwaysOnTop, SqlNote.AlwaysOnTop);
      Assert.AreEqual(JsonNote.Collapsed, SqlNote.Collapsed);
      Assert.AreEqual(JsonNote.Locked, SqlNote.Locked);
      Assert.AreEqual(JsonNote.Favorite, SqlNote.Favorite);
      Assert.AreEqual(Double(JsonNote.CreatedAt), Double(SqlNote.CreatedAt), 0.001);
      Assert.AreEqual(Double(JsonNote.UpdatedAt), Double(SqlNote.UpdatedAt), 0.001);

      Assert.AreEqual(Length(JsonNote.Tags), Length(SqlNote.Tags));
      Assert.AreEqual(JsonNote.Tags[0], SqlNote.Tags[0]);
      Assert.AreEqual(JsonNote.Tags[1], SqlNote.Tags[1]);

      Assert.AreEqual(Length(JsonNote.ChecklistItems), Length(SqlNote.ChecklistItems));
      Assert.AreEqual(JsonNote.ChecklistItems[0].Text, SqlNote.ChecklistItems[0].Text);
      Assert.AreEqual(JsonNote.ChecklistItems[0].Done, SqlNote.ChecklistItems[0].Done);
      Assert.AreEqual(JsonNote.ChecklistItems[1].Text, SqlNote.ChecklistItems[1].Text);
      Assert.AreEqual(JsonNote.ChecklistItems[1].Done, SqlNote.ChecklistItems[1].Done);
    finally
      SqlNotes.Free;
      JsonNotes.Free;
    end;
  finally
    SqlStorage.Free;
    JsonStorage.Free;
    if TDirectory.Exists(TempDirSql) then
      TDirectory.Delete(TempDirSql, True);
    if TDirectory.Exists(TempDirJson) then
      TDirectory.Delete(TempDirJson, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestOuterTransactionCommit;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  N1, N2: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_TxCommit_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Storage.BeginTransaction;
    Assert.IsTrue(Storage.IsInTransaction, 'Storage should be in transaction');

    N1 := TNote.Create(1, 'Tx Note 1', 'Content 1', ncYellow);
    N2 := TNote.Create(2, 'Tx Note 2', 'Content 2', ncGreen);
    try
      Assert.IsTrue(Storage.SaveNote(N1));
      Assert.IsTrue(Storage.SaveNote(N2));
    finally
      N1.Free;
      N2.Free;
    end;

    Assert.IsTrue(Storage.IsInTransaction, 'Storage should still be in transaction prior to commit');
    Storage.CommitTransaction;
    Assert.IsFalse(Storage.IsInTransaction, 'Storage should not be in transaction after commit');

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(2, Notes.Count, 'Both notes should be committed and persisted');
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestOuterTransactionRollback;
var
  Storage: TSQLiteStorage;
  TempDir: string;
  Note: TNote;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_TxRollback_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Storage.BeginTransaction;
    Assert.IsTrue(Storage.IsInTransaction);

    Note := TNote.Create(1, 'Uncommitted Note', 'Content', ncYellow);
    try
      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should succeed inside active outer transaction');
    finally
      Note.Free;
    end;

    Assert.IsTrue(Storage.IsInTransaction, 'SaveNote must not commit outer transaction early');
    Storage.RollbackTransaction;
    Assert.IsFalse(Storage.IsInTransaction, 'Transaction should be closed after rollback');

    Notes := Storage.LoadAllNotes;
    try
      Assert.AreEqual(0, Notes.Count, 'Note saved inside rolled back transaction must not be persisted');
    finally
      Notes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TSQLiteStorageTestFixture.TestSaveNoteDoesNotRollbackOuterTransactionOnFailure;
var
  Storage: TSQLiteStorage;
  TempDir: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_SQLiteTest_TxFailOwnership_' + IntToStr(TThread.GetTickCount));
  Storage := TSQLiteStorage.Create(TempDir);
  try
    Storage.Initialize;
    Storage.BeginTransaction;
    Assert.IsTrue(Storage.IsInTransaction);

    // Passing nil note causes SaveNote to return False
    Assert.IsFalse(Storage.SaveNote(nil));
    Assert.IsTrue(Storage.IsInTransaction, 'SaveNote failure must not rollback or close the outer transaction owned by caller');

    Storage.RollbackTransaction;
    Assert.IsFalse(Storage.IsInTransaction);
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSQLiteStorageTestFixture);

end.
