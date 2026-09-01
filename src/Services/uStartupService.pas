unit uStartupService;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  Winapi.ShlObj, Winapi.ActiveX, Winapi.KnownFolders;

type
  TStartupService = class
  public
    class function IsAutoStartEnabled: Boolean;
    class procedure SetAutoStart(AEnable: Boolean);
    class function GetStartupFolder: string;
  end;

implementation

uses
  System.Win.Registry;

{ TStartupService }

class function TStartupService.IsAutoStartEnabled: Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Software\Microsoft\Windows\CurrentVersion\Run', False) then
      Result := Reg.ValueExists('StickyNotes');
  finally
    Reg.Free;
  end;
end;

class procedure TStartupService.SetAutoStart(AEnable: Boolean);
var
  Reg: TRegistry;
  AppPath: string;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Software\Microsoft\Windows\CurrentVersion\Run', True) then
    begin
      AppPath := ParamStr(0);
      if AEnable then
        Reg.WriteString('StickyNotes', '"' + AppPath + '"')
      else
        Reg.DeleteValue('StickyNotes');
    end;
  finally
    Reg.Free;
  end;
end;

class function TStartupService.GetStartupFolder: string;
var
  Path: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if SHGetFolderPath(0, CSIDL_STARTUP, 0, SHGFP_TYPE_CURRENT, @Path[0]) = S_OK then
    Result := Path;
end;

end.