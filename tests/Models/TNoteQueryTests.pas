unit TNoteQueryTests;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DUnitX.TestFramework,
  uNote, uEnums, uNoteQuery;

type
  [TestFixture]
  TNoteQueryTestFixture = class
  private
    FQuery: INoteQuery;
    FSource: TObjectList<TNote>;
    function Stamp(ASeconds: Integer): TDateTime;
  public
    [SetUp]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestEmptyCollection;
    [Test]
    procedure TestEmptyQueryReturnsAll;
    [Test]
    procedure TestExactTitleMatch;
    [Test]
    procedure TestPartialTitleMatch;
    [Test]
    procedure TestCaseInsensitiveMatch;
    [Test]
    procedure TestContentMatch;
    [Test]
    procedure TestNoMatchReturnsEmpty;
    [Test]
    procedure TestMultipleMatches;
    [Test]
    procedure TestNoMutationOfSourceNotes;
    [Test]
    procedure TestOwnershipSafety;
    [Test]
    procedure TestWhitespaceTolerance;
    [Test]
    procedure TestNilSourceSafe;
    [Test]
    procedure TestOrderingMostRecentlyModifiedFirst;
    [Test]
    procedure TestOrderingTieBreakByIDDesc;
    [Test]
    procedure TestTagSearch;
    [Test]
    procedure TestChecklistSearch;
    [Test]
    procedure TestCombinedSearch;
    [Test]
    procedure TestTagSearchSubstring;
    [Test]
    procedure TestChecklistSearchSubstring;
    [Test]
    procedure TestSearchMatchesMultipleFields;
  end;

implementation

procedure TNoteQueryTestFixture.Setup;
begin
  FQuery := TNoteQuery.Create;
  // The source list OWNS its notes (like TNoteManager does).
  FSource := TObjectList<TNote>.Create(True);
end;

procedure TNoteQueryTestFixture.TearDown;
begin
  FSource.Free;
end;

function TNoteQueryTestFixture.Stamp(ASeconds: Integer): TDateTime;
begin
  // Deterministic, distinct timestamps (UpdatedAt is writable on TNote).
  Result := EncodeDate(2024, 1, 1) + (ASeconds / SecsPerDay);
end;

procedure TNoteQueryTestFixture.TestEmptyCollection;
var
  Results: TObjectList<TNote>;
begin
  Results := FQuery.Search('anything', FSource);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestEmptyQueryReturnsAll;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(1, 'Title 1', 'Content 1', ncYellow));
  FSource.Add(TNote.Create(2, 'Title 2', 'Content 2', ncBlue));
  FSource[0].UpdatedAt := Stamp(100);
  FSource[1].UpdatedAt := Stamp(200);
  Results := FQuery.Search('', FSource);
  try
    Assert.AreEqual(2, Results.Count);
    // Deterministic order: most recently modified first.
    Assert.AreEqual<Int64>(2, Results[0].ID);
    Assert.AreEqual<Int64>(1, Results[1].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestExactTitleMatch;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(10, 'Groceries', 'Buy milk', ncYellow));
  FSource.Add(TNote.Create(11, 'Ideas', 'Random thought', ncGreen));
  Results := FQuery.Search('Groceries', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(10, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestPartialTitleMatch;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(20, 'My Shopping List', 'Eggs', ncYellow));
  FSource.Add(TNote.Create(21, 'Project Plan', 'Roadmap', ncBlue));
  Results := FQuery.Search('Shop', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(20, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestCaseInsensitiveMatch;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(30, 'Meeting Notes', 'Decide budget', ncGreen));
  FSource.Add(TNote.Create(31, 'Grocery', 'Milk', ncYellow));
  Results := FQuery.Search('meeting', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(30, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestContentMatch;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(40, 'Grocery', 'Buy MILK today', ncYellow));
  FSource.Add(TNote.Create(41, 'Work', 'Standup at 10', ncGreen));
  Results := FQuery.Search('milk', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(40, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestNoMatchReturnsEmpty;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(50, 'Title', 'Body', ncYellow));
  Results := FQuery.Search('zzz_no_match_zzz', FSource);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestMultipleMatches;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(60, 'Alpha', 'common token', ncYellow));
  FSource.Add(TNote.Create(61, 'Beta', 'no match here', ncGreen));
  FSource.Add(TNote.Create(62, 'Gamma', 'Has COMMON token too', ncBlue));
  FSource[0].UpdatedAt := Stamp(100);
  FSource[1].UpdatedAt := Stamp(300);
  FSource[2].UpdatedAt := Stamp(200);
  Results := FQuery.Search('common', FSource);
  try
    Assert.AreEqual(2, Results.Count);
    Assert.AreEqual<Int64>(62, Results[0].ID);  // newer
    Assert.AreEqual<Int64>(60, Results[1].ID);  // older
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestNoMutationOfSourceNotes;
var
  Results: TObjectList<TNote>;
  Title1, Title2, Content2, Updated1: string;
  A, B: TNote;
begin
  A := TNote.Create(70, 'Original Title', 'Original Content', ncYellow);
  B := TNote.Create(71, 'Other', 'Body', ncGreen);
  FSource.Add(A);
  FSource.Add(B);
  Title1 := A.Title;
  Title2 := B.Title;
  Content2 := B.Content;
  Updated1 := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', A.UpdatedAt);
  Results := FQuery.Search('body', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual(Title1, A.Title);
    Assert.AreEqual(Title2, B.Title);
    Assert.AreEqual(Content2, B.Content);
    Assert.AreEqual(Updated1, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', A.UpdatedAt));
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestOwnershipSafety;
var
  Results: TObjectList<TNote>;
begin
  // Source owns its notes (OwnsObjects = True), like TNoteManager.
  FSource.Add(TNote.Create(80, 'Keep Me', 'alive', ncYellow));
  FSource.Add(TNote.Create(81, 'Also Keep', 'present', ncGreen));
  FSource[0].UpdatedAt := Stamp(100);
  FSource[1].UpdatedAt := Stamp(200);

  Results := FQuery.Search('', FSource);
  try
    // Contract: query results must not own notes.
    Assert.AreEqual(2, Results.Count);
    Assert.IsFalse(Results.OwnsObjects, 'Query result list must NOT own the notes');
    Assert.AreEqual<Int64>(81, Results[0].ID);  // most recent first
    Assert.AreEqual<Int64>(80, Results[1].ID);
  finally
    // Freeing the result list must NOT destroy the source notes.
    Results.Free;
  end;

  // The source notes must still be alive and reachable.
  Assert.AreEqual(2, FSource.Count, 'Source notes must survive result-list disposal');
  Assert.AreEqual<Int64>(80, FSource[0].ID);
  Assert.AreEqual('Keep Me', FSource[0].Title);
end;

procedure TNoteQueryTestFixture.TestWhitespaceTolerance;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(90, 'Padded', 'content', ncYellow));
  Results := FQuery.Search('   padded   ', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(90, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestNilSourceSafe;
var
  Results: TObjectList<TNote>;
begin
  Results := FQuery.Search('anything', nil);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestOrderingMostRecentlyModifiedFirst;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(1, 'N1', 'x', ncYellow));
  FSource.Add(TNote.Create(2, 'N2', 'x', ncGreen));
  FSource.Add(TNote.Create(3, 'N3', 'x', ncBlue));
  FSource[0].UpdatedAt := Stamp(300);  // newest
  FSource[1].UpdatedAt := Stamp(100);  // oldest
  FSource[2].UpdatedAt := Stamp(200);
  Results := FQuery.Search('x', FSource);
  try
    Assert.AreEqual(3, Results.Count);
    Assert.AreEqual<Int64>(1, Results[0].ID);
    Assert.AreEqual<Int64>(3, Results[1].ID);
    Assert.AreEqual<Int64>(2, Results[2].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestOrderingTieBreakByIDDesc;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(5, 'N5', 'x', ncYellow));
  FSource.Add(TNote.Create(4, 'N4', 'x', ncGreen));
  FSource[0].UpdatedAt := Stamp(150);
  FSource[1].UpdatedAt := Stamp(150);  // identical timestamp
  Results := FQuery.Search('x', FSource);
  try
    Assert.AreEqual(2, Results.Count);
    Assert.AreEqual<Int64>(5, Results[0].ID);  // higher ID first on tie
    Assert.AreEqual<Int64>(4, Results[1].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestTagSearch;
var
  Results: TObjectList<TNote>;
begin
  // Create notes with tags
  FSource.Add(TNote.Create(100, 'Work Note', 'Important project', ncYellow));
  FSource.Add(TNote.Create(101, 'Personal Note', 'Shopping list', ncGreen));
  FSource.Add(TNote.Create(102, 'Meeting Notes', 'Discussion topics', ncBlue));

  // Add tags to notes
  FSource[0].AddTag('work');
  FSource[0].AddTag('project');
  FSource[1].AddTag('personal');
  FSource[1].AddTag('shopping');
  FSource[2].AddTag('meeting');
  FSource[2].AddTag('work');  // Shared tag with first note

  // Test searching by tag
  Results := FQuery.Search('work', FSource);
  try
    Assert.AreEqual(2, Results.Count);  // Both notes with 'work' tag
    Assert.IsTrue((Results[0].ID = 100) or (Results[0].ID = 102));
    Assert.IsTrue((Results[1].ID = 100) or (Results[1].ID = 102));
    Assert.AreNotEqual(Results[0].ID, Results[1].ID);  // Should be different notes
  finally
    Results.Free;
  end;

  // Test case-insensitive tag search
  Results := FQuery.Search('PROJECT', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(100, Results[0].ID);
  finally
    Results.Free;
  end;

  // Test tag that doesn't exist
  Results := FQuery.Search('nonexistent', FSource);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestChecklistSearch;
var
  Results: TObjectList<TNote>;
begin
  // Create notes with checklist items
  FSource.Add(TNote.Create(200, 'Tasks', '', ncYellow));
  FSource.Add(TNote.Create(201, 'Shopping', '', ncGreen));
  FSource.Add(TNote.Create(202, 'Project', '', ncBlue));

  // Add checklist items
  FSource[0].AddChecklistItem('Review code');
  FSource[0].AddChecklistItem('Write tests');
  FSource[1].AddChecklistItem('Buy groceries');
  FSource[1].AddChecklistItem('Call mom');
  FSource[2].AddChecklistItem('Deploy to production');
  FSource[2].AddChecklistItem('Review code');  // Shared item with first note

  // Test searching in checklist items
  Results := FQuery.Search('code', FSource);
  try
    Assert.AreEqual(2, Results.Count);  // Both notes with 'code' in checklist
    Assert.IsTrue((Results[0].ID = 200) or (Results[0].ID = 202));
    Assert.IsTrue((Results[1].ID = 200) or (Results[1].ID = 202));
    Assert.AreNotEqual(Results[0].ID, Results[1].ID);  // Should be different notes
  finally
    Results.Free;
  end;

  // Test searching for specific checklist item
  Results := FQuery.Search('groceries', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(201, Results[0].ID);
  finally
    Results.Free;
  end;

  // Test search that doesn't match any checklist items
  Results := FQuery.Search('nonexistent', FSource);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestCombinedSearch;
var
  Results: TObjectList<TNote>;
begin
  // Create notes with tags and checklist items
  FSource.Add(TNote.Create(300, 'Work Project', '', ncYellow));
  FSource.Add(TNote.Create(301, 'Personal Tasks', '', ncGreen));
  FSource.Add(TNote.Create(302, 'Meeting Notes', '', ncBlue));

  // Add tags and checklist items
  FSource[0].AddTag('work');
  FSource[0].AddTag('project');
  FSource[0].AddChecklistItem('Review pull requests');
  FSource[0].AddChecklistItem('Update documentation');

  FSource[1].AddTag('personal');
  FSource[1].AddTag('tasks');
  FSource[1].AddChecklistItem('Buy groceries');
  FSource[1].AddChecklistItem('Call dentist');

  FSource[2].AddTag('meeting');
  FSource[2].AddTag('notes');
  FSource[2].AddChecklistItem('Follow up on action items');
  FSource[2].AddChecklistItem('Schedule next meeting');

  // Test search that matches title
  Results := FQuery.Search('Work', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(300, Results[0].ID);
  finally
    Results.Free;
  end;

  // Test search that matches tag
  Results := FQuery.Search('meeting', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(302, Results[0].ID);
  finally
    Results.Free;
  end;

  // Test search that matches checklist item
  Results := FQuery.Search('groceries', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(301, Results[0].ID);
  finally
    Results.Free;
  end;

  // Test search that matches multiple fields (should return all matching notes)
  Results := FQuery.Search('project', FSource);
  try
    Assert.AreEqual(1, Results.Count);  // Only first note has 'project' tag
    Assert.AreEqual<Int64>(300, Results[0].ID);
  finally
    Results.Free;
  end;

  // Test empty query returns all notes
  Results := FQuery.Search('', FSource);
  try
    Assert.AreEqual(3, Results.Count);
  finally
    Results.Free;
  end;
end;

// Phase 6A Part 2: Additional query integration edge cases

procedure TNoteQueryTestFixture.TestTagSearchSubstring;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(400, 'Work Items', '', ncYellow));
  FSource[0].AddTag('project-management');
  FSource[0].AddTag('urgent');

  Results := FQuery.Search('project', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(400, Results[0].ID);
  finally
    Results.Free;
  end;

  Results := FQuery.Search('urgent', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(400, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestChecklistSearchSubstring;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(500, 'My Tasks', '', ncGreen));
  FSource[0].AddChecklistItem('Review pull requests before merge');
  FSource[0].AddChecklistItem('Update documentation');

  Results := FQuery.Search('documentation', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(500, Results[0].ID);
  finally
    Results.Free;
  end;

  Results := FQuery.Search('pull', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(500, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestSearchMatchesMultipleFields;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(600, 'Project Alpha', '', ncYellow));
  FSource[0].AddTag('work');
  FSource[0].AddChecklistItem('Design review');

  FSource.Add(TNote.Create(601, 'Personal Items', '', ncGreen));
  FSource[1].AddTag('personal');
  FSource[1].AddChecklistItem('Buy groceries');

  // Search matches title
  Results := FQuery.Search('Project Alpha', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(600, Results[0].ID);
  finally
    Results.Free;
  end;

  // Search matches tag
  Results := FQuery.Search('work', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(600, Results[0].ID);
  finally
    Results.Free;
  end;

  // Search matches checklist item
  Results := FQuery.Search('groceries', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(601, Results[0].ID);
  finally
    Results.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteQueryTestFixture);

end.