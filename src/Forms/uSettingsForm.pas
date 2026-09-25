unit uSettingsForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Buttons,
  uSettings;

type
  TSettingsForm = class(TForm)
    pcSettings: TPageControl;
    tsGeneral: TTabSheet;
    tsAppearance: TTabSheet;
    tsHotkeys: TTabSheet;
    tsBackup: TTabSheet;
    pnlButtons: TPanel;
    btnOK: TButton;
    btnCancel: TButton;
    btnApply: TButton;
    // General
    grpGeneral: TGroupBox;
    chkAutoStart: TCheckBox;
    chkConfirmDelete: TCheckBox;
    lblAutosaveDelay: TLabel;
    edtAutosaveDelay: TEdit;
    udAutosaveDelay: TUpDown;
    lblDefaultSize: TLabel;
    edtDefaultWidth: TEdit;
    edtDefaultHeight: TEdit;
    lblDefaultColor: TLabel;
    cbDefaultColor: TComboBox;
    chkDefaultAlwaysOnTop: TCheckBox;
    chkEnableHotkeys: TCheckBox;
    // Appearance
    grpTheme: TGroupBox;
    chkDarkTheme: TCheckBox;
    chkAutoHideToolbar: TCheckBox;
    lblFontSettings: TLabel;
    lblCurrentFont: TLabel;
    btnChooseFont: TButton;
    dlgFont: TFontDialog;
    // Hotkeys
    grpHotkeys: TGroupBox;
    lblHotkeyNewNote: TLabel;
    edtHotkeyNewNote: TEdit;
    lblHotkeySearch: TLabel;
    edtHotkeySearch: TEdit;
    // Backup
    grpBackup: TGroupBox;
    chkBackupEnabled: TCheckBox;
    lblBackupInterval: TLabel;
    edtBackupInterval: TEdit;
    udBackupInterval: TUpDown;
    lblBackupRetention: TLabel;
    edtBackupRetention: TEdit;
    udBackupRetention: TUpDown;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnOKClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure chkDarkThemeClick(Sender: TObject);
    procedure btnChooseFontClick(Sender: TObject);
  private
    FSettings: TSettings;
    FOriginalSettings: TSettings;
    // Phase 7B: sync controls are created in code (see FormCreate), so the
    // dialog's DFM needs no change.
    FGrpSync: TGroupBox;
    FChkSyncEnabled: TCheckBox;
    FLblSyncFolder: TLabel;
    FEdtSyncFolder: TEdit;
    FBtnBrowseSync: TButton;
    procedure LoadControls;
    procedure SaveControls;
    procedure SyncBrowseClick(Sender: TObject);
  public
    procedure LoadSettings(ASettings: TSettings);
    procedure SaveSettings(ASettings: TSettings);
    destructor Destroy; override;
  end;

var
  SettingsForm: TSettingsForm;

implementation

uses
  uEnums, uThemeService, Vcl.FileCtrl, Winapi.ShellAPI;

{$R *.dfm}

{ TSettingsForm }

procedure TSettingsForm.FormCreate(Sender: TObject);
var
  C: TNoteColor;
begin
  // Populate default color combo
  for C := Low(TNoteColor) to High(TNoteColor) do
    cbDefaultColor.Items.Add(NoteColorToName(C));
  cbDefaultColor.Style := csDropDownList;

  // Setup up/down controls
  udAutosaveDelay.Min := 100;
  udAutosaveDelay.Max := 60000;
  udAutosaveDelay.Increment := 100;

  udBackupInterval.Min := 1;
  udBackupInterval.Max := 30;
  udBackupInterval.Increment := 1;

  udBackupRetention.Min := 0;
  udBackupRetention.Max := 365;
  udBackupRetention.Increment := 1;

  // Phase 7B: sync controls, created in code and placed under the backup group
  // on the same tab (keeps the DFM untouched).
  tsBackup.Caption := 'Backup / Sync';

  FGrpSync := TGroupBox.Create(Self);
  FGrpSync.Parent := tsBackup;
  FGrpSync.Left := 16;
  FGrpSync.Top := 152;
  FGrpSync.Width := 441;
  FGrpSync.Height := 105;
  FGrpSync.Caption := 'Sync Settings';

  FChkSyncEnabled := TCheckBox.Create(Self);
  FChkSyncEnabled.Parent := FGrpSync;
  FChkSyncEnabled.Left := 12;
  FChkSyncEnabled.Top := 24;
  FChkSyncEnabled.Width := 400;
  FChkSyncEnabled.Caption := 'Enable folder sync (Drive / Dropbox / OneDrive)';

  FLblSyncFolder := TLabel.Create(Self);
  FLblSyncFolder.Parent := FGrpSync;
  FLblSyncFolder.Left := 12;
  FLblSyncFolder.Top := 52;
  FLblSyncFolder.Caption := 'Sync folder:';

  FEdtSyncFolder := TEdit.Create(Self);
  FEdtSyncFolder.Parent := FGrpSync;
  FEdtSyncFolder.Left := 12;
  FEdtSyncFolder.Top := 72;
  FEdtSyncFolder.Width := 370;

  FBtnBrowseSync := TButton.Create(Self);
  FBtnBrowseSync.Parent := FGrpSync;
  FBtnBrowseSync.Left := 388;
  FBtnBrowseSync.Top := 71;
  FBtnBrowseSync.Width := 45;
  FBtnBrowseSync.Height := 25;
  FBtnBrowseSync.Caption := '...';
  FBtnBrowseSync.OnClick := SyncBrowseClick;

  // Phase 4C: snapshot for the Cancel rollback path. Allocated once
  // per form instance and refreshed by LoadSettings. Released in
  // Destroy (declared on the class) so we do not leak one TSettings
  // per visit to the Settings dialog.
  FOriginalSettings := TSettings.Create;
end;

destructor TSettingsForm.Destroy;
begin
  FreeAndNil(FOriginalSettings);
  inherited;
end;

procedure TSettingsForm.FormShow(Sender: TObject);
begin
  LoadControls;
end;

procedure TSettingsForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Phase 4C: any non-OK close path (Cancel button, Esc key, X button,
  // Alt+F4) must roll the in-memory settings back to the snapshot.
  // btnCancelClick already does this for the explicit Cancel click,
  // but the other paths bypass it. Centralise the rollback here so the
  // dialog is safe regardless of how it is dismissed.
  if (ModalResult <> mrOk) and Assigned(FSettings) and Assigned(FOriginalSettings) then
    FSettings.Assign(FOriginalSettings);
end;

procedure TSettingsForm.LoadSettings(ASettings: TSettings);
begin
  FSettings := ASettings;
  FOriginalSettings.Assign(ASettings);
  LoadControls;
end;

procedure TSettingsForm.SaveSettings(ASettings: TSettings);
begin
  SaveControls;
  ASettings.Assign(FSettings);
end;

procedure TSettingsForm.LoadControls;
begin
  if FSettings = nil then Exit;
  
  chkAutoStart.Checked := FSettings.AutoStart;
  chkConfirmDelete.Checked := FSettings.ConfirmDelete;
  edtAutosaveDelay.Text := FSettings.AutosaveDelay.ToString;
  edtDefaultWidth.Text := FSettings.DefaultWidth.ToString;
  edtDefaultHeight.Text := FSettings.DefaultHeight.ToString;
  cbDefaultColor.ItemIndex := Ord(FSettings.DefaultColor);
  chkDefaultAlwaysOnTop.Checked := FSettings.DefaultAlwaysOnTop;
  chkEnableHotkeys.Checked := FSettings.EnableHotkeys;
  chkDarkTheme.Checked := FSettings.DarkTheme;
  chkAutoHideToolbar.Checked := FSettings.AutoHideToolbar;
  lblCurrentFont.Caption := Format('%s, %d pt', [FSettings.FontName, FSettings.FontSize]);
  edtHotkeyNewNote.Text := FSettings.HotkeyNewNote;
  edtHotkeySearch.Text := FSettings.HotkeySearch;
  chkBackupEnabled.Checked := FSettings.BackupEnabled;
  edtBackupInterval.Text := FSettings.BackupIntervalDays.ToString;
  edtBackupRetention.Text := FSettings.BackupRetentionDays.ToString;
  FChkSyncEnabled.Checked := FSettings.SyncEnabled;
  FEdtSyncFolder.Text := FSettings.SyncFolder;
end;

procedure TSettingsForm.SaveControls;
begin
  if FSettings = nil then Exit;
  
  FSettings.AutoStart := chkAutoStart.Checked;
  FSettings.ConfirmDelete := chkConfirmDelete.Checked;
  FSettings.AutosaveDelay := StrToIntDef(edtAutosaveDelay.Text, 1000);
  FSettings.DefaultWidth := StrToIntDef(edtDefaultWidth.Text, 300);
  FSettings.DefaultHeight := StrToIntDef(edtDefaultHeight.Text, 250);
  FSettings.DefaultColor := TNoteColor(cbDefaultColor.ItemIndex);
  FSettings.DefaultAlwaysOnTop := chkDefaultAlwaysOnTop.Checked;
  FSettings.EnableHotkeys := chkEnableHotkeys.Checked;
  FSettings.DarkTheme := chkDarkTheme.Checked;
  FSettings.AutoHideToolbar := chkAutoHideToolbar.Checked;
  FSettings.HotkeyNewNote := edtHotkeyNewNote.Text;
  FSettings.HotkeySearch := edtHotkeySearch.Text;
  FSettings.BackupEnabled := chkBackupEnabled.Checked;
  FSettings.BackupIntervalDays := StrToIntDef(edtBackupInterval.Text, 1);
  FSettings.BackupRetentionDays := StrToIntDef(edtBackupRetention.Text, 30);
  FSettings.SyncEnabled := FChkSyncEnabled.Checked;
  FSettings.SyncFolder := Trim(FEdtSyncFolder.Text);
end;

procedure TSettingsForm.SyncBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := FEdtSyncFolder.Text;
  if SelectDirectory('Select the folder your cloud client syncs', '', Dir) then
    FEdtSyncFolder.Text := Dir;
end;

procedure TSettingsForm.btnChooseFontClick(Sender: TObject);
begin
  if FSettings = nil then Exit;
  
  dlgFont.Font.Name := FSettings.FontName;
  dlgFont.Font.Size := FSettings.FontSize;
  if dlgFont.Execute then
  begin
    FSettings.FontName := dlgFont.Font.Name;
    FSettings.FontSize := dlgFont.Font.Size;
    lblCurrentFont.Caption := Format('%s, %d pt', [FSettings.FontName, FSettings.FontSize]);
  end;
end;

// Phase 4F: the former live theme preview (ApplyPreview -> TrySetStyle)
// was removed. Applying a VCL style while this dialog is showing forces a
// handle recreation of the showing modal form, which re-enters its show
// sequence and raises EInvalidOperation "Cannot change Visible in OnShow
// or OnHide". The selected theme is applied safely on OK instead, via
// TTrayForm.OnSettings -> TThemeService.SetDarkTheme (after the modal is
// hidden). btnApply still persists the other settings without touching
// the live style.

procedure TSettingsForm.btnOKClick(Sender: TObject);
begin
  SaveControls;
  ModalResult := mrOk;
end;

procedure TSettingsForm.btnCancelClick(Sender: TObject);
begin
  // Phase 4C: rollback is centralised in FormClose so all non-OK
  // dismiss paths are covered uniformly.
  ModalResult := mrCancel;
end;

procedure TSettingsForm.btnApplyClick(Sender: TObject);
begin
  SaveControls;
end;

procedure TSettingsForm.chkDarkThemeClick(Sender: TObject);
begin
  // Selection is applied on OK (see comment above).
end;

end.