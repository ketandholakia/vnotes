unit uCredentialStore;

// Phase 7E wiring: secret storage for sync credentials.
//
// The design doc is explicit that sync secrets must NOT live in settings.ini.
// On Windows they go to the Credential Manager (DPAPI-protected, per-user);
// an in-memory implementation is provided for tests and as a safe fallback.

interface

const
  // Credential Manager target used for the WebDAV sync password.
  SyncWebDavCredentialTarget = 'VNotes/SyncWebDav';

type
  ICredentialStore = interface
    ['{7E4A1B2C-3D4E-5F60-7182-93A4B5C6D7E8}']
    function GetSecret(const ATarget: string): string;      // '' when absent
    procedure SetSecret(const ATarget, ASecret: string);
    procedure DeleteSecret(const ATarget: string);
  end;

function CreateWindowsCredentialStore: ICredentialStore;
function CreateMemoryCredentialStore: ICredentialStore;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Winapi.WinCred;

type
  TWindowsCredentialStore = class(TInterfacedObject, ICredentialStore)
  public
    function GetSecret(const ATarget: string): string;
    procedure SetSecret(const ATarget, ASecret: string);
    procedure DeleteSecret(const ATarget: string);
  end;

  TMemoryCredentialStore = class(TInterfacedObject, ICredentialStore)
  private
    FMap: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function GetSecret(const ATarget: string): string;
    procedure SetSecret(const ATarget, ASecret: string);
    procedure DeleteSecret(const ATarget: string);
  end;

{ TWindowsCredentialStore }

function TWindowsCredentialStore.GetSecret(const ATarget: string): string;
var
  Cred: PCREDENTIALW;
  Blob: TBytes;
begin
  Result := '';
  if ATarget = '' then Exit;
  Cred := nil;
  if not CredReadW(PWideChar(ATarget), CRED_TYPE_GENERIC, 0, Cred) then Exit;
  try
    if (Cred <> nil) and (Cred^.CredentialBlobSize > 0) and (Cred^.CredentialBlob <> nil) then
    begin
      SetLength(Blob, Cred^.CredentialBlobSize);
      Move(Cred^.CredentialBlob^, Blob[0], Cred^.CredentialBlobSize);
      Result := TEncoding.UTF8.GetString(Blob);
    end;
  finally
    CredFree(Cred);
  end;
end;

procedure TWindowsCredentialStore.SetSecret(const ATarget, ASecret: string);
var
  Cred: CREDENTIALW;
  Blob: TBytes;
begin
  if ATarget = '' then Exit;
  Blob := TEncoding.UTF8.GetBytes(ASecret);
  FillChar(Cred, SizeOf(Cred), 0);
  Cred.&Type := CRED_TYPE_GENERIC;
  Cred.TargetName := PWideChar(ATarget);
  Cred.UserName := PWideChar(ATarget);
  Cred.Persist := CRED_PERSIST_LOCAL_MACHINE;
  Cred.CredentialBlobSize := Length(Blob);
  if Length(Blob) > 0 then
    Cred.CredentialBlob := @Blob[0]
  else
    Cred.CredentialBlob := nil;
  if not CredWriteW(@Cred, 0) then
    raise Exception.CreateFmt('Could not store the sync credential (Windows error %d)', [GetLastError]);
end;

procedure TWindowsCredentialStore.DeleteSecret(const ATarget: string);
begin
  if ATarget = '' then Exit;
  CredDeleteW(PWideChar(ATarget), CRED_TYPE_GENERIC, 0);
end;

{ TMemoryCredentialStore }

constructor TMemoryCredentialStore.Create;
begin
  inherited Create;
  FMap := TDictionary<string, string>.Create;
end;

destructor TMemoryCredentialStore.Destroy;
begin
  FMap.Free;
  inherited;
end;

function TMemoryCredentialStore.GetSecret(const ATarget: string): string;
begin
  if not FMap.TryGetValue(ATarget, Result) then
    Result := '';
end;

procedure TMemoryCredentialStore.SetSecret(const ATarget, ASecret: string);
begin
  FMap.AddOrSetValue(ATarget, ASecret);
end;

procedure TMemoryCredentialStore.DeleteSecret(const ATarget: string);
begin
  FMap.Remove(ATarget);
end;

function CreateWindowsCredentialStore: ICredentialStore;
begin
  Result := TWindowsCredentialStore.Create;
end;

function CreateMemoryCredentialStore: ICredentialStore;
begin
  Result := TMemoryCredentialStore.Create;
end;

end.
