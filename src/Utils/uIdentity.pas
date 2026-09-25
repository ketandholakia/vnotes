unit uIdentity;

// Phase 7A - sync identity primitives.
//
// Cloud sync needs two identifiers that the original local-only design never
// had:
//   * a globally-unique note id (the local Int64 ID collides across devices),
//   * a stable per-installation device id (to record who produced a revision).
//
// This unit is intentionally dependency-light and side-effect-light: note GUIDs
// are pure; the device id is the only thing that touches disk, and only once.

interface

// A globally-unique note identifier: UUIDv4 rendered lowercase, no braces.
function GenerateNoteGuid: string;

// Stable per-installation device identifier, persisted in <ABasePath>\device.id
// and created on first use. Deliberately NOT part of the backup set: restoring a
// backup on another machine must not clone its device identity.
// Returns '' if the file cannot be read or written (callers treat that as
// "identity unavailable" rather than failing the save).
function GetOrCreateDeviceId(const ABasePath: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils;

const
  DeviceIdFileName = 'device.id';

function GenerateNoteGuid: string;
var
  G: TGUID;
begin
  if CreateGUID(G) <> 0 then
    raise Exception.Create('GenerateNoteGuid: CreateGUID failed');
  Result := GUIDToString(G);                        // {XXXXXXXX-....-XXXXXXXXXXXX}
  Result := LowerCase(Copy(Result, 2, Length(Result) - 2)); // strip braces
end;

function GetOrCreateDeviceId(const ABasePath: string): string;
var
  Path: string;
begin
  Result := '';
  if ABasePath = '' then Exit;
  Path := TPath.Combine(ABasePath, DeviceIdFileName);
  try
    if TFile.Exists(Path) then
      Result := Trim(TFile.ReadAllText(Path, TEncoding.UTF8))
    else
    begin
      Result := GenerateNoteGuid;
      TDirectory.CreateDirectory(ABasePath);
      // ASCII: no BOM, so the file is a clean single-line token.
      TFile.WriteAllText(Path, Result, TEncoding.ASCII);
    end;
  except
    Result := ''; // best-effort: never let identity I/O break a save
  end;
end;

end.
