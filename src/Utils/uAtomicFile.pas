unit uAtomicFile;

// Phase 7G/WP4: atomic text writes for sync metadata.
//
// Strategy (design S5; WP4 sections 5-8): serialize fully -> write a uniquely
// named temp file in the target's folder -> flush it to disk -> close it ->
// replace the target with MoveFileEx(MOVEFILE_REPLACE_EXISTING or
// MOVEFILE_WRITE_THROUGH). The target is therefore always either the old
// valid file or the new valid file - never a torn or partially written
// document - and a failure at any stage leaves the previous file untouched.
// The original is never deleted before the replacement succeeds.
//
// Crash residue: an interruption between the temp write and the replace can
// leave a "<target>.tmp.<pid>.<seq>" file behind. Stale temps are never read
// and never promoted; they are cleaned up (best effort) the next time this
// unit writes the same target. Unique names also keep writers of different
// targets from colliding on one temp name.
//
// Honest limits (WP4 section 13 / documentation duty): FlushFileBuffers
// pushes the temp file's bytes before the replace and MOVEFILE_WRITE_THROUGH
// flushes the rename metadata, but this is not a filesystem transaction:
// sync-state.json and sync-journal.json stay two files whose crash
// consistency comes from write ordering (journal first), not from the OS.
//
// Callers are responsible for serialising writers to one path (the journal
// object locks; the state file has a single writer).

interface

// Writes AText (UTF-8, no BOM) to APath atomically; raises on failure and
// leaves the previous file untouched.
procedure WriteTextAtomic(const APath, AText: string);

// WP4 section 13: a defensive well-formedness check for the JSON documents
// the metadata files carry. Raises when AText does not parse as valid JSON.
// WriteTextAtomic itself stays text-generic; the metadata writers call this
// before handing bytes to the filesystem so a serializer defect can never
// replace a valid file with garbage. (Defensive only: the RTL serializer
// produces valid output by construction, so this cannot fire in practice.)
procedure AssureValidJsonText(const AText: string);

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Classes, System.SyncObjs,
  Winapi.Windows;

var
  GTempSeq: Integer = 0; // process-wide, incremented atomically

procedure CleanupStaleTempFiles(const APath: string);
var
  Dir, Mask: string;
  Stale: TArray<string>;
  FileName: string;
begin
  // Best effort: a stale temp is an interrupted-write artifact, never a data
  // source. Deleting it cannot lose metadata (the live file is APath itself)
  // and failing to delete it must never fail the pending write.
  try
    Dir := TPath.GetDirectoryName(APath);
    if (Dir = '') or (not TDirectory.Exists(Dir)) then Exit;
    Mask := TPath.GetFileName(APath) + '.tmp.*';
    Stale := TDirectory.GetFiles(Dir, Mask);
    for FileName in Stale do
      try
        TFile.Delete(FileName);
      except
        // swallow: cleanup is opportunistic
      end;
  except
    // swallow: cleanup is opportunistic
  end;
end;

procedure AssureValidJsonText(const AText: string);
var
  Root: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(AText);
  if Root = nil then
    raise Exception.Create('sync metadata serialization produced invalid JSON');
  Root.Free;
end;

procedure WriteTextAtomic(const APath, AText: string);
var
  TmpPath: string;
  Stream: TFileStream;
  Bytes: TBytes;
begin
  if APath = '' then
    raise Exception.Create('WriteTextAtomic: path is empty');
  // Unique per process and per write: no collision with a writer of another
  // target, and no overwriting of a stale artifact from an earlier crash.
  TmpPath := Format('%s.tmp.%d.%d',
    [APath, GetCurrentProcessId, TInterlocked.Increment(GTempSeq)]);
  try
    CleanupStaleTempFiles(APath); // interrupted-write residue from earlier runs
    Bytes := TEncoding.UTF8.GetBytes(AText);
    Stream := TFileStream.Create(TmpPath, fmCreate);
    try
      if Length(Bytes) > 0 then
        Stream.WriteBuffer(Bytes[0], Length(Bytes));
      // Push the bytes to disk before the rename: after a successful replace
      // the target must not point at data that only lives in the cache.
      if not FlushFileBuffers(Stream.Handle) then
        RaiseLastOSError;
    finally
      Stream.Free; // closes before the rename
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
