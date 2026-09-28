unit uSyncEngine;

// Phase 7B: the reconcile engine.
//
// Phase 7G/WP1 foundation: the reconcile now runs from an immutable,
// main-thread-captured value snapshot, and every local mutation is applied
// through a main-thread compare-and-set (GUID + expected Rev). The worker
// never dereferences a live TNote: if a note changed or vanished after the
// snapshot, the mutation is deferred and the next run reconciles it. Runs are
// non-reentrant and cancellable (ISyncService.Cancel), and the synced baseline
// records revisions that actually completed - never a re-read of the live
// note.
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
//
// WP1 deliberately keeps the reconcile semantics above unchanged; the WP5
// rewrite (docs/PHASE_7G_RECONCILE_DESIGN.md) replaces them on top of this
// snapshot + CAS foundation.
//
// Phase 7G/WP2: sync-state.json is now version 2 ({"version":2,"synced":...};
// v1 files migrate once into the journal) and local deletions are recorded
// durably in sync-journal.json via RecordLocalDeletion (the journal is loaded
// on the main thread before each run).
//
// Phase 7G/WP3: the synced baseline is reconstructed strictly from completed
// operations (pushed / pulled / created / verified-unchanged); deferred or
// failed work keeps its previous baseline and is retried, and LastRunSummary
// exposes per-run accounting for tests and WP5.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uNote, uNoteManager, uServiceInterfaces, uSyncJournal;

type
  // WP1: outcome of a compare-and-set mutation attempt made on the sync
  // worker's behalf. arDeferred covers "the note changed since the snapshot"
  // as well as "the create-guard found the guid already present"; either way
  // the next run re-evaluates the note.
  TSyncApplyResult = (arApplied, arDeferred, arNotFound, arCancelled);

  // WP1: an immutable snapshot of everything the reconcile needs from one
  // local note. Captured on the main thread; the worker operates on copies of
  // this record only. Payload and Signature are computed at capture time (on
  // the main thread) so the worker never touches a live TNote.
  TSyncNoteSnapshot = record
    Guid: string;
    Rev: Int64;
    DeviceId: string;
    Title: string;
    Payload: string;
    Signature: string;
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Height: Integer;
  end;

  // WP3: accounting for one sync run. Counts include only operations that
  // actually completed; Deferred counts operations skipped for the next run
  // (they never advance the baseline). Succeeded means the run finished
  // without an abort (deferrals are allowed); Cancelled marks a run stopped
  // by ISyncService.Cancel.
  TSyncRunSummary = record
    Succeeded: Boolean;
    Cancelled: Boolean;
    Pushed: Integer;     // local payloads accepted by the backend
    Pulled: Integer;     // remote payloads applied locally
    Created: Integer;    // of Pulled: notes newly created locally
    Removed: Integer;    // local deletions propagated to the backend
    Conflicts: Integer;  // conflict resolutions performed
    Deferred: Integer;   // operations skipped for the next run
  end;

  TSyncEngine = class(TInterfacedObject, ISyncService)
  private
    FNoteManager: INoteManager;
    FBackend: ISyncBackend;
    FStatePath: string;
    FSynced: TDictionary<string, Int64>;    // guid -> rev at last successful sync
    FDeleted: TDictionary<string, Boolean>; // guids deleted locally since a prior sync
    // WP2: durable local-deletion journal (sync-journal.json, sibling of the
    // state file); the UI thread records into it while a run may be loading it.
    FJournal: TSyncJournal;
    FOnProgress: TSyncProgress;
    FOnComplete: TSyncComplete;
    // WP1: run gate and cooperative cancellation. Both fields are touched from
    // more than one thread, always via TInterlocked.
    FSyncActive: Integer;      // 0 = idle, 1 = a run is in flight
    FCancelRequested: Integer; // 0 = normal, 1 = stop at the next checkpoint
    // WP3: accounting for the most recent run (zeroed when a run starts).
    FLastRunSummary: TSyncRunSummary;
    function GetOnProgress: TSyncProgress;
    procedure SetOnProgress(const Value: TSyncProgress);
    function GetOnComplete: TSyncComplete;
    procedure SetOnComplete(const Value: TSyncComplete);
    procedure Report(const AMessage: string; AProgress: Integer);
    procedure NotifyComplete(const ASuccess: Boolean; const AMessage: string);
    // WP2: parses sync-journal.json on the main thread (before reconcile), so
    // the worker only consumes already-loaded values.
    procedure LoadJournalOnMainThread;
    procedure LoadState;
    procedure SaveState;
    function ContentSignature(const ANote: TNote): string;
    function PayloadOf(const ANote: TNote): string;
    function TryParse(const APayload: string): TNote;
    procedure CopySyncedFields(const ASource, ADest: TNote; AKeepGeometry: Boolean);
    // WP1 - cancellation handling. CheckCancelled raises the private
    // ESyncCancelled to unwind a run without saving state.
    function TryEnterSync: Boolean;
    procedure LeaveSync;
    procedure ClearCancel;
    function IsCancelled: Boolean;
    procedure CheckCancelled;
    // WP1 - main-thread helpers. These read the live note model, so they must
    // only ever run on the main thread (inside TMainInvoker closures).
    function FindNoteByGuid(const AGuid: string): TNote;
    procedure CaptureSnapshot(const ADest: TDictionary<string, TSyncNoteSnapshot>);
  public
    constructor Create(const ANoteManager: INoteManager; const ABackend: ISyncBackend;
      const AStateFilePath: string);
    destructor Destroy; override;
    function IsConfigured: Boolean;
    function SyncNow: Boolean;
    // Phase 7G/WP1: cooperative cancellation. Safe to call at any time and
    // from any thread; a run notices at its next checkpoint and stops without
    // writing sync state.
    procedure Cancel;
    // Phase 7G/WP2: record a local note deletion in the journal the moment it
    // actually happened - durable before the next run ever starts. Repeated
    // calls for the same guid never produce a second entry.
    procedure RecordLocalDeletion(const AGuid: string; ARev: Int64);
    // Phase 7G/WP1: main-thread compare-and-set entry points used by the
    // reconcile below (and by the WP1 tests). AMutation runs on the main
    // thread, and only if the note still exists and still has AExpectedRev.
    function TryApplyNoteCAS(const AGuid: string; AExpectedRev: Int64;
      const AMutation: TProc<TNote>): TSyncApplyResult;
    // Creates a note on the main thread. With a non-empty AGuardGuid the
    // create is skipped (deferred) if a note with that guid already exists;
    // an empty guard marks a brand-new identity (e.g. a conflict copy).
    function TryCreateNoteCAS(const AGuardGuid: string;
      const ACreate: TProc): TSyncApplyResult;
    property OnProgress: TSyncProgress read GetOnProgress write SetOnProgress;
    property OnComplete: TSyncComplete read GetOnComplete write SetOnComplete;
    // Phase 7G/WP3: accounting for the most recent run. Written by the run
    // thread; read it after SyncNow returns (or after WaitForIdle).
    property LastRunSummary: TSyncRunSummary read FLastRunSummary;
  end;

implementation

uses
  System.JSON, System.Classes, System.SyncObjs, System.IOUtils,
  uJsonStorage, uSyncState, uILogger, uMainThread;

type
  // Raised by CheckCancelled to unwind a run that was cancelled. Private to
  // this unit: SyncNow catches it and reports a distinct cancellation outcome.
  ESyncCancelled = class(Exception);

{ TSyncEngine }

constructor TSyncEngine.Create(const ANoteManager: INoteManager; const ABackend: ISyncBackend;
  const AStateFilePath: string);
var
  JournalPath: string;
begin
  inherited Create;
  FNoteManager := ANoteManager;
  FBackend := ABackend;
  FStatePath := AStateFilePath;
  FSynced := TDictionary<string, Int64>.Create;
  FDeleted := TDictionary<string, Boolean>.Create;
  FSyncActive := 0;
  FCancelRequested := 0;
  // WP2: the journal lives next to the state file (design S4.2).
  JournalPath := '';
  if FStatePath <> '' then
    JournalPath := TPath.Combine(TPath.GetDirectoryName(FStatePath), 'sync-journal.json');
  FJournal := TSyncJournal.Create(JournalPath);
end;

destructor TSyncEngine.Destroy;
begin
  FJournal.Free;
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
  if not Assigned(FOnProgress) then Exit;
  // Marshalled: the callback may touch the UI.
  TMainInvoker.Run(
    procedure
    begin
      FOnProgress(AMessage, AProgress);
    end);
end;

procedure TSyncEngine.NotifyComplete(const ASuccess: Boolean; const AMessage: string);
begin
  if not Assigned(FOnComplete) then Exit;
  TMainInvoker.Run(
    procedure
    begin
      FOnComplete(ASuccess, AMessage);
    end);
end;

function TSyncEngine.TryEnterSync: Boolean;
begin
  // Non-reentrancy gate: only the caller that flips 0 -> 1 may run; a
  // concurrent second SyncNow gets False immediately.
  Result := TInterlocked.CompareExchange(FSyncActive, 1, 0) = 0;
end;

procedure TSyncEngine.LeaveSync;
begin
  TInterlocked.Exchange(FSyncActive, 0);
end;

procedure TSyncEngine.Cancel;
begin
  // Set-only: the flag is cleared when the next run starts, so cancelling with
  // no run in flight is a no-op.
  TInterlocked.Exchange(FCancelRequested, 1);
end;

function TSyncEngine.IsCancelled: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelRequested, 0, 0) <> 0;
end;

procedure TSyncEngine.ClearCancel;
begin
  TInterlocked.Exchange(FCancelRequested, 0);
end;

procedure TSyncEngine.CheckCancelled;
begin
  if IsCancelled then
    raise ESyncCancelled.Create('Sync run cancelled');
end;

procedure TSyncEngine.RecordLocalDeletion(const AGuid: string; ARev: Int64);
begin
  // Called the moment a note was actually deleted locally (the application
  // hooks TNoteManager.OnNoteDeleted, whose event only fires after the storage
  // delete succeeded). Durable immediately: a crash before the next run must
  // not lose the deletion (design S4.2). Journal.Add is per-guid, so repeated
  // delete attempts never produce duplicate entries.
  FJournal.Add(AGuid, ARev, Now);
  FJournal.Save;
end;

function TSyncEngine.FindNoteByGuid(const AGuid: string): TNote;
var
  I: Integer;
  Note: TNote;
begin
  // Main thread only (reads the live note model); called from CAS closures.
  Result := nil;
  if AGuid = '' then Exit;
  for I := 0 to FNoteManager.NoteCount - 1 do
  begin
    Note := FNoteManager.Notes[I];
    if (Note <> nil) and (Note.Guid = AGuid) then
      Exit(Note);
  end;
end;

procedure TSyncEngine.CaptureSnapshot(const ADest: TDictionary<string, TSyncNoteSnapshot>);
begin
  // The note model is UI-thread owned: capture, once, every value the worker
  // will need - payload and signature included. After this call the note
  // objects may change or be freed at any time and the run is unaffected.
  TMainInvoker.Run(
    procedure
    var
      Idx: Integer;
      Note: TNote;
      Snap: TSyncNoteSnapshot;
    begin
      for Idx := 0 to FNoteManager.NoteCount - 1 do
      begin
        Note := FNoteManager.Notes[Idx];
        if Note = nil then Continue;
        if Note.Guid = '' then
          FNoteManager.PersistNote(Note); // storage stamps a guid
        if Note.Guid = '' then Continue;
        Snap.Guid := Note.Guid;
        Snap.Rev := Note.Rev;
        Snap.DeviceId := Note.DeviceId;
        Snap.Title := Note.Title;
        Snap.Payload := PayloadOf(Note);
        Snap.Signature := ContentSignature(Note);
        Snap.Left := Note.Left;
        Snap.Top := Note.Top;
        Snap.Width := Note.Width;
        Snap.Height := Note.Height;
        ADest.AddOrSetValue(Snap.Guid, Snap);
      end;
    end);
end;

function TSyncEngine.TryApplyNoteCAS(const AGuid: string; AExpectedRev: Int64;
  const AMutation: TProc<TNote>): TSyncApplyResult;
var
  Outcome: TSyncApplyResult;
begin
  if IsCancelled then Exit(arCancelled);
  Outcome := arDeferred; // safe default: never pretend something was applied
  TMainInvoker.Run(
    procedure
    var
      Note: TNote;
    begin
      Note := FindNoteByGuid(AGuid);
      if Note = nil then
      begin
        // Deleted (or replaced) on the main thread while the run was in
        // flight: never resurrect it here; the next run reconciles.
        Outcome := arNotFound;
        Exit;
      end;
      if Note.Rev <> AExpectedRev then
      begin
        // A local edit raced the snapshot. Applying the stale mutation would
        // overwrite it, so defer - the next run sees the new revision.
        Outcome := arDeferred;
        Exit;
      end;
      AMutation(Note);
      Outcome := arApplied;
    end);
  Result := Outcome;
end;

function TSyncEngine.TryCreateNoteCAS(const AGuardGuid: string;
  const ACreate: TProc): TSyncApplyResult;
var
  Outcome: TSyncApplyResult;
begin
  if IsCancelled then Exit(arCancelled);
  Outcome := arDeferred; // safe default: never pretend something was applied
  TMainInvoker.Run(
    procedure
    begin
      if (AGuardGuid <> '') and (FindNoteByGuid(AGuardGuid) <> nil) then
      begin
        // The guid is no longer absent - do not create a second note with it.
        Outcome := arDeferred;
        Exit;
      end;
      ACreate();
      Outcome := arApplied;
    end);
  Result := Outcome;
end;

procedure TSyncEngine.LoadJournalOnMainThread;
var
  LoadError: string;
begin
  if FJournal.Path = '' then Exit;
  LoadError := '';
  // The journal is parsed on the main thread (WP2 design S16): the worker only
  // consumes already-loaded values. The explicit error capture keeps this
  // robust regardless of how TThread.Synchronize propagates exceptions.
  TMainInvoker.Run(
    procedure
    begin
      try
        FJournal.Load;
      except
        on E: Exception do
          LoadError := E.Message;
      end;
    end);
  if LoadError <> '' then
    raise ESyncJournalError.Create('sync journal could not be loaded: ' + LoadError);
end;

procedure TSyncEngine.LoadState;
var
  Loaded: TDictionary<string, Int64>;
begin
  // WP2: version-2 state (with a one-time v1 -> v2 migration into the
  // journal). A file that cannot be used raises - the run then aborts instead
  // of silently treating synchronized metadata as empty. FDeleted is
  // runtime-only in v2 and deliberately keeps accumulating for the engine's
  // lifetime (its in-file role has moved to the journal).
  Loaded := LoadSyncState(FStatePath, FJournal);
  FSynced.Free;
  FSynced := Loaded;
end;

procedure TSyncEngine.SaveState;
begin
  SaveSyncState(FStatePath, FSynced);
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
  Snapshot: TDictionary<string, TSyncNoteSnapshot>;
  RemoteSet: TDictionary<string, Boolean>;
  DeferredGuids: TDictionary<string, Boolean>;
  AppliedPulls: TDictionary<string, Int64>;
  CreatedGuids: TDictionary<string, Int64>; // WP3: guid -> applied remote rev
  NewSynced: TDictionary<string, Int64>;
  RemoteNames: TArray<string>;
  Guid, Payload, RemoteETag: string;
  UseETags: Boolean;
  Snap: TSyncNoteSnapshot;
  RemoteNote: TNote;
  LocalRev, RemoteRev, AppliedRev, PreviousRev: Int64;
  Pushed, Pulled, Created, Conflicts, Removed, Deferred: Integer;
  ApplyResult: TSyncApplyResult;
  Logger: ILogger;

  // WP1: verify (on the main thread) that the live note still exists and still
  // has the snapshot revision before a backend write carries its payload.
  function ValidateNoteCAS: TSyncApplyResult;
  begin
    Result := TryApplyNoteCAS(Snap.Guid, Snap.Rev,
      procedure(Note: TNote)
      begin
        // Existence + revision check only; the write itself happens after.
      end);
  end;

begin
  Result := False;
  Logger := CreateLogger;
  // WP3: zero the counters up front so the run accounting is meaningful on
  // every exit path (success, cancellation, failure).
  Pushed := 0; Pulled := 0; Created := 0; Conflicts := 0; Removed := 0; Deferred := 0;
  FLastRunSummary := Default(TSyncRunSummary);
  if FBackend = nil then
  begin
    NotifyComplete(False, 'Sync is not configured');
    Exit;
  end;

  // WP1: one run at a time. A second request returns at once - no second
  // worker, no duplicated backend traffic.
  if not TryEnterSync then
  begin
    Logger.Info('Sync: a run is already in progress; request ignored');
    Exit;
  end;

  try
    try
      ClearCancel;
      Snapshot := TDictionary<string, TSyncNoteSnapshot>.Create;
      DeferredGuids := TDictionary<string, Boolean>.Create;
      AppliedPulls := TDictionary<string, Int64>.Create;
      CreatedGuids := TDictionary<string, Int64>.Create;
      try
        UseETags := FBackend.SupportsETags;
        LoadJournalOnMainThread; // main-thread parse (WP2 S16); fails the run if unreadable
        LoadState;
        Report('Scanning local notes...', 10);
        CaptureSnapshot(Snapshot); // main thread; worker never sees a live TNote
        RemoteSet := TDictionary<string, Boolean>.Create;
        try
          CheckCancelled; // before the first backend call
          RemoteNames := FBackend.ListNames;
          for Guid in RemoteNames do
            RemoteSet.AddOrSetValue(Guid, True);

          // Propagate local deletions FIRST: a guid we synced before, that is
          // no longer present locally and not already tombstoned, was deleted
          // here. Running this before the pull loop is what stops the remote
          // copy from resurrecting the note.
          for Guid in FSynced.Keys do
          begin
            CheckCancelled;
            if Snapshot.ContainsKey(Guid) then Continue;
            if FDeleted.ContainsKey(Guid) then Continue;
            FDeleted.AddOrSetValue(Guid, True);
            CheckCancelled; // immediately before the backend call
            FBackend.Remove(Guid);
            Inc(Removed);
          end;

          Report('Pulling remote changes...', 40);
          for Guid in RemoteNames do
          begin
            CheckCancelled;
            if UseETags then
              Payload := FBackend.ReadWithETag(Guid, RemoteETag)
            else
            begin
              Payload := FBackend.Read(Guid);
              RemoteETag := '';
            end;
            if Payload = '' then Continue;
            RemoteNote := TryParse(Payload);
            if RemoteNote = nil then Continue; // never act on unreadable remote data
            try
              RemoteRev := RemoteNote.Rev;

              // Locally-known deletion wins: keep it from resurrecting remotely.
              if FDeleted.ContainsKey(Guid) then
              begin
                CheckCancelled;
                FBackend.Remove(Guid);
                Inc(Removed);
                Continue;
              end;

              if not Snapshot.TryGetValue(Guid, Snap) then
              begin
                // New remote note -> materialise locally with a fresh local ID,
                // returning a Created window (consistent with the app's model).
                ApplyResult := TryCreateNoteCAS(Guid,
                  procedure
                  var
                    Created: TNote;
                  begin
                    Created := FNoteManager.CreateNote(RemoteNote.Title, RemoteNote.Content,
                      RemoteNote.Color, RemoteNote.Left, RemoteNote.Top, RemoteNote.Width,
                      RemoteNote.Height, RemoteNote.AlwaysOnTop);
                    CopySyncedFields(RemoteNote, Created, False);
                    FNoteManager.PersistNote(Created);
                  end);
                case ApplyResult of
                  arApplied:
                    begin
                      // WP3: a created note is an applied operation - its
                      // baseline advances to the applied remote revision
                      // (design S2.4).
                      Inc(Pulled);
                      Inc(Created);
                      CreatedGuids.AddOrSetValue(Guid, RemoteRev);
                    end;
                  arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                else
                  Inc(Deferred);
                end;
                Continue;
              end;

              LocalRev := Snap.Rev; // from the snapshot, never from the live note
              if RemoteRev > LocalRev then
              begin
                // Apply the pull through the CAS gate: if the user edited this
                // note while the run was in flight, the apply is skipped and
                // the next run reconciles the newer revision.
                ApplyResult := TryApplyNoteCAS(Guid, Snap.Rev,
                  procedure(Note: TNote)
                  begin
                    CopySyncedFields(RemoteNote, Note, True); // keep local geometry
                    FNoteManager.PersistNote(Note);
                  end);
                case ApplyResult of
                  arApplied:
                    begin
                      Inc(Pulled);
                      AppliedPulls.AddOrSetValue(Guid, RemoteRev);
                    end;
                  arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                else
                  begin
                    Inc(Deferred);
                    DeferredGuids.AddOrSetValue(Guid, True);
                  end;
                end;
              end
              else if RemoteRev < LocalRev then
              begin
                // Do not push a snapshot the user has since changed or deleted:
                // verify on the main thread first, then do the backend write.
                ApplyResult := ValidateNoteCAS;
                if ApplyResult = arCancelled then
                  raise ESyncCancelled.Create('Sync run cancelled');
                if ApplyResult <> arApplied then
                begin
                  Inc(Deferred);
                  DeferredGuids.AddOrSetValue(Guid, True);
                  Logger.Warning('Sync: ' + Guid + ' changed locally during sync; push deferred');
                  Continue;
                end;
                CheckCancelled;
                if (not UseETags) or FBackend.WriteIfMatch(Guid, Snap.Payload, RemoteETag) then
                  Inc(Pushed)
                else
                begin
                  // The remote changed underneath us between read and write;
                  // make no destructive move - the next run re-reads and
                  // reconciles.
                  Inc(Conflicts);
                  Inc(Deferred);
                  DeferredGuids.AddOrSetValue(Guid, True);
                  Logger.Warning('Sync: remote ' + Guid + ' changed during sync; deferring to next run');
                end;
              end
              else if Snap.Signature <> ContentSignature(RemoteNote) then
              begin
                // Equal revision, diverged content: keep local, never lose the
                // remote edit - preserve it as a visible conflict copy.
                ApplyResult := TryCreateNoteCAS('',
                  procedure
                  var
                    ConflictNote: TNote;
                  begin
                    ConflictNote := FNoteManager.CreateNote(
                      Snap.Title + ' (conflict from ' + Copy(RemoteNote.DeviceId, 1, 8) + ')',
                      RemoteNote.Content, RemoteNote.Color, Snap.Left + 30, Snap.Top + 30,
                      Snap.Width, Snap.Height, False);
                    CopySyncedFields(RemoteNote, ConflictNote, False);
                    ConflictNote.Guid := ''; // a NEW note, not the same identity
                    ConflictNote.Rev := 1;
                    ConflictNote.ConflictOf := Snap.Guid; // Phase 7C: mark it resolvable
                    FNoteManager.PersistNote(ConflictNote);
                  end);
                if ApplyResult = arCancelled then
                  raise ESyncCancelled.Create('Sync run cancelled');
                if ApplyResult <> arApplied then
                begin
                  Inc(Deferred);
                  DeferredGuids.AddOrSetValue(Guid, True);
                end;
                // Rewrite the remote with the kept local version - but only if
                // the local note still matches the snapshot.
                ApplyResult := ValidateNoteCAS;
                if ApplyResult = arCancelled then
                  raise ESyncCancelled.Create('Sync run cancelled');
                if ApplyResult <> arApplied then
                begin
                  Inc(Deferred);
                  DeferredGuids.AddOrSetValue(Guid, True);
                  Logger.Warning('Sync: ' + Guid + ' changed locally during sync; remote rewrite deferred');
                end
                else
                begin
                  CheckCancelled;
                  if UseETags then
                  begin
                    if not FBackend.WriteIfMatch(Guid, Snap.Payload, RemoteETag) then
                    begin
                      Inc(Deferred);
                      DeferredGuids.AddOrSetValue(Guid, True);
                      Logger.Warning('Sync: remote ' + Guid + ' changed during sync; conflict copy kept, remote rewrite deferred');
                    end;
                  end
                  else
                    FBackend.Write(Guid, Snap.Payload);
                end;
                Inc(Conflicts);
              end;
            finally
              RemoteNote.Free;
            end;
          end;

          Report('Pushing local changes...', 70);
          for Snap in Snapshot.Values do
          begin
            CheckCancelled;
            if RemoteSet.ContainsKey(Snap.Guid) then Continue; // already handled above
            // Verify the note still matches the snapshot, then write it as a
            // new object (If-None-Match: *) so we never clobber one created
            // remotely or locally mid-sync.
            ApplyResult := ValidateNoteCAS;
            if ApplyResult = arCancelled then
              raise ESyncCancelled.Create('Sync run cancelled');
            if ApplyResult <> arApplied then
            begin
              Inc(Deferred);
              DeferredGuids.AddOrSetValue(Snap.Guid, True);
              Logger.Warning('Sync: ' + Snap.Guid + ' changed locally during sync; push deferred');
              Continue;
            end;
            CheckCancelled; // immediately before the backend call
            if (not UseETags) or FBackend.WriteIfMatch(Snap.Guid, Snap.Payload, '') then
              Inc(Pushed)
            else
            begin
              Inc(Conflicts);
              Inc(Deferred);
              DeferredGuids.AddOrSetValue(Snap.Guid, True);
              Logger.Warning('Sync: ' + Snap.Guid + ' appeared remotely during sync; deferring to next run');
            end;
          end;

          // Record the new synced baseline: previous baseline + operations
          // that actually completed this run. Deferred or skipped notes keep
          // their previous baseline so the next run re-evaluates them - never
          // a re-read of the live note (WP3 design S17).
          NewSynced := TDictionary<string, Int64>.Create;
          try
            for Snap in Snapshot.Values do
            begin
              if DeferredGuids.ContainsKey(Snap.Guid) then
              begin
                if FSynced.TryGetValue(Snap.Guid, PreviousRev) then
                  NewSynced.AddOrSetValue(Snap.Guid, PreviousRev);
              end
              else if AppliedPulls.TryGetValue(Snap.Guid, AppliedRev) then
                NewSynced.AddOrSetValue(Snap.Guid, AppliedRev)
              else
                NewSynced.AddOrSetValue(Snap.Guid, Snap.Rev);
            end;
            // WP3: notes created from the remote are applied operations too -
            // their baseline advances to the applied remote revision.
            for Guid in CreatedGuids.Keys do
              NewSynced.AddOrSetValue(Guid, CreatedGuids[Guid]);
            FSynced.Free;
            FSynced := NewSynced;
            NewSynced := nil;
          finally
            NewSynced.Free;
          end;

          SaveState;
          Report('Sync complete', 100);
          Result := True;
          // WP3: publish the run accounting - only completed operations are in
          // these counts; deferred ones are counted separately.
          FLastRunSummary.Succeeded := True;
          FLastRunSummary.Cancelled := False;
          FLastRunSummary.Pushed := Pushed;
          FLastRunSummary.Pulled := Pulled;
          FLastRunSummary.Created := Created;
          FLastRunSummary.Removed := Removed;
          FLastRunSummary.Conflicts := Conflicts;
          FLastRunSummary.Deferred := Deferred;
          Logger.Info(Format('Sync: pushed %d, pulled %d, conflicts %d, removed %d, deferred %d',
            [Pushed, Pulled, Conflicts, Removed, Deferred]));
          if Assigned(FOnComplete) then
          begin
            // A partial run (anything skipped or deferred) must say so.
            if Deferred > 0 then
              NotifyComplete(True, Format(
                'Sync complete: %d pushed, %d pulled, %d conflicts, %d removed; %d deferred to next run',
                [Pushed, Pulled, Conflicts, Removed, Deferred]))
            else
              NotifyComplete(True, Format(
                'Sync complete: %d pushed, %d pulled, %d conflicts, %d removed',
                [Pushed, Pulled, Conflicts, Removed]));
          end;
        finally
          RemoteSet.Free;
        end;
      finally
        CreatedGuids.Free;
        AppliedPulls.Free;
        DeferredGuids.Free;
        Snapshot.Free;
      end;
    except
      on E: ESyncCancelled do
      begin
        // Distinct cancellation outcome; no state was written (design S6), so
        // the next run picks up whatever is still pending. Completed
        // operations already live in the local/remote stores and are
        // re-conciled - and only then recorded - by that next run.
        FLastRunSummary.Succeeded := False;
        FLastRunSummary.Cancelled := True;
        FLastRunSummary.Pushed := Pushed;
        FLastRunSummary.Pulled := Pulled;
        FLastRunSummary.Created := Created;
        FLastRunSummary.Removed := Removed;
        FLastRunSummary.Conflicts := Conflicts;
        FLastRunSummary.Deferred := Deferred;
        Logger.Info('Sync cancelled');
        NotifyComplete(False, 'Sync cancelled');
        Result := False;
      end;
      on E: Exception do
      begin
        // The run aborted: nothing is saved, and the affected operations have
        // not advanced the baseline (the state file is left untouched).
        FLastRunSummary.Succeeded := False;
        FLastRunSummary.Cancelled := False;
        FLastRunSummary.Pushed := Pushed;
        FLastRunSummary.Pulled := Pulled;
        FLastRunSummary.Created := Created;
        FLastRunSummary.Removed := Removed;
        FLastRunSummary.Conflicts := Conflicts;
        FLastRunSummary.Deferred := Deferred;
        Logger.Error('Sync failed: ' + E.Message);
        NotifyComplete(False, 'Sync failed: ' + E.Message);
        Result := False;
      end;
    end;
  finally
    LeaveSync;
  end;
end;

end.
