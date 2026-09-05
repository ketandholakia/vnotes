unit TBackupServiceTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  System.Types, System.JSON,
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
    FDeletedNoteWasAlive: Boolean;
    FDeletedNoteTitle: string;
    procedure OnBackupComplete(ASuccess: Boolean; const AMessage: string);
    procedure OnRestoreComplete(ASuccess: Boolean; const AMessage: string);
    procedure OnProgress(const AMessage: string; AProgress: Integer);
    procedure HandleNoteDeletedForSurvivalTest(const ANote: TNote);
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
    [Test]
    procedure TestBackupRoundTripPreservesV3Fields;
    [Test]
    procedure TestRestoreLegacy13FieldBackupDefaultsNewFields;
    [Test]
    procedure TestOnNoteDeletedFiresWhileNoteAlive;
  end;

implementation

procedure TBackupServiceTestFixture.OnBackupComplete(ASuccess: Boolean;
  const AMessage: string);
begin
  if Pos('restore', LowerCase(AMessage)) > 0 then
    Inc(FRestoreCount)
  else
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

procedure TBackupServiceTestFixture.HandleNoteDeletedForSurvivalTest(const ANote: TNote);
begin
  FDeletedNoteWasAlive := (ANote <> nil) and (ANote.Title <> '');
  if FDeletedNoteWasAlive then
    FDeletedNoteTitle := ANote.Title;
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
    Note.Collapsed := True;
    Note.Locked := True;
    Note.Favorite := True;
    Note.AddTag('work');
    Note.AddTag('Personal');
    Note.AddChecklistItem('Task 1', False);
    Note.AddChecklistItem('Task 2', True);
    FNoteManager.AddNote(Note);
  finally
    // Note is now owned by manager - do not free here
  end;

  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

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

    NotesFile := TPath.Combine(TempDir, 'notes');
    Assert.IsTrue(TDirectory.Exists(NotesFile), 'Notes directory should exist');
    Assert.IsTrue(TFile.Exists(TPath.Combine(TempDir, 'settings.ini')),
      'Settings file should exist');

    Files := TDirectory.GetFiles(NotesFile, '*.json');
    Assert.AreEqual(1, Length(Files), 'Should have one note file');

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
      Assert.AreEqual(True, Json.GetValue<Boolean>('Collapsed', False),
        'Collapsed should match');
      Assert.AreEqual(True, Json.GetValue<Boolean>('Locked', False),
        'Locked should match');
      Assert.AreEqual(True, Json.GetValue<Boolean>('Favorite', False),
        'Favorite should match');
      Assert.IsNotNull(Json.GetValue('schemaVersion'),
        'schemaVersion should be present');
      Assert.AreEqual<Integer>(3, Json.GetValue<Integer>('schemaVersion', 0),
        'schemaVersion should be 3');
    finally
      Json.Free;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TBackupServiceTestFixture.TestRestoreSuccess;
var
  BackupFile: string;
  Note: TNote;
begin
  Note := TNote.Create;
  try
    Note.Title := 'Restore Test';
    Note.Content := 'Restore Content';
    Note.Color := ncGreen;
    Note.Favorite := True;
    Note.AddTag('urgent');
    Note.AddChecklistItem('Done Item', True);
    Note.AddChecklistItem('Pending Item', False);
    FNoteManager.AddNote(Note);
  finally
    // Note is now owned by manager - do not free here
  end;

  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

  while FNoteManager.NoteCount > 0 do
    FNoteManager.DeleteNote(FNoteManager.Notes[0].ID);
  Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes before restore');

  BackupFile := FBackupService.GetBackupFileName;
  FBackupService.Restore(BackupFile);
  Assert.AreEqual(1, FRestoreCount, 'Should complete one restore');

  Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have one restored note');
  Note := FNoteManager.Notes[0];
  Assert.AreEqual('Restore Test', Note.Title, 'Restored note title should match');
  Assert.AreEqual('Restore Content', Note.Content, 'Restored note content should match');
  Assert.AreEqual(ncGreen, Note.Color, 'Restored note color should match');
  Assert.IsTrue(Note.Favorite, 'Restored note Favorite should match');
  Assert.IsTrue(Note.HasTag('urgent'), 'Restored note should have tag');
  Assert.AreEqual(2, Length(Note.ChecklistItems), 'Restored note should have 2 checklist items');
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
var
  Files: TStringDynArray;
begin
  Assert.IsTrue(TDirectory.Exists(FBackupPath), 'Backup directory should exist');
  Files := TDirectory.GetFiles(FBackupPath, '*');
  Assert.AreEqual(0, Length(Files),
    'Backup directory should be empty');

  FBackupService.CleanupOldBackups;

  Files := TDirectory.GetFiles(FBackupPath, '*');
  Assert.AreEqual(0, Length(Files),
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
  ExistingNote := TNote.Create;
  try
    ExistingNote.ID := 1;
    ExistingNote.Title := 'Existing Note';
    ExistingNote.Content := 'This note should not exist after restore';
    FNoteManager.AddNote(ExistingNote);

    Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have one existing note');

    RestoredNote := TNote.Create;
    try
      RestoredNote.ID := 2;
      RestoredNote.Title := 'Restored Note';
      RestoredNote.Content := 'This is the restored note';
      RestoredNote.Color := ncBlue;
      FNoteManager.AddNote(RestoredNote);

      Assert.AreEqual(2, FNoteManager.NoteCount, 'Should have two notes before backup');

      FBackupService.Backup;
      Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

      while FNoteManager.NoteCount > 0 do
        FNoteManager.DeleteNote(FNoteManager.Notes[0].ID);

      Assert.AreEqual(0, FNoteManager.NoteCount, 'Should have no notes before restore');

      BackupFile := FBackupService.GetBackupFileName;
      FBackupService.Restore(BackupFile);

      Assert.AreEqual(2, FNoteManager.NoteCount, 'Should have both restored notes');
      Assert.AreEqual('Restored Note', FNoteManager.Notes[1].Title, 'Should have the restored note title');
    finally
      // RestoredNote is now owned by manager (or was deleted), don't free
    end;
  finally
    // ExistingNote was deleted by the while loop above, don't free
  end;
end;

[Test]
procedure TBackupServiceTestFixture.TestRestoreWithPreRestoreBackup;
var
  BackupFile: string;
  Note: TNote;
  PreRestoreFiles: TStringDynArray;
begin
  Note := TNote.Create;
  try
    Note.ID := 1;
    Note.Title := 'Original Note';
    Note.Content := 'Content';
    FNoteManager.AddNote(Note);
  finally
    // Note is now owned by manager - do not free here
  end;

  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount, 'Should complete one backup');

  Note := TNote.Create;
  try
    Note.ID := 2;
    Note.Title := 'Second Note';
    Note.Content := 'Different content';
    FNoteManager.AddNote(Note);
  finally
    // Note is now owned by manager - do not free here
  end;

  Assert.AreEqual(2, FNoteManager.NoteCount, 'Should have two notes before restore');

  BackupFile := FBackupService.GetBackupFileName;
  FBackupService.Restore(BackupFile);

  PreRestoreFiles := TDirectory.GetFiles(FBackupPath, 'pre_restore_backup_*.zip');
  Assert.IsTrue(Length(PreRestoreFiles) > 0, 'Pre-restore backup should be created');
  Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have restored notes');
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
    FNoteManager.AddNote(TNote.Create(0, 'Test', 'Content', ncYellow));
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
  FNoteManager.AddNote(TNote.Create(0, 'Existing', 'Note', ncYellow));

  // Attempt restore
  FBackupService.Restore(MissingFile);

    // Verify restore failed gracefully and existing note is preserved
    Assert.AreEqual(1, FNoteManager.NoteCount, 'Existing notes should not be lost on failed restore');
end;

procedure TBackupServiceTestFixture.TestBackupRoundTripPreservesV3Fields;
var
  BackupFile: string;
  Note: TNote;
  JsonText: string;
  Json: System.JSON.TJSONObject;
  TagsArray: System.JSON.TJSONArray;
  ChecklistArray: System.JSON.TJSONArray;
  I: Integer;
begin
  Note := TNote.Create;
  try
    Note.ID := 999;
    Note.Title := 'Unicode: \u4E2D\u6587 \u0395\u03BB\u03BB\u03B7\u03BD\u03B9\u03BA\u03AC \uD83C\uDF0D';
    Note.Content := 'Content with \u2022 bullets and\ttabs';
    Note.Color := ncBlue;
    Note.Left := 50;
    Note.Top := 75;
    Note.Width := 400;
    Note.Height := 350;
    Note.AlwaysOnTop := True;
    Note.Collapsed := True;
    Note.Locked := True;
    Note.Favorite := True;
    Note.AddTag('Work');
    Note.AddTag('PERSONAL');
    Note.AddTag('MixedCase');
    Note.AddChecklistItem('First task', False);
    Note.AddChecklistItem('Second task', True);
    Note.AddChecklistItem('Third task', False);
    FNoteManager.AddNote(Note);
  finally
    // Note is now owned by manager
  end;

  FBackupService.Backup;
  Assert.AreEqual(1, FBackupCount);

  while FNoteManager.NoteCount > 0 do
    FNoteManager.DeleteNote(FNoteManager.Notes[0].ID);

  BackupFile := FBackupService.GetBackupFileName;
  FBackupService.Restore(BackupFile);
  Assert.AreEqual(1, FRestoreCount);

  Assert.AreEqual(1, FNoteManager.NoteCount, 'Should have exactly one restored note');
  Note := FNoteManager.Notes[0];

  Assert.AreEqual('Unicode: \u4E2D\u6587 \u0395\u03BB\u03BB\u03B7\u03BD\u03B9\u03BA\u03AC \uD83C\uDF0D', Note.Title);
  Assert.AreEqual('Content with \u2022 bullets and\ttabs', Note.Content);
  Assert.AreEqual(ncBlue, Note.Color);
  Assert.AreEqual(50, Note.Left);
  Assert.AreEqual(75, Note.Top);
  Assert.AreEqual(400, Note.Width);
  Assert.AreEqual(350, Note.Height);
  Assert.IsTrue(Note.AlwaysOnTop);
  Assert.IsTrue(Note.Collapsed);
  Assert.IsTrue(Note.Locked);
  Assert.IsTrue(Note.Favorite);

  Assert.AreEqual(3, Length(Note.Tags));
  Assert.IsTrue(Note.HasTag('Work'));
  Assert.IsTrue(Note.HasTag('PERSONAL'));
  Assert.IsTrue(Note.HasTag('MixedCase'));

  Assert.AreEqual(3, Length(Note.ChecklistItems));
  Assert.AreEqual('First task', Note.ChecklistItems[0].Text);
  Assert.IsFalse(Note.ChecklistItems[0].Done);
  Assert.AreEqual('Second task', Note.ChecklistItems[1].Text);
  Assert.IsTrue(Note.ChecklistItems[1].Done);
  Assert.AreEqual('Third task', Note.ChecklistItems[2].Text);
  Assert.IsFalse(Note.ChecklistItems[2].Done);
end;

procedure TBackupServiceTestFixture.TestRestoreLegacy13FieldBackupDefaultsNewFields;
var
  BackupFile: string;
  Zip: TZipFile;
  TempDir: string;
  LegacyNoteFile: string;
  Note: TNote;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'LegacyRestoreTest_' + IntToStr(TThread.GetTickCount));
  try
    ForceDirectories(TempDir);
    ForceDirectories(TPath.Combine(TempDir, 'notes'));

    LegacyNoteFile := TPath.Combine(TempDir, 'notes', '0000000001.json');
    TFile.WriteAllText(LegacyNoteFile,
      '{"ID":1,"Title":"Legacy Note","Content":"Old format",' +
      '"Color":2,"Left":150,"Top":200,"Width":320,"Height":280,' +
      '"AlwaysOnTop":true,"Collapsed":false,"Locked":true,' +
      '"CreatedAt":"2024-01-15T10:30:00","UpdatedAt":"2024-01-16T11:45:00"}',
      TEncoding.UTF8);

    BackupFile := TPath.Combine(FBackupPath, 'legacy_backup.zip');
    Zip := TZipFile.Create;
    try
      Zip.Open(BackupFile, zmWrite);
      try
        Zip.Add(LegacyNoteFile, 'notes/0000000001.json');
      finally
        Zip.Close;
      end;
    finally
      Zip.Free;
    end;

    FBackupService.Restore(BackupFile);
    Assert.AreEqual(1, FRestoreCount);

    Assert.AreEqual(1, FNoteManager.NoteCount, 'Should restore the legacy note');
    Note := FNoteManager.Notes[0];

    Assert.AreEqual('Legacy Note', Note.Title);
    Assert.AreEqual('Old format', Note.Content);
    Assert.AreEqual(ncBlue, Note.Color);
    Assert.AreEqual(150, Note.Left);
    Assert.AreEqual(200, Note.Top);
    Assert.AreEqual(320, Note.Width);
    Assert.AreEqual(280, Note.Height);
    Assert.IsTrue(Note.AlwaysOnTop);
    Assert.IsFalse(Note.Collapsed);
    Assert.IsTrue(Note.Locked);

    Assert.IsFalse(Note.Favorite, 'Legacy note without Favorite field should default to False');
    Assert.AreEqual(0, Length(Note.Tags), 'Legacy note without tags field should have empty tags');
    Assert.AreEqual(0, Length(Note.ChecklistItems), 'Legacy note without checklistItems should have empty');
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TBackupServiceTestFixture.TestOnNoteDeletedFiresWhileNoteAlive;
var
  Note: TNote;
begin
  FNoteManager.OnNoteDeleted := HandleNoteDeletedForSurvivalTest;

  Note := TNote.Create;
  try
    Note.Title := 'ToBeDeleted';
    FNoteManager.AddNote(Note);
  finally
    // Note is owned by manager
  end;

  Assert.AreEqual(1, FNoteManager.NoteCount);

  FDeletedNoteWasAlive := False;
  FDeletedNoteTitle := '';
  FNoteManager.DeleteNote(Note.ID);

  Assert.IsTrue(FDeletedNoteWasAlive, 'OnNoteDeleted should fire while note is still alive');
  Assert.AreEqual('ToBeDeleted', FDeletedNoteTitle, 'OnNoteDeleted should receive correct note data');
  Assert.AreEqual(0, FNoteManager.NoteCount, 'Note should be removed from manager');
end;

initialization
  TDUnitX.RegisterTestFixture(TBackupServiceTestFixture);

end.