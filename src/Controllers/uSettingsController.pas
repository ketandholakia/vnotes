unit uSettingsController;

interface

uses
  System.SysUtils, System.Classes,
  uSettings;

type
  TSettingsController = class
  private
    FSettings: TSettings;
    FSettingsFile: string;
  public
    constructor Create(const ASettingsFile: string);
    destructor Destroy; override;
    procedure LoadSettings;
    procedure SaveSettings;
    function GetSettings: TSettings;
    procedure ApplyToApplication;
    procedure ApplyTheme(ADarkTheme: Boolean);
  end;

implementation

uses
  Vcl.Forms, Vcl.Themes, Vcl.Styles,
  Winapi.Windows, uStartupService;

{ TSettingsController }

constructor TSettingsController.Create(const ASettingsFile: string);
begin
  inherited Create;
  FSettingsFile := ASettingsFile;
  FSettings := TSettings.Create;
end;

destructor TSettingsController.Destroy;
begin
  FSettings.Free;
  inherited;
end;

procedure TSettingsController.LoadSettings;
begin
  FSettings.LoadFromFile(FSettingsFile);
end;

procedure TSettingsController.SaveSettings;
begin
  FSettings.SaveToFile(FSettingsFile);
end;

function TSettingsController.GetSettings: TSettings;
begin
  Result := FSettings;
end;

procedure TSettingsController.ApplyToApplication;
begin
  ApplyTheme(FSettings.DarkTheme);
  TStartupService.SetAutoStart(FSettings.AutoStart);
end;

procedure TSettingsController.ApplyTheme(ADarkTheme: Boolean);
begin
  if ADarkTheme then
  begin
    try
      TStyleManager.TrySetStyle('Windows10 Dark');
    except
      TStyleManager.TrySetStyle('Dark');
    end;
  end
  else
  begin
    TStyleManager.TrySetStyle('Windows10');
  end;
end;

end.