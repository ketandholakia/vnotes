unit TSyncIntegrationTests;

// End-to-end smoke test of the sync wiring.
//
// Everything else tests the pieces in isolation; these tests drive the REAL
// composition root (TNoteApplication) exactly as the app does: it reads
// settings.ini from an isolated profile directory, builds the storage, the sync
// engine, the runner and the scheduler, and then two independent profiles are
// synced against one shared remote folder - a genuine two-device round trip.
//
// TNoteApplication.Initialize is deliberately NOT called: it applies a VCL style
// via TStyleManager, which is documented to hang in a console test host (the
// reason the suite has TestApplicationShutdownIsSafe instead of
// TestApplicationInitializeShutdown). Create() alone performs the wiring under
// test here, and notes can be created directly through the note manager.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  DUnitX.TestFramework,
  uSettings, uNote, uEnums, uNoteApplication, uServiceInterfaces;

type
  [TestFixture]
  TSyncIntegrationTestFixture = class
  private
    FBase: string;
    FRemote: string;
    function NewProfile(const AName: string): string;
    procedure WriteSyncSettings(const ABasePath, ABackend, AFolder, AUrl: string;
      AEnabled: Boolean);
    function RemoteNoteCount: Integer;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCompositionRootBuildsSyncService;
    [Test]
    procedure TestSyncDisabledBuildsNoService;
    [Test]
    procedure TestWebDavBackendIsSelected;
    [Test]
    procedure TestTwoProfilesRoundTripThroughSharedFolder;
  end;

implementation

procedure TSyncIntegrationTestFixture.SetUp;
begin
  FBase := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_IntegrationTest_' + IntToStr(TThread.GetTickCount));
  FRemote := TPath.Combine(FBase, 'remote');
  ForceDirectories(FBase);
  ForceDirectories(FRemote);
end;

procedure TSyncIntegrationTestFixture.TearDown;
begin
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

function TSyncIntegrationTestFixture.NewProfile(const AName: string): string;
begin
  Result := TPath.Combine(FBase, AName);
  ForceDirectories(Result);
end;

procedure TSyncIntegrationTestFixture.WriteSyncSettings(const ABasePath, ABackend,
  AFolder, AUrl: string; AEnabled: Boolean);
var
  S: TSettings;
begin
  S := TSettings.Create;
  try
    S.SyncEnabled := AEnabled;
    S.SyncBackendType := ABackend;
    S.SyncFolder := AFolder;
    S.SyncWebDavUrl := AUrl;
    S.SyncIntervalMinutes := 5;
    S.SaveToFile(TPath.Combine(ABasePath, 'settings.ini'));
  finally
    S.Free;
  end;
end;

function TSyncIntegrationTestFixture.RemoteNoteCount: Integer;
var
  NotesDir: string;
begin
  NotesDir := TPath.Combine(FRemote, 'notes');
  if not TDirectory.Exists(NotesDir) then
    Exit(0);
  Result := Length(TDirectory.GetFiles(NotesDir, '*.json'));
end;

procedure TSyncIntegrationTestFixture.TestCompositionRootBuildsSyncService;
var
  Profile: string;
  App: TNoteApplication;
begin
  Profile := NewProfile('a');
  WriteSyncSettings(Profile, 'folder', FRemote, '', True);

  App := TNoteApplication.Create(0, Profile);
  try
    Assert.IsNotNull(App.SyncService, 'a configured folder sync must build a sync service');
    Assert.IsNotNull(App.SyncRunner, 'a configured sync must build a runner');
    Assert.IsNotNull(App.SyncScheduler, 'a configured sync must build a scheduler');
  finally
    App.Free;
  end;
end;

procedure TSyncIntegrationTestFixture.TestSyncDisabledBuildsNoService;
var
  Profile: string;
  App: TNoteApplication;
begin
  Profile := NewProfile('b');
  WriteSyncSettings(Profile, 'folder', FRemote, '', False);

  App := TNoteApplication.Create(0, Profile);
  try
    Assert.IsNull(App.SyncService, 'sync disabled must not build a sync service');
    Assert.IsNull(App.SyncScheduler);
  finally
    App.Free;
  end;
end;

procedure TSyncIntegrationTestFixture.TestWebDavBackendIsSelected;
var
  Profile: string;
  App: TNoteApplication;
begin
  Profile := NewProfile('c');
  WriteSyncSettings(Profile, 'webdav', '', 'https://dav.example.invalid/notes', True);

  App := TNoteApplication.Create(0, Profile);
  try
    // The backend is only exercised on SyncNow; here we assert the wiring chose
    // the WebDAV path (a folder backend would leave SyncFolder empty => no service).
    Assert.IsNotNull(App.SyncService, 'the WebDAV backend must be selected from settings');
  finally
    App.Free;
  end;
end;

procedure TSyncIntegrationTestFixture.TestTwoProfilesRoundTripThroughSharedFolder;
var
  ProfileA, ProfileB: string;
  AppA, AppB: TNoteApplication;
begin
  ProfileA := NewProfile('deviceA');
  ProfileB := NewProfile('deviceB');
  WriteSyncSettings(ProfileA, 'folder', FRemote, '', True);
  WriteSyncSettings(ProfileB, 'folder', FRemote, '', True);

  AppA := TNoteApplication.Create(0, ProfileA);
  try
    // Device A creates a note and publishes it.
    AppA.NoteManager.CreateNote('From device A', 'hello', ncYellow, 10, 10, 300, 200, False);
    Assert.IsTrue(AppA.SyncService.SyncNow, 'device A sync should succeed');
    Assert.AreEqual<Integer>(1, RemoteNoteCount, 'device A note must reach the remote');

    // Device B starts empty and pulls it.
    AppB := TNoteApplication.Create(0, ProfileB);
    try
      Assert.AreEqual<Integer>(0, AppB.NoteManager.NoteCount, 'device B starts empty');
      Assert.IsTrue(AppB.SyncService.SyncNow, 'device B sync should succeed');
      Assert.AreEqual<Integer>(1, AppB.NoteManager.NoteCount, 'device B must pull the remote note');
      Assert.AreEqual<string>('From device A', AppB.NoteManager.Notes[0].Title);

      // Device B edits its copy with a higher revision and publishes; A pulls it.
      AppB.NoteManager.Notes[0].Content := 'edited on B';
      AppB.NoteManager.Notes[0].Rev := 50;
      AppB.NoteManager.PersistNote(AppB.NoteManager.Notes[0]);
      Assert.IsTrue(AppB.SyncService.SyncNow, 'device B re-sync should succeed');

      Assert.IsTrue(AppA.SyncService.SyncNow, 'device A re-sync should succeed');
      Assert.AreEqual<string>('edited on B', AppA.NoteManager.Notes[0].Content,
        'the higher revision must propagate back to device A');
    finally
      AppB.Free;
    end;
  finally
    AppA.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncIntegrationTestFixture);

end.
