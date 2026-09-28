unit uSyncEngine;

// Phase 7B: the reconcile engine.
//
// Phase 7G/WP1 foundation: the reconcile runs from an immutable,
// main-thread-captured value snapshot, and every local mutation is applied
// through a main-thread compare-and-set (GUID + expected Rev). The worker
// never dereferences a live TNote: if a note changed or vanished after the
// snapshot, the mutation is deferred and the next run reconciles it. Runs are
// non-reentrant and cancellable (ISyncService.Cancel), and the synced baseline
// records revisions that actually completed - never a re-read of the live
// note.
//
// Phase 7G/WP5: the reconcile decision matrix (docs/PHASE_7G_RECONCILE_DESIGN.md
// S2/S3) replaces the legacy absence-inference behavior. In brief:
//   * both live           -> revision comparison; equal content aligns revs;
//                            diverged content resolves by the deterministic
//                            winner rule (rev, then deviceId, then content
//                            hash) with a deterministic conflict copy.
//   * remote absent       -> never deletes: local notes are pushed, journal
//                            entries without a remote object are dropped.
//   * remote tombstone    -> deletes an unchanged local note ("edit beats
//                            delete" re-publishes a locally changed one).
//   * local absent + a durable journal entry + an unchanged remote object
//                            -> writes a tombstone (the only deletion form).
// The decision for one guid is a pure function of its inputs
// (ReconcileDecision); the executor below only applies it through the WP1
// snapshot/CAS boundary. Revs are never reset, every content-changing write
// advances them, and repeated runs reach a fixed point that writes nothing.
//
// Phase 7G/WP2: sync-state.json is version 2 ({"version":2,"synced":...};
// v1 files migrate once into the journal) and local deletions are recorded
// durably in sync-journal.json via RecordLocalDeletion (the journal is loaded
// on the main thread before each run).
//
// Phase 7G/WP3: the synced baseline is reconstructed strictly from completed
// operations (pushed / pulled / created / verified-unchanged); deferred or
// failed work keeps its previous baseline and is retried, and LastRunSummary
// exposes per-run accounting.
//
// Phase 7G/WP4: metadata is written through uAtomicFile (unique temp file,
// flush, atomic replace); a metadata persistence failure is surfaced and
// marked in the run summary.

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

  // WP5: the pure reconcile inputs for one guid (design S2). All values; no
  // I/O, no live objects.
  TReconcileInput = record
    Guid: string;              // the original guid (needed for the copy identity)
    LocalPresent: Boolean;     // a live local note exists in the snapshot
    LocalRev: Int64;
    LocalDeviceId: string;
    LocalSignature: string;
    RemotePresent: Boolean;    // the remote store has an object for this guid
    RemoteDeleted: Boolean;    // that object is a tombstone
    RemoteRev: Int64;
    RemoteDeviceId: string;
    RemoteSignature: string;
    BaselineKnown: Boolean;    // the previous baseline has an entry for the guid
    BaselineRev: Int64;
    JournalPresent: Boolean;   // the local deletion journal has an entry
    JournalRev: Int64;
  end;

  // WP5: the deterministic decision for one guid (design S2/S3).
  TSyncDecisionKind = (
    sdkNothing,         // no action (optionally drop a stale journal entry)
    sdkPushLocal,       // publish the local version at PublishRev
    sdkAdoptRev,        // identical content: adopt the higher remote rev locally
    sdkPullRemote,      // apply the remote version locally
    sdkDeleteLocal,     // apply a remote tombstone to an unchanged local note
    sdkWriteTombstone,  // propagate a local deletion at PublishRev
    sdkConflictPublish, // winner is local: publish it and keep the remote loser
    sdkConflictPull     // winner is remote: pull it and keep the local loser
  );

  TSyncDecision = record
    Kind: TSyncDecisionKind;
    PublishRev: Int64;    // the rev to publish; 0 when unused
    ClearJournal: Boolean; // drop the journal entry (after a successful apply)
    CopyGuid: string;     // deterministic conflict-copy identity ('' = none)
    // Defensive: diverged content with no changed-side flags. Unreachable
    // with this build; protects against same-rev content swaps from older
    // builds - treated as a conflict and logged.
    DefensiveWarning: Boolean;
  end;

  // WP5: the pure decision function (design S2/S3). Identical inputs produce
  // identical decisions on every replica: no randomness, no clock, no I/O, no
  // iteration order. Callers execute the decision through WP1's CAS boundary.
  function ReconcileDecision(const AInput: TReconcileInput): TSyncDecision;

type
  // WP3: accounting for one sync run. Counts include only operations that
  // actually completed; Deferred counts operations skipped for the next run
  // (they never advance the baseline). Succeeded means the run finished
  // without an abort AND its metadata was persisted (deferrals are allowed);
  // Cancelled marks a run stopped by ISyncService.Cancel.
  TSyncRunSummary = record
    Succeeded: Boolean;
    Cancelled: Boolean;
    // WP4: the operations completed but the sync metadata could not be
    // persisted (the previous valid metadata was preserved); the run is not
    // reported as fully synchronized.
    MetadataFailed: Boolean;
    Pushed: Integer;     // local payloads accepted by the backend
    Pulled: Integer;     // remote payloads applied locally
    Created: Integer;    // of Pulled: notes newly created locally
    Removed: Integer;    // local deletions applied from remote tombstones
    // WP5: deletions propagated to the remote as tombstones.
    TombstonesWritten: Integer;
    Conflicts: Integer;  // conflict resolutions performed
    Deferred: Integer;   // operations skipped for the next run
  end;

  TSyncEngine = class(TInterfacedObject, ISyncService)
  private
    FNoteManager: INoteManager;
    FBackend: ISyncBackend;
    FStatePath: string;
    FSynced: TDictionary<string, Int64>; // guid -> rev at last successful sync
    // WP2: durable local-deletion journal (sync-journal.json, sibling of the
    // state file); the UI thread records into it while a run may be loading it.
    FJournal: TSyncJournal;
    // WP5: this installation's device id (tombstone authorship; same source
    // as the note storages use).
    FDeviceId: string;
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
    // WP5: the same payload with a different Rev (conflict publishing).
    function PayloadWithRev(const APayload: string; ARev: Int64): string;
    // WP5: the canonical tombstone payload (design S4.1).
    function TombstonePayload(const AGuid: string; ARev: Int64; ADeletedAt: TDateTime): string;
    // WP5: the deterministic conflict-copy payload built from the loser.
    function ConflictCopyPayload(const ALoser: TNote; const AOrigGuid, ACopyGuid: string): string;
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
    // reconcile below (and by the tests). AMutation runs on the main thread,
    // and only if the note still exists and still has AExpectedRev.
    function TryApplyNoteCAS(const AGuid: string; AExpectedRev: Int64;
      const AMutation: TProc<TNote>): TSyncApplyResult;
    // Creates a note on the main thread. With a non-empty AGuardGuid the
    // create is skipped (deferred) if a note with that guid already exists.
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
  System.JSON, System.Classes, System.Hash, System.SyncObjs, System.IOUtils,
  uEnums, uJsonStorage, uSyncState, uIdentity, uILogger, uMainThread;

type
  // Raised by CheckCancelled to unwind a run that was cancelled. Private to
  // this unit: SyncNow catches it and reports a distinct cancellation outcome.
  ESyncCancelled = class(Exception);

  // WP5: the number of deletions (applied + written) in one run above which a
  // warn-only note is logged and appended to the completion message (design
  // S4.3). The threshold never aborts anything.
  TDeletionThreshold = class
  const
    Base = 25;
  end;

function MaxInt64(const A, B: Int64): Int64;
begin
  if A >= B then
    Result := A
  else
    Result := B;
end;

// WP5: lowercase SHA-256 hex (RTL System.Hash; SHA-256 is the default).
function Sha256HexLower(const AText: string): string;
begin
  Result := LowerCase(THashSHA2.GetHashString(AText));
end;

// WP5: the deterministic conflict-copy identity (design S3.2):
// SHA256(origGuid + '|' + loserDeviceId + '|' + loserRev), first 16 bytes as
// lowercase hex grouped like GenerateNoteGuid. Identical on every replica.
function ConflictCopyGuid(const AOrigGuid, ALoserDeviceId: string;
  ALoserRev: Int64): string;
var
  Hash: string;
begin
  Hash := Sha256HexLower(AOrigGuid + '|' + ALoserDeviceId + '|' + IntToStr(ALoserRev));
  Result := Copy(Hash, 1, 8) + '-' + Copy(Hash, 9, 4) + '-' + Copy(Hash, 13, 4) +
    '-' + Copy(Hash, 17, 4) + '-' + Copy(Hash, 21, 12);
end;

// WP5: the winner rule (design S3.1): Rev desc, then DeviceId desc, then
// content hash desc. Pure string/int comparison - deterministic everywhere.
function LocalVersionWins(ALocalRev: Int64; const ALocalDeviceId, ALocalHash: string;
  ARemoteRev: Int64; const ARemoteDeviceId, ARemoteHash: string): Boolean;
begin
  if ALocalRev <> ARemoteRev then
    Exit(ALocalRev > ARemoteRev);
  if ALocalDeviceId <> ARemoteDeviceId then
    Exit(ALocalDeviceId > ARemoteDeviceId);
  Result := ALocalHash > ARemoteHash;
end;

function ReconcileDecision(const AInput: TReconcileInput): TSyncDecision;
var
  ChangedL, ChangedR: Boolean;
begin
  Result.Kind := sdkNothing;
  Result.PublishRev := 0;
  Result.ClearJournal := False;
  Result.CopyGuid := '';
  Result.DefensiveWarning := False;

  // --- Remote absent (design S2.2): absence never deletes anything.
  if not AInput.RemotePresent then
  begin
    if AInput.LocalPresent then
    begin
      Result.Kind := sdkPushLocal;
      Result.PublishRev := AInput.LocalRev;
    end
    else if AInput.JournalPresent then
      Result.ClearJournal := True; // no remote presence to delete
    Exit;
  end;

  // --- Remote is a tombstone (design S2.3).
  if AInput.RemoteDeleted then
  begin
    if not AInput.LocalPresent then
    begin
      if AInput.JournalPresent then
        Result.ClearJournal := True; // the deletion is already represented remotely
      Exit;
    end;
    ChangedL := (not AInput.BaselineKnown) or (AInput.LocalRev > AInput.BaselineRev);
    if (not ChangedL) and AInput.BaselineKnown and
       (AInput.RemoteRev > AInput.BaselineRev) then
    begin
      // The local note is unchanged since the common state: apply the deletion.
      Result.Kind := sdkDeleteLocal;
    end
    else
    begin
      // Edit beats delete (locally changed, baseline unknown, or a stale
      // tombstone that predates the common state).
      Result.Kind := sdkPushLocal;
      Result.PublishRev := MaxInt64(AInput.LocalRev, AInput.RemoteRev) + 1;
    end;
    Exit;
  end;

  // --- Local absent, remote live (design S2.4).
  if not AInput.LocalPresent then
  begin
    if AInput.JournalPresent then
    begin
      if AInput.BaselineKnown and (AInput.RemoteRev = AInput.BaselineRev) then
      begin
        // The remote is unchanged since the common state: propagate the
        // deletion as a tombstone.
        Result.Kind := sdkWriteTombstone;
        Result.PublishRev := MaxInt64(AInput.RemoteRev, AInput.JournalRev) + 1;
        Result.ClearJournal := True;
      end
      else
      begin
        // Edit beats delete: the remote changed since the common state (or the
        // baseline is unknown); the note returns locally.
        Result.Kind := sdkPullRemote;
        Result.ClearJournal := True;
      end;
    end
    else
      Result.Kind := sdkPullRemote; // a new remote note
    Exit;
  end;

  // --- Both sides live (design S2.1).
  if AInput.LocalSignature = AInput.RemoteSignature then
  begin
    if AInput.LocalRev = AInput.RemoteRev then
      Exit; // already synchronized: no-op
    if AInput.LocalRev > AInput.RemoteRev then
    begin
      Result.Kind := sdkPushLocal; // bring the remote up to the local rev
      Result.PublishRev := AInput.LocalRev;
    end
    else
      Result.Kind := sdkAdoptRev; // identical content: adopt the higher rev
    Exit;
  end;

  ChangedL := (not AInput.BaselineKnown) or (AInput.LocalRev > AInput.BaselineRev);
  ChangedR := (not AInput.BaselineKnown) or (AInput.RemoteRev > AInput.BaselineRev);
  if ChangedL and (not ChangedR) then
  begin
    Result.Kind := sdkPushLocal;
    Result.PublishRev := AInput.LocalRev;
    Exit;
  end;
  if ChangedR and (not ChangedL) then
  begin
    Result.Kind := sdkPullRemote;
    Exit;
  end;

  // --- Conflict (both changed, baseline unknown, or the defensive row).
  Result.DefensiveWarning := (not ChangedL) and (not ChangedR);
  if LocalVersionWins(AInput.LocalRev, AInput.LocalDeviceId,
       Sha256HexLower(AInput.LocalSignature),
       AInput.RemoteRev, AInput.RemoteDeviceId,
       Sha256HexLower(AInput.RemoteSignature)) then
  begin
    Result.Kind := sdkConflictPublish;
    Result.PublishRev := MaxInt64(AInput.LocalRev, AInput.RemoteRev) + 1;
    // The loser is the remote version; preserve it under the deterministic
    // identity derived from the loser's device id and revision.
    Result.CopyGuid := ConflictCopyGuid(AInput.Guid, AInput.RemoteDeviceId,
      AInput.RemoteRev);
  end
  else
  begin
    Result.Kind := sdkConflictPull;
    Result.CopyGuid := ConflictCopyGuid(AInput.Guid, AInput.LocalDeviceId,
      AInput.LocalRev);
  end;
end;

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
  FSyncActive := 0;
  FCancelRequested := 0;
  // WP2: the journal lives next to the state file (design S4.2).
  // WP5: the device id (tombstone authorship) comes from the same profile.
  JournalPath := '';
  if FStatePath <> '' then
  begin
    JournalPath := TPath.Combine(TPath.GetDirectoryName(FStatePath), 'sync-journal.json');
    FDeviceId := GetOrCreateDeviceId(TPath.GetDirectoryName(FStatePath));
  end;
  FJournal := TSyncJournal.Create(JournalPath);
end;

destructor TSyncEngine.Destroy;
begin
  FJournal.Free;
  FSynced.Free;
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
  // of silently treating synchronized metadata as empty.
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

function TSyncEngine.PayloadWithRev(const APayload: string; ARev: Int64): string;
var
  Note: TNote;
begin
  Result := '';
  Note := TryParse(APayload);
  if Note = nil then Exit;
  try
    Note.Rev := ARev;
    Result := PayloadOf(Note);
  finally
    Note.Free;
  end;
end;

function TSyncEngine.TombstonePayload(const AGuid: string; ARev: Int64;
  ADeletedAt: TDateTime): string;
var
  Tomb: TNote;
begin
  // Design S4.1: canonical note payload with Deleted = true and empty content.
  Tomb := TNote.Create(1, '', '', ncYellow);
  try
    Tomb.Guid := AGuid;
    Tomb.Rev := ARev;
    Tomb.DeviceId := FDeviceId;
    Tomb.Deleted := True;
    Tomb.DeletedAt := ADeletedAt;
    Tomb.CreatedAt := ADeletedAt;
    Tomb.UpdatedAt := ADeletedAt;
    Result := PayloadOf(Tomb);
  finally
    Tomb.Free;
  end;
end;

function TSyncEngine.ConflictCopyPayload(const ALoser: TNote;
  const AOrigGuid, ACopyGuid: string): string;
var
  Copy: TNote;
begin
  // Design S3.2: the loser's synced fields under the deterministic identity;
  // every field here is a pure function of the loser, so both replicas build
  // byte-identical payloads.
  Copy := TNote.Create(1, '', '', ncYellow);
  try
    CopySyncedFields(ALoser, Copy, True);
    Copy.Title := ALoser.Title + ' (conflict from ' +
      System.Copy(ALoser.DeviceId, 1, 8) + ')';
    Copy.Guid := ACopyGuid;
    Copy.Rev := ALoser.Rev;
    Copy.DeviceId := ALoser.DeviceId;
    Copy.ConflictOf := AOrigGuid;
    Result := PayloadOf(Copy);
  finally
    Copy.Free;
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
  PushedRevs: TDictionary<string, Int64>;
  CreatedGuids: TDictionary<string, Int64>;      // WP3: guid -> applied rev
  ResolvedDeletions: TDictionary<string, Int64>; // WP5: guid -> tombstone/applied rev
  PendingTombstones: TDictionary<string, Boolean>; // WP5: deferred tombstone writes
  NewSynced: TDictionary<string, Int64>;
  RemoteNames: TArray<string>;
  Guid, Payload, RemoteETag, Msg: string;
  UseETags: Boolean;
  Snap: TSyncNoteSnapshot;
  RemoteNote, RemoteNote2: TNote;
  LocalRev, RemoteRev, PreviousRev, AppliedRev: Int64;
  Pushed, Pulled, Created, Conflicts, Removed, TombstonesWritten, DeletedTotal,
    Deferred, Threshold: Integer;
  ApplyResult: TSyncApplyResult;
  JournalChanged: Boolean;
  JournalTomb: TSyncTombstone;
  ReconcileCtx: TReconcileInput;
  Decision: TSyncDecision;
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

  procedure MarkDeferred(const AGuid: string);
  begin
    Inc(Deferred);
    DeferredGuids.AddOrSetValue(AGuid, True);
  end;

  procedure ClearJournalEntry(const AGuid: string);
  begin
    FJournal.Remove(AGuid);
    JournalChanged := True;
  end;

  // WP5: ensure the deterministic conflict copy exists locally and remotely;
  // creation is idempotent (create-if-absent + If-None-Match) so repeated
  // reconciliation never produces a second copy.
  procedure EnsureConflictCopy(const AOrigGuid, ACopyGuid, ALoserDeviceId: string;
    ALoserRev: Int64; ALoser: TNote);
  begin
    if ACopyGuid = '' then Exit;
    if RemoteSet.ContainsKey(ACopyGuid) then Exit;      // already on the remote
    if CreatedGuids.ContainsKey(ACopyGuid) then Exit;   // created earlier in this run
    ApplyResult := TryCreateNoteCAS(ACopyGuid,
      procedure
      var
        NewCopy: TNote;
      begin
        NewCopy := FNoteManager.CreateNote(
          ALoser.Title, ALoser.Content, ALoser.Color, Snap.Left + 30, Snap.Top + 30,
          Snap.Width, Snap.Height, ALoser.AlwaysOnTop);
        CopySyncedFields(ALoser, NewCopy, True); // keep the +30 offset geometry
        // The deterministic title suffix must be applied AFTER CopySyncedFields
        // (mirroring ConflictCopyPayload exactly): otherwise the local copy's
        // signature would differ from the pushed payload's and the copy would
        // re-resolve as a phantom conflict on the next run.
        NewCopy.Title := ALoser.Title + ' (conflict from ' +
          System.Copy(ALoserDeviceId, 1, 8) + ')';
        NewCopy.Guid := ACopyGuid;
        NewCopy.Rev := ALoserRev;
        NewCopy.DeviceId := ALoserDeviceId;
        NewCopy.ConflictOf := AOrigGuid;
        FNoteManager.PersistNote(NewCopy);
      end);
    case ApplyResult of
      arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
      arApplied:
        begin
          // Push it now so the pair converges in this run when possible; a
          // failed push defers and the next run's push loop retries.
          CheckCancelled;
          Payload := ConflictCopyPayload(ALoser, AOrigGuid, ACopyGuid);
          if (Payload <> '') and
             ((not UseETags) or FBackend.WriteIfMatch(ACopyGuid, Payload, '')) then
            CreatedGuids.AddOrSetValue(ACopyGuid, ALoserRev)
          else
          begin
            Inc(Deferred);
            Logger.Warning('Sync: conflict copy ' + ACopyGuid +
              ' could not be pushed yet; retrying next run');
          end;
        end
    else
      Inc(Deferred); // the guid is already present; the normal paths reconcile it
    end;
  end;

begin
  Result := False;
  Logger := CreateLogger;
  // WP3: zero the counters up front so the run accounting is meaningful on
  // every exit path (success, cancellation, failure).
  Pushed := 0; Pulled := 0; Created := 0; Conflicts := 0; Removed := 0;
  TombstonesWritten := 0; Deferred := 0;
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
      JournalChanged := False;
      Snapshot := TDictionary<string, TSyncNoteSnapshot>.Create;
      DeferredGuids := TDictionary<string, Boolean>.Create;
      AppliedPulls := TDictionary<string, Int64>.Create;
      PushedRevs := TDictionary<string, Int64>.Create;
      CreatedGuids := TDictionary<string, Int64>.Create;
      ResolvedDeletions := TDictionary<string, Int64>.Create;
      PendingTombstones := TDictionary<string, Boolean>.Create;
      try
        UseETags := FBackend.SupportsETags;
        LoadJournalOnMainThread; // main-thread parse (WP2 S16); fails the run if unreadable
        LoadState;
        Report('Scanning local notes...', 10);
        CaptureSnapshot(Snapshot); // main thread; worker never sees a live TNote
        if (Snapshot.Count = 0) and (FSynced.Count > 0) then
          Logger.Warning(Format(
            'Sync: the local note set is empty while the synced baseline knows %d notes; pulling only, not deleting',
            [FSynced.Count]));
        RemoteSet := TDictionary<string, Boolean>.Create;
        try
          CheckCancelled; // before the first backend call
          RemoteNames := FBackend.ListNames;
          for Guid in RemoteNames do
            RemoteSet.AddOrSetValue(Guid, True);

          // WP5: stale-journal sweep (design S4.2). A journal entry for a note
          // that is alive locally, or that has no remote presence at all, is
          // dropped; entries whose remote object still exists are processed
          // below under the S2.4 rules.
          for JournalTomb in FJournal.Enumerate do
          begin
            CheckCancelled;
            Guid := JournalTomb.Guid;
            if Snapshot.ContainsKey(Guid) then
            begin
              ClearJournalEntry(Guid);
              Logger.Warning('Sync: dropped a stale deletion journal entry for a live note');
            end
            else if not RemoteSet.ContainsKey(Guid) then
              ClearJournalEntry(Guid);
          end;

          Report('Reconciling remote changes...', 40);
          for Guid in RemoteNames do
          begin
            CheckCancelled;
            if CreatedGuids.ContainsKey(Guid) then Continue; // created earlier in this run
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
              // Build the immutable inputs and let the pure decision function
              // (design S2/S3) determine the outcome.
              ReconcileCtx := Default(TReconcileInput);
              ReconcileCtx.Guid := Guid;
              ReconcileCtx.LocalPresent := Snapshot.TryGetValue(Guid, Snap);
              if ReconcileCtx.LocalPresent then
              begin
                ReconcileCtx.LocalRev := Snap.Rev;
                ReconcileCtx.LocalDeviceId := Snap.DeviceId;
                ReconcileCtx.LocalSignature := Snap.Signature;
              end;
              ReconcileCtx.RemotePresent := True;
              ReconcileCtx.RemoteDeleted := RemoteNote.Deleted;
              ReconcileCtx.RemoteRev := RemoteNote.Rev;
              ReconcileCtx.RemoteDeviceId := RemoteNote.DeviceId;
              ReconcileCtx.RemoteSignature := ContentSignature(RemoteNote);
              ReconcileCtx.BaselineKnown := FSynced.TryGetValue(Guid, PreviousRev);
              ReconcileCtx.BaselineRev := PreviousRev;
              ReconcileCtx.JournalPresent := FJournal.TryGet(Guid, JournalTomb);
              ReconcileCtx.JournalRev := JournalTomb.Rev;
              Decision := ReconcileDecision(ReconcileCtx);
              if Decision.DefensiveWarning then
                Logger.Warning('Sync: ' + Guid +
                  ' diverged without changed-side flags; resolving defensively');

              LocalRev := ReconcileCtx.LocalRev;
              RemoteRev := ReconcileCtx.RemoteRev;
              case Decision.Kind of
                sdkNothing:
                  begin
                    if Decision.ClearJournal then
                      ClearJournalEntry(Guid);
                  end;

                sdkDeleteLocal:
                  begin
                    // Apply the remote tombstone to the unchanged local note
                    // through the CAS gate.
                    ApplyResult := TryApplyNoteCAS(Guid, Snap.Rev,
                      procedure(Note: TNote)
                      begin
                        FNoteManager.DeleteNote(Note.ID);
                      end);
                    case ApplyResult of
                      arApplied:
                        begin
                          Inc(Removed);
                          ResolvedDeletions.AddOrSetValue(Guid, RemoteRev);
                        end;
                      arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                    else
                      MarkDeferred(Guid);
                    end;
                  end;

                sdkPullRemote:
                  begin
                    if not ReconcileCtx.LocalPresent then
                    begin
                      // A new remote note (or the edit-beats-delete return):
                      // materialise it locally with a fresh local id.
                      ApplyResult := TryCreateNoteCAS(Guid,
                        procedure
                        var
                          PulledNote: TNote;
                        begin
                          PulledNote := FNoteManager.CreateNote(RemoteNote.Title,
                            RemoteNote.Content, RemoteNote.Color, RemoteNote.Left,
                            RemoteNote.Top, RemoteNote.Width, RemoteNote.Height,
                            RemoteNote.AlwaysOnTop);
                          CopySyncedFields(RemoteNote, PulledNote, False);
                          FNoteManager.PersistNote(PulledNote);
                        end);
                      case ApplyResult of
                        arApplied:
                          begin
                            Inc(Pulled);
                            Inc(Created);
                            CreatedGuids.AddOrSetValue(Guid, RemoteRev);
                            if Decision.ClearJournal and ReconcileCtx.JournalPresent then
                              ClearJournalEntry(Guid);
                          end;
                        arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                      else
                        MarkDeferred(Guid);
                      end;
                      Continue;
                    end;
                    // Apply the remote version to the existing note; a raced
                    // local edit defers the whole row (including any journal
                    // clearing).
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
                          if Decision.ClearJournal and ReconcileCtx.JournalPresent then
                            ClearJournalEntry(Guid);
                        end;
                      arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                    else
                      MarkDeferred(Guid);
                    end;
                  end;

                sdkPushLocal:
                  begin
                    // Do not push a snapshot the user has since changed: verify
                    // on the main thread first, then do the backend write.
                    ApplyResult := ValidateNoteCAS;
                    if ApplyResult = arCancelled then
                      raise ESyncCancelled.Create('Sync run cancelled');
                    if ApplyResult <> arApplied then
                    begin
                      MarkDeferred(Guid);
                      Logger.Warning('Sync: ' + Guid + ' changed locally during sync; push deferred');
                      Continue;
                    end;
                    CheckCancelled;
                    if Decision.PublishRev <> Snap.Rev then
                      Payload := PayloadWithRev(Snap.Payload, Decision.PublishRev)
                    else
                      Payload := Snap.Payload;
                    if (Payload <> '') and ((not UseETags) or
                       FBackend.WriteIfMatch(Guid, Payload, RemoteETag)) then
                    begin
                      Inc(Pushed);
                      PushedRevs.AddOrSetValue(Guid, Decision.PublishRev);
                      if Decision.PublishRev <> Snap.Rev then
                      begin
                        // Keep the local rev in step with the published one
                        // (edit beats delete / aligned publications).
                        ApplyResult := TryApplyNoteCAS(Guid, Snap.Rev,
                          procedure(Note: TNote)
                          begin
                            Note.Rev := Decision.PublishRev;
                            FNoteManager.PersistNote(Note);
                          end);
                        if ApplyResult = arCancelled then
                          raise ESyncCancelled.Create('Sync run cancelled');
                      end;
                    end
                    else
                    begin
                      MarkDeferred(Guid);
                      Logger.Warning('Sync: remote ' + Guid + ' changed during sync; deferring to next run');
                    end;
                  end;

                sdkAdoptRev:
                  begin
                    // Identical content, the remote carries the higher rev.
                    ApplyResult := TryApplyNoteCAS(Guid, Snap.Rev,
                      procedure(Note: TNote)
                      begin
                        Note.Rev := RemoteRev;
                        FNoteManager.PersistNote(Note);
                      end);
                    case ApplyResult of
                      arApplied: AppliedPulls.AddOrSetValue(Guid, RemoteRev);
                      arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                    else
                      MarkDeferred(Guid);
                    end;
                  end;

                sdkWriteTombstone:
                  begin
                    // Propagate the local deletion (design S2.4/S4.1). A failed
                    // write keeps the journal entry for the next run.
                    CheckCancelled;
                    Payload := TombstonePayload(Guid, Decision.PublishRev,
                      JournalTomb.DeletedAt);
                    if (Payload <> '') and ((not UseETags) or
                       FBackend.WriteIfMatch(Guid, Payload, RemoteETag)) then
                    begin
                      Inc(TombstonesWritten);
                      ResolvedDeletions.AddOrSetValue(Guid, Decision.PublishRev);
                      ClearJournalEntry(Guid);
                    end
                    else
                    begin
                      Inc(Deferred);
                      PendingTombstones.AddOrSetValue(Guid, True);
                      Logger.Warning('Sync: tombstone for ' + Guid +
                        ' could not be written yet; retrying next run');
                    end;
                  end;

                sdkConflictPublish:
                  begin
                    // Winner is the local version: publish it at R* and keep
                    // the remote loser under the deterministic copy identity.
                    ApplyResult := ValidateNoteCAS;
                    if ApplyResult = arCancelled then
                      raise ESyncCancelled.Create('Sync run cancelled');
                    if ApplyResult <> arApplied then
                    begin
                      MarkDeferred(Guid);
                      Logger.Warning('Sync: ' + Guid + ' changed locally during sync; conflict publish deferred');
                      Continue;
                    end;
                    CheckCancelled;
                    Payload := PayloadWithRev(Snap.Payload, Decision.PublishRev);
                    if (Payload <> '') and ((not UseETags) or
                       FBackend.WriteIfMatch(Guid, Payload, RemoteETag)) then
                    begin
                      Inc(Pushed);
                      Inc(Conflicts);
                      PushedRevs.AddOrSetValue(Guid, Decision.PublishRev);
                      ApplyResult := TryApplyNoteCAS(Guid, Snap.Rev,
                        procedure(Note: TNote)
                        begin
                          Note.Rev := Decision.PublishRev; // content unchanged
                          FNoteManager.PersistNote(Note);
                        end);
                      if ApplyResult = arCancelled then
                        raise ESyncCancelled.Create('Sync run cancelled');
                      EnsureConflictCopy(Guid, Decision.CopyGuid,
                        RemoteNote.DeviceId, RemoteRev, RemoteNote);
                    end
                    else
                    begin
                      MarkDeferred(Guid);
                      Logger.Warning('Sync: remote ' + Guid +
                        ' changed during sync; conflict publish deferred');
                    end;
                  end;

                sdkConflictPull:
                  begin
                    // Winner is the remote version: pull it and keep the local
                    // loser under the deterministic copy identity.
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
                          Inc(Conflicts);
                          AppliedPulls.AddOrSetValue(Guid, RemoteRev);
                          // The loser is the local version; parse its snapshot
                          // payload to build the copy from values only.
                          RemoteNote2 := TryParse(Snap.Payload);
                          try
                            if RemoteNote2 <> nil then
                              EnsureConflictCopy(Guid, Decision.CopyGuid,
                                Snap.DeviceId, LocalRev, RemoteNote2);
                          finally
                            RemoteNote2.Free;
                          end;
                        end;
                      arCancelled: raise ESyncCancelled.Create('Sync run cancelled');
                    else
                      MarkDeferred(Guid);
                    end;
                  end;
              end;
            finally
              RemoteNote.Free;
            end;
          end;

          Report('Pushing local changes...', 70);
          for Snap in Snapshot.Values do
          begin
            CheckCancelled;
            if RemoteSet.ContainsKey(Snap.Guid) then Continue; // handled above
            ReconcileCtx := Default(TReconcileInput);
            ReconcileCtx.Guid := Snap.Guid;
            ReconcileCtx.LocalPresent := True;
            ReconcileCtx.LocalRev := Snap.Rev;
            ReconcileCtx.LocalDeviceId := Snap.DeviceId;
            ReconcileCtx.LocalSignature := Snap.Signature;
            Decision := ReconcileDecision(ReconcileCtx);
            if Decision.Kind <> sdkPushLocal then Continue;
            // Verify the note still matches the snapshot, then write it as a
            // new object (If-None-Match: *) so we never clobber one created
            // remotely or locally mid-sync.
            ApplyResult := ValidateNoteCAS;
            if ApplyResult = arCancelled then
              raise ESyncCancelled.Create('Sync run cancelled');
            if ApplyResult <> arApplied then
            begin
              MarkDeferred(Snap.Guid);
              Logger.Warning('Sync: ' + Snap.Guid + ' changed locally during sync; push deferred');
              Continue;
            end;
            CheckCancelled;
            if (not UseETags) or FBackend.WriteIfMatch(Snap.Guid, Snap.Payload, '') then
            begin
              Inc(Pushed);
              PushedRevs.AddOrSetValue(Snap.Guid, Decision.PublishRev);
            end
            else
            begin
              MarkDeferred(Snap.Guid);
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
              else if PushedRevs.TryGetValue(Snap.Guid, AppliedRev) then
                NewSynced.AddOrSetValue(Snap.Guid, AppliedRev)
              else if AppliedPulls.TryGetValue(Snap.Guid, AppliedRev) then
                NewSynced.AddOrSetValue(Snap.Guid, AppliedRev)
              else
                NewSynced.AddOrSetValue(Snap.Guid, Snap.Rev);
            end;
            // Notes created from the remote (and deterministic conflict
            // copies) are applied operations: their baseline advances to the
            // applied revision.
            for Guid in CreatedGuids.Keys do
              NewSynced.AddOrSetValue(Guid, CreatedGuids[Guid]);
            // Deletions resolved this run (tombstones written / applied) are
            // recorded at the resolved revision.
            for Guid in ResolvedDeletions.Keys do
              NewSynced.AddOrSetValue(Guid, ResolvedDeletions[Guid]);
            // Deferred tombstone writes keep their previous baseline.
            for Guid in PendingTombstones.Keys do
              if FSynced.TryGetValue(Guid, PreviousRev) then
                NewSynced.AddOrSetValue(Guid, PreviousRev);
            FSynced.Free;
            FSynced := NewSynced;
            NewSynced := nil;
          finally
            NewSynced.Free;
          end;

          // WP4: persist the metadata (journal changes first: deletion
          // information must land before the state rewrite). A failure here is
          // distinguishable from an operation failure: the run still reports
          // failed, and MetadataFailed marks that the operations themselves
          // had completed and only the metadata write was lost.
          try
            if JournalChanged then
              FJournal.Save;
            SaveState;
          except
            FLastRunSummary.MetadataFailed := True;
            raise;
          end;
          Report('Sync complete', 100);
          Result := True;
          // WP3: publish the run accounting - only completed operations are in
          // these counts; deferred ones are counted separately.
          FLastRunSummary.Succeeded := True;
          FLastRunSummary.Cancelled := False;
          FLastRunSummary.MetadataFailed := False;
          FLastRunSummary.Pushed := Pushed;
          FLastRunSummary.Pulled := Pulled;
          FLastRunSummary.Created := Created;
          FLastRunSummary.Removed := Removed;
          FLastRunSummary.TombstonesWritten := TombstonesWritten;
          FLastRunSummary.Conflicts := Conflicts;
          FLastRunSummary.Deferred := Deferred;
          Logger.Info(Format('Sync: pushed %d, pulled %d, conflicts %d, removed %d, tombstones %d, deferred %d',
            [Pushed, Pulled, Conflicts, Removed, TombstonesWritten, Deferred]));
          if Assigned(FOnComplete) then
          begin
            // WP5 (design S4.3): a run that exceeds the deletion threshold is
            // surfaced loudly but never aborted.
            Msg := Format('Sync complete: %d pushed, %d pulled, %d conflicts, %d removed',
              [Pushed, Pulled, Conflicts, Removed]);
            DeletedTotal := Removed + TombstonesWritten;
            Threshold := TDeletionThreshold.Base;
            if (Snapshot.Count * TDeletionThreshold.Base) div 100 > Threshold then
              Threshold := (Snapshot.Count * TDeletionThreshold.Base) div 100;
            if DeletedTotal > Threshold then
            begin
              Logger.Warning(Format('Sync: %d deletions in one run (above the usual threshold of %d)',
                [DeletedTotal, Threshold]));
              Msg := Msg + Format('; %d deletions (above the warning threshold)', [DeletedTotal]);
            end;
            // WP3/WP4: a partial run (anything skipped or deferred) must say so.
            if Deferred > 0 then
              Msg := Msg + Format('; %d deferred to next run', [Deferred]);
            NotifyComplete(True, Msg);
          end;
        finally
          RemoteSet.Free;
        end;
      finally
        PendingTombstones.Free;
        ResolvedDeletions.Free;
        CreatedGuids.Free;
        PushedRevs.Free;
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
        FLastRunSummary.TombstonesWritten := TombstonesWritten;
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
        FLastRunSummary.TombstonesWritten := TombstonesWritten;
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
