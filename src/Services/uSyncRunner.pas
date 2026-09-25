unit uSyncRunner;

// Phase 7E follow-up: run a sync off the UI thread.
//
// SyncNow performs network/filesystem I/O; running it on the main thread would
// freeze the UI for the duration of a slow server round-trip. The runner starts
// SyncNow on a worker thread.
//
// Completion is reported through the engine's own OnProgress/OnComplete, which
// the engine marshals back to the main thread (see TMainInvoker) - so no extra
// notification plumbing is needed here.
//
// Overlap is prevented by a single-worker guard: Start is a no-op while a sync
// is already running.

interface

uses
  System.SysUtils, System.Classes,
  uServiceInterfaces;

type
  TSyncRunner = class
  private
    FService: ISyncService;
    FThread: TThread;
    procedure DoRun;
  public
    constructor Create(const AService: ISyncService);
    destructor Destroy; override;
    function IsRunning: Boolean;
    // Starts a sync if one is not already running. Non-blocking.
    procedure Start;
    // Blocks until the current run (if any) has finished. For tests/diagnostics.
    procedure WaitForIdle;
  end;

implementation

{ TSyncRunner }

constructor TSyncRunner.Create(const AService: ISyncService);
begin
  inherited Create;
  FService := AService;
end;

destructor TSyncRunner.Destroy;
begin
  WaitForIdle;
  if FThread <> nil then
    FreeAndNil(FThread);
  inherited;
end;

function TSyncRunner.IsRunning: Boolean;
begin
  Result := (FThread <> nil) and (not FThread.Finished);
end;

procedure TSyncRunner.Start;
begin
  if FService = nil then Exit;
  if IsRunning then Exit; // never overlap
  if FThread <> nil then
    FreeAndNil(FThread); // reclaim the previous, finished worker
  FThread := TThread.CreateAnonymousThread(DoRun);
  FThread.FreeOnTerminate := False; // owned here; reclaimed above / in Destroy
  FThread.Start;
end;

procedure TSyncRunner.DoRun;
begin
  FService.SyncNow;
end;

procedure TSyncRunner.WaitForIdle;
begin
  if FThread <> nil then
    FThread.WaitFor;
end;

end.
