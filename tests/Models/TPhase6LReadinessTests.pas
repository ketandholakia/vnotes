unit TPhase6LReadinessTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  System.Types, System.JSON, System.Generics.Collections,
  Winapi.Windows, Winapi.ShlObj,
  DUnitX.TestFramework,
  uBackupService, uSettings, uNoteManager, uStorage,
  uJsonStorage, uSQLiteStorage, uStorageResolver, uStorageMigrationService,
  uStorageMigrationOrchestrator, uNote, uEnums, uNoteApplication;

type
  [TestFixture]
  TPhase6LReadinessTestFixture = class
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
    procedure OnProgress(const AMessage: string; AProgress: Integer);
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestStorageResolverDefaultReturnsJson;
    [Test]
    procedure TestStorageResolverReturnsSQLiteWhenConfigured;
    [Test]
    procedure TestSettingsStorageFieldsDefaultAndIni;
    [Test]
    procedure TestSettingsStorageFieldsAssign;
    [Test]
    procedure TestSQLiteBackupIncludesDbAndSettings;
    [Test]
    procedure TestSQLiteRestoreValidDb;
    [Test]
    procedure TestSQLiteRestoreRejectsCorruptDb;
    [Test]
    procedure TestLegacyJsonRestoreMigratesToSQLite;
    [Test]
    procedure TestRestoreFailurePreservesExistingDatabase;
    [Test]
    procedure TestProductionBackendIsJsonInNoteApplication;
    [Test]
    procedure TestRestoreCleansUpOrphanedSidecarFiles;
  end;

implementation

procedure TPhase6LReadinessTestFixture.OnBackupComplete(ASuccess: Boolean; const AMessage: string);
begin
  if Pos('restore', LowerCase(AMessage)) > 0 then
    Inc(FRestoreCount)
  else
    Inc(FBackupCount);
end;

procedure TPhase6LReadinessTestFixture.OnProgress(const AMessage: string; AProgress: Integer);
begin
  FProgressMessages.Add(Format('%s (%d%%)', [AMessage, AProgress]));
end;

procedure TPhase6LReadinessTestFixture.SetUp;
begin
  FBasePath := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_Phase6LTest_' + IntToStr(TThread.GetTickCount));
  FNotesPath := TPath.Combine(FBasePath, 'notes');
  FBackupPath := TPath.Combine(FBasePath, 'backups');
  ForceDirectories(FNotesPath);
  ForceDirectories(FBackupPath);

  FSettings := TSettings.Create;
  FStorage := TStorageResolver.ResolveStorage(FBasePath, FSettings);
  FNoteManager := TNoteManager.Create(FStorage);
  FNoteManager.Initialize;

  FBackupService := TBackupService.Create(FNoteManager, FSettings, FBackupPath);
  FBackupService.OnComplete := OnBackupComplete;
  FBackupService.OnProgress := OnProgress;

  FBackupCount := 0;
  FRestoreCount := 0;
  FProgressMessages := TStringList.Create;
end;

procedure TPhase6LReadinessTestFixture.TearDown;
begin
  FreeAndNil(FProgressMessages);
  FreeAndNil(FBackupService);
  FreeAndNil(FSettings);
  FreeAndNil(FNoteManager);
  FStorage := nil;
  if TDirectory.Exists(FBasePath) then
    TDirectory.Delete(FBasePath, True);
end;

procedure TPhase6LReadinessTestFixture.TestStorageResolverDefaultReturnsJson;
var
  S: TSettings;
  Storage: INoteStorage;
  SettingsPath: string;
begin
  FNoteManager.Finalize;
  if TFile.Exists(TPath.Combine(FBasePath, 'vnotes.db')) then
    TFile.Delete(TPath.Combine(FBasePath, 'vnotes.db'));

  S := TSettings.Create;
  try
    S.StorageBackend := 'JSON';
    S.MigrationCompleted := False;
    SettingsPath := TPath.Combine(FBasePath, 'settings.ini');
    S.SaveToFile(SettingsPath);

    TStorageMigrationOrchestrator.OrchestrateStorage(FBasePath, S, SettingsPath);
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsNotNull(Storage, 'Storage should not be nil');
  finally
    S.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestStorageResolverReturnsSQLiteWhenConfigured;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := 'SQLite';
    S.MigrationCompleted := True;
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsNotNull(Storage, 'Storage should not be nil');
    Assert.IsTrue(Storage is TSQLiteStorage, 'Configured storage should be TSQLiteStorage');
  finally
    S.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestSettingsStorageFieldsDefaultAndIni;
var
  S1, S2: TSettings;
  IniPath: string;
begin
  S1 := TSettings.Create;
  try
    Assert.AreEqual('JSON', S1.StorageBackend, 'Default StorageBackend should be JSON');
    Assert.IsFalse(S1.MigrationCompleted, 'Default MigrationCompleted should be False');
    Assert.AreEqual('', S1.MigrationTimestamp, 'Default MigrationTimestamp should be empty');

    S1.StorageBackend := 'SQLite';
    S1.MigrationCompleted := True;
    S1.MigrationTimestamp := '2026-09-06T14:30:00Z';

    IniPath := TPath.Combine(FBasePath, 'test_settings.ini');
    S1.SaveToFile(IniPath);

    S2 := TSettings.Create;
    try
      S2.LoadFromFile(IniPath);
      Assert.AreEqual('SQLite', S2.StorageBackend, 'StorageBackend should roundtrip');
      Assert.IsTrue(S2.MigrationCompleted, 'MigrationCompleted should roundtrip');
      Assert.AreEqual('2026-09-06T14:30:00Z', S2.MigrationTimestamp, 'MigrationTimestamp should roundtrip');
    finally
      S2.Free;
    end;
  finally
    S1.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestSettingsStorageFieldsAssign;
var
  S1, S2: TSettings;
begin
  S1 := TSettings.Create;
  S2 := TSettings.Create;
  try
    S1.StorageBackend := 'SQLite';
    S1.MigrationCompleted := True;
    S1.MigrationTimestamp := '2026-09-06T15:00:00Z';

    S2.Assign(S1);
    Assert.AreEqual('SQLite', S2.StorageBackend);
    Assert.IsTrue(S2.MigrationCompleted);
    Assert.AreEqual('2026-09-06T15:00:00Z', S2.MigrationTimestamp);
  finally
    S1.Free;
    S2.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestSQLiteBackupIncludesDbAndSettings;
var
  Note: TNote;
  SqlStorage: TSQLiteStorage;
  BackupFile: string;
  TempDir: string;
  Zip: TZipFile;
begin
  // Create a note in NoteManager
  Note := TNote.Create;
  Note.Title := 'Backup DB Note';
  Note.Content := 'Database content';
  Note.AddTag('SQLiteTest');
  FNoteManager.AddNote(Note);

  // Initialize a valid vnotes.db in FBasePath as well
  SqlStorage := TSQLiteStorage.Create(FBasePath);
  try
    SqlStorage.Initialize;
    SqlStorage.SaveNote(Note);
  finally
    SqlStorage.Finalize;
    SqlStorage.Free;
  end;

  Assert.IsTrue(TFile.Exists(TPath.Combine(FBasePath, 'vnotes.db')), 'vnotes.db should exist');

  // Create backup
  Assert.IsTrue(FBackupService.Backup, 'Backup should succeed');
  BackupFile := FBackupService.GetBackupFileName;
  Assert.IsTrue(TFile.Exists(BackupFile), 'Backup file should exist');

  // Extract and verify contents
  TempDir := TPath.Combine(FBasePath, 'extracted_zip');
  ForceDirectories(TempDir);

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

  Assert.IsTrue(TFile.Exists(TPath.Combine(TempDir, 'vnotes.db')),
    'vnotes.db should be packaged inside backup ZIP');
  Assert.IsTrue(TFile.Exists(TPath.Combine(TempDir, 'settings.ini')),
    'settings.ini should be inside backup ZIP');
  Assert.IsTrue(TFile.Exists(TPath.Combine(TempDir, 'manifest.json')),
    'manifest.json should be inside backup ZIP');
end;

procedure TPhase6LReadinessTestFixture.TestSQLiteRestoreValidDb;
var
  Note: TNote;
  SqlStorage: TSQLiteStorage;
  BackupFile: string;
  RestoredNotes: TObjectList<TNote>;
begin
  FSettings.StorageBackend := 'SQLite';
  FSettings.MigrationCompleted := True;
  FStorage := TStorageResolver.ResolveStorage(FBasePath, FSettings);
  FreeAndNil(FBackupService);
  FreeAndNil(FNoteManager);
  FNoteManager := TNoteManager.Create(FStorage);
  FNoteManager.Initialize;
  FBackupService := TBackupService.Create(FNoteManager, FSettings, FBackupPath);

  Note := TNote.Create;
  Note.ID := 101;
  Note.Title := 'SQLite Restore Note';
  Note.Content := 'Verify restore functionality';
  Note.Color := ncPurple;
  Note.Favorite := True;
  Note.AddTag('db_tag');
  FNoteManager.AddNote(Note);

  // Put note in vnotes.db as well
  SqlStorage := TSQLiteStorage.Create(FBasePath);
  try
    SqlStorage.Initialize;
    SqlStorage.SaveNote(Note);
  finally
    SqlStorage.Finalize;
    SqlStorage.Free;
  end;

  Assert.IsTrue(FBackupService.Backup, 'Backup should succeed');
  BackupFile := FBackupService.GetBackupFileName;

  // Wipe vnotes.db and NoteManager
  while FNoteManager.NoteCount > 0 do
    FNoteManager.DeleteNote(FNoteManager.Notes[0].ID);

  FNoteManager.Finalize;
  if TFile.Exists(TPath.Combine(FBasePath, 'vnotes.db')) then
    TFile.Delete(TPath.Combine(FBasePath, 'vnotes.db'));
  FNoteManager.Initialize;

  Assert.AreEqual(0, FNoteManager.NoteCount);

  // Restore backup
  FBackupService.Restore(BackupFile);
  Assert.AreEqual(1, FNoteManager.NoteCount, 'Note should be restored');
  Assert.AreEqual('SQLite Restore Note', FNoteManager.Notes[0].Title);

  // Verify vnotes.db was also restored and is valid
  Assert.IsTrue(TFile.Exists(TPath.Combine(FBasePath, 'vnotes.db')), 'vnotes.db should be restored');
  SqlStorage := TSQLiteStorage.Create(FBasePath);
  try
    SqlStorage.Initialize;
    RestoredNotes := SqlStorage.LoadAllNotes;
    try
      Assert.AreEqual(1, RestoredNotes.Count, 'vnotes.db should contain restored note');
      Assert.AreEqual('SQLite Restore Note', RestoredNotes[0].Title);
    finally
      RestoredNotes.Free;
    end;
  finally
    SqlStorage.Finalize;
    SqlStorage.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestSQLiteRestoreRejectsCorruptDb;
var
  CorruptZip: string;
  TempDir: string;
  Zip: TZipFile;
  CorruptDbPath: string;
  OriginalNote: TNote;
begin
  FSettings.StorageBackend := 'SQLite';
  FSettings.MigrationCompleted := True;

  OriginalNote := TNote.Create;
  OriginalNote.ID := 1;
  OriginalNote.Title := 'Preserved Note';
  FNoteManager.AddNote(OriginalNote);

  // Create corrupt zip with invalid vnotes.db content
  CorruptZip := TPath.Combine(FBackupPath, 'corrupt_db_backup.zip');
  TempDir := TPath.Combine(FBasePath, 'corrupt_builder');
  ForceDirectories(TempDir);

  CorruptDbPath := TPath.Combine(TempDir, 'vnotes.db');
  TFile.WriteAllText(CorruptDbPath, 'THIS IS NOT A REAL SQLITE DATABASE HEADER', TEncoding.UTF8);

  Zip := TZipFile.Create;
  try
    Zip.Open(CorruptZip, zmWrite);
    try
      Zip.Add(CorruptDbPath, 'vnotes.db');
    finally
      Zip.Close;
    end;
  finally
    Zip.Free;
  end;

  FRestoreCount := 0;
  FBackupService.Restore(CorruptZip);

  // Verify restore failed and existing notes were preserved
  Assert.AreEqual(1, FNoteManager.NoteCount, 'Existing notes should be preserved when corrupt DB is rejected');
  Assert.AreEqual('Preserved Note', FNoteManager.Notes[0].Title);
end;

procedure TPhase6LReadinessTestFixture.TestLegacyJsonRestoreMigratesToSQLite;
var
  LegacyZip: string;
  TempDir: string;
  LegacyNoteFile: string;
  Zip: TZipFile;
  AppDbPath: string;
  SqlStorage: TSQLiteStorage;
  NotesList: TObjectList<TNote>;
begin
  FSettings.StorageBackend := 'SQLite';
  FSettings.MigrationCompleted := True;
  FStorage := TStorageResolver.ResolveStorage(FBasePath, FSettings);
  FreeAndNil(FBackupService);
  FreeAndNil(FNoteManager);
  FNoteManager := TNoteManager.Create(FStorage);
  FNoteManager.Initialize;
  FBackupService := TBackupService.Create(FNoteManager, FSettings, FBackupPath);

  // Create a legacy JSON-only backup zip
  LegacyZip := TPath.Combine(FBackupPath, 'legacy_json_backup.zip');
  TempDir := TPath.Combine(FBasePath, 'legacy_builder');
  ForceDirectories(TPath.Combine(TempDir, 'notes'));

  LegacyNoteFile := TPath.Combine(TempDir, 'notes', '0000000005.json');
  TFile.WriteAllText(LegacyNoteFile,
    '{"schemaVersion":3,"ID":5,"Title":"Legacy JSON Note","Content":"Restored from JSON",' +
    '"Color":1,"Left":120,"Top":150,"Width":350,"Height":300,' +
    '"AlwaysOnTop":false,"Collapsed":false,"Locked":false,' +
    '"Favorite":true,"tags":["legacy"],"checklistItems":[],' +
    '"CreatedAt":"2026-09-01T10:00:00","UpdatedAt":"2026-09-01T10:00:00"}',
    TEncoding.UTF8);

  Zip := TZipFile.Create;
  try
    Zip.Open(LegacyZip, zmWrite);
    try
      Zip.Add(LegacyNoteFile, 'notes/0000000005.json');
    finally
      Zip.Close;
    end;
  finally
    Zip.Free;
  end;

  AppDbPath := TPath.Combine(FBasePath, 'vnotes.db');
  FNoteManager.Finalize;
  if TFile.Exists(AppDbPath) then TFile.Delete(AppDbPath);
  FNoteManager.Initialize;

  // Restore legacy zip
  FBackupService.Restore(LegacyZip);
  Assert.AreEqual(1, FNoteManager.NoteCount, 'Note should be restored from legacy zip');
  Assert.AreEqual('Legacy JSON Note', FNoteManager.Notes[0].Title);

  // Verify vnotes.db was automatically created/migrated as part of restore compatibility
  Assert.IsTrue(TFile.Exists(AppDbPath), 'vnotes.db should be created via migration on legacy restore');

  SqlStorage := TSQLiteStorage.Create(FBasePath);
  try
    SqlStorage.Initialize;
    NotesList := SqlStorage.LoadAllNotes;
    try
      Assert.AreEqual(1, NotesList.Count, 'Migrated SQLite database should contain legacy note');
      Assert.AreEqual('Legacy JSON Note', NotesList[0].Title);
      Assert.IsTrue(NotesList[0].Favorite);
    finally
      NotesList.Free;
    end;
  finally
    SqlStorage.Finalize;
    SqlStorage.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestRestoreFailurePreservesExistingDatabase;
var
  AppDbPath: string;
  SqlStorage: TSQLiteStorage;
  Note: TNote;
  BadZip: string;
  NotesList: TObjectList<TNote>;
begin
  // Set up existing valid database
  AppDbPath := TPath.Combine(FBasePath, 'vnotes.db');
  Note := TNote.Create;
  Note.ID := 99;
  Note.Title := 'Original Database Note';
  Note.Content := 'Do not delete me';
  FNoteManager.AddNote(Note);

  SqlStorage := TSQLiteStorage.Create(FBasePath);
  try
    SqlStorage.Initialize;
    SqlStorage.SaveNote(Note);
  finally
    SqlStorage.Finalize;
    SqlStorage.Free;
  end;

  Assert.IsTrue(TFile.Exists(AppDbPath), 'vnotes.db must exist before restore attempt');

  // Attempt restore of non-existent file
  BadZip := TPath.Combine(FBackupPath, 'non_existent_file.zip');
  FBackupService.Restore(BadZip);

  // Verify pre-existing vnotes.db is intact and uncorrupted
  Assert.IsTrue(TFile.Exists(AppDbPath), 'vnotes.db must be preserved on failed restore');
  SqlStorage := TSQLiteStorage.Create(FBasePath);
  try
    SqlStorage.Initialize;
    NotesList := SqlStorage.LoadAllNotes;
    try
      Assert.AreEqual(1, NotesList.Count, 'vnotes.db should still contain original note');
      Assert.AreEqual('Original Database Note', NotesList[0].Title);
    finally
      NotesList.Free;
    end;
  finally
    SqlStorage.Finalize;
    SqlStorage.Free;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestProductionBackendIsJsonInNoteApplication;
var
  App: TNoteApplication;
  AppDataPath, SettingsFile, BakFile, DbFile, DbBakFile, NotesDir, NotesBakDir: string;
  PathBuf: array[0..MAX_PATH] of Char;
begin
  if Winapi.ShlObj.SHGetFolderPath(0, CSIDL_APPDATA, 0, SHGFP_TYPE_CURRENT, @PathBuf[0]) = S_OK then
    AppDataPath := TPath.Combine(PathBuf, 'StickyNotes')
  else
    AppDataPath := TPath.Combine(TPath.GetTempPath, 'StickyNotes');

  SettingsFile := TPath.Combine(AppDataPath, 'settings.ini');
  BakFile := SettingsFile + '.testbak';
  DbFile := TPath.Combine(AppDataPath, 'vnotes.db');
  DbBakFile := DbFile + '.testbak';
  NotesDir := TPath.Combine(AppDataPath, 'notes');
  NotesBakDir := NotesDir + '.testbak';

  if TFile.Exists(SettingsFile) then
    TFile.Move(SettingsFile, BakFile);
  if TFile.Exists(DbFile) then
    TFile.Move(DbFile, DbBakFile);
  if TDirectory.Exists(NotesDir) then
    TDirectory.Move(NotesDir, NotesBakDir);
  try
    App := TNoteApplication.Create(0);
    try
      Assert.IsNotNull(App.NoteManager, 'NoteManager should not be nil');
      Assert.AreEqual('SQLite', App.Settings.StorageBackend, 'Production StorageBackend is SQLite in Phase 6M');
      Assert.IsTrue(App.Settings.MigrationCompleted, 'Production MigrationCompleted is True in Phase 6M');
    finally
      App.Free;
    end;
  finally
    if TFile.Exists(BakFile) then
    begin
      if TFile.Exists(SettingsFile) then TFile.Delete(SettingsFile);
      TFile.Move(BakFile, SettingsFile);
    end;
    if TFile.Exists(DbBakFile) then
    begin
      if TFile.Exists(DbFile) then TFile.Delete(DbFile);
      TFile.Move(DbBakFile, DbFile);
    end;
    if TDirectory.Exists(NotesBakDir) then
    begin
      if TDirectory.Exists(NotesDir) then TDirectory.Delete(NotesDir, True);
      TDirectory.Move(NotesBakDir, NotesDir);
    end;
  end;
end;

procedure TPhase6LReadinessTestFixture.TestRestoreCleansUpOrphanedSidecarFiles;
var
  AppDbPath: string;
  WalPath, ShmPath, JournalPath: string;
  Note: TNote;
  BackupFile: string;
begin
  FSettings.StorageBackend := 'SQLite';
  FSettings.MigrationCompleted := True;

  Note := TNote.Create;
  Note.Title := 'Sidecar Cleanup Note';
  FNoteManager.AddNote(Note);

  Assert.IsTrue(FBackupService.Backup, 'Backup should succeed');
  BackupFile := FBackupService.GetBackupFileName;

  // Create orphaned sidecar files in FBasePath
  AppDbPath := TPath.Combine(FBasePath, 'vnotes.db');
  WalPath := AppDbPath + '-wal';
  ShmPath := AppDbPath + '-shm';
  JournalPath := AppDbPath + '-journal';

  TFile.WriteAllText(WalPath, 'dummy wal', TEncoding.UTF8);
  TFile.WriteAllText(ShmPath, 'dummy shm', TEncoding.UTF8);
  TFile.WriteAllText(JournalPath, 'dummy journal', TEncoding.UTF8);

  Assert.IsTrue(TFile.Exists(WalPath), 'WAL file should exist before restore');
  Assert.IsTrue(TFile.Exists(ShmPath), 'SHM file should exist before restore');
  Assert.IsTrue(TFile.Exists(JournalPath), 'Journal file should exist before restore');

  // Perform restore
  FBackupService.Restore(BackupFile);

  // Assert sidecar files were cleaned up during database replacement
  Assert.IsFalse(TFile.Exists(WalPath), 'Orphaned WAL file should be removed on restore');
  Assert.IsFalse(TFile.Exists(ShmPath), 'Orphaned SHM file should be removed on restore');
  Assert.IsFalse(TFile.Exists(JournalPath), 'Orphaned Journal file should be removed on restore');
end;

initialization
  TDUnitX.RegisterTestFixture(TPhase6LReadinessTestFixture);

end.
