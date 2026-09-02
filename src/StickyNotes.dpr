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
  uILogger in 'Utils\uILogger.pas',
  uSingleInstance in 'Utils\uSingleInstance.pas';

{$R *.res}
// VCL styles (Windows10, Windows10 Blue, Windows10 Dark) are embedded in the
// project .res (StickyNotes.res) via the IDE Project > Appearance mechanism.
// Do NOT link a second style .res here: duplicate VCLSTYLE resources make
// TStyleManager auto-discovery raise EDuplicateStyleException at startup.

var
  SingleInstance: TSingleInstance;

begin
  // Phase 4C: ensure only one Sticky Notes instance runs for this user.
  // Acquire is performed before Application.Initialize so a second
  // launch can short-circuit without ever instantiating the tray form.
  SingleInstance := TSingleInstance.Create;
  try
    if not SingleInstance.Acquire then
    begin
      // Ask the running instance to surface itself, then exit cleanly.
      SingleInstance.SignalExisting;
      SingleInstance.Free;
      SingleInstance := nil;
      Exit;
    end;
  except
    // If the guard itself fails, fall through and start normally rather
    // than blocking the user from launching the application.
    SingleInstance.Free;
    SingleInstance := nil;
  end;

  try
    Application.Initialize;
    Application.MainFormOnTaskbar := False;
    Application.ShowMainForm := False;
    TStyleManager.TrySetStyle('Windows10');
    Application.Title := 'Sticky Notes';

    // Enable runtime themes
    // Create the main tray form (hidden)
    Application.CreateForm(TTrayForm, TrayForm);

    // Run the application
    Application.Run;
  finally
    if Assigned(SingleInstance) then
    begin
      SingleInstance.Free;
      SingleInstance := nil;
    end;
  end;
end.