unit TStorageResolverTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  DUnitX.TestFramework,
  uSettings, uStorage, uJsonStorage, uSQLiteStorage, uStorageResolver;

type
  [TestFixture]
  TStorageResolverTestFixture = class
  private
    FBasePath: string;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure DefaultBackendResolvesToJson;
    [Test]
    procedure EmptyBackendResolvesToJson;
    [Test]
    procedure JsonBackendResolvesToJson;
    [Test]
    procedure SQLiteBackendResolvesToSQLite;
    [Test]
    procedure SQLiteBackendIsCaseInsensitive;
    [Test]
    procedure BackendIsTrimmed;
    [Test]
    procedure NilSettingsResolvesToJson;
    [Test]
    procedure UnrecognisedBackendRaises;
  end;

implementation

procedure TStorageResolverTestFixture.SetUp;
begin
  FBasePath := TPath.Combine(TPath.GetTempPath,
    'StickyNotes_ResolverTest_' + IntToStr(TThread.GetTickCount));
  ForceDirectories(FBasePath);
end;

procedure TStorageResolverTestFixture.TearDown;
begin
  if TDirectory.Exists(FBasePath) then
    TDirectory.Delete(FBasePath, True);
end;

procedure TStorageResolverTestFixture.DefaultBackendResolvesToJson;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create; // StorageBackend defaults to 'JSON'
  try
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsTrue(Storage is TJsonStorage, 'Default backend should resolve to TJsonStorage');
  finally
    S.Free;
  end;
end;

procedure TStorageResolverTestFixture.EmptyBackendResolvesToJson;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := '';
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsTrue(Storage is TJsonStorage, 'Blank backend should resolve to TJsonStorage');
  finally
    S.Free;
  end;
end;

procedure TStorageResolverTestFixture.JsonBackendResolvesToJson;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := 'JSON';
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsTrue(Storage is TJsonStorage, 'JSON backend should resolve to TJsonStorage');
  finally
    S.Free;
  end;
end;

procedure TStorageResolverTestFixture.SQLiteBackendResolvesToSQLite;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := 'SQLite';
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsTrue(Storage is TSQLiteStorage, 'SQLite backend should resolve to TSQLiteStorage');
  finally
    S.Free;
  end;
end;

procedure TStorageResolverTestFixture.SQLiteBackendIsCaseInsensitive;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := 'SQLITE';
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsTrue(Storage is TSQLiteStorage, 'Backend matching should be case-insensitive');
  finally
    S.Free;
  end;
end;

procedure TStorageResolverTestFixture.BackendIsTrimmed;
var
  S: TSettings;
  Storage: INoteStorage;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := '  sqlite  ';
    Storage := TStorageResolver.ResolveStorage(FBasePath, S);
    Assert.IsTrue(Storage is TSQLiteStorage, 'Surrounding whitespace should be ignored');
  finally
    S.Free;
  end;
end;

procedure TStorageResolverTestFixture.NilSettingsResolvesToJson;
var
  Storage: INoteStorage;
begin
  Storage := TStorageResolver.ResolveStorage(FBasePath, nil);
  Assert.IsTrue(Storage is TJsonStorage, 'Nil settings should resolve to the JSON default');
end;

procedure TStorageResolverTestFixture.UnrecognisedBackendRaises;
var
  S: TSettings;
begin
  S := TSettings.Create;
  try
    S.StorageBackend := 'sqlite3';
    Assert.WillRaise(
      procedure
      begin
        TStorageResolver.ResolveStorage(FBasePath, S);
      end,
      EArgumentException,
      'An unrecognised backend must raise rather than silently fall back to JSON');
  finally
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStorageResolverTestFixture);

end.
