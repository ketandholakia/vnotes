unit uEnums;

interface

uses
  System.SysUtils, System.UITypes;

type
  TNoteColor = (
    ncYellow,
    ncGreen,
    ncBlue,
    ncPink,
    ncPurple,
    ncOrange,
    ncWhite,
    ncGray
  );

  TStorageType = (
    stJson,
    stSQLite,
    stCloud
  );

const
  NOTE_COLOR_VALUES: array[TNoteColor] of TColor = (
    $0080FFFF, // Yellow (BGR: $FFFF80)
    $0080FF80, // Green (BGR: $80FF80)
    $00FFC080, // Blue (BGR: $80C0FF)
    $00C080FF, // Pink (BGR: $FF80C0)
    $00FF80FF, // Purple (BGR: $FF80FF)
    $0080C0FF, // Orange (BGR: $FFC080)
    $00FFFFFF, // White
    $00E0E0E0  // Gray
  );

  NOTE_COLOR_NAMES: array[TNoteColor] of string = (
    'Yellow',
    'Green',
    'Blue',
    'Pink',
    'Purple',
    'Orange',
    'White',
    'Gray'
  );

function ColorToNoteColor(AColor: TColor): TNoteColor;
function NoteColorToColor(ANoteColor: TNoteColor): TColor;
function NoteColorToName(ANoteColor: TNoteColor): string;
function NoteColorFromName(const AName: string): TNoteColor;

implementation

function ColorToNoteColor(AColor: TColor): TNoteColor;
var
  C: TNoteColor;
begin
  Result := ncYellow;
  for C := Low(TNoteColor) to High(TNoteColor) do
    if NOTE_COLOR_VALUES[C] = AColor then
      Exit(C);
end;

function NoteColorToColor(ANoteColor: TNoteColor): TColor;
begin
  Result := NOTE_COLOR_VALUES[ANoteColor];
end;

function NoteColorToName(ANoteColor: TNoteColor): string;
begin
  Result := NOTE_COLOR_NAMES[ANoteColor];
end;

function NoteColorFromName(const AName: string): TNoteColor;
var
  C: TNoteColor;
begin
  Result := ncYellow;
  for C := Low(TNoteColor) to High(TNoteColor) do
    if SameText(NOTE_COLOR_NAMES[C], AName) then
      Exit(C);
end;

end.