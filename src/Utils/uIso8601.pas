unit uIso8601;

interface

uses
  System.SysUtils, System.DateUtils;

function DateTimeToISO8601(const ADateTime: TDateTime): string;

implementation

function DateTimeToISO8601(const ADateTime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', ADateTime);
end;

end.
