unit uSingleInstance;

{
  Phase 4C: lightweight single-instance guard.

  Uses a Windows named mutex to ensure only one Sticky Notes process
  is running for the current user/session. A second launch detects the
  existing instance and signals it to surface (bring the tray form /
  notes to the foreground) via a registered window message.

  Design notes:
   - The lock state (Acquire / Release / IsOwner) is the testable core.
     It only depends on Winapi.Windows mutex APIs and is unit-tested.
   - SignalExisting uses a registered window message targeting a known
     window title (the tray form caption). The tray form watches for the
     registered message via its WndProc; on receipt it shows the notes
     list and brings itself to the front.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes;

const
  // Window title of the tray form (used by a second instance to locate the
  // running one with FindWindow). Kept in sync with uTrayForm's DFM caption.
  SN_WINDOW_TITLE = 'Sticky Notes Tray';
  // Registered window message: ask the existing instance to surface itself.
  SN_APPEAR_MSG = 'StickyNotes.SingleInstance.Appear';

// Returns the registered window message handle that callers should listen
// for on their WndProc. Cached per-process; safe to call repeatedly.
function SingleInstanceAppearMessage: UINT;

type
  TSingleInstance = class
  private
    FMutex: THandle;
    FIsOwner: Boolean;
    FName: string;
    function FindExistingWindow: HWND;
  public
    constructor Create(const AName: string = 'StickyNotes');
    destructor Destroy; override;
    // Returns True if this process became the owner of the named slot,
    // False if another instance was already running.
    function Acquire: Boolean;
    // Release the named slot. Idempotent and safe to call multiple times.
    procedure Release;
    // Signal an already-running instance to bring itself forward. Safe to
    // call only when Acquire returned False; otherwise it is a no-op.
    procedure SignalExisting;
    property IsOwner: Boolean read FIsOwner;
    property Name: string read FName;
  end;

implementation

var
  GAppearMessage: UINT = 0;

function GetAppearMessage: UINT;
begin
  if GAppearMessage = 0 then
    GAppearMessage := RegisterWindowMessage(PChar(SN_APPEAR_MSG));
  Result := GAppearMessage;
end;

function SingleInstanceAppearMessage: UINT;
begin
  Result := GetAppearMessage;
end;

{ TSingleInstance }

constructor TSingleInstance.Create(const AName: string = 'StickyNotes');
begin
  inherited Create;
  FName := AName;
  FMutex := 0;
  FIsOwner := False;
end;

destructor TSingleInstance.Destroy;
begin
  Release;
  inherited;
end;

function TSingleInstance.Acquire: Boolean;
begin
  Result := False;
  if FIsOwner and (FMutex <> 0) then
  begin
    Result := True;
    Exit;
  end;
  if FMutex = 0 then
    FMutex := CreateMutex(nil, True, PChar('Local\' + FName));
  if FMutex = 0 then
  begin
    // Could not even create the mutex - behave as not-owner to be safe.
    Exit;
  end;
  case GetLastError of
    ERROR_ALREADY_EXISTS:
      begin
        FIsOwner := False;
        CloseHandle(FMutex);
        FMutex := 0;
      end;
    ERROR_SUCCESS:
      begin
        FIsOwner := True;
        Result := True;
      end;
  else
    begin
      FIsOwner := False;
      CloseHandle(FMutex);
      FMutex := 0;
    end;
  end;
end;

procedure TSingleInstance.Release;
begin
  if FMutex <> 0 then
  begin
    CloseHandle(FMutex);
    FMutex := 0;
  end;
  FIsOwner := False;
end;

procedure TSingleInstance.SignalExisting;
var
  W: HWND;
  Msg: UINT;
begin
  if FIsOwner then Exit;
  W := FindExistingWindow;
  if W = 0 then Exit;
  Msg := GetAppearMessage;
  if Msg <> 0 then
    PostMessage(W, Msg, 0, 0);
end;

function TSingleInstance.FindExistingWindow: HWND;
begin
  // Title-based lookup. The tray form is created with ShowMainForm := False
  // so its HWND is allocated but not visible; FindWindow still locates it.
  Result := FindWindow(nil, PChar(SN_WINDOW_TITLE));
end;

end.