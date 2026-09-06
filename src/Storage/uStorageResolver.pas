unit uStorageResolver;

interface

uses
  System.SysUtils, uStorage, uJsonStorage, uSQLiteStorage, uSettings;

type
  TStorageResolver = class
  public
    class function ResolveStorage(const AAppDataPath: string; ASettings: TSettings): INoteStorage;
  end;

implementation

class function TStorageResolver.ResolveStorage(const AAppDataPath: string; ASettings: TSettings): INoteStorage;
begin
  if (ASettings <> nil) and SameText(ASettings.StorageBackend, 'SQLite') then
    Result := TSQLiteStorage.Create(AAppDataPath)
  else
    Result := TJsonStorage.Create(AAppDataPath);
end;

end.

