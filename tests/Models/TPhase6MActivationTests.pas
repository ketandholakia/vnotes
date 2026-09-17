unit TPhase6MActivationTests;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  System.Generics.Collections, System.DateUtils, System.Types,
  uNote, uStorage, uJsonStorage, uSQLiteStorage, uSettings, uEnums,
  uStorageMigrationService, uStorageMigrationOrchestrator, uBackupService, uNoteManager;

type
  [TestFixture]
  TPhase6MActivationTestFixture = class
  private
    FTempDir: string;
    FSettingsFile: string;
    FSettings: TSettings;
    function CreateSampleNote(AID: Integer; const ATitle: string): TNote;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestExistingJsonMigrationActivation;
    [Test]
    procedure TestRepeatedStartup;
    [Test]
    procedure TestFreshInstall;
    [Test]
    procedure TestEmptyJsonInstallation;
    [Test]
    procedure TestInterruptedMigrationRecovery;
    [Test]
    procedure TestDivergentPreExistingDatabaseQuarantine;
    [Test]
    procedure TestActivatedSQLiteMissingDbFailsNoFallback;
    [Test]
    procedure TestActivatedSQLiteCorruptDbFailsNoFallback;
    [Test]
    procedure TestBackupAndRestoreWithSQLitePrimary;
    [Test]
    procedure TestLegacyJsonBackupRestoreMaintainsSQLiteBackend;
  end;

implementation

function TPhase6MActivationTestFixture.CreateSampleNote(AID: Integer; const ATitle: string): TNote;
var
  Item: TChecklistItem;
  TagsArr: TArray<string>;
  ItemsArr: TArray<TChecklistItem>;
begin
  Result := TNote.Create;
  Result.ID := AID;
  Result.Title := ATitle;
  Result.Content := 'Content for ' + ATitle;
  Result.Color := ncBlue;
  Result.Left := 100;
  Result.Top := 150;
  Result.Width := 350;
  Result.Height := 280;
  Result.AlwaysOnTop := True;
  Result.Collapsed := False;
  Result.Locked := False;
  Result.Favorite := True;
  Result.CreatedAt := Now;
  Result.UpdatedAt := Now;

  SetLength(TagsArr, 1);
  TagsArr[0] := 'Work';
  Result.Tags := TagsArr;

  Item.Text := 'Task 1';
  Item.Done := True;
  SetLength(ItemsArr, 1);
  ItemsArr[0] := Item;
  Result.ChecklistItems := ItemsArr;
end;

procedure TPhase6MActivationTestFixture.SetUp;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VNotes_Phase6M_Tests_' + GUIDToString(TGUID.NewGuid));
  TDirectory.CreateDirectory(FTempDir);
  FSettingsFile := TPath.Combine(FTempDir, 'settings.ini');
  FSettings := TSettings.Create;
end;

procedure TPhase6MActivationTestFixture.TearDown;
begin
  FSettings.Free;
  if TDirectory.Exists(FTempDir) then
  begin
    try
      TDirectory.Delete(FTempDir, True);
    except
      // Ignore cleanup exceptions in temporary test folders
    end;
  end;
end;

procedure TPhase6MActivationTestFixture.TestExistingJsonMigrationActivation;
var
  JsonStorage: TJsonStorage;
  Note1, Note2: TNote;
  Storage: INoteStorage;
  LoadedNotes: TObjectList<TNote>;
  NotesPath: string;
begin
  NotesPath := TPath.Combine(FTempDir, 'notes');
  TDirectory.CreateDirectory(NotesPath);

  JsonStorage := TJsonStorage.Create(FTempDir);
  try
    JsonStorage.Initialize;
    Note1 := CreateSampleNote(1, 'First JSON Note');
    try
      JsonStorage.SaveNote(Note1);
    finally
      Note1.Free;
    end;
    Note2 := CreateSampleNote(2, 'Second JSON Note');
    try
      JsonStorage.SaveNote(Note2);
    finally
      Note2.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  Assert.IsFalse(FSettings.MigrationCompleted);
  Assert.AreEqual('JSON', FSettings.StorageBackend);

  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);

  Assert.IsTrue(Storage is TSQLiteStorage);
  Assert.IsTrue(FSettings.MigrationCompleted);
  Assert.AreEqual('SQLite', FSettings.StorageBackend);
  Assert.IsTrue(FSettings.MigrationTimestamp <> '');
  Assert.IsTrue(TFile.Exists(FSettingsFile));

  // Verify original JSON files are untouched
  Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(NotesPath, '*.json'))));

  LoadedNotes := Storage.LoadAllNotes;
  try
    Assert.AreEqual(2, Integer(LoadedNotes.Count));
  finally
    LoadedNotes.Free;
  end;
end;

procedure TPhase6MActivationTestFixture.TestRepeatedStartup;
var
  JsonStorage: TJsonStorage;
  Note1: TNote;
  Storage1, Storage2: INoteStorage;
  LoadedNotes: TObjectList<TNote>;
begin
  JsonStorage := TJsonStorage.Create(FTempDir);
  try
    JsonStorage.Initialize;
    Note1 := CreateSampleNote(1, 'Single Note');
    try
      JsonStorage.SaveNote(Note1);
    finally
      Note1.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  Storage1 := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);
  Assert.IsTrue(Storage1 is TSQLiteStorage);

  // Second startup with populated settings
  Storage2 := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);
  Assert.IsTrue(Storage2 is TSQLiteStorage);

  LoadedNotes := Storage2.LoadAllNotes;
  try
    Assert.AreEqual(1, Integer(LoadedNotes.Count));
  finally
    LoadedNotes.Free;
  end;
end;

procedure TPhase6MActivationTestFixture.TestFreshInstall;
var
  Storage: INoteStorage;
  DbPath: string;
begin
  DbPath := TPath.Combine(FTempDir, 'vnotes.db');
  Assert.IsFalse(TFile.Exists(DbPath));

  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);

  Assert.IsTrue(Storage is TSQLiteStorage);
  Assert.IsTrue(FSettings.MigrationCompleted);
  Assert.AreEqual('SQLite', FSettings.StorageBackend);
  Assert.IsTrue(TFile.Exists(DbPath));
end;

procedure TPhase6MActivationTestFixture.TestEmptyJsonInstallation;
var
  NotesPath: string;
  Storage: INoteStorage;
begin
  NotesPath := TPath.Combine(FTempDir, 'notes');
  TDirectory.CreateDirectory(NotesPath);

  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);

  Assert.IsTrue(Storage is TSQLiteStorage);
  Assert.IsTrue(FSettings.MigrationCompleted);
  Assert.AreEqual('SQLite', FSettings.StorageBackend);
end;

procedure TPhase6MActivationTestFixture.TestInterruptedMigrationRecovery;
var
  JsonStorage: TJsonStorage;
  Note1: TNote;
  MigRes: TMigrationResult;
  Storage: INoteStorage;
  LoadedNotes: TObjectList<TNote>;
begin
  JsonStorage := TJsonStorage.Create(FTempDir);
  try
    JsonStorage.Initialize;
    Note1 := CreateSampleNote(1, 'Interrupted Note');
    try
      JsonStorage.SaveNote(Note1);
    finally
      Note1.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  // Run migration service directly so vnotes.db exists with matching content
  MigRes := TStorageMigrationService.MigrateJsonToSQLite(FTempDir);
  Assert.IsTrue(MigRes.Success);

  // Leave FSettings unupdated (simulating crash before settings.ini save)
  FSettings.MigrationCompleted := False;
  FSettings.StorageBackend := 'JSON';

  // Orchestration must reconcile matching DB without duplicating notes
  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);

  Assert.IsTrue(Storage is TSQLiteStorage);
  Assert.IsTrue(FSettings.MigrationCompleted);
  Assert.AreEqual('SQLite', FSettings.StorageBackend);

  LoadedNotes := Storage.LoadAllNotes;
  try
    Assert.AreEqual(1, Integer(LoadedNotes.Count));
  finally
    LoadedNotes.Free;
  end;
end;

procedure TPhase6MActivationTestFixture.TestDivergentPreExistingDatabaseQuarantine;
var
  JsonStorage: TJsonStorage;
  SqlStorage: TSQLiteStorage;
  Note1, NoteDivergent: TNote;
  Storage: INoteStorage;
  LoadedNotes: TObjectList<TNote>;
  OrphanFiles: TStringDynArray;
begin
  // Create JSON note ID=1
  JsonStorage := TJsonStorage.Create(FTempDir);
  try
    JsonStorage.Initialize;
    Note1 := CreateSampleNote(1, 'Original JSON Note');
    try
      JsonStorage.SaveNote(Note1);
    finally
      Note1.Free;
    end;
  finally
    JsonStorage.Free;
  end;

  // Create SQLite DB note ID=99 (divergent data)
  SqlStorage := TSQLiteStorage.Create(FTempDir);
  try
    SqlStorage.Initialize;
    NoteDivergent := CreateSampleNote(99, 'Divergent Note');
    try
      SqlStorage.SaveNote(NoteDivergent);
    finally
      NoteDivergent.Free;
    end;
  finally
    SqlStorage.Free;
  end;

  // MigrationCompleted = False
  FSettings.MigrationCompleted := False;
  FSettings.StorageBackend := 'JSON';

  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);

  Assert.IsTrue(Storage is TSQLiteStorage);
  Assert.IsTrue(FSettings.MigrationCompleted);

  // Check that divergent database was quarantined
  OrphanFiles := TDirectory.GetFiles(FTempDir, 'vnotes.db.orphan.*');
  Assert.IsTrue(Length(OrphanFiles) > 0);

  // Check active SQLite storage contains only the migrated JSON note ID=1
  LoadedNotes := Storage.LoadAllNotes;
  try
    Assert.AreEqual(1, LoadedNotes.Count);
    Assert.AreEqual(1, Integer(LoadedNotes[0].ID));
  finally
    LoadedNotes.Free;
  end;
end;

procedure TPhase6MActivationTestFixture.TestActivatedSQLiteMissingDbFailsNoFallback;
var
  DbPath: string;
  Failed: Boolean;
begin
  FSettings.StorageBackend := 'SQLite';
  FSettings.MigrationCompleted := True;

  DbPath := TPath.Combine(FTempDir, 'vnotes.db');
  if TFile.Exists(DbPath) then TFile.Delete(DbPath);

  Failed := False;
  try
    TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);
  except
    on E: ESQLiteActivationException do
      Failed := True;
  end;

  Assert.IsTrue(Failed);
end;

procedure TPhase6MActivationTestFixture.TestActivatedSQLiteCorruptDbFailsNoFallback;
var
  DbPath: string;
  Failed: Boolean;
begin
  FSettings.StorageBackend := 'SQLite';
  FSettings.MigrationCompleted := True;

  DbPath := TPath.Combine(FTempDir, 'vnotes.db');
  TFile.WriteAllText(DbPath, 'Corrupt Garbage Data Not SQLite');

  Failed := False;
  try
    TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);
  except
    on E: ESQLiteActivationException do
      Failed := True;
  end;

  Assert.IsTrue(Failed);
end;

procedure TPhase6MActivationTestFixture.TestBackupAndRestoreWithSQLitePrimary;
var
  Storage: INoteStorage;
  NoteManager: TNoteManager;
  BackupService: TBackupService;
  BackupsDir, BackupPath: string;
  Note1: TNote;
  LoadedNotes: TObjectList<TNote>;
begin
  // Initialize fresh SQLite production storage
  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);

  NoteManager := TNoteManager.Create(Storage);
  try
    NoteManager.Initialize;

    Note1 := CreateSampleNote(10, 'Active SQLite Note');
    // AddNote (not SaveNote): SaveNote persists manager-owned notes only
    // (anti-resurrection guard), so a note must be added to the manager
    // before it can be saved. AddNote transfers ownership to the manager.
    NoteManager.AddNote(Note1);

    BackupsDir := TPath.Combine(FTempDir, 'backups');
    BackupService := TBackupService.Create(NoteManager, FSettings, BackupsDir, FTempDir);
    try
      Assert.IsTrue(BackupService.Backup);
      BackupPath := BackupService.GetBackupFileName;
      Assert.IsTrue(TFile.Exists(BackupPath));

      // Delete note 10
      NoteManager.DeleteNote(10);
      Assert.AreEqual(0, NoteManager.NoteCount);

      // Restore backup
      BackupService.Restore(BackupPath);

      // Reload notes
      LoadedNotes := Storage.LoadAllNotes;
      try
        Assert.AreEqual(1, LoadedNotes.Count);
        Assert.AreEqual(10, Integer(LoadedNotes[0].ID));
      finally
        LoadedNotes.Free;
      end;
    finally
      BackupService.Free;
    end;
  finally
    NoteManager.Free;
  end;
end;

procedure TPhase6MActivationTestFixture.TestLegacyJsonBackupRestoreMaintainsSQLiteBackend;
var
  Storage: INoteStorage;
  NoteManager: TNoteManager;
  BackupService: TBackupService;
  BackupsDir, ZipPath, JsonPath: string;
  JsonNotesDir: string;
  Note1: TNote;
  LoadedNotes: TObjectList<TNote>;
  Zip: TZipFile;
begin
  // Initialize active SQLite production backend
  Storage := TStorageMigrationOrchestrator.OrchestrateStorage(FTempDir, FSettings, FSettingsFile);
  Assert.AreEqual('SQLite', FSettings.StorageBackend);

  // Prepare a legacy JSON zip backup manually
  JsonNotesDir := TPath.Combine(FTempDir, 'legacy_notes');
  TDirectory.CreateDirectory(JsonNotesDir);

  Note1 := CreateSampleNote(55, 'Legacy Backup Note');
  try
    JsonPath := TPath.Combine(JsonNotesDir, 'note_55.json');
    TFile.WriteAllText(JsonPath, Format('{"id":55,"title":"Legacy Backup Note","content":"Content","color":0,"left":0,"top":0,"width":300,"height":250,"always_on_top":false,"collapsed":false,"locked":false,"favorite":false,"created_at":"2026-09-06T12:00:00.000Z","updated_at":"2026-09-06T12:00:00.000Z","tags":[],"checklist":[]}', []));
  finally
    Note1.Free;
  end;

  BackupsDir := TPath.Combine(FTempDir, 'backups');
  TDirectory.CreateDirectory(BackupsDir);
  ZipPath := TPath.Combine(BackupsDir, 'legacy_backup.zip');

  // Zip the legacy notes folder
  Zip := TZipFile.Create;
  try
    Zip.Open(ZipPath, zmWrite);
    Zip.Add(JsonPath, 'notes/note_55.json');
  finally
    Zip.Free;
  end;

  NoteManager := TNoteManager.Create(Storage);
  try
    NoteManager.Initialize;
    BackupService := TBackupService.Create(NoteManager, FSettings, BackupsDir, FTempDir);
    try
      // Restore legacy JSON backup
      BackupService.Restore(ZipPath);

      // Verify active storage is STILL SQLite and note 55 was imported
      Assert.AreEqual('SQLite', FSettings.StorageBackend);
      Assert.IsTrue(FSettings.MigrationCompleted);

      LoadedNotes := Storage.LoadAllNotes;
      try
        Assert.AreEqual(1, LoadedNotes.Count);
        Assert.AreEqual(55, Integer(LoadedNotes[0].ID));
      finally
        LoadedNotes.Free;
      end;
    finally
      BackupService.Free;
    end;
  finally
    NoteManager.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPhase6MActivationTestFixture);

end.
