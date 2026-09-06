unit TStorageMigrationServiceTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.DateUtils,
  DUnitX.TestFramework, uStorageMigrationService, uJsonStorage, uSQLiteStorage,
  uNote, uEnums;

type
  [TestFixture]
  TStorageMigrationServiceTestFixture = class
  public
    [Test]
    procedure TestMigrateEmptyJsonDirectory;
    [Test]
    procedure TestMigrateSingleNote;
    [Test]
    procedure TestMigrateMultipleNotes;
    [Test]
    procedure TestMigrateFullRichNote;
    [Test]
    procedure TestMigrateTagsAndOrdering;
    [Test]
    procedure TestMigrateChecklistAndOrdering;
    [Test]
    procedure TestMigrateFavorite;
    [Test]
    procedure TestMigratePositionAndSize;
    [Test]
    procedure TestMigrateTimestamps;
    [Test]
    procedure TestMigrateMultipleIDs;
    [Test]
    procedure TestMigrateMalformedJsonFailsEntirely;
    [Test]
    procedure TestMigrateExistingEmptySQLiteDbSucceeds;
    [Test]
    procedure TestMigrateExistingNonEmptySQLiteDbFails;
    [Test]
    procedure TestMigrateOriginalJsonFilesUntouched;
    [Test]
    procedure TestMigrateResultValuesOnSuccess;
    [Test]
    procedure TestMigrateResultValuesOnFailure;
  end;

implementation

procedure TStorageMigrationServiceTestFixture.TestMigrateEmptyJsonDirectory;
var
  TempDir: string;
  Res: TMigrationResult;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Empty_' + IntToStr(TThread.GetTickCount));
  TDirectory.CreateDirectory(TempDir);
  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success, 'Migrating empty JSON directory should succeed');
    Assert.AreEqual(0, Res.NotesMigrated, 'NotesMigrated should be 0');
    Assert.AreEqual(0, Res.NotesFailed, 'NotesFailed should be 0');
    Assert.AreEqual('', Res.ErrorMessage);
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateSingleNote;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Single_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Single Title', 'Single Content', ncBlue);
    try
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success, 'Migration of single note should succeed');
    Assert.AreEqual(1, Res.NotesMigrated);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
        Assert.AreEqual<Int64>(1, Notes[0].ID);
        Assert.AreEqual<string>('Single Title', Notes[0].Title);
        Assert.AreEqual<string>('Single Content', Notes[0].Content);
        Assert.AreEqual<TNoteColor>(ncBlue, Notes[0].Color);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateMultipleNotes;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  N1, N2, N3: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Multi_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    N1 := TNote.Create(1, 'Note 1', 'Content 1', ncYellow);
    N2 := TNote.Create(2, 'Note 2', 'Content 2', ncGreen);
    N3 := TNote.Create(3, 'Note 3', 'Content 3', ncPink);
    try
      JsonStorage.SaveNote(N1);
      JsonStorage.SaveNote(N2);
      JsonStorage.SaveNote(N3);
    finally
      N1.Free;
      N2.Free;
      N3.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);
    Assert.AreEqual(3, Res.NotesMigrated);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(3, Notes.Count);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateFullRichNote;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Rich_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(42, 'Rich Title', 'Rich Content', ncPurple);
    try
      Note.Left := 200;
      Note.Top := 300;
      Note.Width := 500;
      Note.Height := 400;
      Note.AlwaysOnTop := True;
      Note.Collapsed := True;
      Note.Locked := True;
      Note.Favorite := True;
      Note.AddTag('tag1');
      Note.AddTag('tag2');
      Note.AddChecklistItem('Task 1', False);
      Note.AddChecklistItem('Task 2', True);
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);
    Assert.AreEqual(1, Res.NotesMigrated);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
        Assert.AreEqual<Int64>(42, Notes[0].ID);
        Assert.AreEqual<string>('Rich Title', Notes[0].Title);
        Assert.AreEqual<string>('Rich Content', Notes[0].Content);
        Assert.AreEqual<TNoteColor>(ncPurple, Notes[0].Color);
        Assert.AreEqual(200, Notes[0].Left);
        Assert.AreEqual(300, Notes[0].Top);
        Assert.AreEqual(500, Notes[0].Width);
        Assert.AreEqual(400, Notes[0].Height);
        Assert.IsTrue(Notes[0].AlwaysOnTop);
        Assert.IsTrue(Notes[0].Collapsed);
        Assert.IsTrue(Notes[0].Locked);
        Assert.IsTrue(Notes[0].Favorite);
        Assert.AreEqual(2, Length(Notes[0].Tags));
        Assert.AreEqual('tag1', Notes[0].Tags[0]);
        Assert.AreEqual('tag2', Notes[0].Tags[1]);
        Assert.AreEqual(2, Length(Notes[0].ChecklistItems));
        Assert.AreEqual('Task 1', Notes[0].ChecklistItems[0].Text);
        Assert.IsFalse(Notes[0].ChecklistItems[0].Done);
        Assert.AreEqual('Task 2', Notes[0].ChecklistItems[1].Text);
        Assert.IsTrue(Notes[0].ChecklistItems[1].Done);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateTagsAndOrdering;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_TagOrd_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      Note.AddTag('alpha');
      Note.AddTag('beta');
      Note.AddTag('gamma');
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
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
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateChecklistAndOrdering;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_CheckOrd_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      Note.AddChecklistItem('First', True);
      Note.AddChecklistItem('Second', False);
      Note.AddChecklistItem('Third', True);
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
        Assert.AreEqual(3, Length(Notes[0].ChecklistItems));
        Assert.AreEqual('First', Notes[0].ChecklistItems[0].Text);
        Assert.IsTrue(Notes[0].ChecklistItems[0].Done);
        Assert.AreEqual('Second', Notes[0].ChecklistItems[1].Text);
        Assert.IsFalse(Notes[0].ChecklistItems[1].Done);
        Assert.AreEqual('Third', Notes[0].ChecklistItems[2].Text);
        Assert.IsTrue(Notes[0].ChecklistItems[2].Done);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateFavorite;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Fav_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      Note.ToggleFavorite;
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
        Assert.IsTrue(Notes[0].Favorite);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigratePositionAndSize;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Pos_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      Note.Left := 333;
      Note.Top := 444;
      Note.Width := 555;
      Note.Height := 666;
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
        Assert.AreEqual(333, Notes[0].Left);
        Assert.AreEqual(444, Notes[0].Top);
        Assert.AreEqual(555, Notes[0].Width);
        Assert.AreEqual(666, Notes[0].Height);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateTimestamps;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
  KnownCreated, KnownUpdated: TDateTime;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Time_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    KnownCreated := EncodeDateTime(2026, 9, 1, 12, 0, 0, 0);
    KnownUpdated := EncodeDateTime(2026, 9, 6, 15, 30, 0, 0);
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      Note.CreatedAt := KnownCreated;
      Note.UpdatedAt := KnownUpdated;
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
        Assert.AreEqual(Double(KnownCreated), Double(Notes[0].CreatedAt), 0.001);
        Assert.AreEqual(Double(KnownUpdated), Double(Notes[0].UpdatedAt), 0.001);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateMultipleIDs;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  N1, N2: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_IDs_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    N1 := TNote.Create(10, 'Title 10', 'Content 10', ncYellow);
    N2 := TNote.Create(20, 'Title 20', 'Content 20', ncGreen);
    try
      JsonStorage.SaveNote(N1);
      JsonStorage.SaveNote(N2);
    finally
      N1.Free;
      N2.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(2, Notes.Count);
        Assert.AreEqual<Int64>(10, Notes[0].ID);
        Assert.AreEqual<Int64>(20, Notes[1].ID);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateMalformedJsonFailsEntirely;
var
  TempDir, NotesDir, BadFile: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Malformed_' + IntToStr(TThread.GetTickCount));
  NotesDir := TPath.Combine(TempDir, 'notes');
  TDirectory.CreateDirectory(NotesDir);

  // Write one good note via JsonStorage
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Good Title', 'Good Content', ncYellow);
    try
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  // Write one malformed file directly
  BadFile := TPath.Combine(NotesDir, '0000000002.json');
  TFile.WriteAllText(BadFile, '{ malformed json content ...', TEncoding.UTF8);

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsFalse(Res.Success, 'Migration should fail when a malformed JSON file exists');
    Assert.AreEqual(0, Res.NotesMigrated);
    Assert.IsTrue(Res.NotesFailed > 0);
    Assert.IsTrue(Length(Res.ErrorMessage) > 0);

    // Verify SQLite database has no notes (rollback)
    if TFile.Exists(TPath.Combine(TempDir, 'vnotes.db')) then
    begin
      SqlStorage := TSQLiteStorage.Create(TempDir);
      try
        SqlStorage.Initialize;
        Notes := SqlStorage.LoadAllNotes;
        try
          Assert.AreEqual(0, Notes.Count, 'No notes should be migrated to SQLite on failure');
        finally
          Notes.Free;
        end;
      finally
        SqlStorage.Free;
      end;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateExistingEmptySQLiteDbSucceeds;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
  Notes: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_ExistEmpty_' + IntToStr(TThread.GetTickCount));
  
  // Pre-create empty SQLite database
  SqlStorage := TSQLiteStorage.Create(TempDir);
  try
    SqlStorage.Initialize;
  finally
    SqlStorage.Free;
  end;

  // Create JSON note
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success, 'Migrating to an existing empty SQLite database should succeed');
    Assert.AreEqual(1, Res.NotesMigrated);

    SqlStorage := TSQLiteStorage.Create(TempDir);
    try
      SqlStorage.Initialize;
      Notes := SqlStorage.LoadAllNotes;
      try
        Assert.AreEqual(1, Notes.Count);
      finally
        Notes.Free;
      end;
    finally
      SqlStorage.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateExistingNonEmptySQLiteDbFails;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_ExistNonEmpty_' + IntToStr(TThread.GetTickCount));

  // Pre-create SQLite DB with 1 note
  SqlStorage := TSQLiteStorage.Create(TempDir);
  try
    SqlStorage.Initialize;
    Note := TNote.Create(99, 'Existing Note', 'Content', ncYellow);
    try
      SqlStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    SqlStorage.Free;
  end;

  // Create JSON note
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'JSON Note', 'Content', ncBlue);
    try
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsFalse(Res.Success, 'Migrating to an existing non-empty SQLite database must fail');
    Assert.AreEqual(0, Res.NotesMigrated);
    Assert.AreEqual('Destination SQLite database is not empty', Res.ErrorMessage);
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateOriginalJsonFilesUntouched;
var
  TempDir, NotesDir, File1: string;
  JsonStorage: TJsonStorage;
  Note: TNote;
  Res: TMigrationResult;
  ContentBefore, ContentAfter: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_Untouched_' + IntToStr(TThread.GetTickCount));
  NotesDir := TPath.Combine(TempDir, 'notes');
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Untouched Title', 'Untouched Content', ncYellow);
    try
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  File1 := TPath.Combine(NotesDir, '0000000001.json');
  Assert.IsTrue(TFile.Exists(File1), 'Source JSON file should exist before migration');
  ContentBefore := TFile.ReadAllText(File1, TEncoding.UTF8);

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);

    Assert.IsTrue(TFile.Exists(File1), 'Source JSON file must still exist after migration');
    ContentAfter := TFile.ReadAllText(File1, TEncoding.UTF8);
    Assert.AreEqual(ContentBefore, ContentAfter, 'Source JSON file content must be identical after migration');
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateResultValuesOnSuccess;
var
  TempDir: string;
  JsonStorage: TJsonStorage;
  Note: TNote;
  Res: TMigrationResult;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_ResSucc_' + IntToStr(TThread.GetTickCount));
  JsonStorage := TJsonStorage.Create(TempDir);
  try
    JsonStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      JsonStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsTrue(Res.Success);
    Assert.AreEqual(1, Res.NotesMigrated);
    Assert.AreEqual(0, Res.NotesFailed);
    Assert.AreEqual('', Res.ErrorMessage);
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TStorageMigrationServiceTestFixture.TestMigrateResultValuesOnFailure;
var
  TempDir: string;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  Res: TMigrationResult;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'StickyNotes_MigrTest_ResFail_' + IntToStr(TThread.GetTickCount));

  // Populate SQLite to trigger failure
  SqlStorage := TSQLiteStorage.Create(TempDir);
  try
    SqlStorage.Initialize;
    Note := TNote.Create(1, 'Title', 'Content', ncYellow);
    try
      SqlStorage.SaveNote(Note);
    finally
      Note.Free;
    end;
  finally
    SqlStorage.Free;
  end;

  try
    Res := TStorageMigrationService.MigrateJsonToSQLite(TempDir);
    Assert.IsFalse(Res.Success);
    Assert.AreEqual(0, Res.NotesMigrated);
    Assert.AreEqual(0, Res.NotesFailed);
    Assert.AreEqual('Destination SQLite database is not empty', Res.ErrorMessage);
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStorageMigrationServiceTestFixture);

end.
