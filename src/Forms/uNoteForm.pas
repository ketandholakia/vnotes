unit uNoteForm;

{
  TNoteForm — refactored to use the five custom components
  =========================================================
  This form is now a thin wiring layer.  All visual rendering and input
  handling for the header, colour picker, tag strip, checklist and scrollbar
  are delegated to the component classes in src/Components/.

  What lives here:
    - Construction / LoadNote / SaveNote
    - Business-logic handlers (save, autosave schedule, delete, duplicate …)
    - Wiring of component events to the editor context

  What was removed:
    - 7 TSpeedButton declarations + ApplyColor wiring for each
    - CreateTagChip / RefreshTagsFooter (→ TNoteTagStrip)
    - RefreshChecklistPanel / all checklist helpers (→ TNoteChecklistPanel)
    - pnlCustomScrollbar + pnlThumb + FTimerScroll (→ TNoteScrollBar)
    - Color sub-menu (→ TNoteColorPicker)
    - pnlMemoContainer + MemoContainerResize + the "Width+30" scrollbar hack
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Variants,
  System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Menus,
  uNote, uNoteEditorContext, uEnums,
  uNoteHeaderBar, uNoteColorPicker, uNoteTagStrip, uNoteChecklistPanel, uNoteScrollBar;

type
  TNoteForm = class(TForm)
    // Only non-component DFM controls remain
    edTitle:    TEdit;
    mmContent:  TMemo;
    pmNote:     TPopupMenu;
    miNewNote:  TMenuItem;
    miDuplicate: TMenuItem;
    N1:         TMenuItem;
    miAlwaysOnTop: TMenuItem;
    miLock:     TMenuItem;
    miCollapse: TMenuItem;
    N3:         TMenuItem;
    miDelete:   TMenuItem;
    miProperties: TMenuItem;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure edTitleChange(Sender: TObject);
    procedure mmContentChange(Sender: TObject);
    procedure mmContentKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
                             MousePos: TPoint; var Handled: Boolean);
    procedure pmNotePopup(Sender: TObject);
    procedure miNewNoteClick(Sender: TObject);
    procedure miDuplicateClick(Sender: TObject);
    procedure miAlwaysOnTopClick(Sender: TObject);
    procedure miLockClick(Sender: TObject);
    procedure miCollapseClick(Sender: TObject);
    procedure miDeleteClick(Sender: TObject);
    procedure miPropertiesClick(Sender: TObject);

  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  private
    // ── Data ──────────────────────────────────────────────────────────────
    FNote:         TNote;
    FEditorContext: INoteEditorContext;
    FCollapsedHeight: Integer;
    FIsClosing:    Boolean;
    FIsLoaded:     Boolean;
    FOnClosed:     TNotifyEvent;

    // ── Components ────────────────────────────────────────────────────────
    FHeaderBar:    TNoteHeaderBar;
    FColorPicker:  TNoteColorPicker;
    FTagStrip:     TNoteTagStrip;
    FChecklist:    TNoteChecklistPanel;
    FScrollBar:    TNoteScrollBar;
    FToolbarTimer: TTimer;

    // ── Construction helpers ───────────────────────────────────────────────
    procedure CreateComponents;
    procedure WireEvents;

    // ── Note load / save ──────────────────────────────────────────────────
    procedure LoadNote;
    procedure SaveNote;

    // ── Visual state ──────────────────────────────────────────────────────
    procedure ApplyColor;
    procedure UpdateUI;

    // ── Header button handler ─────────────────────────────────────────────
    procedure HeaderButtonClick(Sender: TObject; Button: TNoteHeaderButton);

    // ── Color picker handler ───────────────────────────────────────────────
    procedure ColorPickerSelected(Sender: TObject; Color: TNoteColor);

    // ── Tag strip handlers ────────────────────────────────────────────────
    procedure TagAdded(Sender: TObject; const Tag: string);
    procedure TagRemoved(Sender: TObject; const Tag: string; Index: Integer);

    // ── Checklist handlers ────────────────────────────────────────────────
    procedure ChecklistItemToggled(Sender: TObject; Index: Integer; Done: Boolean);
    procedure ChecklistItemTextChanged(Sender: TObject; Index: Integer; const Text: string);
    procedure ChecklistItemAdded(Sender: TObject; const Text: string);
    procedure ChecklistItemRemoved(Sender: TObject; Index: Integer);

    // ── Collapse / content mode ───────────────────────────────────────────
    procedure CollapseNote;
    procedure ExpandNote;
    procedure UpdateContentMode;

    // ── Autohide Toolbar ──────────────────────────────────────────────────
    procedure ToolbarTimerTick(Sender: TObject);

    // ── Win32 messages ────────────────────────────────────────────────────
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMGetMinMaxInfo(var Message: TWMGetMinMaxInfo); message WM_GETMINMAXINFO;
    procedure WMExitSizeMove(var Message: TMessage); message WM_EXITSIZEMOVE;

  public
    constructor CreateNote(AOwner: TComponent; ANote: TNote;
                           const AContext: INoteEditorContext);

    procedure CloseWithoutSaving;
    procedure Save;
    procedure ApplyFontSettings;

    // ── Test-helper accessors (kept for test compatibility) ───────────────
    function ChecklistRowCount: Integer;
    function ChecklistRowText(AIndex: Integer): string;
    function ChecklistRowDone(AIndex: Integer): Boolean;
    function IsChecklistPanelVisible: Boolean;

    property Note: TNote read FNote;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
  end;

var
  NoteForm: TNoteForm;

implementation

{$R *.dfm}

uses
  Winapi.ShellAPI, uWindowUtils, uColorUtils, uMonitorUtils;

const
  MIN_WIDTH        = 200;
  MIN_HEIGHT       = 150;
  COLLAPSED_HEIGHT = 40;

{ ── Construction ─────────────────────────────────────────────────────────── }

constructor TNoteForm.CreateNote(AOwner: TComponent; ANote: TNote;
                                 const AContext: INoteEditorContext);
begin
  inherited Create(AOwner);
  FNote             := ANote;
  FEditorContext    := AContext;
  FCollapsedHeight  := COLLAPSED_HEIGHT;
  FIsClosing        := False;
  FIsLoaded         := False;
end;

procedure TNoteForm.FormCreate(Sender: TObject);
begin
  TWindowUtils.EnableBorderlessWindow(Self);
  TWindowUtils.EnableRoundedCorners(Self);

  DoubleBuffered := True;
  KeyPreview     := True;

  // Suppress style-engine override on key controls so our custom colors
  // survive theme changes
  edTitle.StyleElements   := [];
  mmContent.StyleElements := [seBorder];

  // Title edit
  edTitle.Align         := alTop;
  edTitle.Height        := 28;
  edTitle.BorderStyle   := bsNone;
  edTitle.Font.Name     := 'Segoe UI';
  edTitle.Font.Size     := 11;
  edTitle.Font.Style    := [fsBold];
  edTitle.ParentFont    := False;

  // Content memo
  mmContent.Align       := alClient;
  mmContent.BorderStyle := bsNone;
  mmContent.ScrollBars  := ssNone;
  mmContent.WordWrap    := True;
  mmContent.Font.Name   := FEditorContext.GetFontName;
  mmContent.Font.Size   := FEditorContext.GetFontSize;

  CreateComponents;
  WireEvents;

  LoadNote;
  ApplyColor;
  UpdateUI;

  TEdgeHitTestHook.Install(Self);
end;

procedure TNoteForm.CreateComponents;
begin
  // ── Header bar ────────────────────────────────────────────────────────────
  FHeaderBar            := TNoteHeaderBar.CreateNote(Self, TWindowUtils.GetCaptionHeight);
  FHeaderBar.Parent     := Self;
  FHeaderBar.Align      := alTop;

  // ── Color picker (non-visual, owns its popup internally) ─────────────────
  FColorPicker          := TNoteColorPicker.CreatePicker(Self);

  // ── Tag strip ─────────────────────────────────────────────────────────────
  FTagStrip             := TNoteTagStrip.CreateStrip(Self);
  FTagStrip.Parent      := Self;
  FTagStrip.Align       := alBottom;
  FTagStrip.Height      := 28;
  FTagStrip.StyleElements := [];

  // ── Custom scrollbar (right side; attaches to mmContent after LoadNote) ──
  FScrollBar            := TNoteScrollBar.CreateScrollBar(Self);
  FScrollBar.Parent     := Self;
  FScrollBar.Align      := alRight;
  FScrollBar.Width      := 8;

  // ── Checklist panel (hidden by default) ───────────────────────────────────
  FChecklist            := TNoteChecklistPanel.CreatePanel(Self);
  FChecklist.Parent     := Self;
  FChecklist.Align      := alClient;
  FChecklist.Visible    := False;
  FChecklist.StyleElements := [];

  FToolbarTimer := TTimer.Create(Self);
  FToolbarTimer.Interval := 100;
  FToolbarTimer.OnTimer := ToolbarTimerTick;
end;

procedure TNoteForm.WireEvents;
begin
  FHeaderBar.OnButtonClick   := HeaderButtonClick;
  FColorPicker.OnColorSelected := ColorPickerSelected;
  FTagStrip.OnTagAdded       := TagAdded;
  FTagStrip.OnTagRemoved     := TagRemoved;
  FChecklist.OnItemToggled   := ChecklistItemToggled;
  FChecklist.OnItemTextChanged := ChecklistItemTextChanged;
  FChecklist.OnItemAdded     := ChecklistItemAdded;
  FChecklist.OnItemRemoved   := ChecklistItemRemoved;
end;

procedure TNoteForm.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opInsert) and not (csLoading in ComponentState) and
     (AComponent is TWinControl) and (AComponent <> Self) and
     not (csDestroying in ComponentState) then
    TEdgeHitTestHook.InstallControl(Self, TWinControl(AComponent));
end;

{ ── Load / Save ──────────────────────────────────────────────────────────── }

procedure TNoteForm.LoadNote;
begin
  edTitle.Text   := FNote.Title;
  mmContent.Text := FNote.Content;
  Left   := FNote.Left;
  Top    := FNote.Top;
  Width  := FNote.Width;
  Height := FNote.Height;
  mmContent.ReadOnly := FNote.Locked;
  edTitle.ReadOnly   := FNote.Locked;

  FTagStrip.SetTags(FNote.Tags);
  FTagStrip.Locked := FNote.Locked;
  FChecklist.SetItems(FNote.ChecklistItems);
  FChecklist.Locked := FNote.Locked;

  // Attach scrollbar after memo has its handle
  FScrollBar.Attach(mmContent);
end;

procedure TNoteForm.SaveNote;
begin
  if FNote.Locked then Exit;

  FNote.Title   := edTitle.Text;
  FNote.Content := mmContent.Text;
  FNote.Left    := Left;
  FNote.Top     := Top;

  if not FNote.Collapsed then
  begin
    FNote.Width  := Width;
    FNote.Height := Height;
  end
  else
  begin
    FNote.Width  := Width;
    FNote.Height := FCollapsedHeight;
  end;

  FEditorContext.SaveNote(FNote);
end;

{ ── Theming ──────────────────────────────────────────────────────────────── }

procedure TNoteForm.ApplyFontSettings;
begin
  if not Assigned(FEditorContext) then Exit;
  mmContent.Font.Name := FEditorContext.GetFontName;
  mmContent.Font.Size := FEditorContext.GetFontSize;
end;

procedure TNoteForm.ApplyColor;
var
  C, FrameColor, ContentColor, TitleColor, TextColor: TColor;
begin
  C            := FEditorContext.GetNoteColor(FNote.Color);
  FrameColor   := TColorUtils.AdjustBrightness(C, -15);
  TitleColor   := C;
  ContentColor := TColorUtils.AdjustBrightness(C, 15);
  TextColor    := FEditorContext.GetNoteTextColor(FNote.Color);

  // Form chrome
  Color := FrameColor;

  // Header bar
  FHeaderBar.BackColor := FrameColor;
  FHeaderBar.IconColor := TextColor;

  // Title edit
  edTitle.Color      := TitleColor;
  edTitle.Font.Color := TextColor;
  edTitle.ParentColor := False;

  // Content memo
  mmContent.Color      := ContentColor;
  mmContent.Font.Color := TextColor;

  // Tag strip
  FTagStrip.BackColor := FrameColor;
  FTagStrip.TextColor := TextColor;

  // Checklist panel
  FChecklist.BackColor  := ContentColor;
  FChecklist.TextColor  := TextColor;
  FChecklist.DoneColor  := TColorUtils.AdjustBrightness(TextColor, 60);
  FChecklist.CheckColor := TextColor;

  // Scrollbar
  FScrollBar.TrackColor := FrameColor;
  FScrollBar.ThumbColor := TColorUtils.AdjustBrightness(ContentColor, -30);

  // Color picker initial selection
  FColorPicker.SelectedColor := FNote.Color;

  Invalidate;
end;

procedure TNoteForm.UpdateUI;
begin
  // Header button states
  FHeaderBar.SetButtonEnabled(nhbPin,      not FNote.Locked);
  FHeaderBar.SetButtonEnabled(nhbCollapse, not FNote.Locked);
  FHeaderBar.SetButtonEnabled(nhbColor,    not FNote.Locked);
  FHeaderBar.SetButtonEnabled(nhbFavorite, not FNote.Locked);
  FHeaderBar.SetButtonEnabled(nhbChecklist, not FNote.Locked);

  FHeaderBar.SetButtonChecked(nhbPin,      FNote.AlwaysOnTop);
  FHeaderBar.SetButtonChecked(nhbCollapse, FNote.Collapsed);
  FHeaderBar.SetButtonChecked(nhbLock,     FNote.Locked);
  FHeaderBar.SetButtonChecked(nhbFavorite, FNote.Favorite);

  // Context menu state
  miAlwaysOnTop.Checked := FNote.AlwaysOnTop;
  miLock.Checked        := FNote.Locked;
  miCollapse.Checked    := FNote.Collapsed;
end;

{ ── Header button dispatcher ─────────────────────────────────────────────── }

procedure TNoteForm.HeaderButtonClick(Sender: TObject; Button: TNoteHeaderButton);
var
  Pt: TPoint;
begin
  case Button of
    nhbClose:
      Close;

    nhbColor:
    begin
      // Show color picker below the header bar
      Pt := ClientToScreen(Point(0, FHeaderBar.Height));
      FColorPicker.ShowAt(Pt.X, Pt.Y);
    end;

    nhbPin:
    begin
      if FNote.Locked then Exit;
      FNote.AlwaysOnTop := not FNote.AlwaysOnTop;
      if FNote.AlwaysOnTop then FormStyle := fsStayOnTop
      else                      FormStyle := fsNormal;
      SaveNote;
      UpdateUI;
    end;

    nhbFavorite:
    begin
      if FNote.Locked then Exit;
      FNote.ToggleFavorite;
      FHeaderBar.SetButtonChecked(nhbFavorite, FNote.Favorite);
      FEditorContext.ScheduleSave(FNote);
    end;

    nhbCollapse:
    begin
      if FNote.Locked then Exit;
      FNote.Collapsed := not FNote.Collapsed;
      if FNote.Collapsed then CollapseNote
      else                     ExpandNote;
      SaveNote;
      UpdateUI;
    end;

    nhbLock:
    begin
      FNote.Locked := not FNote.Locked;
      mmContent.ReadOnly := FNote.Locked;
      edTitle.ReadOnly   := FNote.Locked;
      FTagStrip.Locked   := FNote.Locked;
      FChecklist.Locked  := FNote.Locked;
      SaveNote;
      UpdateUI;
    end;

    nhbChecklist:
    begin
      if FNote.Locked then Exit;
      FChecklist.Visible := not FChecklist.Visible;
      UpdateContentMode;
    end;
  end;
end;

{ ── Color picker ─────────────────────────────────────────────────────────── }

procedure TNoteForm.ColorPickerSelected(Sender: TObject; Color: TNoteColor);
begin
  if FNote.Locked then Exit;
  FNote.Color := Color;
  ApplyColor;
  SaveNote;
  UpdateUI;
end;

{ ── Tag strip ────────────────────────────────────────────────────────────── }

procedure TNoteForm.TagAdded(Sender: TObject; const Tag: string);
begin
  if FNote.Locked then Exit;
  if FNote.AddTag(Tag) then
    FEditorContext.ScheduleSave(FNote)
  else
    // Tag already existed; refresh strip to reflect current state
    FTagStrip.SetTags(FNote.Tags);
end;

procedure TNoteForm.TagRemoved(Sender: TObject; const Tag: string; Index: Integer);
begin
  if FNote.Locked then Exit;
  if FNote.RemoveTag(Tag) then
    FEditorContext.ScheduleSave(FNote);
end;

{ ── Checklist ────────────────────────────────────────────────────────────── }

procedure TNoteForm.ChecklistItemToggled(Sender: TObject; Index: Integer; Done: Boolean);
begin
  if FNote.Locked then Exit;
  FNote.ToggleChecklistItem(Index);
  // Sync component state (note model is authoritative)
  FChecklist.SetItems(FNote.ChecklistItems);
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.ChecklistItemTextChanged(Sender: TObject; Index: Integer; const Text: string);
begin
  if FNote.Locked then Exit;
  FNote.SetChecklistItemText(Index, Text);
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.ChecklistItemAdded(Sender: TObject; const Text: string);
begin
  if FNote.Locked then Exit;
  FNote.AddChecklistItem(Text);
  FChecklist.SetItems(FNote.ChecklistItems);
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.ChecklistItemRemoved(Sender: TObject; Index: Integer);
begin
  if FNote.Locked then Exit;
  FNote.RemoveChecklistItem(Index);
  FChecklist.SetItems(FNote.ChecklistItems);
  FEditorContext.ScheduleSave(FNote);
end;

{ ── Collapse / expand ────────────────────────────────────────────────────── }

procedure TNoteForm.CollapseNote;
begin
  Height          := FCollapsedHeight;
  mmContent.Visible := False;
  FChecklist.Visible := False;
  edTitle.Visible  := False;
  FTagStrip.Visible := False;
end;

procedure TNoteForm.ExpandNote;
begin
  Height           := FNote.Height;
  mmContent.Visible := True;
  edTitle.Visible   := True;
  FTagStrip.Visible := True;
  UpdateContentMode;
end;

procedure TNoteForm.UpdateContentMode;
begin
  if FChecklist.Visible and (FNote.ChecklistTotalCount > 0) then
  begin
    mmContent.Visible  := False;
    FChecklist.Visible := True;
  end
  else
  begin
    mmContent.Visible  := True;
    FChecklist.Visible := False;
  end;
end;

{ ── Autohide Toolbar ─────────────────────────────────────────────────────── }

procedure TNoteForm.ToolbarTimerTick(Sender: TObject);
var
  P: TPoint;
begin
  if not FIsLoaded or FIsClosing then Exit;
  
  if (FEditorContext = nil) or not FEditorContext.GetAutoHideToolbar or FNote.Locked then
  begin
    if not FHeaderBar.Visible then
      FHeaderBar.Visible := True;
    Exit;
  end;

  // The popup color picker or context menu might be active; keep toolbar visible
  if (FColorPicker <> nil) and FColorPicker.IsPopupVisible then
  begin
    if not FHeaderBar.Visible then
      FHeaderBar.Visible := True;
    Exit;
  end;

  P := ScreenToClient(Mouse.CursorPos);
  
  // Hover zone: Top 60 pixels of the form, extending slightly above the window
  if (P.X >= 0) and (P.X < ClientWidth) and (P.Y >= -10) and (P.Y < 60) then
  begin
    if not FHeaderBar.Visible then
      FHeaderBar.Visible := True;
  end
  else
  begin
    if FHeaderBar.Visible then
      FHeaderBar.Visible := False;
  end;
end;

{ ── Form events ──────────────────────────────────────────────────────────── }

procedure TNoteForm.FormShow(Sender: TObject);
var
  Desired, Clamped: TRect;
begin
  Desired := Rect(FNote.Left, FNote.Top,
                  FNote.Left + FNote.Width, FNote.Top + FNote.Height);
  if TMonitorUtils.EnsureNoteRectVisible(Desired, Clamped) then
    SetBounds(FNote.Left, FNote.Top, FNote.Width, FNote.Height)
  else
  begin
    FNote.Left := Clamped.Left;
    FNote.Top  := Clamped.Top;
    SetBounds(Clamped.Left, Clamped.Top, FNote.Width, FNote.Height);
    FEditorContext.SaveNote(FNote);
  end;

  if FNote.AlwaysOnTop then
    FormStyle := fsStayOnTop;

  if FNote.Collapsed then
    CollapseNote;

  UpdateUI;
  FIsLoaded := True;
end;

procedure TNoteForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FIsClosing := True;
  SaveNote;
  FEditorContext.CancelSave(FNote.ID);
  if Assigned(FOnClosed) then
    FOnClosed(Self);
  Action := caFree;
end;

procedure TNoteForm.FormDestroy(Sender: TObject);
begin
  if not FIsClosing then
    SaveNote;
end;

procedure TNoteForm.FormResize(Sender: TObject);
begin
  if not FIsLoaded then Exit;
  if not FNote.Collapsed then
  begin
    FNote.Width  := Width;
    FNote.Height := Height;
  end;
  FNote.Left := Left;
  FNote.Top  := Top;
end;

procedure TNoteForm.edTitleChange(Sender: TObject);
begin
  if FNote.Locked then Exit;
  FNote.Title := edTitle.Text;
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.mmContentChange(Sender: TObject);
begin
  if not FNote.Locked then
    FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.mmContentKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (ssCtrl in Shift) then
    Close;
end;

procedure TNoteForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F4) and (ssAlt in Shift) then
    Close
  else if (ssCtrl in Shift) and not (ssAlt in Shift) and not (ssShift in Shift) then
  begin
    case Key of
      Ord('F'): begin HeaderButtonClick(nil, nhbFavorite);  Key := 0; end;
      Ord('P'): begin HeaderButtonClick(nil, nhbPin);       Key := 0; end;
      Ord('M'): begin HeaderButtonClick(nil, nhbCollapse);  Key := 0; end;
      Ord('L'): begin HeaderButtonClick(nil, nhbLock);      Key := 0; end;
      Ord('K'): begin HeaderButtonClick(nil, nhbChecklist); Key := 0; end;
      Ord('D'): begin miDeleteClick(nil);                   Key := 0; end;
    end;
  end;
end;

procedure TNoteForm.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
                                    MousePos: TPoint; var Handled: Boolean);
begin
  if ssCtrl in Shift then
  begin
    mmContent.Font.Size := Max(8, Min(24, mmContent.Font.Size + WheelDelta div 120));
    Handled := True;
  end;
end;

{ ── Context-menu handlers ────────────────────────────────────────────────── }

procedure TNoteForm.pmNotePopup(Sender: TObject);
begin
  miDuplicate.Enabled    := not FNote.Locked;
  miDelete.Enabled       := not FNote.Locked;
  miProperties.Enabled   := True;
  miAlwaysOnTop.Enabled  := not FNote.Locked;
  miLock.Enabled         := True;
  miCollapse.Enabled     := not FNote.Locked;
  miNewNote.Enabled      := True;
end;

procedure TNoteForm.miNewNoteClick(Sender: TObject);
begin
  FEditorContext.CreateNote('', '', ncYellow);
end;

procedure TNoteForm.miDuplicateClick(Sender: TObject);
begin
  if FNote.Locked then Exit;
  FEditorContext.CreateNote(FNote.Title + ' (copy)', FNote.Content, FNote.Color,
    FNote.Left + 30, FNote.Top + 30, FNote.Width, FNote.Height, FNote.AlwaysOnTop);
end;

procedure TNoteForm.miAlwaysOnTopClick(Sender: TObject);
begin
  HeaderButtonClick(nil, nhbPin);
end;

procedure TNoteForm.miLockClick(Sender: TObject);
begin
  HeaderButtonClick(nil, nhbLock);
end;

procedure TNoteForm.miCollapseClick(Sender: TObject);
begin
  HeaderButtonClick(nil, nhbCollapse);
end;

procedure TNoteForm.miDeleteClick(Sender: TObject);
begin
  if FNote.Locked then Exit;
  if (not FEditorContext.GetConfirmDelete) or
     (MessageDlg('Delete this note?', mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
  begin
    FEditorContext.DeleteNote(FNote.ID);
    Close;
  end;
end;

procedure TNoteForm.miPropertiesClick(Sender: TObject);
begin
  ShowMessage(Format('Note ID: %d'#13#10'Created: %s'#13#10'Modified: %s',
    [FNote.ID, DateTimeToStr(FNote.CreatedAt), DateTimeToStr(FNote.UpdatedAt)]));
end;

{ ── Public API ───────────────────────────────────────────────────────────── }

procedure TNoteForm.CloseWithoutSaving;
begin
  FIsClosing := True;
  Close;
end;

procedure TNoteForm.Save;
begin
  SaveNote;
end;

{ ── Test-helper accessors ────────────────────────────────────────────────── }

function TNoteForm.ChecklistRowCount: Integer;
begin
  Result := Length(FNote.ChecklistItems);
end;

function TNoteForm.ChecklistRowText(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FNote.ChecklistItems)) then
    Result := FNote.ChecklistItems[AIndex].Text
  else
    Result := '';
end;

function TNoteForm.ChecklistRowDone(AIndex: Integer): Boolean;
begin
  if (AIndex >= 0) and (AIndex < Length(FNote.ChecklistItems)) then
    Result := FNote.ChecklistItems[AIndex].Done
  else
    Result := False;
end;

function TNoteForm.IsChecklistPanelVisible: Boolean;
begin
  Result := FChecklist.Visible;
end;

{ ── Win32 ────────────────────────────────────────────────────────────────── }

procedure TNoteForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or WS_THICKFRAME;
end;

procedure TNoteForm.WMNCHitTest(var Message: TWMNCHitTest);
begin
  TWindowUtils.HandleNCHitTest(Self, Message);
end;

procedure TNoteForm.WMGetMinMaxInfo(var Message: TWMGetMinMaxInfo);
begin
  inherited;
  Message.MinMaxInfo.ptMinTrackSize.X := MIN_WIDTH;
  Message.MinMaxInfo.ptMinTrackSize.Y := MIN_HEIGHT;
end;

procedure TNoteForm.WMExitSizeMove(var Message: TMessage);
begin
  inherited;
  if not FNote.Collapsed then
  begin
    FNote.Width  := Width;
    FNote.Height := Height;
  end;
  FNote.Left := Left;
  FNote.Top  := Top;
  FEditorContext.ScheduleSave(FNote);
end;

end.