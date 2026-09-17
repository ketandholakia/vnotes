unit uIso8601;

// Single source of truth for the timestamp format used by every persisted
// surface: JSON note files, SQLite rows, backup ZIP note exports, the backup
// manifest, and settings.ini.
//
// WRITE: local wall-clock with an explicit UTC offset and millisecond
//        precision, e.g. 2026-09-17T14:33:25.400+05:30.
//
// READ : offset-bearing values ("...+05:30", "-0700", "...Z") are converted to
//        local time. Offset-less values are treated as naive LOCAL wall-clock,
//        because that is what V-Notes wrote before 2026-09-17.
//
// The READ half is not optional. System.DateUtils.ISO8601ToDate interprets an
// offset-less string as UTC, so calling it with AReturnUTC = False on a legacy
// value shifts that value by the local UTC offset (+05:30 on this machine) and
// the shift is then made permanent by the next save. That regression is
// documented as C1 in docs/CODE_REVIEW_2026-09-17.md.

interface

uses
  System.SysUtils, System.DateUtils;

/// <summary>
/// Formats a timestamp for storage: local time, explicit UTC offset,
/// millisecond precision.
/// </summary>
function DateTimeToStoredISO8601(const AValue: TDateTime): string;

/// <summary>
/// Parses a stored timestamp, accepting both the current offset-bearing format
/// and the legacy offset-less one. Returns AIfEmptyOrInvalid when the value is
/// empty or cannot be parsed; this function never raises.
/// </summary>
function StoredISO8601ToDateTime(const AText: string; const AIfEmptyOrInvalid: TDateTime): TDateTime;

/// <summary>
/// True when the string carries an explicit UTC offset or a trailing 'Z'.
/// </summary>
function HasExplicitUtcOffset(const AText: string): Boolean;

implementation

function HasExplicitUtcOffset(const AText: string): Boolean;
var
  Tail: string;
begin
  Result := False;
  if AText = '' then
    Exit;

  // A trailing Z (or z) marks UTC.
  if (AText[Length(AText)] = 'Z') or (AText[Length(AText)] = 'z') then
    Exit(True);

  // '+' can only ever be a UTC offset: neither "yyyy-mm-dd" nor "hh:nn:ss"
  // contains one.
  if Pos('+', AText) > 0 then
    Exit(True);

  // Look for '-' only after the date part, where it can only be a negative
  // offset (the date separators are inside the first 10 characters).
  Tail := Copy(AText, 11, MaxInt);
  Result := Pos('-', Tail) > 0;
end;

function DateTimeToStoredISO8601(const AValue: TDateTime): string;
begin
  Result := DateToISO8601(AValue, False);
end;

function StoredISO8601ToDateTime(const AText: string; const AIfEmptyOrInvalid: TDateTime): TDateTime;
var
  S: string;
begin
  S := Trim(AText);
  if S = '' then
    Exit(AIfEmptyOrInvalid);

  try
    if HasExplicitUtcOffset(S) then
      // Absolute instant -> convert to local time.
      Result := ISO8601ToDate(S, False)
    else
      // Legacy naive local wall-clock: ask for UTC back so the wall-clock
      // value survives unchanged instead of being shifted by the offset.
      Result := ISO8601ToDate(S, True);
  except
    Result := AIfEmptyOrInvalid;
  end;
end;

end.
