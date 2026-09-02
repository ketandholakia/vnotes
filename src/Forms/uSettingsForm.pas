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
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnOKClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure chkDarkThemeClick(Sender: TObject);
  private
    FSettings: TSettings;
    FOriginalSettings: TSettings;
    procedure LoadControls;
    procedure SaveControls;
    procedure ApplyPreview;
  public
    procedure LoadSettings(ASettings: TSettings);
    procedure SaveSettings(ASettings: TSettings);
    destructor Destroy; override;
  end;

var
  SettingsForm: TSettingsForm;

implementation

uses
  uEnums, uThemeService, Winapi.ShellAPI, Vcl.Themes, Vcl.Styles;

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
  edtHotkeyNewNote.Text := FSettings.HotkeyNewNote;
  edtHotkeySearch.Text := FSettings.HotkeySearch;
  chkBackupEnabled.Checked := FSettings.BackupEnabled;
  edtBackupInterval.Text := FSettings.BackupIntervalDays.ToString;
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
  FSettings.HotkeyNewNote := edtHotkeyNewNote.Text;
  FSettings.HotkeySearch := edtHotkeySearch.Text;
  FSettings.BackupEnabled := chkBackupEnabled.Checked;
  FSettings.BackupIntervalDays := StrToIntDef(edtBackupInterval.Text, 1);
end;

procedure TSettingsForm.ApplyPreview;
begin
  // Apply theme preview
  if chkDarkTheme.Checked then
    TStyleManager.TrySetStyle('Windows10 Dark')
  else
    TStyleManager.TrySetStyle('Windows10');
end;

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
  ApplyPreview;
end;

procedure TSettingsForm.chkDarkThemeClick(Sender: TObject);
begin
  ApplyPreview;
end;

end.