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
    // Phase 6B.1: distinct tags
    [Test]
    procedure TestDistinctTagsUnique;
    [Test]
    procedure TestDistinctTagsCaseInsensitiveUnique;
    [Test]
    procedure TestDistinctTagsWhitespaceIgnored;
    [Test]
    procedure TestDistinctTagsDeterministicOrder;
    [Test]
    procedure TestDistinctTagsEmptyCollection;
    [Test]
    procedure TestDistinctTagsNoMutation;
    // Phase 6B.1: tag filtering
    [Test]
    procedure TestFilterByTagExactMatch;
    [Test]
    procedure TestFilterByTagCaseInsensitive;
    [Test]
    procedure TestFilterByTagTrimsInput;
    [Test]
    procedure TestFilterByTagNotSubstring;
    [Test]
    procedure TestFilterByTagEmptyTagReturnsEmpty;
    [Test]
    procedure TestFilterByTagDeterministicOrdering;
    [Test]
    procedure TestFilterByTagMultipleMatchingNotes;
    [Test]
    procedure TestFilterByTagNonOwning;
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

// Phase 6B.1: distinct tags

procedure TNoteQueryTestFixture.TestDistinctTagsUnique;
var
  Tags: TArray<string>;
begin
  FSource.Add(TNote.Create(700, 'A', '', ncYellow));
  FSource[0].AddTag('work');
  FSource[0].AddTag('urgent');
  FSource.Add(TNote.Create(701, 'B', '', ncGreen));
  FSource[1].AddTag('work'); // duplicate across notes
  FSource[1].AddTag('personal');

  Tags := FQuery.DistinctTags(FSource);
  Assert.AreEqual(3, Length(Tags), 'Duplicates collapse to one entry');
  Assert.AreEqual('personal', Tags[0]);
  Assert.AreEqual('urgent', Tags[1]);
  Assert.AreEqual('work', Tags[2]);
end;

procedure TNoteQueryTestFixture.TestDistinctTagsCaseInsensitiveUnique;
var
  Tags: TArray<string>;
begin
  FSource.Add(TNote.Create(710, 'A', '', ncYellow));
  FSource[0].AddTag('Work');
  FSource.Add(TNote.Create(711, 'B', '', ncGreen));
  FSource[1].AddTag('WORK');
  FSource.Add(TNote.Create(712, 'C', '', ncBlue));
  FSource[2].AddTag('work');

  Tags := FQuery.DistinctTags(FSource);
  Assert.AreEqual(1, Length(Tags), 'Case variants collapse to one tag');
  // Casing of the first occurrence is kept.
  Assert.AreEqual('Work', Tags[0]);
end;

procedure TNoteQueryTestFixture.TestDistinctTagsWhitespaceIgnored;
var
  Tags: TArray<string>;
begin
  FSource.Add(TNote.Create(720, 'A', '', ncYellow));
  FSource[0].AddTag('  spaced  '); // trims to 'spaced'
  FSource[0].AddTag('   ');        // whitespace-only: ignored
  FSource.Add(TNote.Create(721, 'B', '', ncGreen));
  FSource[1].AddTag('spaced');     // duplicate after trim

  Tags := FQuery.DistinctTags(FSource);
  Assert.AreEqual(1, Length(Tags));
  Assert.AreEqual('spaced', Tags[0]);
end;

procedure TNoteQueryTestFixture.TestDistinctTagsDeterministicOrder;
var
  Tags: TArray<string>;
begin
  FSource.Add(TNote.Create(730, 'A', '', ncYellow));
  FSource[0].AddTag('zeta');
  FSource[0].AddTag('alpha');
  FSource.Add(TNote.Create(731, 'B', '', ncGreen));
  FSource[1].AddTag('Mike');
  FSource[1].AddTag('beta');

  Tags := FQuery.DistinctTags(FSource);
  Assert.AreEqual(4, Length(Tags));
  Assert.AreEqual('alpha', Tags[0]);
  Assert.AreEqual('beta', Tags[1]);
  Assert.AreEqual('Mike', Tags[2]);
  Assert.AreEqual('zeta', Tags[3]);
end;

procedure TNoteQueryTestFixture.TestDistinctTagsEmptyCollection;
var
  Tags: TArray<string>;
begin
  Tags := FQuery.DistinctTags(FSource);
  Assert.AreEqual(0, Length(Tags), 'Empty collection => empty result');

  Tags := FQuery.DistinctTags(nil);
  Assert.AreEqual(0, Length(Tags), 'Nil collection => empty result');
end;

procedure TNoteQueryTestFixture.TestDistinctTagsNoMutation;
var
  Tags: TArray<string>;
  N: TNote;
begin
  N := TNote.Create(740, 'A', '', ncYellow);
  N.AddTag('zulu');
  FSource.Add(N);
  FSource.Add(TNote.Create(741, 'B', '', ncGreen));
  FSource[1].AddTag('alpha');

  Tags := FQuery.DistinctTags(FSource);
  Assert.AreEqual(2, Length(Tags));
  // Source notes untouched: tag order/ownership unchanged.
  Assert.AreEqual(1, Length(FSource[0].Tags));
  Assert.AreEqual('zulu', FSource[0].Tags[0]);
  Assert.AreEqual(1, Length(FSource[1].Tags));
  Assert.AreEqual('alpha', FSource[1].Tags[0]);
end;

// Phase 6B.1: tag filtering

procedure TNoteQueryTestFixture.TestFilterByTagExactMatch;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(750, 'A', '', ncYellow));
  FSource[0].AddTag('work');
  FSource.Add(TNote.Create(751, 'B', '', ncGreen));
  FSource[1].AddTag('personal');

  Results := FQuery.FilterByTag('work', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(750, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagCaseInsensitive;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(760, 'A', '', ncYellow));
  FSource[0].AddTag('Work');

  Results := FQuery.FilterByTag('WORK', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(760, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagTrimsInput;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(770, 'A', '', ncYellow));
  FSource[0].AddTag('work');

  Results := FQuery.FilterByTag('  work  ', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.AreEqual<Int64>(770, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagNotSubstring;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(780, 'A', '', ncYellow));
  FSource[0].AddTag('project-management');

  // 'project' is a substring of 'project-management' but NOT a tag => no hit.
  Results := FQuery.FilterByTag('project', FSource);
  try
    Assert.AreEqual(0, Results.Count, 'Substring must not match');
  finally
    Results.Free;
  end;

  Results := FQuery.FilterByTag('project-management', FSource);
  try
    Assert.AreEqual(1, Results.Count, 'Exact tag matches');
    Assert.AreEqual<Int64>(780, Results[0].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagEmptyTagReturnsEmpty;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(790, 'A', '', ncYellow));
  FSource.Add(TNote.Create(791, 'B', '', ncGreen));

  // Explicitly defined: empty/blank tag matches nothing, not "return all".
  Results := FQuery.FilterByTag('', FSource);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;

  Results := FQuery.FilterByTag('   ', FSource);
  try
    Assert.AreEqual(0, Results.Count);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagDeterministicOrdering;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(1, 'N1', '', ncYellow));
  FSource.Add(TNote.Create(2, 'N2', '', ncGreen));
  FSource.Add(TNote.Create(3, 'N3', '', ncBlue));
  FSource[0].AddTag('work');
  FSource[1].AddTag('work');
  FSource[2].AddTag('work');
  FSource[0].UpdatedAt := Stamp(300);  // newest
  FSource[1].UpdatedAt := Stamp(100);  // oldest
  FSource[2].UpdatedAt := Stamp(200);

  Results := FQuery.FilterByTag('work', FSource);
  try
    Assert.AreEqual(3, Results.Count);
    Assert.AreEqual<Int64>(1, Results[0].ID);  // UpdatedAt DESC
    Assert.AreEqual<Int64>(3, Results[1].ID);
    Assert.AreEqual<Int64>(2, Results[2].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagMultipleMatchingNotes;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(5, 'N5', '', ncYellow));
  FSource.Add(TNote.Create(4, 'N4', '', ncGreen));
  FSource[0].AddTag('work');
  FSource[1].AddTag('work');
  FSource[0].UpdatedAt := Stamp(150);
  FSource[1].UpdatedAt := Stamp(150);  // tie => ID DESC

  Results := FQuery.FilterByTag('work', FSource);
  try
    Assert.AreEqual(2, Results.Count);
    Assert.AreEqual<Int64>(5, Results[0].ID);  // higher ID first on tie
    Assert.AreEqual<Int64>(4, Results[1].ID);
  finally
    Results.Free;
  end;
end;

procedure TNoteQueryTestFixture.TestFilterByTagNonOwning;
var
  Results: TObjectList<TNote>;
begin
  FSource.Add(TNote.Create(800, 'Keep Me', '', ncYellow));
  FSource[0].AddTag('work');

  Results := FQuery.FilterByTag('work', FSource);
  try
    Assert.AreEqual(1, Results.Count);
    Assert.IsFalse(Results.OwnsObjects, 'FilterByTag result must NOT own notes');
    Assert.AreEqual('Keep Me', Results[0].Title);
  finally
    Results.Free;
  end;

  // Source note must survive result-list disposal.
  Assert.AreEqual(1, FSource.Count, 'Source notes must survive');
  Assert.AreEqual('Keep Me', FSource[0].Title);
end;

initialization
  TDUnitX.RegisterTestFixture(TNoteQueryTestFixture);

end.