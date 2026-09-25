unit TSyncBackendTests;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  DUnitX.TestFramework,
  uServiceInterfaces, uFolderSyncBackend, uWebDavBackend;

type
  [TestFixture]
  TSyncBackendTestFixture = class
  private
    FRoot: string;
    FBackend: ISyncBackend;
  public
    [SetUp]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFolderBackendSupportsETags;
    [Test]
    procedure TestReadWithETagEmptyWhenAbsent;
    [Test]
    procedure TestReadWithETagNonEmptyWhenPresent;
    [Test]
    procedure TestWriteIfMatchFailsOnStaleTag;
    [Test]
    procedure TestWriteIfMatchSucceedsWithMatchingTag;
    [Test]
    procedure TestWriteIfMatchEmptyTagRequiresAbsence;
    [Test]
    procedure TestWebDavDisplayNameNormalisesTrailingSlash;
    [Test]
    procedure TestWebDavSupportsETags;
  end;

implementation

procedure TSyncBackendTestFixture.SetUp;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'StickyNotes_BackendTest_' + IntToStr(TThread.GetTickCount));
  ForceDirectories(FRoot);
  FBackend := TFolderSyncBackend.Create(FRoot);
end;

procedure TSyncBackendTestFixture.TearDown;
begin
  FBackend := nil;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSyncBackendTestFixture.TestFolderBackendSupportsETags;
begin
  Assert.IsTrue(FBackend.SupportsETags, 'the folder backend exposes mtime-based ETags');
end;

procedure TSyncBackendTestFixture.TestReadWithETagEmptyWhenAbsent;
var
  Tag: string;
begin
  Assert.AreEqual<string>('', FBackend.ReadWithETag('missing', Tag));
  Assert.AreEqual<string>('', Tag, 'an absent object has no ETag');
end;

procedure TSyncBackendTestFixture.TestReadWithETagNonEmptyWhenPresent;
var
  Tag: string;
begin
  FBackend.Write('note-a', '{"x":1}');
  Assert.AreEqual<string>('{"x":1}', FBackend.ReadWithETag('note-a', Tag));
  Assert.IsTrue(Tag <> '', 'a present object must have an ETag');
end;

procedure TSyncBackendTestFixture.TestWriteIfMatchFailsOnStaleTag;
var
  Tag: string;
begin
  FBackend.Write('note-b', 'original');
  FBackend.ReadWithETag('note-b', Tag);
  // Something else changes the object...
  FBackend.Write('note-b', 'changed-elsewhere');
  // ...so a write based on the old tag must be refused, leaving it untouched.
  Assert.IsFalse(FBackend.WriteIfMatch('note-b', 'my-write', Tag),
    'a stale ETag must not overwrite a newer object');
  Assert.AreEqual<string>('changed-elsewhere', FBackend.Read('note-b'));
end;

procedure TSyncBackendTestFixture.TestWriteIfMatchSucceedsWithMatchingTag;
var
  Tag: string;
begin
  FBackend.Write('note-c', 'v1');
  FBackend.ReadWithETag('note-c', Tag);
  Assert.IsTrue(FBackend.WriteIfMatch('note-c', 'v2', Tag),
    'a matching ETag must allow the write');
  Assert.AreEqual<string>('v2', FBackend.Read('note-c'));
end;

procedure TSyncBackendTestFixture.TestWriteIfMatchEmptyTagRequiresAbsence;
begin
  Assert.IsTrue(FBackend.WriteIfMatch('note-d', 'new', ''),
    'an empty tag means the object must not exist yet');
  Assert.IsFalse(FBackend.WriteIfMatch('note-d', 'again', ''),
    'a second create must be refused because the object now exists');
end;

procedure TSyncBackendTestFixture.TestWebDavDisplayNameNormalisesTrailingSlash;
var
  B: TWebDavBackend;
begin
  B := TWebDavBackend.Create('https://example.invalid/dav/notes', 'user', 'pass');
  try
    Assert.AreEqual<string>('https://example.invalid/dav/notes/', B.DisplayName);
  finally
    B.Free;
  end;
end;

procedure TSyncBackendTestFixture.TestWebDavSupportsETags;
var
  B: TWebDavBackend;
begin
  B := TWebDavBackend.Create('https://example.invalid/dav', '', '');
  try
    Assert.IsTrue(B.SupportsETags);
  finally
    B.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyncBackendTestFixture);

end.
