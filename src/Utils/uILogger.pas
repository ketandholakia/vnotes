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

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes;

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
begin
  if not FActive then Exit;
  OutputDebugString(PChar(Format('[%s] %s', [TLogger.LogLevelToString(ALevel), AMessage])));
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

end.