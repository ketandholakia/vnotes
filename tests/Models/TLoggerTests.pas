unit TLoggerTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  DUnitX.TestFramework,
  uILogger;

type
  [TestFixture]
  TLoggerTestFixture = class
  private
    FLogPath: string;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure WritesToConfiguredFile;
    [Test]
    procedure IncludesTimestampLevelAndMessage;
    [Test]
    procedure GetLogFilePathReflectsConfiguration;
    [Test]
    procedure BlankPathDisablesFileOutput;
  end;

implementation

procedure TLoggerTestFixture.SetUp;
begin
  FLogPath := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_LoggerTest_' + IntToStr(TThread.GetTickCount) + '.log');
  ConfigureLogFile(FLogPath);
end;

procedure TLoggerTestFixture.TearDown;
begin
  // Never leak file routing into other fixtures.
  ConfigureLogFile('');
  if TFile.Exists(FLogPath) then
    TFile.Delete(FLogPath);
  if TFile.Exists(FLogPath + '.1') then
    TFile.Delete(FLogPath + '.1');
end;

procedure TLoggerTestFixture.WritesToConfiguredFile;
var
  Logger: ILogger;
begin
  Logger := CreateLogger;
  Logger.Info('hello-from-test');
  Assert.IsTrue(TFile.Exists(FLogPath), 'log file should be created');
  Assert.IsTrue(TFile.ReadAllText(FLogPath).Contains('hello-from-test'),
    'log file should contain the emitted message');
end;

procedure TLoggerTestFixture.IncludesTimestampLevelAndMessage;
var
  Logger: ILogger;
  Text: string;
begin
  Logger := CreateLogger;
  Logger.Warning('warn-msg');
  Text := TFile.ReadAllText(FLogPath);
  Assert.IsTrue(Text.Contains('[WARNING]'), 'level tag should be present');
  Assert.IsTrue(Text.Contains('warn-msg'), 'message should be present');
  // A timestamp of the form [yyyy-mm-dd hh:nn:ss.
  Assert.IsTrue(Text.Contains('[' + FormatDateTime('yyyy-mm-dd', Now)),
    'a timestamp should be present');
end;

procedure TLoggerTestFixture.GetLogFilePathReflectsConfiguration;
begin
  Assert.AreEqual<string>(FLogPath, GetLogFilePath);
  ConfigureLogFile('');
  Assert.AreEqual<string>('', GetLogFilePath, 'blank path should clear the file sink');
end;

procedure TLoggerTestFixture.BlankPathDisablesFileOutput;
var
  Logger: ILogger;
begin
  ConfigureLogFile('');
  Logger := CreateLogger;
  Logger.Error('should-not-be-written');
  Assert.IsFalse(TFile.Exists(FLogPath), 'no file should be written when disabled');
end;

initialization
  TDUnitX.RegisterTestFixture(TLoggerTestFixture);

end.
