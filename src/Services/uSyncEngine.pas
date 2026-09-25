unit uSyncEngine;

// Phase 7B: the reconcile engine.
//
// Reconciles the local note set against an ISyncBackend by note guid:
//   * new local note        -> push to remote
//   * new remote note       -> pull into the local set (with a fresh local ID)
//   * both sides, remote rev higher -> pull (keeping device-local geometry)
//   * both sides, local rev higher  -> push
//   * both sides, equal rev, differing content -> keep local, write a conflict copy
//   * locally-deleted since last sync (tracked in a small state file)
//                           -> remove from remote so it cannot resurrect
//
// Design notes / deliberate 7B simplifications (see docs/PHASE_7_CLOUD_SYNC_DESIGN.md):
//   * Window geometry is device-local: it is never applied from a remote note.
//   * Ordering is by note Rev (monotonic), not by wall-clock time.
//   * The interchange format is the canonical JSON note payload (TJsonStorage),
//     so the local file format and the sync format can never drift apart.
//   * Unreadable / future-schema remote payloads are skipped, never applied.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uNote, uNoteManager, uServiceInterfaces;

type
  TSyncEngine = class(TInterfacedObject, ISyncService)
  private
    FNoteManager: INoteManager;
    FBackend: ISyncBackend;
    FStatePath: string;
    FSynced: TDictionary<string, Int64>;    // guid -> rev at last successful sync
    FDeleted: TDictionary<string, Boolean>; // guids deleted locally since a prior sync
    FOnProgress: TSyncProgress;
    FOnComplete: TSyncComplete;
    function GetOnProgress: TSyncProgress;
    procedure SetOnProgress(const Value: TSyncProgress);
    function GetOnComplete: TSyncComplete;
    procedure SetOnComplete(const Value: TSyncComplete);
    procedure Report(const AMessage: string; AProgress: Integer);
    procedure LoadState;
    procedure SaveState;
    function ContentSignature(const ANote: TNote): string;
    function PayloadOf(const ANote: TNote): string;
    function TryParse(const APayload: string): TNote;
    procedure CopySyncedFields(const ASource, ADest: TNote; AKeepGeometry: Boolean);
  public
    constructor Create(const ANoteManager: INoteManager; const ABackend: ISyncBackend;
      const AStateFilePath: string);
    destructor Destroy; override;
    function IsConfigured: Boolean;
    function SyncNow: Boolean;
    property OnProgress: TSyncProgress read GetOnProgress write SetOnProgress;
    property OnComplete: TSyncComplete read GetOnComplete write SetOnComplete;
  end;

implementation

uses
  System.JSON, System.Classes, System.IOUtils,
  uJsonStorage, uILogger;

{ TSyncEngine }

constructor TSyncEngine.Create(const ANoteManager: INoteManager; const ABackend: ISyncBackend;
  const AStateFilePath: string);
begin
  inherited Create;
  FNoteManager := ANoteManager;
  FBackend := ABackend;
  FStatePath := AStateFilePath;
  FSynced := TDictionary<string, Int64>.Create;
  FDeleted := TDictionary<string, Boolean>.Create;
end;

destructor TSyncEngine.Destroy;
begin
  FSynced.Free;
  FDeleted.Free;
  inherited;
end;

function TSyncEngine.GetOnProgress: TSyncProgress;
begin
  Result := FOnProgress;
end;

procedure TSyncEngine.SetOnProgress(const Value: TSyncProgress);
begin
  FOnProgress := Value;
end;

function TSyncEngine.GetOnComplete: TSyncComplete;
begin
  Result := FOnComplete;
end;

procedure TSyncEngine.SetOnComplete(const Value: TSyncComplete);
begin
  FOnComplete := Value;
end;

procedure TSyncEngine.Report(const AMessage: string; AProgress: Integer);
begin
  if Assigned(FOnProgress) then
    FOnProgress(AMessage, AProgress);
end;

procedure TSyncEngine.LoadState;
var
  Text: string;
  Root: TJSONValue;
  Obj, SyncedObj: TJSONObject;
  DeletedArr: TJSONArray;
  Pair: TJSONPair;
  I: Integer;
begin
  FSynced.Clear;
  FDeleted.Clear;
  if (FStatePath = '') or (not FileExists(FStatePath)) then Exit;
  try
    Text := TFile.ReadAllText(FStatePath);
    Root := TJSONObject.ParseJSONValue(Text);
    try
      if not (Root is TJSONObject) then Exit;
      Obj := Root as TJSONObject;
      SyncedObj := Obj.GetValue('synced') as TJSONObject;
      if SyncedObj <> nil then
        for Pair in SyncedObj do
          FSynced.AddOrSetValue(Pair.JsonString.Value, (Pair.JsonValue as TJSONNumber).AsInt64);
      DeletedArr := Obj.GetValue('deleted') as TJSONArray;
      if DeletedArr <> nil then
        for I := 0 to DeletedArr.Count - 1 do
          FDeleted.AddOrSetValue(DeletedArr.Items[I].Value, True);
    finally
      Root.Free;
    end;
  except
    on E: Exception do
      CreateLogger.Warning('Sync: could not read sync state (' + E.Message + '); treating as first sync');
  end;
end;

procedure TSyncEngine.SaveState;
var
  Obj, SyncedObj: TJSONObject;
  DeletedArr: TJSONArray;
  Guid: string;
begin
  Obj := TJSONObject.Create;
  try
    SyncedObj := TJSONObject.Create;
    for Guid in FSynced.Keys do
      SyncedObj.AddPair(Guid, TJSONNumber.Create(FSynced[Guid]));
    Obj.AddPair('synced', SyncedObj);

    DeletedArr := TJSONArray.Create;
    for Guid in FDeleted.Keys do
      DeletedArr.Add(Guid);
    Obj.AddPair('deleted', DeletedArr);

    TFile.WriteAllText(FStatePath, Obj.ToJSON, TEncoding.UTF8);
  finally
    Obj.Free;
  end;
end;

function TSyncEngine.ContentSignature(const ANote: TNote): string;
var
  Tags, Items: string;
  Tag: string;
  Item: TChecklistItem;
begin
  Tags := '';
  for Tag in ANote.Tags do
    Tags := Tags + Tag + #31;
  Items := '';
  for Item in ANote.ChecklistItems do
    Items := Items + Item.Text + #30 + BoolToStr(Item.Done, True) + #31;
  // Deliberately excludes geometry, ID, Guid, Rev, DeviceId and timestamps.
  Result := Format('%s|%s|%d|%s|%s|%s|%s|%s|%s',
    [ANote.Title, ANote.Content, Ord(ANote.Color),
     BoolToStr(ANote.AlwaysOnTop, True), BoolToStr(ANote.Collapsed, True),
     BoolToStr(ANote.Locked, True), BoolToStr(ANote.Favorite, True), Tags, Items]);
end;

function TSyncEngine.PayloadOf(const ANote: TNote): string;
var
  Json: TJSONObject;
begin
  Json := TJsonStorage.NoteToJson(ANote);
  try
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

function TSyncEngine.TryParse(const APayload: string): TNote;
var
  Root: TJSONValue;
begin
  Result := nil;
  try
    Root := TJSONObject.ParseJSONValue(APayload);
    if Root = nil then Exit;
    try
      if Root is TJSONObject then
        Result := TJsonStorage.JsonToNote(Root as TJSONObject);
    finally
      Root.Free;
    end;
  except
    on E: Exception do
    begin
      Result := nil;
      CreateLogger.Warning('Sync: skipping unreadable remote note (' + E.Message + ')');
    end;
  end;
end;

procedure TSyncEngine.CopySyncedFields(const ASource, ADest: TNote; AKeepGeometry: Boolean);
begin
  ADest.Title := ASource.Title;
  ADest.Content := ASource.Content;
  ADest.Color := ASource.Color;
  if not AKeepGeometry then
  begin
    ADest.Left := ASource.Left;
    ADest.Top := ASource.Top;
    ADest.Width := ASource.Width;
    ADest.Height := ASource.Height;
  end;
  ADest.AlwaysOnTop := ASource.AlwaysOnTop;
  ADest.Collapsed := ASource.Collapsed;
  ADest.Locked := ASource.Locked;
  ADest.Favorite := ASource.Favorite;
  ADest.Tags := System.Copy(ASource.Tags);
  ADest.ChecklistItems := System.Copy(ASource.ChecklistItems);
  ADest.CreatedAt := ASource.CreatedAt;
  ADest.UpdatedAt := ASource.UpdatedAt;
  ADest.Guid := ASource.Guid;
  ADest.Rev := ASource.Rev;
  ADest.DeviceId := ASource.DeviceId;
  ADest.Deleted := ASource.Deleted;
  ADest.DeletedAt := ASource.DeletedAt;
end;

function TSyncEngine.IsConfigured: Boolean;
begin
  Result := FBackend <> nil;
end;

function TSyncEngine.SyncNow: Boolean;
var
  LocalByGuid: TDictionary<string, TNote>;
  LocalOrder: TObjectList<TNote>;
  RemoteNames: TArray<string>;
  RemoteSet: TDictionary<string, Boolean>;
  Guid, Payload: string;
  Note, RemoteNote, ConflictNote: TNote;
  LocalRev, RemoteRev: Int64;
  Pushed, Pulled, Conflicts, Removed: Integer;
  Logger: ILogger;
  I: Integer;
begin
  Result := False;
  Logger := CreateLogger;
  if FBackend = nil then
  begin
    if Assigned(FOnComplete) then
      FOnComplete(False, 'Sync is not configured');
    Exit;
  end;

  Pushed := 0; Pulled := 0; Conflicts := 0; Removed := 0;
  LoadState;
  Report('Scanning local notes...', 10);

  LocalOrder := TObjectList<TNote>.Create(False); // references only
  LocalByGuid := TDictionary<string, TNote>.Create;
  try
    // Ensure every local note has a guid, then index it.
    for I := 0 to FNoteManager.NoteCount - 1 do
    begin
      Note := FNoteManager.Notes[I];
      if Note = nil then Continue;
      if Note.Guid = '' then
        FNoteManager.PersistNote(Note); // storage stamps a guid
      if Note.Guid <> '' then
      begin
        LocalOrder.Add(Note);
        LocalByGuid.AddOrSetValue(Note.Guid, Note);
      end;
    end;

    RemoteNames := FBackend.ListNames;
    RemoteSet := TDictionary<string, Boolean>.Create;
    try
      for Guid in RemoteNames do
        RemoteSet.AddOrSetValue(Guid, True);

      // Propagate local deletions FIRST: a guid we synced before, that is no
      // longer present locally and not already tombstoned, was deleted here.
      // Running this before the pull loop is what stops the remote copy from
      // resurrecting the note.
      for Guid in FSynced.Keys do
      begin
        if LocalByGuid.ContainsKey(Guid) then Continue;
        if FDeleted.ContainsKey(Guid) then Continue;
        FDeleted.AddOrSetValue(Guid, True);
        FBackend.Remove(Guid);
        Inc(Removed);
      end;

      Report('Pulling remote changes...', 40);
      for Guid in RemoteNames do
      begin
        Payload := FBackend.Read(Guid);
        if Payload = '' then Continue;
        RemoteNote := TryParse(Payload);
        if RemoteNote = nil then Continue; // never act on unreadable remote data
        try
          RemoteRev := RemoteNote.Rev;

          // Locally-known deletion wins: keep it from resurrecting remotely.
          if FDeleted.ContainsKey(Guid) then
          begin
            FBackend.Remove(Guid);
            Inc(Removed);
            Continue;
          end;

          if not LocalByGuid.ContainsKey(Guid) then
          begin
            // New remote note -> materialise locally with a fresh local ID,
            // returning a Created window (consistent with the app's model).
            Note := FNoteManager.CreateNote(RemoteNote.Title, RemoteNote.Content,
              RemoteNote.Color, RemoteNote.Left, RemoteNote.Top, RemoteNote.Width,
              RemoteNote.Height, RemoteNote.AlwaysOnTop);
            CopySyncedFields(RemoteNote, Note, False);
            FNoteManager.PersistNote(Note);
            LocalByGuid.AddOrSetValue(Guid, Note);
            Inc(Pulled);
            Continue;
          end;

          Note := LocalByGuid[Guid];
          LocalRev := Note.Rev;
          if RemoteRev > LocalRev then
          begin
            CopySyncedFields(RemoteNote, Note, True); // keep local geometry
            FNoteManager.PersistNote(Note);
            Inc(Pulled);
          end
          else if RemoteRev < LocalRev then
          begin
            FBackend.Write(Guid, PayloadOf(Note));
            Inc(Pushed);
          end
          else if ContentSignature(Note) <> ContentSignature(RemoteNote) then
          begin
            // Equal revision, diverged content: keep local, never lose the
            // remote edit - preserve it as a visible conflict copy.
            ConflictNote := FNoteManager.CreateNote(
              Note.Title + ' (conflict from ' + Copy(RemoteNote.DeviceId, 1, 8) + ')',
              RemoteNote.Content, RemoteNote.Color, Note.Left + 30, Note.Top + 30,
              Note.Width, Note.Height, False);
            CopySyncedFields(RemoteNote, ConflictNote, False);
            ConflictNote.Guid := ''; // a NEW note, not the same identity
            ConflictNote.Rev := 1;
            ConflictNote.ConflictOf := Note.Guid; // Phase 7C: mark it resolvable
            FNoteManager.PersistNote(ConflictNote);
            FBackend.Write(Guid, PayloadOf(Note));
            Inc(Conflicts);
          end;
        finally
          RemoteNote.Free;
        end;
      end;

      Report('Pushing local changes...', 70);
      for Note in LocalOrder do
      begin
        if RemoteSet.ContainsKey(Note.Guid) then Continue; // already handled above
        FBackend.Write(Note.Guid, PayloadOf(Note));
        Inc(Pushed);
      end;

      // Record the new synced baseline (only guids still present locally).
      FSynced.Clear;
      for Note in LocalOrder do
        FSynced.AddOrSetValue(Note.Guid, Note.Rev);

      SaveState;
      Report('Sync complete', 100);
      Result := True;
      Logger.Info(Format('Sync: pushed %d, pulled %d, conflicts %d, removed %d',
        [Pushed, Pulled, Conflicts, Removed]));
      if Assigned(FOnComplete) then
        FOnComplete(True, Format('Sync complete: %d pushed, %d pulled, %d conflicts, %d removed',
          [Pushed, Pulled, Conflicts, Removed]));
    finally
      RemoteSet.Free;
    end;
  except
    on E: Exception do
    begin
      Logger.Error('Sync failed: ' + E.Message);
      if Assigned(FOnComplete) then
        FOnComplete(False, 'Sync failed: ' + E.Message);
      Result := False;
    end;
  end;
  LocalOrder.Free;
  LocalByGuid.Free;
end;

end.
