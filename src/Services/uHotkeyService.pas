unit uHotkeyService;

interface

uses
  System.SysUtils, System.Classes, System.Types, Winapi.Windows, Winapi.Messages,
  Vcl.Forms;

type
  THotkeyID = (hkNewNote, hkSearch);
  THotkeyEvent = procedure of object;

  THotkeyService = class
  private
    FHandle: HWND;
    FRegistered: array[THotkeyID] of Boolean;
    FHotkeys: array[THotkeyID] of record
      Modifiers: UINT;
      Key: UINT;
      Enabled: Boolean;
      Event: THotkeyEvent;
      HotkeyStr: string; // kept so EnableHotkey(True) can re-register later
    end;
    FOnHotkey: array[THotkeyID] of THotkeyEvent;
    procedure WndProc(var Message: TMessage);
    function ParseHotkey(const AHotkeyStr: string; out AModifiers, AKey: UINT): Boolean;
  public
    constructor Create(AHandle: HWND);
    destructor Destroy; override;
    function RegisterHotkey(AID: THotkeyID; const AHotkeyStr: string; AEvent: THotkeyEvent): Boolean;
    function UnregisterHotkey(AID: THotkeyID): Boolean;
    procedure SetHotkey(AID: THotkeyID; const AHotkeyStr: string; AEvent: THotkeyEvent);
    procedure EnableHotkey(AID: THotkeyID; AEnable: Boolean);
    procedure HandleMessage(var Message: TMessage);  // Public method for message handling
  end;

implementation

const
  HOTKEY_MSG = WM_HOTKEY;
  BASE_HOTKEY_ID = $8000;

{ THotkeyService }

constructor THotkeyService.Create(AHandle: HWND);
var
  ID: THotkeyID;
begin
  inherited Create;
  FHandle := AHandle;
  for ID := Low(THotkeyID) to High(THotkeyID) do
  begin
    FRegistered[ID] := False;
    FHotkeys[ID].Enabled := False;
    FHotkeys[ID].Event := nil;
  end;
end;

destructor THotkeyService.Destroy;
var
  ID: THotkeyID;
begin
  for ID := Low(THotkeyID) to High(THotkeyID) do
    UnregisterHotkey(ID);
  inherited;
end;

function THotkeyService.ParseHotkey(const AHotkeyStr: string; out AModifiers, AKey: UINT): Boolean;
var
  Parts: TStringDynArray;
  Part, PartText: string;
begin
  Result := False;
  AModifiers := 0;
  AKey := 0;
  
  Parts := AHotkeyStr.Split(['+']);
  if Length(Parts) = 0 then Exit;
  
  for Part in Parts do
  begin
    PartText := Trim(Part);
    if SameText(PartText, 'Ctrl') or SameText(PartText, 'Control') then
      AModifiers := AModifiers or MOD_CONTROL
    else if SameText(PartText, 'Alt') then
      AModifiers := AModifiers or MOD_ALT
    else if SameText(PartText, 'Shift') then
      AModifiers := AModifiers or MOD_SHIFT
    else if SameText(PartText, 'Win') or SameText(PartText, 'Windows') then
      AModifiers := AModifiers or MOD_WIN
    else
    begin
      if Length(PartText) = 1 then
        AKey := Ord(UpCase(PartText[1]))
      else if SameText(PartText, 'F1') then AKey := VK_F1
      else if SameText(PartText, 'F2') then AKey := VK_F2
      else if SameText(PartText, 'F3') then AKey := VK_F3
      else if SameText(PartText, 'F4') then AKey := VK_F4
      else if SameText(PartText, 'F5') then AKey := VK_F5
      else if SameText(PartText, 'F6') then AKey := VK_F6
      else if SameText(PartText, 'F7') then AKey := VK_F7
      else if SameText(PartText, 'F8') then AKey := VK_F8
      else if SameText(PartText, 'F9') then AKey := VK_F9
      else if SameText(PartText, 'F10') then AKey := VK_F10
      else if SameText(PartText, 'F11') then AKey := VK_F11
      else if SameText(PartText, 'F12') then AKey := VK_F12
      else if SameText(PartText, 'Space') then AKey := VK_SPACE
      else if SameText(PartText, 'Enter') then AKey := VK_RETURN
      else if SameText(PartText, 'Esc') or SameText(PartText, 'Escape') then AKey := VK_ESCAPE
      else if SameText(PartText, 'Tab') then AKey := VK_TAB
      else if SameText(PartText, 'Del') or SameText(PartText, 'Delete') then AKey := VK_DELETE
      else if SameText(PartText, 'Ins') or SameText(PartText, 'Insert') then AKey := VK_INSERT
      else if SameText(PartText, 'Home') then AKey := VK_HOME
      else if SameText(PartText, 'End') then AKey := VK_END
      else if SameText(PartText, 'PgUp') or SameText(PartText, 'PageUp') then AKey := VK_PRIOR
      else if SameText(PartText, 'PgDn') or SameText(PartText, 'PageDown') then AKey := VK_NEXT
      else if SameText(PartText, 'Left') then AKey := VK_LEFT
      else if SameText(PartText, 'Right') then AKey := VK_RIGHT
      else if SameText(PartText, 'Up') then AKey := VK_UP
      else if SameText(PartText, 'Down') then AKey := VK_DOWN
      else
        Exit;
    end;
  end;
  
  if AKey <> 0 then
    Result := True;
end;

function THotkeyService.RegisterHotkey(AID: THotkeyID; const AHotkeyStr: string; AEvent: THotkeyEvent): Boolean;
var
  Modifiers, Key: UINT;
  HotkeyID: Integer;
begin
  Result := False;
  if not ParseHotkey(AHotkeyStr, Modifiers, Key) then Exit;
  
  UnregisterHotkey(AID);
  
  HotkeyID := BASE_HOTKEY_ID + Ord(AID);
  if Winapi.Windows.RegisterHotKey(FHandle, HotkeyID, Modifiers, Key) then
  begin
    FRegistered[AID] := True;
    FHotkeys[AID].Modifiers := Modifiers;
    FHotkeys[AID].Key := Key;
    FHotkeys[AID].Enabled := True;
    FHotkeys[AID].Event := AEvent;
    FHotkeys[AID].HotkeyStr := AHotkeyStr;
    Result := True;
  end;
end;

function THotkeyService.UnregisterHotkey(AID: THotkeyID): Boolean;
var
  HotkeyID: Integer;
begin
  Result := False;
  if not FRegistered[AID] then Exit;
  
  HotkeyID := BASE_HOTKEY_ID + Ord(AID);
  if Winapi.Windows.UnregisterHotKey(FHandle, HotkeyID) then
  begin
    FRegistered[AID] := False;
    FHotkeys[AID].Enabled := False;
    Result := True;
  end;
end;

procedure THotkeyService.SetHotkey(AID: THotkeyID; const AHotkeyStr: string; AEvent: THotkeyEvent);
begin
  if FHotkeys[AID].Enabled then
    UnregisterHotkey(AID);
  RegisterHotkey(AID, AHotkeyStr, AEvent);
end;

procedure THotkeyService.EnableHotkey(AID: THotkeyID; AEnable: Boolean);
begin
  if AEnable and not FHotkeys[AID].Enabled then
    RegisterHotkey(AID, FHotkeys[AID].HotkeyStr, FHotkeys[AID].Event)
  else if not AEnable and FHotkeys[AID].Enabled then
    UnregisterHotkey(AID);
end;

procedure THotkeyService.WndProc(var Message: TMessage);
var
  ID: THotkeyID;
  HotkeyID: Integer;
begin
  if Message.Msg = HOTKEY_MSG then
  begin
    HotkeyID := Integer(Message.WParam);
    if (HotkeyID >= BASE_HOTKEY_ID) and (HotkeyID <= BASE_HOTKEY_ID + Ord(High(THotkeyID))) then
    begin
      ID := THotkeyID(HotkeyID - BASE_HOTKEY_ID);
      if FHotkeys[ID].Enabled and Assigned(FHotkeys[ID].Event) then
        FHotkeys[ID].Event();
      Message.Result := 0;
    end;
  end
  else
    Message.Result := LRESULT(Winapi.Windows.DefWindowProc(FHandle, Message.Msg, Message.WParam, Message.LParam));
end;

procedure THotkeyService.HandleMessage(var Message: TMessage);
begin
  WndProc(Message);
end;

end.