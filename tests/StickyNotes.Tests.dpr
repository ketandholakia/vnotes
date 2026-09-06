program StickyNotes.Tests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.AutoDetect.Console,
  TNoteTests in 'Models\TNoteTests.pas',
  TSettingsTests in 'Models\TSettingsTests.pas',
  TJsonStorageTests in 'Models\TJsonStorageTests.pas',
  TSQLiteStorageTests in 'Models\TSQLiteStorageTests.pas',
  TAutosaveServiceTests in 'Models\TAutosaveServiceTests.pas',
  TNoteApplicationTests in 'Models\TNoteApplicationTests.pas',
  TNoteManagerTests in 'Models\TNoteManagerTests.pas',
  TNoteQueryTests in 'Models\TNoteQueryTests.pas',
  TSingleInstanceTests in 'Models\TSingleInstanceTests.pas',
  TBackupSchedulerTests in 'Models\TBackupSchedulerTests.pas',
  TBackupServiceTests in 'Models\TBackupServiceTests.pas',
  TMonitorUtilsTests in 'Models\TMonitorUtilsTests.pas',
  TStorageMigrationServiceTests in 'Models\TStorageMigrationServiceTests.pas',
  TPhase6LReadinessTests in 'Models\TPhase6LReadinessTests.pas',
  uStorageMigrationOrchestrator in '..\src\Services\uStorageMigrationOrchestrator.pas',
  TPhase6MActivationTests in 'Models\TPhase6MActivationTests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
begin
  try
    // Check command line options
    TDUnitX.CheckCommandLine;

    // Create the test runner
    runner := TDUnitX.CreateRunner;

    // Tell the runner to use RTTI to find fixtures
    runner.UseRTTI := True;

    // Add a console logger
    logger := TDUnitXConsoleLogger.Create;
    runner.AddLogger(logger);

    // Run tests
    results := runner.Execute;

    // Output results
    System.Writeln(Format('Tests run: %d, Passed: %d, Failed: %d, Errors: %d, Skipped: %d',
      [results.GetTestCount, results.GetPassCount, results.GetFailureCount, results.GetErrorCount, results.GetIgnoredCount]));

    // Exit with appropriate code
    if results.GetAllPassed then
      System.ExitCode := 0
    else
      System.ExitCode := 1;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.