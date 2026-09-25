unit TJsonStorageTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.SyncObjs, System.JSON,
  DUnitX.TestFramework, uJsonStorage, uNote, uEnums, uILogger, uStorage;

type
  [TestFixture]
  TJsonStorageTestFixture = class
  public
    [Test]
    procedure TestSaveLoadNote;
    [Test]
    procedure TestAtomicSave;
    [Test]
    procedure TestDeleteNote;
    [Test]
    procedure TestLoadAllNotesWithValidFiles;
    [Test]
    procedure TestLoadAllNotesSkipsCorrupted;
    [Test]
    procedure TestSaveNoteFailureSafety;
    [Test]
    procedure TestSaveWritesSchemaVersion;
    [Test]
    procedure TestLoadLegacyUnversionedNote;
    [Test]
    procedure TestLoadExplicitSchemaVersion1;
    [Test]
    procedure TestFutureSchemaVersionSkippedAndPreserved;
    [Test]
    procedure TestInvalidSchemaVersionSkippedAndPreserved;
    [Test]
    procedure TestSaveLoadNoteWithTagsAndChecklistRoundTrips;
    [Test]
    procedure TestLoadLegacyAndV1NotesDefaultToEmptyTagsAndChecklist;
    [Test]
    procedure TestLoadMalformedTagsAndChecklistDegradesGracefully;
    // Phase 6C.1: Favorite flag persistence.
    [Test]
    procedure TestSaveLoadNoteWithFavoriteRoundTrips;
    [Test]
    procedure TestLoadLegacyV0V1V2NotesDefaultFavoriteFalse;
    [Test]
    procedure TestLoadV3NoteWithoutFavoriteDefaultsFalse;
    [Test]
    procedure TestLoadMalformedFavoriteDegradesGracefully;
    [Test]
    procedure TestSyncIdentityRoundTripsOnSaveLoad;
    [Test]
    procedure TestLegacyV3NoteDefaultsSyncIdentity;
  end;

implementation

procedure TJsonStorageTestFixture.TestSaveLoadNote;
var
  Storage: TJsonStorage;
  Note: TNote;
  LoadedNote: TNote;
  FileName: string;
  TempDir: string;
  LoadedNotes: TObjectList<TNote>;
  CurrentNote: TNote;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_StorageTest_';
  Storage := TJsonStorage.Create(TempDir);
  try
    Note := TNote.Create(1, 'Test Title', 'Test Content', ncGreen);
    try
      // Save note
      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should return True');

      // Check file was created
      FileName := TPath.Combine(TempDir, 'notes\0000000001.json');
      Assert.IsTrue(TFile.Exists(FileName), 'JSON file should exist after save');

      // Load all notes
      LoadedNote := nil;
      LoadedNotes := Storage.LoadAllNotes;
      try
        for CurrentNote in LoadedNotes do
        begin
          if CurrentNote.ID = 1 then
          begin
            LoadedNote := CurrentNote;
            Break;
          end;
        end;

        Assert.IsNotNull(LoadedNote, 'Loaded note should not be nil');
        Assert.AreEqual<Int64>(1, LoadedNote.ID);
        Assert.AreEqual<string>('Test Title', LoadedNote.Title);
        Assert.AreEqual<string>('Test Content', LoadedNote.Content);
        Assert.AreEqual<TNoteColor>(ncGreen, LoadedNote.Color);
      finally
        LoadedNotes.Free;
      end;

      // Delete note
      Assert.IsTrue(Storage.DeleteNote(1), 'DeleteNote should return True');

      // Verify file is gone
      Assert.IsFalse(TFile.Exists(FileName), 'JSON file should be deleted after DeleteNote');
    finally
      Note.Free;
    end;
  finally
    Storage.Free;
    // Cleanup temp dir
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestAtomicSave;
var
  Storage: TJsonStorage;
  Note: TNote;
  FileName: string;
  TempDir: string;
  LoadedNote: TNote;
  LoadedNotes: TObjectList<TNote>;
  CurrentNote: TNote;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_AtomicTest_';
  Storage := TJsonStorage.Create(TempDir);
  try
    // SaveNote will create directories automatically

    Note := TNote.Create(42, 'Atomic Test', 'Atomic Content', ncBlue);
    try
      // Save note twice (should overwrite)
      Assert.IsTrue(Storage.SaveNote(Note), 'First save should succeed');
      Note.Content := 'Modified Content';
      Assert.IsTrue(Storage.SaveNote(Note), 'Second save should succeed');

      // Verify the file exists and is valid JSON
      FileName := TPath.Combine(TempDir, 'notes\0000000042.json');
      Assert.IsTrue(TFile.Exists(FileName), 'JSON file should exist after atomic save');

      // Read and verify
      LoadedNote := nil;
      LoadedNotes := Storage.LoadAllNotes;
      try
        for CurrentNote in LoadedNotes do
        begin
          if CurrentNote.ID = 42 then
          begin
            LoadedNote := CurrentNote;
            Break;
          end;
        end;

        Assert.IsNotNull(LoadedNote, 'Loaded note should not be nil');
        Assert.AreEqual<Int64>(42, LoadedNote.ID);
        Assert.AreEqual<string>('Modified Content', LoadedNote.Content, 'Content should be the modified version');
      finally
        LoadedNotes.Free;
      end;
    finally
      Note.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestDeleteNote;
var
  Storage: TJsonStorage;
  Note: TNote;
  FileName: string;
  TempDir: string;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_DeleteTest_';
  Storage := TJsonStorage.Create(TempDir);
  try
    Note := TNote.Create(99, 'To Be Deleted', 'Delete me', ncYellow);
    try
      Assert.IsTrue(Storage.SaveNote(Note), 'Save should succeed');
      FileName := TPath.Combine(TempDir, 'notes\0000000099.json');
      Assert.IsTrue(TFile.Exists(FileName), 'File should exist after save');

      Assert.IsTrue(Storage.DeleteNote(99), 'Delete should succeed');
      Assert.IsFalse(TFile.Exists(FileName), 'File should be deleted');
    finally
      Note.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadAllNotesWithValidFiles;
var
  Storage: TJsonStorage;
  TempDir: string;
  Loaded: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_LoadTest_';
  Storage := TJsonStorage.Create(TempDir);
  try
    // Create some note files manually
    TDirectory.CreateDirectory(TPath.Combine(TempDir, 'notes'));
    TFile.WriteAllText(TPath.Combine(TempDir, 'notes\0000000001.json'), '{"ID":1,"Title":"Note 1","Content":"Content 1","Color":0,"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,"Collapsed":false,"Locked":false,"CreatedAt":"2026-01-15T10:30:00","UpdatedAt":"2026-01-15T10:35:00"}', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(TempDir, 'notes\0000000002.json'), '{"ID":2,"Title":"Note 2","Content":"Content 2","Color":1,"Left":200,"Top":200,"Width":400,"Height":300,"AlwaysOnTop":true,"Collapsed":false,"Locked":false,"CreatedAt":"2026-01-15T11:00:00","UpdatedAt":"2026-01-15T11:05:00"}', TEncoding.UTF8);

    Loaded := Storage.LoadAllNotes;
    try
      Assert.AreEqual(2, Loaded.Count, 'Should load 2 notes');
      Assert.AreEqual('Note 1', Loaded[0].Title);
      Assert.AreEqual('Note 2', Loaded[1].Title);
    finally
      Loaded.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadAllNotesSkipsCorrupted;
var
  Storage: TJsonStorage;
  TempDir: string;
  Loaded: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_CorruptTest_';
  Storage := TJsonStorage.Create(TempDir);
  try
    TDirectory.CreateDirectory(TPath.Combine(TempDir, 'notes'));
    // Write a corrupted JSON file
    TFile.WriteAllText(TPath.Combine(TempDir, 'notes\0000000001.json'), 'This is not valid JSON{{{', TEncoding.UTF8);
    // Write a valid JSON file
    TFile.WriteAllText(TPath.Combine(TempDir, 'notes\0000000002.json'), '{"ID":2,"Title":"Valid","Content":"Valid"}', TEncoding.UTF8);

    Loaded := Storage.LoadAllNotes;
    try
      // Should only load the valid note, not crash
      Assert.AreEqual(1, Loaded.Count, 'Should load only 1 valid note, skipping corrupted');
      Assert.AreEqual('Valid', Loaded[0].Title);
    finally
      Loaded.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestSaveNoteFailureSafety;
var
  Storage: TJsonStorage;
  Note: TNote;
  FileName: string;
  TempDir: string;
  LockThread: TThread;
  OriginalContent: string;
  LockAcquired: TEvent;
  Finished: Boolean;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_FailSafeTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    Note := TNote.Create(100, 'Original Title', 'Original Content', ncYellow);
    try
      // First save — creates the valid note file
      Assert.IsTrue(Storage.SaveNote(Note), 'First save should succeed');
      FileName := TPath.Combine(TempDir, 'notes\0000000100.json');
      Assert.IsTrue(TFile.Exists(FileName), 'File should exist after first save');

      // Preserve original content for comparison
      OriginalContent := TFile.ReadAllText(FileName, TEncoding.UTF8);

      // Modify the note so the replacement is detectably different
      Note.Title := 'Replacement Title';
      Note.Content := 'Replacement Content';

      // Lock the destination file from a background thread with exclusive access.
      // This forces MoveFileEx (called by SaveNote) to fail with a sharing violation,
      // while the original file remains intact.
      LockAcquired := TEvent.Create(nil, True, False, '');
      Finished := False;

      LockThread := TThread.CreateAnonymousThread(
        procedure
        var
          LockFS: TFileStream;
        begin
          LockFS := TFileStream.Create(FileName, fmOpenReadWrite or fmShareExclusive);
          try
            LockAcquired.SetEvent;
            while not Finished do
              TThread.Sleep(50);
          finally
            LockFS.Free;
          end;
        end
      );
      LockThread.FreeOnTerminate := False;
      LockThread.Start;

      try
        // Wait for the lock to be acquired (5 s timeout)
        if LockAcquired.WaitFor(5000) = wrSignaled then
        begin
          // Attempt second save — must fail because destination is exclusively locked
          Assert.IsFalse(Storage.SaveNote(Note),
            'SaveNote must return False when destination file is locked');

          // While the lock is still held, verify the file STILL EXISTS
          // (we cannot read it yet because it's exclusively locked)
          Assert.IsTrue(TFile.Exists(FileName),
            'Original file must still exist after failed save attempt');

          // Verify temp file is cleaned up (MoveFileEx never succeeded)
          Assert.IsFalse(TFile.Exists(FileName + '.tmp'),
            'Temporary file must be removed after failed save');
        end
        else
          Assert.Fail('Background thread failed to acquire file lock within 5 seconds');
      finally
        Finished := True;
        LockThread.WaitFor;
        LockThread.Free;
        LockAcquired.Free;
      end;

      // Now that the lock is released, verify original content is preserved
      Assert.AreEqual<string>(OriginalContent,
        TFile.ReadAllText(FileName, TEncoding.UTF8),
        'Original file content must be identical after failed save');
    finally
      Note.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestSaveWritesSchemaVersion;
var
  Storage: TJsonStorage;
  Note: TNote;
  FileName, JsonText, TempDir: string;
  Json: TJSONValue;
  Pair: TJSONPair;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_SchemaWriteTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    Note := TNote.Create(1, 'Schema', 'Version test', ncYellow);
    try
      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should succeed');
      FileName := TPath.Combine(TempDir, 'notes\0000000001.json');
      Assert.IsTrue(TFile.Exists(FileName), 'Note file should exist');

      JsonText := TFile.ReadAllText(FileName, TEncoding.UTF8);
      Json := TJSONObject.ParseJSONValue(JsonText);
      try
        Assert.IsNotNull(Json, 'Saved file should be valid JSON');
        Pair := (Json as TJSONObject).Get('schemaVersion');
        Assert.IsNotNull(Pair, 'Saved JSON must contain schemaVersion');
        Assert.IsTrue(Pair.JsonValue is TJSONNumber, 'schemaVersion must be a JSON number');
Assert.AreEqual<Int64>(NoteSchemaVersion, (Pair.JsonValue as TJSONNumber).AsInt64,
'schemaVersion must equal the current schema version');
      finally
        Json.Free;
      end;
    finally
      Note.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadLegacyUnversionedNote;
var
  Storage: TJsonStorage;
  NotesDir, FileName, LegacyJson, OriginalContent, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
  Note: TNote;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_LegacyTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);
    FileName := TPath.Combine(NotesDir, '0000000007.json');

    // Actual pre-versioning format: no schemaVersion field
    LegacyJson :=
      '{"ID":7,"Title":"Legacy Title","Content":"Legacy Content",' +
      '"Color":2,"Left":150,"Top":200,"Width":320,"Height":280,' +
      '"AlwaysOnTop":true,"Collapsed":false,"Locked":true,' +
      '"CreatedAt":"2024-01-15T10:30:00","UpdatedAt":"2024-01-16T11:45:00"}';
    TFile.WriteAllText(FileName, LegacyJson, TEncoding.UTF8);
    OriginalContent := TFile.ReadAllText(FileName, TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedNotes.Count, 'Legacy note should load successfully');
      Note := LoadedNotes[0];
      Assert.AreEqual<Int64>(7, Note.ID);
      Assert.AreEqual<string>('Legacy Title', Note.Title);
      Assert.AreEqual<string>('Legacy Content', Note.Content);
      Assert.AreEqual<TNoteColor>(ncBlue, Note.Color);
      Assert.AreEqual<Integer>(150, Note.Left);
      Assert.AreEqual<Integer>(200, Note.Top);
      Assert.AreEqual<Integer>(320, Note.Width);
      Assert.AreEqual<Integer>(280, Note.Height);
      Assert.IsTrue(Note.AlwaysOnTop, 'AlwaysOnTop should be preserved');
      Assert.IsFalse(Note.Collapsed, 'Collapsed should be preserved');
      Assert.IsTrue(Note.Locked, 'Locked should be preserved');
    finally
      LoadedNotes.Free;
    end;

    // Loading must NOT rewrite the legacy file
    Assert.AreEqual<string>(OriginalContent,
      TFile.ReadAllText(FileName, TEncoding.UTF8),
      'Loading a legacy file must not modify it');
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadExplicitSchemaVersion1;
var
  Storage: TJsonStorage;
  NotesDir, FileName, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_SchemaV1Test_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);
    FileName := TPath.Combine(NotesDir, '0000000005.json');
    TFile.WriteAllText(FileName,
      '{"schemaVersion":1,"ID":5,"Title":"V1 Note","Content":"Explicit",' +
      '"Color":1,"Left":100,"Top":100,"Width":300,"Height":250,' +
      '"AlwaysOnTop":false,"Collapsed":false,"Locked":false,' +
      '"CreatedAt":"2024-06-01T08:00:00","UpdatedAt":"2024-06-01T08:00:00"}',
      TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedNotes.Count, 'Explicit v1 note should load');
      Assert.AreEqual<Int64>(5, LoadedNotes[0].ID);
      Assert.AreEqual<string>('V1 Note', LoadedNotes[0].Title);
      Assert.AreEqual<TNoteColor>(ncGreen, LoadedNotes[0].Color);
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestFutureSchemaVersionSkippedAndPreserved;
var
  Storage: TJsonStorage;
  NotesDir, FutureFile, FutureContent, TempDir: string;
  Note: TNote;
  LoadedNotes: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_FutureSchemaTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);

    // A note from a future application version
    FutureFile := TPath.Combine(NotesDir, '0000000002.json');
    TFile.WriteAllText(FutureFile,
      '{"schemaVersion":999,"ID":2,"Title":"Future","Content":"Future","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00"}', TEncoding.UTF8);
    FutureContent := TFile.ReadAllText(FutureFile, TEncoding.UTF8);

    // A normal current-version note alongside it
    Note := TNote.Create(1, 'Valid', 'Valid note', ncYellow);
    try
      Assert.IsTrue(Storage.SaveNote(Note), 'Saving a valid note should succeed');
    finally
      Note.Free;
    end;

    LoadedNotes := Storage.LoadAllNotes;
    try
      // Future-version file skipped; valid file still loaded
      Assert.AreEqual<Integer>(1, LoadedNotes.Count,
        'Only the valid note should load; the future-version note must be skipped');
      Assert.AreEqual<Int64>(1, LoadedNotes[0].ID);
    finally
      LoadedNotes.Free;
    end;

    // The future-version file must remain intact
    Assert.IsTrue(TFile.Exists(FutureFile), 'Future-version file must not be deleted');
    Assert.AreEqual<string>(FutureContent,
      TFile.ReadAllText(FutureFile, TEncoding.UTF8),
      'Future-version file must not be modified');
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestInvalidSchemaVersionSkippedAndPreserved;
var
  Storage: TJsonStorage;
  NotesDir, BadFile, BadContent, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_InvalidSchemaTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);

    // Malformed schemaVersion: string instead of integer
    BadFile := TPath.Combine(NotesDir, '0000000003.json');
    TFile.WriteAllText(BadFile,
      '{"schemaVersion":"abc","ID":3,"Title":"Bad","Content":"Bad","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00"}', TEncoding.UTF8);
    BadContent := TFile.ReadAllText(BadFile, TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(0, LoadedNotes.Count,
        'Invalid schemaVersion must be safely rejected, not loaded');
    finally
      LoadedNotes.Free;
    end;

    Assert.IsTrue(TFile.Exists(BadFile), 'Invalid-schema file must not be deleted');
    Assert.AreEqual<string>(BadContent,
      TFile.ReadAllText(BadFile, TEncoding.UTF8),
      'Invalid-schema file must not be modified');
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestSaveLoadNoteWithTagsAndChecklistRoundTrips;
var
  Storage: TJsonStorage;
  Note, LoadedNote: TNote;
  TempDir: string;
  LoadedNotes: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_TagsChecklistTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    Note := TNote.Create(9, 'Shopping', 'Weekly run', ncGreen);
    try
      Note.AddTag('errands');
      Note.AddTag('personal');
      Note.AddChecklistItem('Milk');
      Note.AddChecklistItem('Eggs', True);

      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should succeed');
    finally
      Note.Free;
    end;

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedNotes.Count);
      LoadedNote := LoadedNotes[0];

      Assert.AreEqual<Integer>(2, Length(LoadedNote.Tags));
      Assert.IsTrue(LoadedNote.HasTag('errands'));
      Assert.IsTrue(LoadedNote.HasTag('personal'));

      Assert.AreEqual<Integer>(2, Length(LoadedNote.ChecklistItems));
      Assert.AreEqual('Milk', LoadedNote.ChecklistItems[0].Text);
      Assert.IsFalse(LoadedNote.ChecklistItems[0].Done);
      Assert.AreEqual('Eggs', LoadedNote.ChecklistItems[1].Text);
      Assert.IsTrue(LoadedNote.ChecklistItems[1].Done);
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadLegacyAndV1NotesDefaultToEmptyTagsAndChecklist;
var
  Storage: TJsonStorage;
  NotesDir, LegacyFile, V1File, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
  LegacyNote, V1Note: TNote;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_TagsChecklistDefaultTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);

    // v0 (unversioned)  predates both schemaVersion and tags/checklistItems.
    LegacyFile := TPath.Combine(NotesDir, '0000000010.json');
    TFile.WriteAllText(LegacyFile,
      '{"ID":10,"Title":"Legacy","Content":"No tags field at all","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00"}', TEncoding.UTF8);

    // v1  has schemaVersion but predates tags/checklistItems.
    V1File := TPath.Combine(NotesDir, '0000000011.json');
    TFile.WriteAllText(V1File,
      '{"schemaVersion":1,"ID":11,"Title":"V1","Content":"Still no tags field",' +
      '"Color":0,"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00"}', TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(2, LoadedNotes.Count);

      LegacyNote := nil;
      V1Note := nil;
      for var N in LoadedNotes do
      begin
        if N.ID = 10 then LegacyNote := N
        else if N.ID = 11 then V1Note := N;
      end;

      Assert.IsNotNull(LegacyNote, 'v0 note should load');
      Assert.AreEqual<Integer>(0, Length(LegacyNote.Tags));
      Assert.AreEqual<Integer>(0, Length(LegacyNote.ChecklistItems));

      Assert.IsNotNull(V1Note, 'v1 note should load');
      Assert.AreEqual<Integer>(0, Length(V1Note.Tags));
      Assert.AreEqual<Integer>(0, Length(V1Note.ChecklistItems));
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadMalformedTagsAndChecklistDegradesGracefully;
var
  Storage: TJsonStorage;
  NotesDir, FileName, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_TagsChecklistMalformedTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);
    FileName := TPath.Combine(NotesDir, '0000000012.json');

    // "tags" is a number instead of an array; "checklistItems" contains one
    // well-formed item and one malformed one (missing "text", a bare string
    // instead of an object). None of this should make the note unloadable.
    TFile.WriteAllText(FileName,
      '{"schemaVersion":2,"ID":12,"Title":"Malformed","Content":"Still loads",' +
      '"Color":0,"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00","tags":123,' +
      '"checklistItems":[{"done":true},"not-an-object",{"text":"Valid","done":false}]}',
      TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedNotes.Count,
        'Note must still load despite malformed tags/checklistItems');
      Assert.AreEqual<Integer>(0, Length(LoadedNotes[0].Tags),
        'Non-array "tags" degrades to empty rather than failing the load');
      // The malformed string element is skipped; the two objects survive
      // (one with a defaulted blank Text, one fully valid).
      Assert.AreEqual<Integer>(2, Length(LoadedNotes[0].ChecklistItems));
      Assert.AreEqual('', LoadedNotes[0].ChecklistItems[0].Text);
      Assert.IsTrue(LoadedNotes[0].ChecklistItems[0].Done);
      Assert.AreEqual('Valid', LoadedNotes[0].ChecklistItems[1].Text);
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

// Phase 6C.1: Favorite flag persistence

procedure TJsonStorageTestFixture.TestSaveLoadNoteWithFavoriteRoundTrips;
var
  Storage: TJsonStorage;
  Note: TNote;
  TempDir: string;
  LoadedNotes: TObjectList<TNote>;
  FavNote, PlainNote: TNote;
  N: TNote;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_FavoriteRoundTripTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    Note := TNote.Create(20, 'Starred', 'Important', ncYellow);
    try
      Note.ToggleFavorite;
      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should succeed');
    finally
      Note.Free;
    end;
    Note := TNote.Create(21, 'Ordinary', 'Routine', ncGreen);
    try
      Assert.IsTrue(Storage.SaveNote(Note), 'SaveNote should succeed');
    finally
      Note.Free;
    end;

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(2, LoadedNotes.Count);
      FavNote := nil;
      PlainNote := nil;
      for N in LoadedNotes do
      begin
        if N.ID = 20 then FavNote := N
        else if N.ID = 21 then PlainNote := N;
      end;
      Assert.IsNotNull(FavNote, 'Favorite note should load');
      Assert.IsTrue(FavNote.Favorite, 'Favorite=True must round-trip');
      Assert.IsNotNull(PlainNote, 'Plain note should load');
      Assert.IsFalse(PlainNote.Favorite, 'Favorite=False must round-trip');
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadLegacyV0V1V2NotesDefaultFavoriteFalse;
var
  Storage: TJsonStorage;
  NotesDir, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
  N: TNote;
  AllDefault: Boolean;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_FavoriteLegacyDefaultTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);

    // v0 (unversioned): predates schemaVersion entirely.
    TFile.WriteAllText(TPath.Combine(NotesDir, '0000000030.json'),
      '{"ID":30,"Title":"Legacy","Content":"No schemaVersion","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00"}', TEncoding.UTF8);
    // v1: has schemaVersion, predates tags/checklistItems/favorite.
    TFile.WriteAllText(TPath.Combine(NotesDir, '0000000031.json'),
      '{"schemaVersion":1,"ID":31,"Title":"V1","Content":"Old","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00"}', TEncoding.UTF8);
    // v2: has tags/checklistItems, predates favorite.
    TFile.WriteAllText(TPath.Combine(NotesDir, '0000000032.json'),
      '{"schemaVersion":2,"ID":32,"Title":"V2","Content":"Older","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00","tags":["work"],"checklistItems":[]}',
      TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(3, LoadedNotes.Count, 'All legacy notes should load');
      AllDefault := True;
      for N in LoadedNotes do
        AllDefault := AllDefault and not N.Favorite;
      Assert.IsTrue(AllDefault, 'v0/v1/v2 notes must default Favorite=False');
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadV3NoteWithoutFavoriteDefaultsFalse;
var
  Storage: TJsonStorage;
  NotesDir, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_FavoriteV3MissingTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);
    // v3 file with the favorite pair deleted (e.g. hand-edited): valid v3,
    // missing field must still default safely rather than failing the load.
    TFile.WriteAllText(TPath.Combine(NotesDir, '0000000033.json'),
      '{"schemaVersion":3,"ID":33,"Title":"V3NoFav","Content":"Edited","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00","tags":[],"checklistItems":[]}',
      TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedNotes.Count, 'Note must still load');
      Assert.IsFalse(LoadedNotes[0].Favorite, 'Missing favorite defaults to False');
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLoadMalformedFavoriteDegradesGracefully;
var
  Storage: TJsonStorage;
  NotesDir, TempDir: string;
  LoadedNotes: TObjectList<TNote>;
  N: TNote;
  AllDefault: Boolean;
begin
  TempDir := TPath.GetTempPath + 'StickyNotes_FavoriteMalformedTest_';
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);

  Storage := TJsonStorage.Create(TempDir);
  try
    NotesDir := TPath.Combine(TempDir, 'notes');
    TDirectory.CreateDirectory(NotesDir);

    // Wrong-typed "favorite" values must degrade to False, never fail the load.
    TFile.WriteAllText(TPath.Combine(NotesDir, '0000000034.json'),
      '{"schemaVersion":3,"ID":34,"Title":"StrFav","Content":"x","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00","tags":[],"checklistItems":[],' +
      '"favorite":"yes"}', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(NotesDir, '0000000035.json'),
      '{"schemaVersion":3,"ID":35,"Title":"NumFav","Content":"x","Color":0,' +
      '"Left":100,"Top":100,"Width":300,"Height":250,"AlwaysOnTop":false,' +
      '"Collapsed":false,"Locked":false,"CreatedAt":"2024-01-01T00:00:00",' +
      '"UpdatedAt":"2024-01-01T00:00:00","tags":[],"checklistItems":[],' +
      '"favorite":1}', TEncoding.UTF8);

    LoadedNotes := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(2, LoadedNotes.Count,
        'Notes must still load despite wrong-typed favorite');
      AllDefault := True;
      for N in LoadedNotes do
        AllDefault := AllDefault and not N.Favorite;
      Assert.IsTrue(AllDefault, 'Wrong-typed favorite degrades to False');
    finally
      LoadedNotes.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestSyncIdentityRoundTripsOnSaveLoad;
var
  Storage: TJsonStorage;
  TempDir: string;
  Note, Loaded: TNote;
  LoadedList: TObjectList<TNote>;
begin
  TempDir := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_JsonIdent_' + IntToStr(TThread.GetTickCount));
  Storage := TJsonStorage.Create(TempDir);
  try
    Storage.Initialize;
    Note := TNote.Create(1, 'Ident', 'Body', ncYellow);
    try
      Note.Guid := '11111111-2222-3333-4444-555555555555';
      Note.Rev := 7;
      Note.ConflictOf := '99999999-0000-1111-2222-333333333333';
      Assert.IsTrue(Storage.SaveNote(Note), 'save should succeed');
    finally
      Note.Free;
    end;

    LoadedList := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedList.Count);
      Loaded := LoadedList[0];
      Assert.AreEqual<string>('11111111-2222-3333-4444-555555555555', Loaded.Guid);
      Assert.AreEqual<Int64>(7, Loaded.Rev);
      Assert.IsTrue(Loaded.DeviceId <> '', 'DeviceId must be stamped on save');
      Assert.IsFalse(Loaded.Deleted);
      Assert.AreEqual<string>('99999999-0000-1111-2222-333333333333', Loaded.ConflictOf,
        'ConflictOf must round-trip');
    finally
      LoadedList.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TJsonStorageTestFixture.TestLegacyV3NoteDefaultsSyncIdentity;
var
  Storage: TJsonStorage;
  TempDir, NotesPath, FileName: string;
  LoadedList: TObjectList<TNote>;
  Json: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_JsonIdentLegacy_' + IntToStr(TThread.GetTickCount));
  NotesPath := TPath.Combine(TempDir, 'notes');
  ForceDirectories(NotesPath);
  FileName := TPath.Combine(NotesPath, '0000000009.json');
  Json :=
    '{"schemaVersion":3,"ID":9,"Title":"Legacy","Content":"No identity","Color":0,' +
    '"Left":10,"Top":20,"Width":300,"Height":200,"AlwaysOnTop":false,' +
    '"Collapsed":false,"Locked":false,"Favorite":false,' +
    '"CreatedAt":"2026-09-17T14:33:25.400+05:30","UpdatedAt":"2026-09-17T14:33:25.400+05:30",' +
    '"tags":[],"checklistItems":[]}';
  TFile.WriteAllText(FileName, Json, TEncoding.UTF8);

  Storage := TJsonStorage.Create(TempDir);
  try
    Storage.Initialize;
    LoadedList := Storage.LoadAllNotes;
    try
      Assert.AreEqual<Integer>(1, LoadedList.Count, 'a v3 note must still load');
      Assert.AreEqual<string>('', LoadedList[0].Guid, 'absent guid defaults to empty');
      Assert.AreEqual<Int64>(1, LoadedList[0].Rev, 'absent rev defaults to 1');
      Assert.IsFalse(LoadedList[0].Deleted, 'absent deleted defaults to False');
    finally
      LoadedList.Free;
    end;
  finally
    Storage.Free;
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonStorageTestFixture);
end.