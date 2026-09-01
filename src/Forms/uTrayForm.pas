unit uTrayForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShlObj, System.SysUtils, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  uNote, uNoteManager, uSettings, uTrayController, uSettingsController,
  uAutosaveService, uHotkeyService, uThemeService, uBackupService,
  uStorage, uNoteForm, uNoteApplication, uNoteEditorContext;

type
  TTrayForm = class(TForm)
    tiMain: TTrayIcon;
    pmTray: TPopupMenu;
    miNewNote: TMenuItem;
    miOpenNotes: TMenuItem;
    N1: TMenuItem;
    miSettings: TMenuItem;
    miBackup: TMenuItem;
    miRestore: TMenuItem;
    N2: TMenuItem;
    miAbout: TMenuItem;
    miExit: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure miNewNoteClick(Sender: TObject);
    procedure miOpenNotesClick(Sender: TObject);
    procedure miSettingsClick(Sender: TObject);
    procedure miBackupClick(Sender: TObject);
    procedure miRestoreClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure tiMainDblClick(Sender: TObject);
  private
    FApplication: TNoteApplication;
    // UI tracking
    FNoteForms: TList<TNoteForm>;

    // NOTE: FTrayController is constructed but never shown (the dfm-wired
    // tiMain/pmTray is the active tray UI). Preserved as dead code.
    FTrayController: TTrayController;
    procedure SetupHotkeys;
    procedure NoteFormClosed(Sender: TObject);
    procedure OnNewNote(Sender: TObject);
    procedure OnOpenNotesList(Sender: TObject);
    procedure OnSettings(Sender: TObject);
    procedure OnBackup(Sender: TObject);
    procedure OnRestore(Sender: TObject);
    procedure OnAbout(Sender: TObject);
    procedure OnExit(Sender: TObject);
    procedure OnNoteCreated(const ANote: TNote);
    procedure OnNoteChanged(const ANote: TNote);
    procedure OnNoteDeleted(const ANote: TNote);
    procedure OnHotkeyNewNote;
    procedure OnHotkeySearch;
    procedure CreateNoteForm(ANote: TNote);
    procedure OpenAllNotes;
    procedure CloseAllNotes;
    procedure SaveAllNotes;
    procedure WndProc(var Message: TMessage); override;
  public
    property App: TNoteApplication read FApplication;
  end;

var
  TrayForm: TTrayForm;

implementation

uses
  uSettingsForm, uAboutForm, uJsonStorage, System.IOUtils;

{$R *.dfm}

{ TTrayForm }

procedure TTrayForm.FormCreate(Sender: TObject);
begin
  FNoteForms := TList<TNoteForm>.Create;

  // Application orchestration layer (owns all services)
  FApplication := TNoteApplication.Create(Handle);

  // Wire UI callbacks
  FApplication.OnNoteCreated := OnNoteCreated;
  FApplication.OnNoteChanged := OnNoteChanged;
  FApplication.OnNoteDeleted := OnNoteDeleted;

  // Initialize (loads settings, storage, notes)
  FApplication.Initialize;

  // Create FTrayController (unused – see declaration comment)
  FTrayController := TTrayController.Create(
    FApplication.NoteManager, FApplication.Settings);
  FTrayController.OnNewNote := OnNewNote;
  FTrayController.OnOpenNotesList := OnOpenNotesList;
  FTrayController.OnSettings := OnSettings;
  FTrayController.OnBackup := OnBackup;
  FTrayController.OnRestore := OnRestore;
  FTrayController.OnAbout := OnAbout;
  FTrayController.OnExit := OnExit;

  // Setup hotkeys (needs form methods as callbacks)
  SetupHotkeys;

  // Setup tray
  tiMain.Icon := Application.Icon;
  tiMain.Hint := 'Sticky Notes';
  tiMain.Visible := True;

  // Open existing notes
  OpenAllNotes;

  // If no notes, create one
  if FApplication.NoteManager.NoteCount = 0 then
    OnNewNote(Self);
end;

procedure TTrayForm.FormDestroy(Sender: TObject);
begin
  SaveAllNotes;
  CloseAllNotes;

  FTrayController.Free;
  FApplication.Free;   // TNoteApplication.Destroy calls Shutdown internally
  FNoteForms.Free;
end;

procedure TTrayForm.NoteFormClosed(Sender: TObject);
var
  Form: TNoteForm;
begin
  Form := Sender as TNoteForm;
  Form.OnClosed := nil; // prevent recursion
  FNoteForms.Remove(Form);
end;

procedure TTrayForm.SetupHotkeys;
begin
  if FApplication.Settings.EnableHotkeys then
  begin
    FApplication.HotkeyService.RegisterHotkey(
      hkNewNote, FApplication.Settings.HotkeyNewNote, OnHotkeyNewNote);
    FApplication.HotkeyService.RegisterHotkey(
      hkSearch, FApplication.Settings.HotkeySearch, OnHotkeySearch);
  end;
end;

procedure TTrayForm.WndProc(var Message: TMessage);
begin
  if Assigned(FApplication) and (Message.Msg = WM_HOTKEY) then
    FApplication.HotkeyService.HandleMessage(Message)
  else
    inherited WndProc(Message);
end;

procedure TTrayForm.OnNewNote(Sender: TObject);
var
  Note: TNote;
begin
  Note := FApplication.NoteManager.CreateNote(
    '', '', FApplication.Settings.DefaultColor);
  Note.Width := FApplication.Settings.DefaultWidth;
  Note.Height := FApplication.Settings.DefaultHeight;
  Note.AlwaysOnTop := FApplication.Settings.DefaultAlwaysOnTop;
  CreateNoteForm(Note);
end;

procedure TTrayForm.OnOpenNotesList(Sender: TObject);
begin
  // Show notes list form - for now just ensure all notes are visible
  OpenAllNotes;
end;

procedure TTrayForm.OnSettings(Sender: TObject);
var
  SettingsForm: TSettingsForm;
begin
  SettingsForm := TSettingsForm.Create(Self);
  try
    SettingsForm.LoadSettings(FApplication.Settings);
    if SettingsForm.ShowModal = mrOk then
    begin
      SettingsForm.SaveSettings(FApplication.Settings);
      FApplication.ThemeService.SetDarkTheme(FApplication.Settings.DarkTheme);
      FApplication.AutosaveService.Delay := FApplication.Settings.AutosaveDelay;

      // Update hotkeys
      if FApplication.Settings.EnableHotkeys then
      begin
        FApplication.HotkeyService.RegisterHotkey(
          hkNewNote, FApplication.Settings.HotkeyNewNote, OnHotkeyNewNote);
        FApplication.HotkeyService.RegisterHotkey(
          hkSearch, FApplication.Settings.HotkeySearch, OnHotkeySearch);
      end
      else
      begin
        FApplication.HotkeyService.UnregisterHotkey(hkNewNote);
        FApplication.HotkeyService.UnregisterHotkey(hkSearch);
      end;

      FApplication.SaveSettings;
    end;
  finally
    SettingsForm.Free;
  end;
end;

procedure TTrayForm.OnBackup(Sender: TObject);
begin
  FApplication.BackupService.Backup;
end;

procedure TTrayForm.OnRestore(Sender: TObject);
var
  OpenDialog: TOpenDialog;
begin
  OpenDialog := TOpenDialog.Create(Self);
  try
    OpenDialog.InitialDir := TPath.Combine(FApplication.AppDataPath, 'backups');
    OpenDialog.Filter := 'Backup files (*.zip)|*.zip';
    if OpenDialog.Execute then
      FApplication.BackupService.Restore(OpenDialog.FileName);
  finally
    OpenDialog.Free;
  end;
end;

procedure TTrayForm.OnAbout(Sender: TObject);
var
  AboutForm: TAboutForm;
begin
  AboutForm := TAboutForm.Create(Self);
  try
    AboutForm.ShowModal;
  finally
    AboutForm.Free;
  end;
end;

procedure TTrayForm.OnExit(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TTrayForm.OnNoteCreated(const ANote: TNote);
begin
  CreateNoteForm(ANote);
end;

procedure TTrayForm.OnNoteChanged(const ANote: TNote);
begin
  // Note was saved, could update UI if needed
end;

procedure TTrayForm.OnNoteDeleted(const ANote: TNote);
var
  I: Integer;
  Form: TNoteForm;
begin
  for I := FNoteForms.Count - 1 downto 0 do
  begin
    Form := FNoteForms[I];
    if Form.Note = ANote then
    begin
      Form.CloseWithoutSaving;
      FNoteForms.Delete(I);
      Break;
    end;
  end;
end;

procedure TTrayForm.OnHotkeyNewNote;
begin
  OnNewNote(Self);
end;

procedure TTrayForm.OnHotkeySearch;
begin
  // TODO: Show search form
  OnOpenNotesList(Self);
end;

procedure TTrayForm.CreateNoteForm(ANote: TNote);
var
  Form: TNoteForm;
  Ctx: INoteEditorContext;
begin
  Ctx := TNoteEditorContext.Create(
    FApplication.NoteManager,
    FApplication.AutosaveService,
    FApplication.ThemeService,
    FApplication.Settings);

  Form := TNoteForm.CreateNote(Self, ANote, Ctx);
  Form.OnClosed := NoteFormClosed;
  FNoteForms.Add(Form);
  Form.Show;
end;

procedure TTrayForm.OpenAllNotes;
var
  I: Integer;
  Note: TNote;
begin
  for I := 0 to FApplication.NoteManager.NoteCount - 1 do
  begin
    Note := FApplication.NoteManager.Notes[I];
    var Found := False;
    for var Form in FNoteForms do
      if Form.Note = Note then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      CreateNoteForm(Note);
  end;
end;

procedure TTrayForm.CloseAllNotes;
var
  I: Integer;
begin
  for I := FNoteForms.Count - 1 downto 0 do
    FNoteForms[I].CloseWithoutSaving;
  FNoteForms.Clear;
end;

procedure TTrayForm.SaveAllNotes;
var
  Form: TNoteForm;
begin
  for Form in FNoteForms do
    Form.Save;
  FApplication.AutosaveService.Flush;
end;

procedure TTrayForm.miNewNoteClick(Sender: TObject);
begin
  OnNewNote(Sender);
end;

procedure TTrayForm.miOpenNotesClick(Sender: TObject);
begin
  OnOpenNotesList(Sender);
end;

procedure TTrayForm.miSettingsClick(Sender: TObject);
begin
  OnSettings(Sender);
end;

procedure TTrayForm.miBackupClick(Sender: TObject);
begin
  OnBackup(Sender);
end;

procedure TTrayForm.miRestoreClick(Sender: TObject);
begin
  OnRestore(Sender);
end;

procedure TTrayForm.miAboutClick(Sender: TObject);
begin
  OnAbout(Sender);
end;

procedure TTrayForm.miExitClick(Sender: TObject);
begin
  OnExit(Sender);
end;

procedure TTrayForm.tiMainDblClick(Sender: TObject);
begin
  OnNewNote(Sender);
end;

end.