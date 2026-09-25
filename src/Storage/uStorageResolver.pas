unit uStorageResolver;

interface

uses
  System.SysUtils, uStorage, uJsonStorage, uSQLiteStorage, uSettings;

type
  TStorageResolver = class
  public
    // Resolves the storage backend named by ASettings.StorageBackend.
    //   '' / 'JSON'  -> TJsonStorage   (default)
    //   'SQLite'     -> TSQLiteStorage
    //   anything else -> raises EArgumentException (fail fast rather than
    //                    silently falling back to JSON and hiding a
    //                    misconfiguration, e.g. a typo such as 'sqlite3').
    // A nil ASettings resolves to JSON so callers that have not loaded
    // settings yet still get a working default backend.
    class function ResolveStorage(const AAppDataPath: string; ASettings: TSettings): INoteStorage;
  end;

implementation

class function TStorageResolver.ResolveStorage(const AAppDataPath: string; ASettings: TSettings): INoteStorage;
var
  Backend: string;
begin
  Backend := '';
  if ASettings <> nil then
    Backend := Trim(ASettings.StorageBackend);

  if (Backend = '') or SameText(Backend, 'JSON') then
    Result := TJsonStorage.Create(AAppDataPath)
  else if SameText(Backend, 'SQLite') then
    Result := TSQLiteStorage.Create(AAppDataPath)
  else
    raise EArgumentException.CreateFmt(
      'Unrecognised storage backend "%s". Expected "JSON" or "SQLite".', [Backend]);
end;

end.
