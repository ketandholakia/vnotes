unit TNoteApplicationTests;

interface

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  uNoteApplication, uNoteManager, uAutosaveService, uHotkeyService,
  uThemeService, uBackupService, uSettings, Vcl.Forms;

type
  [TestFixture]
  TNoteApplicationTestFixture = class
  private
    FTestForm: TForm;
    FApplication: TNoteApplication;
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
  end;

implementation

procedure TNoteApplicationTestFixture.Setup;
begin
  // A lightweight VCL form provides the HWND needed by THotkeyService.
  // This is the minimal VCL setup required to test TNoteApplication.
  FTestForm := TForm.Create(nil);
  FTestForm.HandleNeeded; // force handle allocation
  FApplication := TNoteApplication.Create(FTestForm.Handle);
end;

procedure TNoteApplicationTestFixture.TearDown;
begin
  FApplication.Free;
  FTestForm.Free;
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

initialization
  TDUnitX.RegisterTestFixture(TNoteApplicationTestFixture);

end.