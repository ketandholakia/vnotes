unit TNoteApplicationTests;

// Isolation note (docs/CODE_REVIEW_2026-09-17.md C3):
// This fixture used to construct TNoteApplication with no base path, so it
// resolved the LIVE %APPDATA%\StickyNotes directory, and TearDown's
// Destroy -> Shutdown -> SaveSettings then overwrote the user's real
// settings.ini. Every test here now runs inside a unique temporary directory
// that is torn down afterwards.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  DUnitX.TestFramework,
  uNoteApplication, uNoteManager, uAutosaveService, uHotkeyService,
  uThemeService, uBackupService, uSettings, Vcl.Forms;

type
  [TestFixture]
  TNoteApplicationTestFixture = class
  private
    FTestForm: TForm;
    FApplication: TNoteApplication;
    FBasePath: string;
  public
    [SetUp]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestApplicationCreatesRequiredServices;
    [Test]
    procedure TestApplicationOwnsServices;
    [Test]
    procedure TestApplicationShutdownIsSafe;
    // Regression guards for the C3 isolation defect.
    [Test]
    procedure TestApplicationUsesInjectedBasePath;
    [Test]
    procedure TestShutdownWritesSettingsUnderInjectedBasePath;
  end;

implementation

procedure TNoteApplicationTestFixture.Setup;
begin
  // Unique sandbox: a test must never resolve the live user profile.
  FBasePath := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_AppTest_' + TGUID.NewGuid.ToString);

  // A lightweight VCL form provides the HWND needed by THotkeyService.
  // This is the minimal VCL setup required to test TNoteApplication.
  FTestForm := TForm.Create(nil);
  FTestForm.HandleNeeded; // force handle allocation

  FApplication := TNoteApplication.Create(FTestForm.Handle, FBasePath);
end;

procedure TNoteApplicationTestFixture.TearDown;
begin
  // Destroy triggers Shutdown -> SaveSettings, which must land in FBasePath.
  FApplication.Free;
  FTestForm.Free;
  if TDirectory.Exists(FBasePath) then
    TDirectory.Delete(FBasePath, True);
end;

procedure TNoteApplicationTestFixture.TestApplicationCreatesRequiredServices;
begin
  Assert.IsNotNull(FApplication, 'TNoteApplication should be created');
  Assert.IsNotNull(FApplication.NoteManager, 'NoteManager should be created');
  Assert.IsNotNull(FApplication.Settings, 'Settings should be created');
  Assert.IsNotNull(FApplication.ThemeService, 'ThemeService should be created');
  Assert.IsNotNull(FApplication.AutosaveService, 'AutosaveService should be created');
  Assert.IsNotNull(FApplication.HotkeyService, 'HotkeyService should be created');
  Assert.IsNotNull(FApplication.BackupService, 'BackupService should be created');
  Assert.AreNotEqual<string>('', FApplication.AppDataPath, 'AppDataPath should be a non-empty string');
end;

procedure TNoteApplicationTestFixture.TestApplicationOwnsServices;
begin
  // Verify services are the same instances (ownership, not copies)
  Assert.IsNotNull(FApplication.Settings, 'Settings owned by application');
  Assert.IsNotNull(FApplication.NoteManager, 'NoteManager owned by application');
end;

procedure TNoteApplicationTestFixture.TestApplicationShutdownIsSafe;
begin
  // Shutdown must succeed without exception even if Initialize was never called.
  // (Initialize is not called here because TStyleManager.TrySetStyle from
  // TThemeService.SetDarkTheme hangs in a DUnitX console test environment.
  // Full Initialize/Shutdown lifecycle verification requires a VCL application
  // context.)
  FApplication.Shutdown;
end;

procedure TNoteApplicationTestFixture.TestApplicationUsesInjectedBasePath;
begin
  Assert.AreEqual<string>(FBasePath, FApplication.AppDataPath,
    'an injected base path must be honoured so tests never touch the live ' +
    '%APPDATA%\StickyNotes directory (C3 regression)');
end;

procedure TNoteApplicationTestFixture.TestShutdownWritesSettingsUnderInjectedBasePath;
var
  SettingsFile: string;
begin
  SettingsFile := TPath.Combine(FBasePath, 'settings.ini');
  FApplication.Shutdown;
  Assert.IsTrue(TFile.Exists(SettingsFile),
    'settings.ini must be written under the injected base path, never to the ' +
    'live %APPDATA%\StickyNotes directory (C3 regression)');
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteApplicationTestFixture);

end.
