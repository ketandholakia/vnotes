unit uTrayForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShlObj, System.SysUtils, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Menus,
  System.Generics.Defaults, uEnums,
  uNote, uNoteManager, uSettings, uSettingsController,
  uAutosaveService, uHotkeyService, uThemeService, uBackupService,
  uStorage, uNoteQuery, uNoteForm, uNoteApplication, uNoteEditorContext,
  uNotesListForm, uConflictForm, uServiceInterfaces;

type
  TTrayForm = class(TForm)
    tiMain: TTrayIcon;
    pmTray: TPopupMenu;
    miNewNote: TMenuItem;
    miOpenNotes: TMenuItem;
    miArrangeNotes: TMenuItem;
    miArrangeCascade: TMenuItem;
    miArrangeGrid: TMenuItem;
    miArrangeByColor: TMenuItem;
    miArrangeByTag: TMenuItem;
    N1: TMenuItem;
    miSettings: TMenuItem;
    miBackup: TMenuItem;
    miRestore: TMenuItem;
    N2: TMenuItem;
    miAbout: TMenuItem;
    miExit: TMenuItem;
    // Phase 7B: created at runtime (not present in the DFM).
    miSyncNow: TMenuItem;
    miSyncConflicts: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure miNewNoteClick(Sender: TObject);
    procedure miOpenNotesClick(Sender: TObject);
    procedure miArrangeCascadeClick(Sender: TObject);
    procedure miArrangeGridClick(Sender: TObject);
    procedure miArrangeByColorClick(Sender: TObject);
    procedure miArrangeByTagClick(Sender: TObject);
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
    FNoteQuery: INoteQuery;
    FNotesListForm: TNotesListForm;
    // Cached handle of the registered "another instance appeared" message.
    FAppearMessage: UINT;

    procedure SetupHotkeys;
    procedure NoteFormClosed(Sender: TObject);
    procedure OnNewNote(Sender: TObject);
    procedure OnOpenNotesList(Sender: TObject);
    procedure OnSettings(Sender: TObject);
    procedure OnBackup(Sender: TObject);
    procedure OnRestore(Sender: TObject);
    procedure OnSyncNow(Sender: TObject);
    procedure SyncProgress(const AMessage: string; AProgress: Integer);
    procedure SyncComplete(ASuccess: Boolean; const AMessage: string);
    procedure OnSyncConflicts(Sender: TObject);
    function CountConflicts: Integer;
    procedure TrayMenuPopup(Sender: TObject);
    procedure BackupProgress(const AMessage: string; AProgress: Integer);
    procedure BackupComplete(ASuccess: Boolean; const AMessage: string);
    procedure RestoreComplete(ASuccess: Boolean; const AMessage: string);
    // Storage-swap guards: the restore path replaces vnotes.db and
    // re-initializes the note manager, which frees every TNote. Open note
    // windows must be closed before the swap and are re-opened after it.
    procedure BackupBeforeStorageSwap(Sender: TObject);
    procedure BackupAfterStorageSwap(Sender: TObject);
    procedure OnAbout(Sender: TObject);
    procedure OnExit(Sender: TObject);
    procedure OnNoteCreated(const ANote: TNote);
    procedure OnNoteChanged(const ANote: TNote);
    procedure OnNoteDeleted(const ANote: TNote);
    // New request handlers for event-driven note open/close
    procedure OnNoteOpenRequested(const ANote: TNote);
    procedure OnNoteCloseRequested(const ANote: TNote);
    procedure OnHotkeyNewNote;
    procedure OnHotkeySearch;
    procedure CreateNoteForm(ANote: TNote);
    function FindNoteForm(ANote: TNote): TNoteForm;
    procedure ShowNoteWindow(ANote: TNote);
    procedure ShowNotesList(AFocusSearch: Boolean);
    procedure OpenAllNotes;
    procedure CloseAllNotes;
    procedure SaveAllNotes;
    procedure HandleAppearMessage;
    procedure WndProc(var Message: TMessage); override;
  public
    property App: TNoteApplication read FApplication;
  end;

var
  TrayForm: TTrayForm;

implementation

uses
  uSettingsForm, uAboutForm, uJsonStorage, uSingleInstance, System.IOUtils;

{$R *.dfm}

{ TTrayForm }

procedure TTrayForm.FormCreate(Sender: TObject);
begin
  FNoteForms := TList<TNoteForm>.Create;
  FAppearMessage := 0;

  // Application orchestration layer (owns all services)
  FApplication := TNoteApplication.Create(Handle);

  // Wire UI callbacks
  FApplication.OnNoteCreated := OnNoteCreated;
  FApplication.OnNoteChanged := OnNoteChanged;
  FApplication.OnNoteDeleted := OnNoteDeleted;
  // Wire new request events for event-driven note open/close
  FApplication.OnNoteOpenRequested := OnNoteOpenRequested;
  FApplication.OnNoteCloseRequested := OnNoteCloseRequested;

  // Wire backup service callbacks for user feedback
  FApplication.BackupService.OnProgress := BackupProgress;
  FApplication.BackupService.OnComplete := BackupComplete;
  FApplication.BackupService.OnBeforeStorageSwap := BackupBeforeStorageSwap;
  FApplication.BackupService.OnAfterStorageSwap := BackupAfterStorageSwap;
  // Initialize (loads settings, storage, notes)
  FApplication.Initialize;

  // In-memory search (Phase 4B)
  FNoteQuery := TNoteQuery.Create;

  // Setup hotkeys (needs form methods as callbacks)
  SetupHotkeys;

  // Setup tray
  tiMain.Icon := Application.Icon;
  tiMain.Hint := 'V-Notes';
  tiMain.Visible := True;

  // Phase 7B: "Sync now" item, created at runtime so the DFM stays untouched.
  // It sits just above the About/Exit separator and is enabled only when a
  // sync folder is configured.
  miSyncNow := TMenuItem.Create(Self);
  miSyncNow.Caption := 'S&ync now';
  miSyncNow.OnClick := OnSyncNow;
  miSyncNow.Enabled := FApplication.SyncService <> nil;
  pmTray.Items.Insert(pmTray.Items.IndexOf(N2), miSyncNow);

  miSyncConflicts := TMenuItem.Create(Self);
  miSyncConflicts.Caption := 'Sync &conflicts...';
  miSyncConflicts.OnClick := OnSyncConflicts;
  pmTray.Items.Insert(pmTray.Items.IndexOf(N2), miSyncConflicts);

  // Refresh sync item state/caption each time the menu opens.
  pmTray.OnPopup := TrayMenuPopup;

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

    // Show any hotkey registration failures after attempting to register
    FApplication.HotkeyService.ShowHotkeyFailures;
  end;
end;

procedure TTrayForm.WndProc(var Message: TMessage);
begin
  if Assigned(FApplication) and (Message.Msg = WM_HOTKEY) then
    FApplication.HotkeyService.HandleMessage(Message)
  else
  begin
    // Phase 4C: when a second instance tries to launch, it posts this
    // registered message to us. Surface the notes list as a friendly
    // "I'm already here" gesture without forcing the (hidden) tray form
    // itself to become visible.
    if FAppearMessage = 0 then
      FAppearMessage := SingleInstanceAppearMessage;
    if (FAppearMessage <> 0) and (Message.Msg = FAppearMessage) then
      HandleAppearMessage
    else
      inherited WndProc(Message);
  end;
end;

procedure TTrayForm.HandleAppearMessage;
begin
  // Bring all open note windows to the front, then show the notes list.
  // This is a best-effort gesture: it does not interrupt the user with
  // dialogs or steal focus if there is no visible UI to surface.
  try
    if (FApplication <> nil) and (FApplication.NoteManager.NoteCount > 0) then
      ShowNotesList(True)
    else
      ShowNotesList(False);
  except
    // Swallow - surfacing the existing instance must never crash the app.
  end;
end;

procedure TTrayForm.OnNewNote(Sender: TObject);
begin
  // Settings-derived defaults are passed INTO CreateNote so the note is
  // fully initialized before OnNoteCreated fires (synchronously inside
  // CreateNote) - OnNoteCreated is the SINGLE window-creation path
  // (TTrayForm.OnNoteCreated -> CreateNoteForm). Creating the form here as
  // well produced the double-open bug. Left/Top 100/100 mirror the TNote
  // constructor defaults; position defaults are not settings-driven.
  FApplication.NoteManager.CreateNote(
    '', '', FApplication.Settings.DefaultColor,
    100, 100,
    FApplication.Settings.DefaultWidth,
    FApplication.Settings.DefaultHeight,
    FApplication.Settings.DefaultAlwaysOnTop);
end;

procedure TTrayForm.OnOpenNotesList(Sender: TObject);
begin
  ShowNotesList(False);
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
      try
        SettingsForm.SaveSettings(FApplication.Settings);
        FApplication.ThemeService.SetDarkTheme(FApplication.Settings.DarkTheme);
        FApplication.AutosaveService.Delay := FApplication.Settings.AutosaveDelay;
        
        for var Form in FNoteForms do
          Form.ApplyFontSettings;

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

        // Phase 4C: re-arm the periodic backup schedule to honour any
        // changes to BackupEnabled / BackupIntervalDays.
        FApplication.RefreshBackupSchedule;

        // Phase 7B: rebuild the sync engine from the new Sync settings.
        FApplication.ApplySyncSettings;
        // Phase 7D: re-arm periodic sync with the new interval.
        FApplication.RefreshSyncSchedule;
        if miSyncNow <> nil then
          miSyncNow.Enabled := FApplication.SyncService <> nil;

        FApplication.SaveSettings;
        tiMain.Hint := 'Settings saved successfully';
      except
        on E: Exception do
        begin
          Application.MessageBox(PChar('Failed to save settings: ' + E.Message),
            'Settings Error', MB_OK or MB_ICONERROR or MB_DEFBUTTON1);
          tiMain.Hint := 'Settings save failed';
        end;
      end;
    end;
  finally
    SettingsForm.Free;
  end;
end;

procedure TTrayForm.OnBackup(Sender: TObject);
begin
  FApplication.BackupService.Backup;
end;

procedure TTrayForm.OnSyncNow(Sender: TObject);
var
  Svc: ISyncService;
begin
  Svc := FApplication.SyncService;
  if Svc = nil then
  begin
    tiMain.BalloonTitle := 'V-Notes';
    tiMain.BalloonHint := 'Sync is not configured. Set a sync folder in Settings.';
    tiMain.ShowBalloonHint;
    Exit;
  end;

  Svc.OnProgress := SyncProgress;
  Svc.OnComplete := SyncComplete;
  tiMain.Hint := 'Syncing...';
  Svc.SyncNow; // the complete handler restores the hint and reports the result
  if FNotesListForm <> nil then
    FNotesListForm.RefreshList;
end;

procedure TTrayForm.SyncProgress(const AMessage: string; AProgress: Integer);
begin
  tiMain.Hint := Format('Sync: %s (%d%%)', [AMessage, AProgress]);
end;

procedure TTrayForm.SyncComplete(ASuccess: Boolean; const AMessage: string);
begin
  tiMain.Hint := 'V-Notes';
  tiMain.BalloonTitle := 'V-Notes';
  tiMain.BalloonHint := AMessage;
  tiMain.ShowBalloonHint;
end;

function TTrayForm.CountConflicts: Integer;
var
  I: Integer;
  N: TNote;
begin
  Result := 0;
  if (FApplication = nil) or (FApplication.NoteManager = nil) then Exit;
  for I := 0 to FApplication.NoteManager.NoteCount - 1 do
  begin
    N := FApplication.NoteManager.Notes[I];
    if (N <> nil) and (N.ConflictOf <> '') then
      Inc(Result);
  end;
end;

procedure TTrayForm.TrayMenuPopup(Sender: TObject);
var
  N: Integer;
begin
  if miSyncNow <> nil then
    miSyncNow.Enabled := FApplication.SyncService <> nil;
  if miSyncConflicts <> nil then
  begin
    N := CountConflicts;
    if N > 0 then
      miSyncConflicts.Caption := Format('Sync &conflicts (%d)...', [N])
    else
      miSyncConflicts.Caption := 'Sync &conflicts...';
  end;
end;

procedure TTrayForm.OnSyncConflicts(Sender: TObject);
var
  Dlg: TConflictForm;
begin
  if CountConflicts = 0 then
  begin
    tiMain.BalloonTitle := 'V-Notes';
    tiMain.BalloonHint := 'No sync conflicts.';
    tiMain.ShowBalloonHint;
    Exit;
  end;
  Dlg := TConflictForm.CreateFor(Self, FApplication.NoteManager);
  try
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

procedure TTrayForm.BackupProgress(const AMessage: string; AProgress: Integer);
begin
  // Optional: Could show progress in tray tooltip or status area if needed
  // For now, we'll rely on the completion notification
end;

procedure TTrayForm.BackupComplete(ASuccess: Boolean; const AMessage: string);
begin
  if ASuccess then
  begin
    // Success notification - keep it subtle since this is expected behavior
    if FApplication.Settings.BackupEnabled then
      tiMain.Hint := 'Backup completed: ' + AMessage;
  end
  else
  begin
    // Failure notification - make this more visible to the user
    Application.MessageBox(PChar('Backup failed: ' + AMessage),
      'Backup Error', MB_OK or MB_ICONERROR or MB_DEFBUTTON1);
    tiMain.Hint := 'Backup failed: ' + AMessage;
  end;
end;

procedure TTrayForm.OnRestore(Sender: TObject);
var
  OpenDialog: TOpenDialog;
  PrevComplete: TBackupComplete;
begin
  OpenDialog := TOpenDialog.Create(Self);
  try
    OpenDialog.InitialDir := TPath.Combine(FApplication.AppDataPath, 'backups');
    OpenDialog.Filter := 'Backup files (*.zip)|*.zip';
    if OpenDialog.Execute then
    begin
      // Swap in the restore completion handler for the duration of the
      // restore only. Leaving it installed made every later backup (manual
      // or scheduled) report through the restore dialog path.
      PrevComplete := FApplication.BackupService.OnComplete;
      FApplication.BackupService.OnComplete := RestoreComplete;
      try
        try
          FApplication.BackupService.Restore(OpenDialog.FileName);
        except
          on E: Exception do
          begin
            Application.MessageBox(PChar('Failed to restore backup: ' + E.Message),
              'Restore Error', MB_OK or MB_ICONERROR or MB_DEFBUTTON1);
            tiMain.Hint := 'Restore failed';
          end;
        end;
      finally
        FApplication.BackupService.OnComplete := PrevComplete;
      end;
    end;
  finally
    OpenDialog.Free;
  end;
end;

procedure TTrayForm.RestoreComplete(ASuccess: Boolean; const AMessage: string);
begin
  if ASuccess then
  begin
    Application.MessageBox(PChar('Restore completed: ' + AMessage),
      'Restore Complete', MB_OK or MB_ICONINFORMATION or MB_DEFBUTTON1);
    tiMain.Hint := 'Restore completed: ' + AMessage;
  end
  else
  begin
    Application.MessageBox(PChar('Restore failed: ' + AMessage),
      'Restore Error', MB_OK or MB_ICONERROR or MB_DEFBUTTON1);
    tiMain.Hint := 'Restore failed: ' + AMessage;
  end;
end;

procedure TTrayForm.BackupBeforeStorageSwap(Sender: TObject);
begin
  // The storage swap re-initializes the note manager and frees every TNote;
  // open note windows hold direct references to those objects and must be
  // closed first, otherwise they become use-after-free dangling windows.
  FApplication.RequestCloseAllNotes;
end;

procedure TTrayForm.BackupAfterStorageSwap(Sender: TObject);
begin
  // The manager has been re-initialized against the restored storage;
  // re-open note windows for the restored notes.
  FApplication.RequestOpenAllNotes;
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
  // Keep an open note list in sync (the list only ever reads notes).
  if FNotesListForm <> nil then
    FNotesListForm.RefreshList;
end;

procedure TTrayForm.OnNoteChanged(const ANote: TNote);
begin
  // Phase 6C.2: a save (e.g. Favorite toggle via autosave) resyncs an open
  // Notes List so the star indicator and Favorite-first ordering appear.
  // Same guard as create/delete - the list only ever reads notes.
  if FNotesListForm <> nil then
    FNotesListForm.RefreshList;
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
      // CloseWithoutSaving triggers FormClose -> OnClosed -> NoteFormClosed,
      // which already removes the form from FNoteForms. The extra
      // FNoteForms.Delete(I) that used to follow ran on a stale index: it
      // raised "list index out of bounds" when the closed window was last
      // in the list, and untracked the WRONG window otherwise.
      Form.CloseWithoutSaving;
      Break;
    end;
  end;
  // Keep an open note list in sync (the list only ever reads notes).
  if FNotesListForm <> nil then
    FNotesListForm.RefreshList;
end;

procedure TTrayForm.OnNoteOpenRequested(const ANote: TNote);
begin
  if Assigned(ANote) then
    ShowNoteWindow(ANote);
end;

procedure TTrayForm.OnNoteCloseRequested(const ANote: TNote);
var
  Form: TNoteForm;
begin
  if Assigned(ANote) then
  begin
    Form := FindNoteForm(ANote);
    if Assigned(Form) then
      Form.Close;
  end;
end;

procedure TTrayForm.OnHotkeyNewNote;
begin
  OnNewNote(Self);
end;

procedure TTrayForm.OnHotkeySearch;
begin
  ShowNotesList(True);
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
begin
  FApplication.RequestOpenAllNotes;
end;

procedure TTrayForm.CloseAllNotes;
begin
  FApplication.RequestCloseAllNotes;
end;

procedure TTrayForm.SaveAllNotes;
var
  Form: TNoteForm;
begin
  for Form in FNoteForms do
    Form.Save;
  FApplication.AutosaveService.Flush;
end;

function TTrayForm.FindNoteForm(ANote: TNote): TNoteForm;
var
  Form: TNoteForm;
begin
  Result := nil;
  for Form in FNoteForms do
    if Form.Note = ANote then
      Exit(Form);
end;

procedure TTrayForm.ShowNoteWindow(ANote: TNote);
var
  Form: TNoteForm;
begin
  if ANote = nil then
    Exit;
  // Reuse the existing note-form lifecycle: bring an already-open window to
  // the front, otherwise create one via the single CreateNoteForm path.
  Form := FindNoteForm(ANote);
  if Form <> nil then
  begin
    if IsIconic(Form.Handle) then
      ShowWindow(Form.Handle, SW_RESTORE);
    Form.Show;
    Form.BringToFront;
    SetForegroundWindow(Form.Handle);
  end
  else
    CreateNoteForm(ANote);
end;

procedure TTrayForm.ShowNotesList(AFocusSearch: Boolean);
begin
  if FNotesListForm = nil then
  begin
    // Owned by Self; hidden (caHide) on close and reused. The list form never
    // owns notes - it reads via the manager and the INoteQuery abstraction.
    FNotesListForm := TNotesListForm.CreateFor(Self, FApplication.NoteManager, FNoteQuery);
    FNotesListForm.OnOpenNote := ShowNoteWindow;
  end;
  FNotesListForm.RefreshList;
  if not FNotesListForm.Visible then
    FNotesListForm.Show
  else
    FNotesListForm.BringToFront;
  if AFocusSearch then
    FNotesListForm.FocusSearch;
end;
procedure TTrayForm.miNewNoteClick(Sender: TObject);
begin
  OnNewNote(Sender);
end;

procedure TTrayForm.miOpenNotesClick(Sender: TObject);
begin
  OnOpenNotesList(Sender);
end;

procedure TTrayForm.miArrangeCascadeClick(Sender: TObject);
var
  Form: TNoteForm;
  L, T, W, H: Integer;
begin
  if FNoteForms.Count = 0 then Exit;
  L := 50; T := 50;
  W := FApplication.Settings.DefaultWidth;
  H := FApplication.Settings.DefaultHeight;
  
  for Form in FNoteForms do
  begin
    Form.SetBounds(L, T, W, H);
    Form.Note.Left := L;
    Form.Note.Top := T;
    Form.Note.Width := W;
    Form.Note.Height := H;
    FApplication.NoteManager.PersistNote(Form.Note); // geometry only: no Touch (H5)
    
    Inc(L, 25);
    Inc(T, 25);
    
    // Basic wrapping if it goes too far off screen
    if L > Screen.WorkAreaRect.Right - W - 50 then L := 50;
    if T > Screen.WorkAreaRect.Bottom - H - 50 then T := 50;
  end;
end;

procedure TTrayForm.miArrangeGridClick(Sender: TObject);
var
  Form: TNoteForm;
  Cols, Rows, Col, Row, CellW, CellH, Cnt, Idx: Integer;
begin
  Cnt := FNoteForms.Count;
  if Cnt = 0 then Exit;
  
  // Try to find a roughly square grid
  Cols := Trunc(Sqrt(Cnt));
  if Cols < 1 then Cols := 1;
  Rows := (Cnt + Cols - 1) div Cols;
  
  // Adjust if aspect ratio is very wide
  if (Screen.WorkAreaWidth > Screen.WorkAreaHeight * 1.5) and (Rows > 1) then
  begin
    Cols := Rows;
    Rows := (Cnt + Cols - 1) div Cols;
  end;
  
  CellW := Screen.WorkAreaWidth div Cols;
  CellH := Screen.WorkAreaHeight div Rows;
  
  for Idx := 0 to Cnt - 1 do
  begin
    Form := FNoteForms[Idx];
    Col := Idx mod Cols;
    Row := Idx div Cols;
    
    Form.SetBounds(
      Screen.WorkAreaRect.Left + Col * CellW,
      Screen.WorkAreaRect.Top + Row * CellH,
      CellW, CellH
    );
    
    Form.Note.Left := Form.Left;
    Form.Note.Top := Form.Top;
    Form.Note.Width := Form.Width;
    Form.Note.Height := Form.Height;
    FApplication.NoteManager.PersistNote(Form.Note); // geometry only: no Touch (H5)
  end;
end;

procedure TTrayForm.miArrangeByColorClick(Sender: TObject);
var
  Form: TNoteForm;
  SortedForms: TList<TNoteForm>;
  CurrentColor: TNoteColor;
  L, T, W, H: Integer;
begin
  if FNoteForms.Count = 0 then Exit;
  
  SortedForms := TList<TNoteForm>.Create;
  try
    SortedForms.AddRange(FNoteForms);
    SortedForms.Sort(TComparer<TNoteForm>.Construct(
      function(const L, R: TNoteForm): Integer
      begin
        Result := Ord(L.Note.Color) - Ord(R.Note.Color);
      end
    ));
    
    W := FApplication.Settings.DefaultWidth;
    H := FApplication.Settings.DefaultHeight;
    
    L := 50; T := 50;
    // FNoteForms is non-empty (guarded above), so the first element exists;
    // unconditional init also silences W1036 (review 2026-09-10 H6).
    CurrentColor := SortedForms[0].Note.Color;
      
    for Form in SortedForms do
    begin
      // When color changes, shift to a new starting point
      if Form.Note.Color <> CurrentColor then
      begin
        CurrentColor := Form.Note.Color;
        L := L + W + 50;
        T := 50;
        if L > Screen.WorkAreaRect.Right - W then
        begin
          L := 50;
          Inc(T, H + 50);
        end;
      end;
      
      Form.SetBounds(L, T, W, H);
      Form.Note.Left := L;
      Form.Note.Top := T;
      Form.Note.Width := W;
      Form.Note.Height := H;
      FApplication.NoteManager.PersistNote(Form.Note); // geometry only: no Touch (H5)
      
      Inc(L, 25);
      Inc(T, 25);
    end;
  finally
    SortedForms.Free;
  end;
end;

procedure TTrayForm.miArrangeByTagClick(Sender: TObject);
var
  Form: TNoteForm;
  SortedForms: TList<TNoteForm>;
  CurrentTag, ThisTag: string;
  L, T, W, H: Integer;
begin
  if FNoteForms.Count = 0 then Exit;
  
  SortedForms := TList<TNoteForm>.Create;
  try
    SortedForms.AddRange(FNoteForms);
    SortedForms.Sort(TComparer<TNoteForm>.Construct(
      function(const L, R: TNoteForm): Integer
      var
        LTag, RTag: string;
      begin
        if Length(L.Note.Tags) > 0 then LTag := L.Note.Tags[0] else LTag := '';
        if Length(R.Note.Tags) > 0 then RTag := R.Note.Tags[0] else RTag := '';
        Result := CompareText(LTag, RTag);
      end
    ));
    
    W := FApplication.Settings.DefaultWidth;
    H := FApplication.Settings.DefaultHeight;
    
    L := 50; T := 50;
    // FNoteForms is non-empty (guarded above); unconditional init also
    // silences W1036 (review 2026-09-10 H6).
    if Length(SortedForms[0].Note.Tags) > 0 then
      CurrentTag := SortedForms[0].Note.Tags[0]
    else
      CurrentTag := '';
      
    for Form in SortedForms do
    begin
      if Length(Form.Note.Tags) > 0 then
        ThisTag := Form.Note.Tags[0]
      else
        ThisTag := '';
        
      if ThisTag <> CurrentTag then
      begin
        CurrentTag := ThisTag;
        L := L + W + 50;
        T := 50;
        if L > Screen.WorkAreaRect.Right - W then
        begin
          L := 50;
          Inc(T, H + 50);
        end;
      end;
      
      Form.SetBounds(L, T, W, H);
      Form.Note.Left := L;
      Form.Note.Top := T;
      Form.Note.Width := W;
      Form.Note.Height := H;
      FApplication.NoteManager.PersistNote(Form.Note); // geometry only: no Touch (H5)
      
      Inc(L, 25);
      Inc(T, 25);
    end;
  finally
    SortedForms.Free;
  end;
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