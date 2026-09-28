unit uSyncState;

// Phase 7G/WP2: sync-state.json persistence (v2) and the v1 -> v2 migration.
//
// v2 format (design S5.1):
//   { "version": 2, "synced": { "<guid>": rev } }
//   - synced: the last successfully synchronized revision per guid.
//   - deletions are NOT part of this file; they live in sync-journal.json.
//
// v1 (legacy) format:
//   { "synced": { "<guid>": rev }, "deleted": [guid, ...] }
//
// Migration (design S5.2): the v1 `deleted` list becomes journal tombstones
// (rev = the guid's synced rev when known, else 0 = unknown; deletedAt =
// migration time - the true time is unknowable, so it is logged), and the
// journal is written BEFORE the v2 state: a crash in between simply
// re-migrates next time (the v1 file still carries the entries). Nothing is
// ever silently lost; invalid JSON / unsupported versions raise and the files
// are left untouched.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSyncJournal;

type
  ESyncStateError = class(Exception);

const
  SyncStateVersion = 2;

// Reads sync-state.json and returns the guid -> revision map (caller owns).
// Raises ESyncStateError when the file exists but cannot be used.
function LoadSyncState(const APath: string; const AJournal: TSyncJournal): TDictionary<string, Int64>;

// Writes sync-state.json in the v2 format, atomically (uAtomicFile).
procedure SaveSyncState(const APath: string; const ASynced: TDictionary<string, Int64>);

implementation

uses
  System.JSON, System.Classes, System.IOUtils,
  uAtomicFile, uIdentity, uIso8601, uILogger;

function LoadSyncState(const APath: string; const AJournal: TSyncJournal): TDictionary<string, Int64>;
var
  Text: string;
  Root: TJSONValue;
  Obj: TJSONObject;
  Pair: TJSONPair;
  VersionVal, SyncedVal, DeletedVal: TJSONValue;
  DeletedArr: TJSONArray;
  Version: Int64;
  Rev: Int64;
  I, MigratedCount: Integer;
  Guid: string;
  Tombstone: TSyncTombstone;
  Logger: ILogger;
begin
  Result := TDictionary<string, Int64>.Create;
  if (APath = '') or (not FileExists(APath)) then
    Exit; // no state file yet: a valid empty starting point
  Logger := CreateLogger;
  try
    Text := TFile.ReadAllText(APath);
  except
    on E: Exception do
      raise ESyncStateError.Create('sync state could not be read (' + E.Message + ')');
  end;
  Root := TJSONObject.ParseJSONValue(Text);
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    raise ESyncStateError.Create('sync state is not valid JSON (file preserved)');
  end;
  try
    Obj := Root as TJSONObject;
    VersionVal := Obj.GetValue('version');
    if VersionVal = nil then
      Version := 1 // legacy files carry no version field
    else if VersionVal is TJSONNumber then
      Version := (VersionVal as TJSONNumber).AsInt64
    else
      raise ESyncStateError.Create('sync state has an invalid version field');
    if (Version <> 1) and (Version <> SyncStateVersion) then
      raise ESyncStateError.CreateFmt('sync state version %d is not supported (this build supports 1 and %d)',
        [Version, SyncStateVersion]);

    SyncedVal := Obj.GetValue('synced');
    if (SyncedVal <> nil) and (not (SyncedVal is TJSONObject)) then
      raise ESyncStateError.Create('sync state "synced" is not an object');
    if SyncedVal is TJSONObject then
      for Pair in TJSONObject(SyncedVal) do
      begin
        if (Pair.JsonString = nil) or (not IsValidNoteGuid(Pair.JsonString.Value)) then
        begin
          Logger.Warning('Sync state: skipping entry with invalid guid');
          Continue;
        end;
        if Pair.JsonValue is TJSONNumber then
          Result.AddOrSetValue(Pair.JsonString.Value, (Pair.JsonValue as TJSONNumber).AsInt64)
        else
          Logger.Warning('Sync state: skipping non-numeric revision for ' + Pair.JsonString.Value);
      end;

    DeletedVal := Obj.GetValue('deleted');
    if (DeletedVal <> nil) and (not (DeletedVal is TJSONArray)) then
      raise ESyncStateError.Create('sync state "deleted" is not an array');
    DeletedArr := DeletedVal as TJSONArray;

    // v1 -> v2 migration of the deleted list (any version that still carries
    // one). Journal first, then the state rewrite - see the unit header.
    MigratedCount := 0;
    if DeletedArr <> nil then
      for I := 0 to DeletedArr.Count - 1 do
      begin
        Guid := DeletedArr.Items[I].Value;
        if not IsValidNoteGuid(Guid) then
        begin
          Logger.Warning('Sync state: cannot migrate deleted entry with invalid guid (' + Guid + ')');
          Continue;
        end;
        if not AJournal.TryGet(Guid, Tombstone) then
        begin
          if not Result.TryGetValue(Guid, Rev) then
            Rev := 0; // unknown: only ever used as a lower bound later
          AJournal.Add(Guid, Rev, Now);
          Inc(MigratedCount);
          Logger.Info(Format('Sync state: migrated deleted guid %s into the sync journal (rev %d)',
            [Guid, Rev]));
        end;
      end;

    if MigratedCount > 0 then
      AJournal.Save; // journal durable BEFORE the state claims v2

    if (Version = 1) or (MigratedCount > 0) then
      SaveSyncState(APath, Result);
  finally
    Root.Free;
  end;
end;

procedure SaveSyncState(const APath: string; const ASynced: TDictionary<string, Int64>);
var
  Obj, SyncedObj: TJSONObject;
  Guid, Text: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('version', TJSONNumber.Create(SyncStateVersion));
    SyncedObj := TJSONObject.Create;
    for Guid in ASynced.Keys do
      SyncedObj.AddPair(Guid, TJSONNumber.Create(ASynced[Guid]));
    Obj.AddPair('synced', SyncedObj);
    Text := Obj.ToJSON;
    AssureValidJsonText(Text); // WP4 S13: never hand garbage to the writer
    WriteTextAtomic(APath, Text);
  finally
    Obj.Free;
  end;
end;

end.
