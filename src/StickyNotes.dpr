program StickyNotes;

uses
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  Winapi.Windows,
  System.SysUtils,
  uTrayForm in 'Forms\uTrayForm.pas' {TrayForm},
  uNoteForm in 'Forms\uNoteForm.pas' {NoteForm},
  uSettingsForm in 'Forms\uSettingsForm.pas' {SettingsForm},
  uAboutForm in 'Forms\uAboutForm.pas' {AboutForm},
  uNotesListForm in 'Forms\uNotesListForm.pas' {NotesListForm},
  uNote in 'Models\uNote.pas',
  uSettings in 'Models\uSettings.pas',
  uEnums in 'Models\uEnums.pas',
  uNoteManager in 'Controllers\uNoteManager.pas',
  uTrayController in 'Controllers\uTrayController.pas',
  uSettingsController in 'Controllers\uSettingsController.pas',
  uStorage in 'Storage\uStorage.pas',
  uJsonStorage in 'Storage\uJsonStorage.pas',
  uSQLiteStorage in 'Storage\uSQLiteStorage.pas',
  uNoteQuery in 'Storage\uNoteQuery.pas',
  uAutosaveService in 'Services\uAutosaveService.pas',
  uHotkeyService in 'Services\uHotkeyService.pas',
  uStartupService in 'Services\uStartupService.pas',
  uThemeService in 'Services\uThemeService.pas',
  uBackupService in 'Services\uBackupService.pas',
  uNoteApplication in 'Application\uNoteApplication.pas',
  uNoteEditorContext in 'Application\uNoteEditorContext.pas',
  uWindowUtils in 'Utils\uWindowUtils.pas',
  uJsonUtils in 'Utils\uJsonUtils.pas',
  uColorUtils in 'Utils\uColorUtils.pas',
  uILogger in 'Utils\uILogger.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := False;
  Application.ShowMainForm := False;
  Application.Title := 'Sticky Notes';
  
  // Enable runtime themes
  TStyleManager.TrySetStyle('Windows10');
  
  // Create the main tray form (hidden)
  Application.CreateForm(TTrayForm, TrayForm);
  
  // Run the application
  Application.Run;
end.