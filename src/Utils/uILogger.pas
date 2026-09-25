unit uILogger;

interface

type
  ILogger = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warning(const AMessage: string);
    procedure Error(const AMessage: string);
  end;

  function CreateLogger: ILogger;

  // Routes every logger instance to a file, in addition to OutputDebugString.
  // Call once at application startup with e.g. <AppData>\vnotes.log so crash /
  // telemetry output survives the process (OutputDebugString alone is invisible
  // unless a debugger is attached). Pass '' to disable file output.
  // Safe to call more than once; the last call wins. Thread-safe.
  procedure ConfigureLogFile(const ALogFilePath: string);

  // The active file sink path ('' when disabled). Exposed for tests/diagnostics.
  function GetLogFilePath: string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs,
  System.IOUtils;

const
  MaxLogBytes = 2 * 1024 * 1024; // rotate once at ~2 MB

var
  GLogFilePath: string = '';
  GLogLock: TCriticalSection;

procedure ConfigureLogFile(const ALogFilePath: string);
begin
  GLogLock.Enter;
  try
    GLogFilePath := ALogFilePath;
  finally
    GLogLock.Leave;
  end;
end;

function GetLogFilePath: string;
begin
  GLogLock.Enter;
  try
    Result := GLogFilePath;
  finally
    GLogLock.Leave;
  end;
end;

// Appends one line, rotating to "<path>.1" once when the file grows too large.
// Best-effort: every failure is swallowed so logging can never crash the app.
procedure AppendLine(const APath, ALine: string);
var
  Dir: string;
begin
  try
    Dir := TPath.GetDirectoryName(APath);
    if Dir <> '' then
      TDirectory.CreateDirectory(Dir);

    if TFile.Exists(APath) and (TFile.GetSize(APath) > MaxLogBytes) then
    begin
      if TFile.Exists(APath + '.1') then
        TFile.Delete(APath + '.1');
      TFile.Move(APath, APath + '.1');
    end;

    TFile.AppendAllText(APath, ALine + sLineBreak, TEncoding.UTF8);
  except
    // Diagnostics must never break the application.
  end;
end;

type
  TLogger = class(TInterfacedObject, ILogger)
  private
    FActive: Boolean;
    FLogLevel: Integer; // 0=Debug, 1=Info, 2=Warning, 3=Error
    procedure Output(const AMessage: string; ALevel: Integer);
  public
    constructor Create; reintroduce;
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warning(const AMessage: string);
    procedure Error(const AMessage: string);
    class function LogLevelToString(ALevel: Integer): string;
    class procedure DefaultLogger(const AMessage: string; ALevel: Integer);
    property Active: Boolean read FActive;
    property LogLevel: Integer read FLogLevel;
  end;

function CreateLogger: ILogger;
begin
  Result := TLogger.Create;
end;

{ TLogger }

constructor TLogger.Create;
begin
  inherited;
  FActive := True;
  FLogLevel := 1; // Info level by default - display Info, Warning, Error
end;

procedure TLogger.Debug(const AMessage: string);
begin
  if FLogLevel <= 0 then
    Output(AMessage, 0);
end;

procedure TLogger.Info(const AMessage: string);
begin
  Output(AMessage, 1);
end;

procedure TLogger.Warning(const AMessage: string);
begin
  Output(AMessage, 2);
end;

procedure TLogger.Error(const AMessage: string);
begin
  Output(AMessage, 3);
end;

procedure TLogger.Output(const AMessage: string; ALevel: Integer);
var
  Line: string;
begin
  if not FActive then Exit;

  Line := Format('[%s][%s] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
     TLogger.LogLevelToString(ALevel),
     AMessage]);

  OutputDebugString(PChar(Line));

  GLogLock.Enter;
  try
    if GLogFilePath <> '' then
      AppendLine(GLogFilePath, Line);
  finally
    GLogLock.Leave;
  end;
end;

class function TLogger.LogLevelToString(ALevel: Integer): string;
begin
  case ALevel of
    0: Result := 'DEBUG';
    1: Result := 'INFO';
    2: Result := 'WARNING';
    3: Result := 'ERROR';
  else
    Result := 'INFO';
  end;
end;

class procedure TLogger.DefaultLogger(const AMessage: string; ALevel: Integer);
var
  Logger: ILogger;
begin
  Logger := TLogger.Create;
  if Logger is TLogger then
    TLogger(Logger).Output(AMessage, ALevel);
end;

initialization
  GLogLock := TCriticalSection.Create;

finalization
  GLogLock.Free;

end.
