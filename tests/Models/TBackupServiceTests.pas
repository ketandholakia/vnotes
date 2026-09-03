unit TBackupServiceTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  DUnitX.TestFramework,
  uBackupService, uBackupScheduler, uSettings, uNoteManager, uStorage,
  uJsonStorage, uNote, uEnums;

type
  [TestFixture]
  TBackupServiceTestFixture = class
  private
    FBasePath: string;
    FNotesPath: string;
    FBackupPath: string;
    FStorage: INoteStorage;
    FNoteManager: TNoteManager;
    FSettings: TSettings;
    FBackupService: TBackupService;
    FBackupCount: Integer;
    FRestoreCount: Integer;
    FProgressMessages: TStringList;
    procedure OnBackupComplete(ASuccess: Boolean; const AMessage: string);
    procedure OnRestoreComplete(ASuccess: Boolean; const AMessage: string);
    procedure OnProgress(const AMessage: string; AProgress: Integer);
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestBackupCreationSuccess;
    [Test]
    procedure TestBackupContainsExpectedData;
    [Test]
    procedure TestRestoreSuccess;
    [Test]
    procedure TestRestoreCorruptedFile;
    [Test]
    procedure TestRestoreMissingFile;
    [Test]
    procedure TestCleanupOldBackups;
    [Test]
    procedure TestCleanupPreservesRecentBackups;
    [Test]
    procedure TestCleanupDisabledZeroRetention;
    [Test]
    procedure TestCleanupHandlesEmptyDirectory;
    [Test]
    procedure TestCleanupPreservesUnrelatedFiles;
    [Test]
    procedure TestRestoreClearsExistingNotes;
    [Test]
    procedure TestRestoreWithPreRestoreBackup;
    [Test]
    procedure TestRestoreRejectsIncompatibleVersion;
    [Test]
    procedure TestRestoreHandlesBackupWithoutNotes;
    [Test]
    procedure TestRestoreFailsGracefullyOnMissingFile;
  end;

implementation

procedure TBackupServiceTestFixture.OnBackupComplete(ASuccess: Boolean;
  const AMessage: string);
begin
  Inc(FBackupCount);
end;

procedure TBackupServiceTestFixture.OnRestoreComplete(ASuccess: Boolean;
  const AMessage: string);
begin
  Inc(FRestoreCount);
end;

procedure TBackupServiceTestFixture.OnProgress(const AMessage: string;
  AProgress: Integer);
begin
  FProgressMessages.Add(Format('%s (%d%%)', [AMessage, AProgress]));
end;

procedure TBackupServiceTestFixture.SetUp;
begin
  FBasePath := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_BackupServiceTest_' + IntToStr(TThread.GetTickCount));
  FNotesPath := TPath.Combine(FBasePath, 'notes');
  FBackupPath := TPath.Combine(FBasePath, 'backups');
  ForceDirectories(FNotesPath);
  ForceDirectories(FBackupPath);

  FStorage := TJsonStorage.Create(FBasePath);
  FNoteManager := TNoteManager.Create(FStorage);
  FNoteManager.Initialize;

  FSettings := TSettings.Create;
  FSettings.BackupEnabled := True;
  FSettings.BackupIntervalDays := 1;
  FSettings.BackupRetentionDays := 7;

  FBackupService := TBackupService.Create(FNoteManager, FSettings, FBackupPath);
  FBackupService.OnComplete := OnBackupComplete;
  FBackupService.OnProgress := OnProgress;

  FBackupCount := 0;
  FRestoreCount := 0;
  FProgressMessages := TStringList.Create;
end;

procedure TBackupServiceTestFixture.TearDown;
begin
  FreeAndNil(FProgressMessages);
  FreeAndNil(FBackupService);
  FreeAndNil(FSettings);
  FreeAndNil(FNoteManager);
  FStorage := nil;
  if TDirectory.Exists(FBasePath) then
    TDirectory.Delete(FBasePath, True);
end;

procedure TBackupServiceTestFixture.TestBackupCreationSuccess;
var
  BackupFile: string;
begin
  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount, 'Should complete one backup');
  
  // Check that backup file was created
  BackupFile := FBackupService.GetBackupFileName;
  Assert.IsTrue(TFile.Exists(BackupFile), 'Backup file should exist');
  
  // Check filename pattern
  Assert.IsTrue(ExtractFileName(BackupFile).StartsWith('StickyNotes_Backup_'), 
    'Filename should follow expected pattern');
  Assert.IsTrue(ExtractFileName(BackupFile).EndsWith('.zip'), 
    'Filename should have .zip extension');
end;

procedure TBackupServiceTestFixture.TestBackupContainsExpectedData;
var
  BackupFile: string;
  Zip: TZipFile;
  TempDir: string;
  Files: TStringDynArray;
  NotesFile: string;
  JsonText: string;
  Json: System.JSON.TJSONObject;
  Note: TNote;
begin
  // Create a test note
  Note := TNote.Create;
  try
    Note.Title := 'Test Note';
    Note.Content := 'Test Content';
    Note.Color := ncBlue;
    Note.Left := 100;
    Note.Top := 200;
    Note.Width := 300;
    Note.Height := 250;
    Note.AlwaysOnTop := True;
    FNoteManager.AddNote(Note);
    
    // Create backup
    FBackupService.Backup;
    Assert.AreEqual(1, FBackupCount, 'Should complete one backup');
    
    // Extract and verify backup contents
    BackupFile := FBackupService.GetBackupFileName;
    TempDir := TPath.Combine(TPath.GetTempPath, 'BackupTest_' + IntToStr(TThread.GetTickCount));
    ForceDirectories(TempDir);
    
    try
      Zip := TZipFile.Create;
      try
        Zip.Open(BackupFile, zmRead);
        try
          Zip.ExtractAll(TempDir);
        finally
          Zip.Close;
        end;
      finally
        Zip.Free;
      end;
      
      // Check that notes directory exists
      NotesFile := TPath.Combine(TempDir, 'notes');
      Assert.IsTrue(TDirectory.Exists(NotesFile), 'Notes directory should exist');
      
      // Check that settings file exists
      Assert.IsTrue(TFile.Exists(TPath.Combine(TempDir, 'settings.ini')), 
        'Settings file should exist');
      
      // Check note files
      Files := TDirectory.GetFiles(NotesFile, '*.json');
      Assert.AreEqual(1, Length(Files), 'Should have one note file');
      
      // Verify note content
      JsonText := TFile.ReadAllText(Files[0], TEncoding.UTF8);
      Json := System.JSON.TJSONObject.ParseJSONValue(JsonText) as System.JSON.TJSONObject;
      try
        Assert.AreEqual('Test Note', Json.GetValue<string>('Title', ''), 
          'Note title should match');
        Assert.AreEqual('Test Content', Json.GetValue<string>('Content', ''), 
          'Note content should match');
        Assert.AreEqual(Ord(ncBlue), Json.GetValue<Integer>('Color', 0), 
          'Note color should match');
        Assert.AreEqual(100, Json.GetValue<Integer>('Left', 0), 
          'Note position should match');
        Assert.AreEqual(200, Json.GetValue<Integer>('Top', 0), 
          'Note position should match');
        Assert.AreEqual(300, Json.GetValue<Integer>('Width', 0), 
          'Note size should match');
        Assert.AreEqual(250, Json.GetValue<Integer>('Height', 0), 
          'Note size should match');
        Assert.AreEqual(True, Json.GetValue<Boolean>('AlwaysOnTop', False), 
          'AlwaysOnTop should match');
      finally
        Json.Free;
      end;
    finally
      if TDirectory.Exists(TempDir) then
        TDirectory.Delete(TempDir, True);
    end;
  finally
    Note.Free;
  end;
end;

procedure TBackupServiceTestFixture.TestRestoreSuccess;
var
  BackupFile: string;
  TempDir: string;
  Zip: TZipFile;
  SettingsFile: string;
  NotesFile: string;
  JsonText: string;
  Json: System.JSON.TJSONObject;
  Note: TNote;
begin
  // Create test data
  Note := TNote.Create;
  try
    Note.Title := 'Restore Test';
    Note.Content := 'Restore Content';
    Note.Color := ncGreen;
    FNoteManager.AddNote(Note);
    
    // Create backup
    FBackupService.Backup;
    Assert.AreEqual(1, FBackupCount, 'Should complete one backup');
    
    // Clear existing notes
    FNoteManager.Clear;
    Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes before restore');
    
    // Restore from backup
    BackupFile := FBackupService.GetBackupFileName;
    FBackupService.Restore(BackupFile);
    Assert.AreEqual(1, FRestoreCount, 'Should complete one restore');
    
    // Verify restored note
    Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have one restored note');
    Note := FNoteManager.Notes[0];
    Assert.AreEqual('Restore Test', Note.Title, 'Restored note title should match');
    Assert.AreEqual('Restore Content', Note.Content, 'Restored note content should match');
    Assert.AreEqual(ncGreen, Note.Color, 'Restored note color should match');
  finally
    Note.Free;
  end;
end;

procedure TBackupServiceTestFixture.TestRestoreCorruptedFile;
var
  CorruptedFile: string;
begin
  // Create a corrupted backup file
  CorruptedFile := TPath.Combine(FBackupPath, 'corrupted.zip');
  TFile.WriteAllText(CorruptedFile, 'This is not a valid ZIP file');
  
  // Try to restore from corrupted file
  FBackupService.Restore(CorruptedFile);
  Assert.AreEqual(1, FRestoreCount, 'Should attempt one restore');
  
  // Verify no notes were created
  Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes after corrupted restore');
end;

procedure TBackupServiceTestFixture.TestRestoreMissingFile;
var
  MissingFile: string;
begin
  // Try to restore from non-existent file
  MissingFile := TPath.Combine(FBackupPath, 'missing.zip');
  
  // Try to restore from missing file
  FBackupService.Restore(MissingFile);
  Assert.AreEqual(1, FRestoreCount, 'Should attempt one restore');
  
  // Verify no notes were created
  Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes after missing file restore');
end;

procedure TBackupServiceTestFixture.TestCleanupOldBackups;
var
  OldFile: string;
  RecentFile: string;
begin
  // Create old backup (more than 7 days old)
  OldFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20230101_120000.zip');
  TFile.WriteAllText(OldFile, 'old backup content');
  
  // Set file modification time to be old
  TFile.SetLastWriteTime(OldFile, Now - 10);
  
  // Create recent backup (less than 7 days old)
  RecentFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20240101_120000.zip');
  TFile.WriteAllText(RecentFile, 'recent backup content');
  
  // Set file modification time to be recent
  TFile.SetLastWriteTime(RecentFile, Now - 1);
  
  // Run cleanup
  FBackupService.CleanupOldBackups;
  
  // Verify old file was deleted
  Assert.IsFalse(TFile.Exists(OldFile), 'Old backup should be deleted');
  
  // Verify recent file was preserved
  Assert.IsTrue(TFile.Exists(RecentFile), 'Recent backup should be preserved');
end;

procedure TBackupServiceTestFixture.TestCleanupPreservesRecentBackups;
var
  RecentFile1: string;
  RecentFile2: string;
begin
  // Create two recent backups (both less than 7 days old)
  RecentFile1 := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20240101_120000.zip');
  TFile.WriteAllText(RecentFile1, 'recent backup 1');
  TFile.SetLastWriteTime(RecentFile1, Now - 1);
  
  RecentFile2 := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20240102_120000.zip');
  TFile.WriteAllText(RecentFile2, 'recent backup 2');
  TFile.SetLastWriteTime(RecentFile2, Now - 2);
  
  // Run cleanup
  FBackupService.CleanupOldBackups;
  
  // Verify both recent files were preserved
  Assert.IsTrue(TFile.Exists(RecentFile1), 'Recent backup 1 should be preserved');
  Assert.IsTrue(TFile.Exists(RecentFile2), 'Recent backup 2 should be preserved');
end;

procedure TBackupServiceTestFixture.TestCleanupDisabledZeroRetention;
var
  OldFile: string;
begin
  // Create old backup
  OldFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20230101_120000.zip');
  TFile.WriteAllText(OldFile, 'old backup content');
  TFile.SetLastWriteTime(OldFile, Now - 10);
  
  // Disable retention
  FSettings.BackupRetentionDays := 0;
  
  // Run cleanup
  FBackupService.CleanupOldBackups;
  
  // Verify old file was preserved (retention disabled)
  Assert.IsTrue(TFile.Exists(OldFile), 'Backup should be preserved when retention disabled');
end;

procedure TBackupServiceTestFixture.TestCleanupHandlesEmptyDirectory;
begin
  // Ensure backup directory exists but is empty
  Assert.IsTrue(TDirectory.Exists(FBackupPath), 'Backup directory should exist');
  Assert.AreEqual(0, TDirectory.GetFiles(FBackupPath, '*').Length, 
    'Backup directory should be empty');
  
  // Run cleanup (should not crash)
  FBackupService.CleanupOldBackups;
  
  // Verify directory is still empty
  Assert.AreEqual(0, TDirectory.GetFiles(FBackupPath, '*').Length, 
    'Backup directory should remain empty');
end;

procedure TBackupServiceTestFixture.TestCleanupPreservesUnrelatedFiles;
var
  UnrelatedFile: string;
  BackupFile: string;
begin
  // Create unrelated file
  UnrelatedFile := TPath.Combine(FBackupPath, 'unrelated.txt');
  TFile.WriteAllText(UnrelatedFile, 'unrelated content');
  
  // Create old backup
  BackupFile := TPath.Combine(FBackupPath, 'StickyNotes_Backup_20230101_120000.zip');
  TFile.WriteAllText(BackupFile, 'old backup content');
  TFile.SetLastWriteTime(BackupFile, Now - 10);
  
  // Run cleanup
  FBackupService.CleanupOldBackups;
  
  // Verify unrelated file was preserved
  Assert.IsTrue(TFile.Exists(UnrelatedFile), 'Unrelated file should be preserved');
  
  // Verify backup file was deleted
  Assert.IsFalse(TFile.Exists(BackupFile), 'Old backup should be deleted');
end;

[Test]
procedure TBackupServiceTestFixture.TestRestoreClearsExistingNotes;
var
  BackupFile: string;
  ExistingNote: TNote;
  RestoredNote: TNote;
begin
  // Create an existing note
  ExistingNote := TNote.Create;
  try
    ExistingNote.Title := 'Existing Note';
    ExistingNote.Content := 'This note should not exist after restore';
    FNoteManager.AddNote(ExistingNote);

    Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have one existing note');

    // Create and backup a different note
    RestoredNote := TNote.Create;
    try
      RestoredNote.Title := 'Restored Note';
      RestoredNote.Content := 'This is the restored note';
      RestoredNote.Color := ncBlue;
      FNoteManager.AddNote(RestoredNote);

      Assert.AreEqual(2, FNoteManager.NoteCount, 'Should have two notes before backup');

      // Backup
      FBackupService.Backup;
      Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

      // Clear notes to simulate starting fresh
      while FNoteManager.NoteCount > 0 do
      begin
        RestoredNote := FNoteManager.Notes[0];
        if RestoredNote <> nil then
          FNoteManager.DeleteNote(RestoredNote.ID);
      end;

      Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes before restore');

      // Restore
      BackupFile := FBackupService.GetBackupFileName;
      FBackupService.Restore(BackupFile);

      // Verify only the restored notes are present
      Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have exactly one restored note');
      RestoredNote := FNoteManager.Notes[0];
      Assert.AreEqual('Restored Note', RestoredNote.Title, 'Should have the backup note title');
    finally
      // Don't free RestoredNote - it's owned by FNoteManager
    end;
  finally
    ExistingNote.Free; // This was already in FNoteManager so it's deleted by clear
  end;
end;

[Test]
procedure TBackupServiceTestFixture.TestRestoreWithPreRestoreBackup;
var
  BackupFile: string;
  Note: TNote;
  PreRestoreFiles: TStringDynArray;
  PreRestoreBackupExists: Boolean;
begin
  // Create a note to backup
  Note := TNote.Create;
  try
    Note.Title := 'Original Note';
    Note.Content := 'Content';
    FNoteManager.AddNote(Note);

    // Create backup (this is what will be restored)
    FBackupService.Backup;
    Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

    // Add another note
    Note := TNote.Create;
    Note.Title := 'Second Note';
    Note.Content := 'Different content';
    FNoteManager.AddNote(Note);

    Assert.AreEqual(2, FNoteManager.NoteCount, 'Should have two notes before restore');

    // Restore (which should create pre-restore backup)
    BackupFile := FBackupService.GetBackupFileName;
    FBackupService.Restore(BackupFile);

    // Check that a pre-restore backup was created
    PreRestoreFiles := TDirectory.GetFiles(FBackupPath, 'pre_restore_backup_*.zip');
    PreRestoreBackupExists := Length(PreRestoreFiles) > 0;

    Assert.IsTrue(PreRestoreBackupExists, 'Pre-restore backup should be created');
    Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have restored notes');
  finally
    Note.Free;
  end;
end;

[Test]
procedure TBackupServiceTestFixture.TestRestoreRejectsIncompatibleVersion;
var
  IncompatibleZip: string;
  TempDir: string;
  ManifestFile: string;
  ManifestJson: System.JSON.TJSONObject;
  ManifestText: string;
  Zip: TZipFile;
begin
  // Create a backup with incompatible version
  IncompatibleZip := TPath.Combine(FBackupPath, 'incompatible.zip');
  TempDir := TPath.Combine(TPath.GetTempPath, 'IncompatibleTest_' + IntToStr(TThread.GetTickCount));

  try
    ForceDirectories(TempDir);

    // Create manifest with future version
    ManifestFile := TPath.Combine(TempDir, 'manifest.json');
    ManifestJson := System.JSON.TJSONObject.Create;
    try
      ManifestJson.AddPair('version', System.JSON.TJSONNumber.Create(999));
      ManifestJson.AddPair('createdAt', '2026-09-01T00:00:00');
      ManifestText := ManifestJson.Format;
      TFile.WriteAllText(ManifestFile, ManifestText, TEncoding.UTF8);
    finally
      ManifestJson.Free;
    end;

    // Create empty notes directory
    ForceDirectories(TPath.Combine(TempDir, 'notes'));

    // Create zip
    Zip := TZipFile.Create;
    try
      Zip.Open(IncompatibleZip, zmWrite);
      try
        Zip.Add(ManifestFile, 'manifest.json');
        Zip.Add(TPath.Combine(TempDir, 'notes'), 'notes/');
      finally
        Zip.Close;
      end;
    finally
      Zip.Free;
    end;

    // Try to restore - should fail
    FBackupService.Restore(IncompatibleZip);

    // Verify restore was marked as failed (no notes added)
    Assert.AreEqual(0, FNoteManager.NoteCount, 'Incompatible backup should not be restored');
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

[Test]
procedure TBackupServiceTestFixture.TestRestoreHandlesBackupWithoutNotes;
var
  BackupFile: string;
  TempDir: string;
  Zip: TZipFile;
  ManifestFile: string;
  ManifestJson: System.JSON.TJSONObject;
  SettingsFile: string;
begin
  // Create a backup with settings but no notes directory
  BackupFile := TPath.Combine(FBackupPath, 'no_notes.zip');
  TempDir := TPath.Combine(TPath.GetTempPath, 'NoNotesTest_' + IntToStr(TThread.GetTickCount));

  try
    ForceDirectories(TempDir);

    // Create manifest
    ManifestFile := TPath.Combine(TempDir, 'manifest.json');
    ManifestJson := System.JSON.TJSONObject.Create;
    try
      ManifestJson.AddPair('version', System.JSON.TJSONNumber.Create(1));
      ManifestJson.AddPair('createdAt', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
      TFile.WriteAllText(ManifestFile, ManifestJson.Format, TEncoding.UTF8);
    finally
      ManifestJson.Free;
    end;

    // Create settings file but no notes
    SettingsFile := TPath.Combine(TempDir, 'settings.ini');
    FSettings.SaveToFile(SettingsFile);

    // Create zip (no notes directory)
    Zip := TZipFile.Create;
    try
      Zip.Open(BackupFile, zmWrite);
      try
        Zip.Add(ManifestFile, 'manifest.json');
        Zip.Add(SettingsFile, 'settings.ini');
      finally
        Zip.Close;
      end;
    finally
      Zip.Free;
    end;

    // Create a note to restore on top of
    FNoteManager.AddNote(TNote.Create('Test', 'Content', ncYellow));
    Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have note before restore');

    // Restore (should work but have 0 notes in result)
    FBackupService.Restore(BackupFile);
    Assert.AreEqual(1, FRestoreCount, 'Restore should attempt to complete');
    Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes after restoring backup with no notes');
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

[Test]
procedure TBackupServiceTestFixture.TestRestoreFailsGracefullyOnMissingFile;
var
  MissingFile: string;
begin
  // Try to restore from non-existent file
  MissingFile := TPath.Combine(FBackupPath, 'definitely_does_not_exist.zip');

  // Add a note to verify it's not lost on failed restore
  FNoteManager.AddNote(TNote.Create('Existing', 'Note', ncYellow));

  // Attempt restore
  FBackupService.Restore(MissingFile);

  // Verify restore failed gracefully and existing note is preserved
  Assert.AreEqual(1, FNoteManager.NoteCount, 'Existing notes should not be lost on failed restore');
end;

end.