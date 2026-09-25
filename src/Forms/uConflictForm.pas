unit uConflictForm;

// Phase 7C: conflict surfacing.
//
// The sync engine never discards a losing edit - it preserves the remote version
// as a separate "conflict copy" note tagged with ConflictOf. This dialog lists
// those copies so the user can resolve them: keep the copy as an ordinary note
// (drops the marker) or delete it (the local original stays).
//
// The UI is built entirely in code (CreateNew) so no DFM resource is required.

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  uNote, uNoteManager;

type
  TConflictForm = class(TForm)
  private
    FNoteManager: INoteManager;
    FList: TListBox;
    FLbl: TLabel;
    FBtnKeep: TButton;
    FBtnDelete: TButton;
    FBtnClose: TButton;
    FGuids: TArray<string>;
    function FindConflictByGuid(const AGuid: string): TNote;
    function SelectedGuid: string;
    procedure RefreshList;
    procedure UpdateButtons;
    procedure DoSelectionChange(Sender: TObject);
    procedure DoKeepAsNormal(Sender: TObject);
    procedure DoDeleteCopy(Sender: TObject);
    procedure DoClose(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; const ANoteManager: INoteManager);
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics, Vcl.Dialogs;

constructor TConflictForm.CreateFor(AOwner: TComponent; const ANoteManager: INoteManager);
begin
  inherited CreateNew(AOwner);
  FNoteManager := ANoteManager;

  Caption := 'Sync conflicts';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 520;
  ClientHeight := 322;

  FLbl := TLabel.Create(Self);
  FLbl.Parent := Self;
  FLbl.Left := 12;
  FLbl.Top := 12;
  FLbl.Width := 496;
  FLbl.Height := 40;
  FLbl.AutoSize := False;
  FLbl.WordWrap := True;
  FLbl.Caption :=
    'These notes are conflict copies created during sync: the same note was ' +
    'edited on another device and could not be merged automatically. Choose one ' +
    'version to keep as a normal note, or delete the copy.';

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Left := 12;
  FList.Top := 58;
  FList.Width := 496;
  FList.Height := 210;
  FList.OnClick := DoSelectionChange;

  FBtnKeep := TButton.Create(Self);
  FBtnKeep.Parent := Self;
  FBtnKeep.Left := 12;
  FBtnKeep.Top := 280;
  FBtnKeep.Width := 160;
  FBtnKeep.Caption := 'Keep as normal note';
  FBtnKeep.OnClick := DoKeepAsNormal;

  FBtnDelete := TButton.Create(Self);
  FBtnDelete.Parent := Self;
  FBtnDelete.Left := 180;
  FBtnDelete.Top := 280;
  FBtnDelete.Width := 120;
  FBtnDelete.Caption := 'Delete copy';
  FBtnDelete.OnClick := DoDeleteCopy;

  FBtnClose := TButton.Create(Self);
  FBtnClose.Parent := Self;
  FBtnClose.Left := 433;
  FBtnClose.Top := 280;
  FBtnClose.Width := 75;
  FBtnClose.Caption := 'Close';
  FBtnClose.Cancel := True;
  FBtnClose.ModalResult := mrClose;
  FBtnClose.OnClick := DoClose;

  RefreshList;
end;

function TConflictForm.SelectedGuid: string;
begin
  if (FList.ItemIndex >= 0) and (FList.ItemIndex < Length(FGuids)) then
    Result := FGuids[FList.ItemIndex]
  else
    Result := '';
end;

function TConflictForm.FindConflictByGuid(const AGuid: string): TNote;
var
  I: Integer;
  N: TNote;
begin
  Result := nil;
  if (FNoteManager = nil) or (AGuid = '') then Exit;
  for I := 0 to FNoteManager.NoteCount - 1 do
  begin
    N := FNoteManager.Notes[I];
    if (N <> nil) and (N.ConflictOf <> '') and (N.Guid = AGuid) then
      Exit(N);
  end;
end;

procedure TConflictForm.RefreshList;
var
  I: Integer;
  N: TNote;
begin
  FList.Items.BeginUpdate;
  try
    FList.Clear;
    SetLength(FGuids, 0);
    if FNoteManager <> nil then
      for I := 0 to FNoteManager.NoteCount - 1 do
      begin
        N := FNoteManager.Notes[I];
        if (N = nil) or (N.ConflictOf = '') then Continue;
        FList.Items.Add(Format('%s   [from device %s]', [N.Title, Copy(N.DeviceId, 1, 8)]));
        SetLength(FGuids, Length(FGuids) + 1);
        FGuids[High(FGuids)] := N.Guid;
      end;
    if FList.Items.Count > 0 then
      FList.ItemIndex := 0;
  finally
    FList.Items.EndUpdate;
  end;
  UpdateButtons;
end;

procedure TConflictForm.UpdateButtons;
begin
  FBtnKeep.Enabled := FList.ItemIndex >= 0;
  FBtnDelete.Enabled := FList.ItemIndex >= 0;
end;

procedure TConflictForm.DoSelectionChange(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TConflictForm.DoKeepAsNormal(Sender: TObject);
var
  N: TNote;
begin
  N := FindConflictByGuid(SelectedGuid);
  if N = nil then Exit;
  N.ConflictOf := ''; // resolved: the copy becomes an ordinary note
  FNoteManager.PersistNote(N);
  RefreshList;
end;

procedure TConflictForm.DoDeleteCopy(Sender: TObject);
var
  N: TNote;
begin
  N := FindConflictByGuid(SelectedGuid);
  if N = nil then Exit;
  if MessageBox(Handle, 'Delete this conflict copy? The other version is kept.',
      'Sync conflicts', MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  FNoteManager.DeleteNote(N.ID);
  RefreshList;
end;

procedure TConflictForm.DoClose(Sender: TObject);
begin
  ModalResult := mrClose;
end;

end.
