unit uNoteQuery;
{
  Phase 4B - in-memory note search.

  Ownership and lifetime contract:
  The query layer never takes ownership of the returned TNote objects.
  Search() returns a fresh TObjectList whose OwnsObjects is False:
  - the list is a temporary container of references to notes owned elsewhere
    (typically by TNoteManager, which owns its TObjectList<TNote> with
    OwnsObjects = True);
  - callers may free the result list freely - freeing it does NOT free notes.
  Search never mutates notes and never touches persistence.
}

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  System.StrUtils,
  uNote;

type
  INoteQuery = interface
    ['{4E4A2C1B-9F6D-4CE8-8D2A-9B4E7F2C1A03}']
    {
      Returns notes matching AQuery, case-insensitive substring across Title
      and Content. Empty/blank query returns ALL notes.
      Results are deterministic: Favorite notes first, then sorted by
      UpdatedAt descending (most recently modified first), tie-broken by
      ID descending.
      Result list has OwnsObjects := False - see ownership contract above.
    }
    function Search(const AQuery: string;
      const ANotes: TObjectList<TNote>): TObjectList<TNote>;
    {
      Phase 6B.1: returns the distinct tags present across ANotes.
      Case-insensitive uniqueness (casing of first occurrence is kept),
      deterministic alphabetical order (case-insensitive), empty and
      whitespace-only tags ignored. Never mutates notes or touches
      persistence. Empty/nil collection returns an empty array.
    }
    function DistinctTags(const ANotes: TObjectList<TNote>): TArray<string>;
    {
      Phase 6B.1: returns notes whose tag set contains ATag (trimmed,
      case-insensitive, exact match - NOT substring). An empty/whitespace
      tag returns an empty result list. Ordering and ownership contract
      identical to Search: Favorite first, then UpdatedAt DESC, ID DESC;
      OwnsObjects = False.
    }
    function FilterByTag(const ATag: string;
      const ANotes: TObjectList<TNote>): TObjectList<TNote>;
  end;

  TNoteQuery = class(TInterfacedObject, INoteQuery)
  public
    function Search(const AQuery: string;
      const ANotes: TObjectList<TNote>): TObjectList<TNote>;
    function DistinctTags(const ANotes: TObjectList<TNote>): TArray<string>;
    function FilterByTag(const ATag: string;
      const ANotes: TObjectList<TNote>): TObjectList<TNote>;
  private
    // Phase 6A Part 2: Helper functions for searching tags and checklist items
    function ContainsTextArray(const ATags: TArray<string>; const AText: string): Boolean;
    function ContainsTextInChecklist(const AItems: TArray<TChecklistItem>; const AText: string): Boolean;
  private
    // Phase 6B.1: shared deterministic comparer (UpdatedAt DESC, ID DESC)
    // used by both Search and FilterByTag.
    // Phase 6C.1: Favorite notes sort first; legacy recency order holds
    // within each group.
    class function CompareForRecency(const L, R: TNote): Integer; static;
    // Shared result construction: non-owning reference list.
    class function NewResultList: TObjectList<TNote>; static;
  end;

implementation

function TNoteQuery.Search(const AQuery: string;
  const ANotes: TObjectList<TNote>): TObjectList<TNote>;
var
  Note: TNote;
  Query: string;
begin
  // OwnsObjects = False: the result holds references only.
  Result := TObjectList<TNote>.Create(False);
  if ANotes = nil then
    Exit;

  Query := Trim(AQuery);
  for Note in ANotes do
  begin
    if (Query = '') or
       ContainsText(Note.Title, Query) or
       ContainsText(Note.Content, Query) or
       ContainsTextArray(Note.Tags, Query) or
       ContainsTextInChecklist(Note.ChecklistItems, Query) then
      Result.Add(Note);
  end;

  // Deterministic order: favorites first, most recently modified first,
  // ID desc as tie-break.
  Result.Sort(TComparer<TNote>.Construct(CompareForRecency));
end;

function TNoteQuery.DistinctTags(const ANotes: TObjectList<TNote>): TArray<string>;
var
  Note: TNote;
  Tag, CleanTag: string;
  Known: TArray<string>;
  I, InsertAt: Integer;
begin
  Result := nil;
  if ANotes = nil then
    Exit;

  for Note in ANotes do
  begin
    for Tag in Note.Tags do
    begin
      CleanTag := Trim(Tag);
      if CleanTag = '' then
        Continue;
      Known := Result;
      // Find the insertion point in the case-insensitively sorted array.
      // Hitting an equal entry means a duplicate (ignore, keep first-seen
      // casing); otherwise insert at InsertAt, shifting the tail right.
      InsertAt := 0;
      while (InsertAt <= High(Known)) and (CompareText(CleanTag, Known[InsertAt]) > 0) do
        Inc(InsertAt);
      if (InsertAt <= High(Known)) and (CompareText(CleanTag, Known[InsertAt]) = 0) then
        Continue;
      SetLength(Result, Length(Known) + 1);
      for I := High(Result) downto InsertAt + 1 do
        Result[I] := Result[I - 1];
      Result[InsertAt] := CleanTag;
    end;
  end;
end;

function TNoteQuery.FilterByTag(const ATag: string;
  const ANotes: TObjectList<TNote>): TObjectList<TNote>;
var
  Note: TNote;
  Wanted: string;
begin
  Result := NewResultList;
  if ANotes = nil then
    Exit;

  // Explicitly defined: an empty/whitespace tag matches nothing (no notes
  // carry a blank tag), rather than "return all".
  Wanted := Trim(ATag);
  if Wanted = '' then
    Exit;

  for Note in ANotes do
    if Note.HasTag(Wanted) then
      Result.Add(Note);

  // Same deterministic order as Search: favorites first, UpdatedAt DESC,
  // ID DESC.
  Result.Sort(TComparer<TNote>.Construct(CompareForRecency));
end;

class function TNoteQuery.CompareForRecency(const L, R: TNote): Integer;
begin
  // Phase 6C.1: Favorite-first ordering. Favorites sort before non-favorites;
  // within each group the legacy order holds (UpdatedAt DESC, ID DESC), so
  // all-False collections order exactly as before.
  if L.Favorite and not R.Favorite then
    Result := -1
  else if R.Favorite and not L.Favorite then
    Result := 1
  else if L.UpdatedAt > R.UpdatedAt then
    Result := -1
  else if L.UpdatedAt < R.UpdatedAt then
    Result := 1
  else if L.ID > R.ID then
    Result := -1
  else if L.ID < R.ID then
    Result := 1
  else
    Result := 0;
end;

class function TNoteQuery.NewResultList: TObjectList<TNote>;
begin
  // OwnsObjects = False: the result holds references only.
  Result := TObjectList<TNote>.Create(False);
end;

function TNoteQuery.ContainsTextArray(const ATags: TArray<string>; const AText: string): Boolean;
var
  Tag: string;
begin
  for Tag in ATags do
    if ContainsText(Tag, AText) then
      Exit(True);
  Result := False;
end;

function TNoteQuery.ContainsTextInChecklist(const AItems: TArray<TChecklistItem>; const AText: string): Boolean;
var
  Item: TChecklistItem;
begin
  for Item in AItems do
    if ContainsText(Item.Text, AText) then
      Exit(True);
  Result := False;
end;

end.