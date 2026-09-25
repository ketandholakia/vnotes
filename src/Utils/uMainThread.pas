unit uMainThread;

// Helper for code that may run either on the UI thread or on a worker thread.
//
// Background sync does its I/O on a worker, but the note model, the VCL and the
// UI-facing callbacks must only be touched on the main thread. Routing those
// through TMainInvoker keeps a single code path that is correct in both cases:
// inline when already on the main thread (so tests and non-threaded callers are
// unaffected), marshalled via TThread.Synchronize otherwise.

interface

uses
  System.Classes;

type
  TMainInvoker = class
  public
    class procedure Run(const AProc: TThreadProcedure);
    class function OnMainThread: Boolean;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows;

class function TMainInvoker.OnMainThread: Boolean;
begin
  Result := GetCurrentThreadId = MainThreadID;
end;

class procedure TMainInvoker.Run(const AProc: TThreadProcedure);
begin
  if OnMainThread then
    AProc()
  else
    TThread.Synchronize(nil, AProc);
end;

end.
