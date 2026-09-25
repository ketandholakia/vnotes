unit TCredentialStoreTests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  uCredentialStore;

type
  [TestFixture]
  TCredentialStoreTestFixture = class
  public
    [Test]
    procedure TestMemoryStoreRoundTrip;
    [Test]
    procedure TestMemoryStoreDelete;
    [Test]
    procedure TestMemoryStoreMissingIsEmpty;
    [Test]
    procedure TestWindowsStoreRoundTrip;
    [Test]
    procedure TestWindowsStoreDelete;
  end;

implementation

procedure TCredentialStoreTestFixture.TestMemoryStoreRoundTrip;
var
  Store: ICredentialStore;
begin
  Store := CreateMemoryCredentialStore;
  Store.SetSecret('target-a', 'secret-value');
  Assert.AreEqual<string>('secret-value', Store.GetSecret('target-a'));
end;

procedure TCredentialStoreTestFixture.TestMemoryStoreDelete;
var
  Store: ICredentialStore;
begin
  Store := CreateMemoryCredentialStore;
  Store.SetSecret('target-b', 'x');
  Store.DeleteSecret('target-b');
  Assert.AreEqual<string>('', Store.GetSecret('target-b'));
end;

procedure TCredentialStoreTestFixture.TestMemoryStoreMissingIsEmpty;
var
  Store: ICredentialStore;
begin
  Store := CreateMemoryCredentialStore;
  Assert.AreEqual<string>('', Store.GetSecret('never-set'));
end;

procedure TCredentialStoreTestFixture.TestWindowsStoreRoundTrip;
var
  Store: ICredentialStore;
begin
  // Uses a dedicated target and always cleans up so the real store is not left dirty.
  Store := CreateWindowsCredentialStore;
  try
    Store.SetSecret('VNotes/TestCredential', 'round-trip-value');
    Assert.AreEqual<string>('round-trip-value', Store.GetSecret('VNotes/TestCredential'));
  finally
    Store.DeleteSecret('VNotes/TestCredential');
  end;
end;

procedure TCredentialStoreTestFixture.TestWindowsStoreDelete;
var
  Store: ICredentialStore;
begin
  Store := CreateWindowsCredentialStore;
  Store.SetSecret('VNotes/TestCredential2', 'y');
  Store.DeleteSecret('VNotes/TestCredential2');
  Assert.AreEqual<string>('', Store.GetSecret('VNotes/TestCredential2'));
end;

initialization
  TDUnitX.RegisterTestFixture(TCredentialStoreTestFixture);

end.
