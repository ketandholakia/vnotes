unit uAtomicFile;

// Phase 7G/WP2: the smallest atomic text-write helper for sync metadata.
//
// Writes a temp file in the target's folder, flushes it, then renames it over
// the destination with MoveFileEx(MOVEFILE_REPLACE_EXISTING) - the same
// mechanism TJsonStorage.SaveNote already uses for note files. A crash can
// therefore never leave a torn sync-state.json / sync-journal.json.
//
// Callers are responsible for serialising writers to one path (the journal
// object locks; the state file has a single writer). WP4 extends this helper
// with .bak handling; WP2 needs only the atomic replace.

interface

// Writes AText (UTF-8, no BOM) to APath atomically; raises on failure and
// leaves the previous file untouched.
procedure WriteTextAtomic(const APath, AText: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, Winapi.Windows;

procedure WriteTextAtomic(const APath, AText: string);
var
  TmpPath: string;
  Stream: TFileStream;
  Bytes: TBytes;
begin
  if APath = '' then
    raise Exception.Create('WriteTextAtomic: path is empty');
  TmpPath := APath + '.tmp';
  try
    Bytes := TEncoding.UTF8.GetBytes(AText);
    Stream := TFileStream.Create(TmpPath, fmCreate);
    try
      if Length(Bytes) > 0 then
        Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free; // closes (flushes) before the rename
    end;
    if not MoveFileEx(PChar(TmpPath), PChar(APath),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    // Best-effort cleanup; the destination is untouched on any failure path.
    if TFile.Exists(TmpPath) then
      try
        TFile.Delete(TmpPath);
      except
        // swallow: the original error is being re-raised
      end;
    raise;
  end;
end;

end.
