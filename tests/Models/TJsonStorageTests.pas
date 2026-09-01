unit TJsonStorageTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.SyncObjs,
  DUnitX.TestFramework, uJsonStorage, uNote, uEnums, uILogger;

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

initialization
  TDUnitX.RegisterTestFixture(TJsonStorageTestFixture);
end.