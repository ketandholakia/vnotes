unit uNote;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, System.Types,
  uEnums;

type
  // A single checklist row. Deliberately a flat record (no Done-timestamp,
  // no sub-items)  matches the plain-JSON-per-note storage model and keeps
  // the future mobile/sync payload trivial to diff field-by-field.
  TChecklistItem = record
    Text: string;
    Done: Boolean;
    constructor Create(const AText: string; ADone: Boolean = False);
  end;

  TNote = class
  private
    FID: Int64;
    FTitle: string;
    FContent: string;
    FColor: TNoteColor;
    FLeft: Integer;
    FTop: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FAlwaysOnTop: Boolean;
    FCollapsed: Boolean;
    FLocked: Boolean;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    FTags: TArray<string>;
    FChecklistItems: TArray<TChecklistItem>;
    function GetColorAsTColor: TColor;
    procedure SetColorAsTColor(const Value: TColor);
    function GetTags: TArray<string>;
    procedure SetTags(const Value: TArray<string>);
    function GetChecklistItems: TArray<TChecklistItem>;
    procedure SetChecklistItems(const Value: TArray<TChecklistItem>);
  public
    constructor Create; overload;
    constructor Create(AID: Int64; const ATitle, AContent: string; AColor: TNoteColor); overload;
    procedure Assign(Source: TNote);
    function Clone: TNote;
    property ID: Int64 read FID write FID;
    property Title: string read FTitle write FTitle;
    property Content: string read FContent write FContent;
    property Color: TNoteColor read FColor write FColor;
    property ColorAsTColor: TColor read GetColorAsTColor write SetColorAsTColor;
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property AlwaysOnTop: Boolean read FAlwaysOnTop write FAlwaysOnTop;
    property Collapsed: Boolean read FCollapsed write FCollapsed;
    property Locked: Boolean read FLocked write FLocked;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    property Tags: TArray<string> read GetTags write SetTags;
    property ChecklistItems: TArray<TChecklistItem> read GetChecklistItems write SetChecklistItems;
    function IsEmpty: Boolean;
    function GetBounds: TRect;
    procedure SetBounds(const ALeft, ATop, AWidth, AHeight: Integer);
    procedure Touch;
    // Tags: case-insensitive, trimmed, deduplicated. Mutators return whether
    // the tag set actually changed (so callers can skip an autosave/Touch).
    function AddTag(const ATag: string): Boolean;
    function RemoveTag(const ATag: string): Boolean;
    function HasTag(const ATag: string): Boolean;
    // Checklist items: order-preserving; index-based like a TList.
    function AddChecklistItem(const AText: string; ADone: Boolean = False): Integer;
    procedure RemoveChecklistItem(AIndex: Integer);
    procedure ToggleChecklistItem(AIndex: Integer);
    procedure SetChecklistItemText(AIndex: Integer; const AText: string);
  end;

  TNoteList = TObjectList<TNote>;

implementation

{ TChecklistItem }

constructor TChecklistItem.Create(const AText: string; ADone: Boolean);
begin
  Text := AText;
  Done := ADone;
end;

{ TNote }

constructor TNote.Create;
begin
  inherited;
  FID := 0;
  FTitle := '';
  FContent := '';
  FColor := ncYellow;
  FLeft := 100;
  FTop := 100;
  FWidth := 300;
  FHeight := 250;
  FAlwaysOnTop := False;
  FCollapsed := False;
  FLocked := False;
  FCreatedAt := Now;
  FUpdatedAt := Now;
  FTags := nil;
  FChecklistItems := nil;
end;

constructor TNote.Create(AID: Int64; const ATitle, AContent: string; AColor: TNoteColor);
begin
  Create;
  FID := AID;
  FTitle := ATitle;
  FContent := AContent;
  FColor := AColor;
end;

procedure TNote.Assign(Source: TNote);
begin
  if Source = nil then Exit;
  FID := Source.FID;
  FTitle := Source.FTitle;
  FContent := Source.FContent;
  FColor := Source.FColor;
  FLeft := Source.FLeft;
  FTop := Source.FTop;
  FWidth := Source.FWidth;
  FHeight := Source.FHeight;
  FAlwaysOnTop := Source.FAlwaysOnTop;
  FCollapsed := Source.FCollapsed;
  FLocked := Source.FLocked;
  FCreatedAt := Source.FCreatedAt;
  FUpdatedAt := Source.FUpdatedAt;
  // Explicit Copy: dynamic-array assignment shares the underlying buffer,
  // and mutating one note's items in place (AddTag/ToggleChecklistItem)
  // would silently mutate Source's array too without this.
  FTags := System.Copy(Source.FTags);
  FChecklistItems := System.Copy(Source.FChecklistItems);
end;

function TNote.Clone: TNote;
begin
  Result := TNote.Create;
  Result.Assign(Self);
end;

function TNote.GetColorAsTColor: TColor;
begin
  Result := NoteColorToColor(FColor);
end;

procedure TNote.SetColorAsTColor(const Value: TColor);
begin
  FColor := ColorToNoteColor(Value);
end;

function TNote.IsEmpty: Boolean;
begin
  // A note carrying only tags and no checklist items is still considered
  // empty (tags alone aren't useful content); a note with checklist items
  // is not, even if Title/Content are blank.
  Result := (FTitle = '') and (FContent = '') and (Length(FChecklistItems) = 0);
end;

function TNote.GetBounds: TRect;
begin
  Result := Rect(FLeft, FTop, FLeft + FWidth, FTop + FHeight);
end;

procedure TNote.SetBounds(const ALeft, ATop, AWidth, AHeight: Integer);
begin
  FLeft := ALeft;
  FTop := ATop;
  FWidth := AWidth;
  FHeight := AHeight;
  Touch;
end;

procedure TNote.Touch;
begin
  FUpdatedAt := Now;
end;

function TNote.GetTags: TArray<string>;
begin
  Result := FTags;
end;

procedure TNote.SetTags(const Value: TArray<string>);
begin
  FTags := System.Copy(Value);
end;

function TNote.GetChecklistItems: TArray<TChecklistItem>;
begin
  Result := FChecklistItems;
end;

procedure TNote.SetChecklistItems(const Value: TArray<TChecklistItem>);
begin
  FChecklistItems := System.Copy(Value);
end;

function TNote.AddTag(const ATag: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := Trim(ATag);
  Result := (Trimmed <> '') and not HasTag(Trimmed);
  if Result then
  begin
    SetLength(FTags, Length(FTags) + 1);
    FTags[High(FTags)] := Trimmed;
  end;
end;

function TNote.RemoveTag(const ATag: string): Boolean;
var
  I, Idx: Integer;
begin
  Idx := -1;
  for I := 0 to High(FTags) do
    if SameText(FTags[I], ATag) then
    begin
      Idx := I;
      Break;
    end;
  Result := Idx >= 0;
  if Result then
  begin
    for I := Idx to High(FTags) - 1 do
      FTags[I] := FTags[I + 1];
    SetLength(FTags, Length(FTags) - 1);
  end;
end;

function TNote.HasTag(const ATag: string): Boolean;
var
  T: string;
begin
  Result := False;
  for T in FTags do
    if SameText(T, ATag) then
      Exit(True);
end;

function TNote.AddChecklistItem(const AText: string; ADone: Boolean): Integer;
begin
  SetLength(FChecklistItems, Length(FChecklistItems) + 1);
  Result := High(FChecklistItems);
  FChecklistItems[Result] := TChecklistItem.Create(AText, ADone);
end;

procedure TNote.RemoveChecklistItem(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FChecklistItems)) then
    Exit;
  for I := AIndex to High(FChecklistItems) - 1 do
    FChecklistItems[I] := FChecklistItems[I + 1];
  SetLength(FChecklistItems, Length(FChecklistItems) - 1);
end;

procedure TNote.ToggleChecklistItem(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FChecklistItems)) then
    Exit;
  FChecklistItems[AIndex].Done := not FChecklistItems[AIndex].Done;
end;

procedure TNote.SetChecklistItemText(AIndex: Integer; const AText: string);
begin
  if (AIndex < 0) or (AIndex > High(FChecklistItems)) then
    Exit;
  FChecklistItems[AIndex].Text := AText;
end;

end.