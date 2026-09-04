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
    [Test]
    procedure TestTagsAddRemoveDedup;
    [Test]
    procedure TestChecklistItemsAddToggleRemove;
    [Test]
    procedure TestAssignAndCloneDeepCopyTagsAndChecklist;
    [Test]
    procedure TestIsEmptyConsidersChecklistItems;
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

procedure TNoteTestFixture.TestTagsAddRemoveDedup;
var
  Note: TNote;
begin
  Note := TNote.Create;
  try
    Assert.AreEqual<Integer>(0, Length(Note.Tags));

    Assert.IsTrue(Note.AddTag('work'));
    Assert.IsTrue(Note.AddTag('urgent'));
    Assert.AreEqual<Integer>(2, Length(Note.Tags));

    // Case-insensitive duplicate is rejected, no change reported.
    Assert.IsFalse(Note.AddTag('Work'));
    Assert.AreEqual<Integer>(2, Length(Note.Tags));

    // Blank/whitespace-only tag is rejected.
    Assert.IsFalse(Note.AddTag('   '));
    Assert.AreEqual<Integer>(2, Length(Note.Tags));

    // Leading/trailing whitespace is trimmed on add.
    Assert.IsTrue(Note.AddTag('  personal  '));
    Assert.IsTrue(Note.HasTag('personal'));

    Assert.IsTrue(Note.HasTag('URGENT')); // case-insensitive lookup
    Assert.IsFalse(Note.HasTag('nonexistent'));

    Assert.IsTrue(Note.RemoveTag('Urgent')); // case-insensitive removal
    Assert.IsFalse(Note.HasTag('urgent'));
    Assert.AreEqual<Integer>(2, Length(Note.Tags));

    Assert.IsFalse(Note.RemoveTag('urgent')); // already gone
  finally
    Note.Free;
  end;
end;

procedure TNoteTestFixture.TestChecklistItemsAddToggleRemove;
var
  Note: TNote;
  Idx: Integer;
begin
  Note := TNote.Create;
  try
    Assert.AreEqual<Integer>(0, Length(Note.ChecklistItems));

    Idx := Note.AddChecklistItem('Buy milk');
    Assert.AreEqual<Integer>(0, Idx);
    Note.AddChecklistItem('Walk dog', True);
    Assert.AreEqual<Integer>(2, Length(Note.ChecklistItems));
    Assert.AreEqual('Buy milk', Note.ChecklistItems[0].Text);
    Assert.IsFalse(Note.ChecklistItems[0].Done);
    Assert.IsTrue(Note.ChecklistItems[1].Done);

    Note.ToggleChecklistItem(0);
    Assert.IsTrue(Note.ChecklistItems[0].Done);
    Note.ToggleChecklistItem(0);
    Assert.IsFalse(Note.ChecklistItems[0].Done);

    Note.SetChecklistItemText(0, 'Buy oat milk');
    Assert.AreEqual('Buy oat milk', Note.ChecklistItems[0].Text);

    // Out-of-range index is a safe no-op, not an exception.
    Note.ToggleChecklistItem(99);
    Note.SetChecklistItemText(-1, 'x');
    Note.RemoveChecklistItem(99);
    Assert.AreEqual<Integer>(2, Length(Note.ChecklistItems));

    Note.RemoveChecklistItem(0);
    Assert.AreEqual<Integer>(1, Length(Note.ChecklistItems));
    Assert.AreEqual('Walk dog', Note.ChecklistItems[0].Text);
  finally
    Note.Free;
  end;
end;

procedure TNoteTestFixture.TestAssignAndCloneDeepCopyTagsAndChecklist;
var
  Original, Cloned: TNote;
begin
  Original := TNote.Create(1, 'Title', 'Content', ncYellow);
  try
    Original.AddTag('work');
    Original.AddChecklistItem('Task 1');

    Cloned := Original.Clone;
    try
      Assert.AreEqual<Integer>(1, Length(Cloned.Tags));
      Assert.AreEqual<Integer>(1, Length(Cloned.ChecklistItems));

      // Mutating the clone must not affect the original (deep copy, not
      // a shared dynamic-array reference).
      Cloned.AddTag('personal');
      Cloned.ToggleChecklistItem(0);
      Cloned.AddChecklistItem('Task 2');

      Assert.AreEqual<Integer>(1, Length(Original.Tags));
      Assert.AreEqual<Integer>(1, Length(Original.ChecklistItems));
      Assert.IsFalse(Original.ChecklistItems[0].Done);

      Assert.AreEqual<Integer>(2, Length(Cloned.Tags));
      Assert.AreEqual<Integer>(2, Length(Cloned.ChecklistItems));
      Assert.IsTrue(Cloned.ChecklistItems[0].Done);
    finally
      Cloned.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TNoteTestFixture.TestIsEmptyConsidersChecklistItems;
var
  Note: TNote;
begin
  Note := TNote.Create;
  try
    Assert.IsTrue(Note.IsEmpty);

    Note.AddTag('work');
    Assert.IsTrue(Note.IsEmpty); // tags alone don't count as content

    Note.AddChecklistItem('Task 1');
    Assert.IsFalse(Note.IsEmpty); // a checklist item makes it non-empty
  finally
    Note.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteTestFixture);

end.