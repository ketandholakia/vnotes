unit TNoteTests;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  uNote, uEnums, DUnitX.TestFramework;

type
  [TestFixture]
  TNoteTestFixture = class
  public
    [Test]
    procedure TestNoteCreation;
    [Test]
    procedure TestSerialization;
    [Test]
    procedure TestEquality;
  end;

implementation

procedure TNoteTestFixture.TestNoteCreation;
var
  Note: TNote;
begin
  // Test default constructor
  Note := TNote.Create;
  try
    Assert.AreEqual<Int64>(0, Note.ID);
    Assert.IsTrue(Note.IsEmpty);
    Assert.AreEqual('Yellow', NoteColorToName(Note.Color));
    Assert.AreEqual(100, Note.Left);
    Assert.AreEqual(100, Note.Top);
    Assert.AreEqual(300, Note.Width);
    Assert.AreEqual(250, Note.Height);
  finally
    Note.Free;
  end;
  // Test parameterized constructor
  Note := TNote.Create(42, 'Test Title', 'Test Content', ncBlue);
  try
    Assert.AreEqual<Int64>(42, Note.ID);
    Assert.AreEqual('Test Title', Note.Title);
    Assert.AreEqual('Test Content', Note.Content);
    Assert.AreEqual<TNoteColor>(ncBlue, Note.Color);
    Assert.AreEqual(100, Note.Left);
    Assert.AreEqual(100, Note.Top);
    Assert.AreEqual(300, Note.Width);
    Assert.AreEqual(250, Note.Height);
  finally
    Note.Free;
  end;
end;

procedure TNoteTestFixture.TestSerialization;
var
  Note: TNote;
  Json: TJSONObject;
begin
  Note := TNote.Create(777, 'Serialize Test', 'Serialize Content', ncGreen);
  try
    // Create JSON manually to test serialization format
    Json := TJSONObject.Create;
    try
      Json.AddPair('ID', TJSONNumber.Create(Note.ID));
      Json.AddPair('Title', Note.Title);
      Json.AddPair('Content', Note.Content);
      Json.AddPair('Color', TJSONNumber.Create(Ord(Note.Color)));
      Json.AddPair('Left', TJSONNumber.Create(Note.Left));
      Json.AddPair('Top', TJSONNumber.Create(Note.Top));
      Json.AddPair('Width', TJSONNumber.Create(Note.Width));
      Json.AddPair('Height', TJSONNumber.Create(Note.Height));

      Assert.IsNotNull(Json);
      // Verify that key values are present
      Assert.AreEqual<Int64>(777, Json.GetValue('ID').Value.ToInt64);
      Assert.AreEqual('Serialize Test', Json.GetValue('Title').Value);
      Assert.AreEqual('Serialize Content', Json.GetValue('Content').Value);
      Assert.AreEqual(Ord(ncGreen), Json.GetValue('Color').Value.ToInteger);
      Assert.AreEqual(100, Json.GetValue('Left').Value.ToInteger);
      Assert.AreEqual(100, Json.GetValue('Top').Value.ToInteger);
      Assert.AreEqual(300, Json.GetValue('Width').Value.ToInteger);
      Assert.AreEqual(250, Json.GetValue('Height').Value.ToInteger);
    finally
      Json.Free;
    end;
  finally
    Note.Free;
  end;
end;

procedure TNoteTestFixture.TestEquality;
var
  NoteA, NoteB: TNote;
begin
  // Two distinct notes with same properties should have equal values
  NoteA := TNote.Create(1, 'Title', 'Content', ncYellow);
  NoteB := TNote.Create(1, 'Title', 'Content', ncYellow);
  try
    Assert.AreEqual(NoteA.ID, NoteB.ID);
    Assert.AreEqual(NoteA.Title, NoteB.Title);
    Assert.AreEqual(NoteA.Content, NoteB.Content);
    Assert.AreEqual(Ord(NoteA.Color), Ord(NoteB.Color));
    Assert.AreEqual(NoteA.Left, NoteB.Left);
    Assert.AreEqual(NoteA.Top, NoteB.Top);
    Assert.AreEqual(NoteA.Width, NoteB.Width);
    Assert.AreEqual(NoteA.Height, NoteB.Height);
  finally
    NoteA.Free;
    NoteB.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteTestFixture);

end.