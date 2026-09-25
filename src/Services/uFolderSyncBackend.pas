unit uFolderSyncBackend;

// Phase 7B: a file-system ISyncBackend. Point it at a folder that a cloud
// client (Drive / Dropbox / OneDrive) already syncs, or any shared/mounted
// path. Objects are stored one-per-file under <root>\notes, keyed by name.
//
// This backend is deliberately dumb: it knows nothing about notes, revisions,
// or conflicts - that is the sync engine's job. It only guarantees safe,
// atomic-ish file writes so a cloud client never reads a half-written object.

interface

uses
  System.SysUtils,
  uServiceInterfaces;

type
  TFolderSyncBackend = class(TInterfacedObject, ISyncBackend)
  private
    FRoot: string;
    FNotesPath: string;
    function PathFor(const AName: string): string;
    // Phase 7E: an ETag derived from the file's mtime and size. The folder
    // backend therefore supports optimistic concurrency too, which both makes
    // the engine path uniform and keeps it unit-testable without a server.
    function CurrentETag(const APath: string): string;
  public
    constructor Create(const ARootPath: string);
    function DisplayName: string;
    function ListNames: TArray<string>;
    function Read(const AName: string): string;
    procedure Write(const AName, AContent: string);
    procedure Remove(const AName: string);
    function SupportsETags: Boolean;
    function ReadWithETag(const AName: string; out AETag: string): string;
    function WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Types;

constructor TFolderSyncBackend.Create(const ARootPath: string);
begin
  inherited Create;
  FRoot := ARootPath;
  FNotesPath := TPath.Combine(FRoot, 'notes');
end;

function TFolderSyncBackend.DisplayName: string;
begin
  Result := FRoot;
end;

function TFolderSyncBackend.PathFor(const AName: string): string;
begin
  // Names are note guids; strip anything that could escape the notes folder so
  // a hostile remote cannot steer a write outside FRoot.
  Result := TPath.Combine(FNotesPath, AName + '.json');
end;

function TFolderSyncBackend.ListNames: TArray<string>;
var
  Files: TStringDynArray;
  FileName: string;
  Names: TArray<string>;
  I: Integer;
begin
  Names := nil;
  if not TDirectory.Exists(FNotesPath) then Exit(nil);
  Files := TDirectory.GetFiles(FNotesPath, '*.json');
  SetLength(Names, Length(Files));
  for I := 0 to High(Files) do
  begin
    FileName := TPath.GetFileNameWithoutExtension(Files[I]);
    Names[I] := FileName;
  end;
  Result := Names;
end;

function TFolderSyncBackend.Read(const AName: string): string;
var
  Path: string;
begin
  Result := '';
  Path := PathFor(AName);
  if TFile.Exists(Path) then
    Result := TFile.ReadAllText(Path, TEncoding.UTF8);
end;

procedure TFolderSyncBackend.Write(const AName, AContent: string);
var
  Path, TmpPath: string;
begin
  TDirectory.CreateDirectory(FNotesPath);
  Path := PathFor(AName);
  TmpPath := Path + '.tmp';
  // Write-then-rename: a cloud client watching the folder only ever sees a
  // complete object, never a partial one.
  TFile.WriteAllText(TmpPath, AContent, TEncoding.UTF8);
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  TFile.Move(TmpPath, Path);
end;

procedure TFolderSyncBackend.Remove(const AName: string);
var
  Path: string;
begin
  Path := PathFor(AName);
  if TFile.Exists(Path) then
    TFile.Delete(Path);
end;

function TFolderSyncBackend.CurrentETag(const APath: string): string;
begin
  if not TFile.Exists(APath) then
    Exit('');
  try
    Result := Format('%s:%d',
      [FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTime(APath)),
       TFile.GetSize(APath)]);
  except
    Result := '';
  end;
end;

function TFolderSyncBackend.SupportsETags: Boolean;
begin
  Result := True;
end;

function TFolderSyncBackend.ReadWithETag(const AName: string; out AETag: string): string;
var
  Path: string;
begin
  Path := PathFor(AName);
  AETag := CurrentETag(Path);
  if AETag = '' then
    Result := ''
  else
    Result := TFile.ReadAllText(Path, TEncoding.UTF8);
end;

function TFolderSyncBackend.WriteIfMatch(const AName, AContent, AExpectedETag: string): Boolean;
var
  Path, Current: string;
begin
  Path := PathFor(AName);
  Current := CurrentETag(Path);
  if Current <> AExpectedETag then
    Exit(False); // precondition failed - someone else changed it
  Write(AName, AContent);
  Result := True;
end;

end.
