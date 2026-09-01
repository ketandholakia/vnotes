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
      Results are deterministic: sorted by UpdatedAt descending (most recently
      modified first), tie-broken by ID descending.
      Result list has OwnsObjects := False - see ownership contract above.
    }
    function Search(const AQuery: string;
      const ANotes: TObjectList<TNote>): TObjectList<TNote>;
  end;

  TNoteQuery = class(TInterfacedObject, INoteQuery)
  public
    function Search(const AQuery: string;
      const ANotes: TObjectList<TNote>): TObjectList<TNote>;
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
       ContainsText(Note.Content, Query) then
      Result.Add(Note);
  end;

  // Deterministic order: most recently modified first, ID desc as tie-break.
  Result.Sort(TComparer<TNote>.Construct(
    function(const L, R: TNote): Integer
    begin
      if L.UpdatedAt > R.UpdatedAt then
        Result := -1
      else if L.UpdatedAt < R.UpdatedAt then
        Result := 1
      else if L.ID > R.ID then
        Result := -1
      else if L.ID < R.ID then
        Result := 1
      else
        Result := 0;
    end));
end;

end.