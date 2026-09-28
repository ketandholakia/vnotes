unit uSyncJournal;

// Phase 7G/WP2: the local deletion (tombstone) journal - sync-journal.json.
//
// The journal is the durable record of "this guid was explicitly deleted
// locally"; WP5 consults it to propagate deletions as tombstones. It is a
// separate file from sync-state.json on purpose (design S4.2): sync-state is
// written only after a completed run, while a deletion must be durable the
// moment it happens.
//
// Format (design S4.2 - the exact approved representation):
//   { "version": 1,
//     "deletions": { "<guid>": { "rev": 7, "deletedAt": "<ISO>" } } }
//
// The object is lock-protected: the UI thread records deletions while a sync
// worker may be loading/migrating the same file. Save() refuses to write
// unless a Load() has succeeded - a corrupt journal must never be replaced
// with a silently emptied one.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs;

type
  ESyncJournalError = class(Exception);

  // One deletion record: the guid, the note's Rev at the moment of deletion
  // (design S4.2 - never a timestamp or a made-up number), and when it
  // happened (retention metadata for a future GC; nothing expires now).
  TSyncTombstone = record
    Guid: string;
    Rev: Int64;
    DeletedAt: TDateTime;
  end;

const
  SyncJournalVersion = 1;

  // Approved retention window (design S4.3). GC itself is deferred; this is
  // only used by IsTombstoneExpired below.
  TombstoneRetentionDays = 90;

// True when a tombstone is past the retention window. A pure calculation - it
// never removes or alters anything. An unknown DeletedAt (0) never expires.
function IsTombstoneExpired(const ATombstone: TSyncTombstone; ANow: TDateTime;
  ARetentionDays: Integer = TombstoneRetentionDays): Boolean;

type
  TSyncJournal = class
  private
    FPath: string;
    FLoaded: Boolean; // set only by a successful Load
    FLock: TCriticalSection;
    FTombstones: TDictionary<string, TSyncTombstone>;
    procedure LoadCore;
    procedure SaveCore;
    procedure AddCore(const AGuid: string; ARev: Int64; ADeletedAt: TDateTime);
  public
    constructor Create(const APath: string);
    destructor Destroy; override;
    // Re-reads the file, replacing the in-memory set. Raises ESyncJournalError
    // on any problem; the file itself is left untouched.
    procedure Load;
    // Atomically writes the current set. Refuses (raises) when the last Load
    // did not succeed, so a corrupt file is never silently overwritten.
    procedure Save;
    // Records a deletion. Idempotent per guid: a repeated delete attempt of
    // the same note never adds a second entry (the map is keyed by guid).
    procedure Add(const AGuid: string; ARev: Int64; ADeletedAt: TDateTime);
    function TryGet(const AGuid: string; out ATombstone: TSyncTombstone): Boolean;
    procedure Remove(const AGuid: string);
    function Count: Integer;
    function Enumerate: TArray<TSyncTombstone>;
    property Path: string read FPath;
  end;

implementation

uses
  System.JSON, System.IOUtils,
  uAtomicFile, uIdentity, uIso8601, uILogger;

function IsTombstoneExpired(const ATombstone: TSyncTombstone; ANow: TDateTime;
  ARetentionDays: Integer): Boolean;
begin
  Result := (ARetentionDays > 0) and (ATombstone.DeletedAt <> 0) and
    (ANow - ATombstone.DeletedAt >= ARetentionDays);
end;

{ TSyncJournal }

constructor TSyncJournal.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
  FLock := TCriticalSection.Create;
  FTombstones := TDictionary<string, TSyncTombstone>.Create;
end;

destructor TSyncJournal.Destroy;
begin
  FTombstones.Free;
  FLock.Free;
  inherited;
end;

procedure TSyncJournal.LoadCore;
var
  Text: string;
  Root: TJSONValue;
  Obj, Deletions, EntryObj: TJSONObject;
  Pair: TJSONPair;
  VersionVal, RevVal, DeletedAtVal: TJSONValue;
  Version: Integer;
  Tombstone: TSyncTombstone;
  Logger: ILogger;
begin
  // A failed load leaves FLoaded = False, so nothing can be Saved until a
  // later Load succeeds: the corrupt file is never overwritten.
  FLoaded := False;
  FTombstones.Clear;
  if FPath = '' then
    raise ESyncJournalError.Create('sync journal path is not configured');
  if not FileExists(FPath) then
  begin
    FLoaded := True; // no journal yet: a valid empty set
    Exit;
  end;
  Logger := CreateLogger;
  try
    Text := TFile.ReadAllText(FPath);
  except
    on E: Exception do
      raise ESyncJournalError.Create('sync journal could not be read (' + E.Message + ')');
  end;
  Root := TJSONObject.ParseJSONValue(Text);
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    raise ESyncJournalError.Create('sync journal is not valid JSON (file preserved)');
  end;
  try
    Obj := Root as TJSONObject;
    VersionVal := Obj.GetValue('version');
    if not (VersionVal is TJSONNumber) then
      raise ESyncJournalError.Create('sync journal has no numeric version');
    Version := (VersionVal as TJSONNumber).AsInt;
    if Version <> SyncJournalVersion then
      raise ESyncJournalError.CreateFmt('sync journal version %d is not supported', [Version]);

    Deletions := Obj.GetValue('deletions') as TJSONObject;
    if Deletions = nil then
      raise ESyncJournalError.Create('sync journal has no "deletions" object');

    for Pair in Deletions do
    begin
      if (Pair.JsonString = nil) or (not IsValidNoteGuid(Pair.JsonString.Value)) then
      begin
        Logger.Warning('Sync journal: dropping entry with invalid guid');
        Continue;
      end;
      if not (Pair.JsonValue is TJSONObject) then
      begin
        Logger.Warning('Sync journal: dropping malformed entry for ' + Pair.JsonString.Value);
        Continue;
      end;
      EntryObj := Pair.JsonValue as TJSONObject;
      Tombstone.Guid := Pair.JsonString.Value;
      Tombstone.Rev := 0;
      RevVal := EntryObj.GetValue('rev');
      if RevVal is TJSONNumber then
      begin
        Tombstone.Rev := (RevVal as TJSONNumber).AsInt64;
        if Tombstone.Rev < 0 then
          Tombstone.Rev := 0;
      end
      else if RevVal <> nil then
        Logger.Warning('Sync journal: entry ' + Tombstone.Guid +
          ' has a non-numeric rev; using 0 (unknown)');
      Tombstone.DeletedAt := 0;
      DeletedAtVal := EntryObj.GetValue('deletedAt');
      if DeletedAtVal is TJSONString then
        Tombstone.DeletedAt := StoredISO8601ToDateTime((DeletedAtVal as TJSONString).Value, 0);
      if Tombstone.DeletedAt = 0 then
        Logger.Warning('Sync journal: entry ' + Tombstone.Guid +
          ' has no readable deletedAt; retention metadata unavailable');
      FTombstones.AddOrSetValue(Tombstone.Guid, Tombstone);
    end;
    FLoaded := True;
  finally
    Root.Free;
  end;
end;

procedure TSyncJournal.SaveCore;
var
  Obj, Deletions, Entry: TJSONObject;
  Tombstone: TSyncTombstone;
  Text: string;
begin
  if not FLoaded then
    raise ESyncJournalError.Create(
      'sync journal was not loaded successfully; refusing to save (file left untouched)');
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('version', TJSONNumber.Create(SyncJournalVersion));
    Deletions := TJSONObject.Create;
    for Tombstone in FTombstones.Values do
    begin
      Entry := TJSONObject.Create;
      Entry.AddPair('rev', TJSONNumber.Create(Tombstone.Rev));
      if Tombstone.DeletedAt <> 0 then
        Entry.AddPair('deletedAt', DateTimeToStoredISO8601(Tombstone.DeletedAt));
      Deletions.AddPair(Tombstone.Guid, Entry);
    end;
    Obj.AddPair('deletions', Deletions);
    Text := Obj.ToJSON;
    AssureValidJsonText(Text); // WP4 S13: never hand garbage to the writer
    WriteTextAtomic(FPath, Text);
  finally
    Obj.Free;
  end;
end;

procedure TSyncJournal.AddCore(const AGuid: string; ARev: Int64; ADeletedAt: TDateTime);
var
  Tombstone: TSyncTombstone;
begin
  if not IsValidNoteGuid(AGuid) then
    raise ESyncJournalError.Create('sync journal: refusing to record an invalid guid (' + AGuid + ')');
  Tombstone.Guid := AGuid;
  Tombstone.Rev := ARev;
  Tombstone.DeletedAt := ADeletedAt;
  FTombstones.AddOrSetValue(AGuid, Tombstone);
end;

procedure TSyncJournal.Load;
begin
  FLock.Enter;
  try
    LoadCore;
  finally
    FLock.Leave;
  end;
end;

procedure TSyncJournal.Save;
begin
  FLock.Enter;
  try
    SaveCore;
  finally
    FLock.Leave;
  end;
end;

procedure TSyncJournal.Add(const AGuid: string; ARev: Int64; ADeletedAt: TDateTime);
begin
  FLock.Enter;
  try
    if not FLoaded then
      LoadCore;
    AddCore(AGuid, ARev, ADeletedAt);
  finally
    FLock.Leave;
  end;
end;

function TSyncJournal.TryGet(const AGuid: string; out ATombstone: TSyncTombstone): Boolean;
begin
  FLock.Enter;
  try
    if not FLoaded then
      LoadCore;
    Result := FTombstones.TryGetValue(AGuid, ATombstone);
  finally
    FLock.Leave;
  end;
end;

procedure TSyncJournal.Remove(const AGuid: string);
begin
  FLock.Enter;
  try
    if not FLoaded then
      LoadCore;
    FTombstones.Remove(AGuid);
  finally
    FLock.Leave;
  end;
end;

function TSyncJournal.Count: Integer;
begin
  FLock.Enter;
  try
    if not FLoaded then
      LoadCore;
    Result := FTombstones.Count;
  finally
    FLock.Leave;
  end;
end;

function TSyncJournal.Enumerate: TArray<TSyncTombstone>;
var
  Tombstone: TSyncTombstone;
  I: Integer;
begin
  FLock.Enter;
  try
    if not FLoaded then
      LoadCore;
    SetLength(Result, FTombstones.Count);
    I := 0;
    for Tombstone in FTombstones.Values do
    begin
      Result[I] := Tombstone;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

end.
