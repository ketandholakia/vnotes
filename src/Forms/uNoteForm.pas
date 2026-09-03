unit uNoteForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Variants,
  System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Menus, Vcl.ComCtrls,
  uNote, uNoteEditorContext, uEnums;

type
  TNoteForm = class(TForm)
    pnlHeader: TPanel;
    btnClose: TButton;
    btnColor: TButton;
    btnPin: TButton;
    btnCollapse: TButton;
    btnLock: TButton;
    mmContent: TMemo;
    pmNote: TPopupMenu;
    miNewNote: TMenuItem;
    miDuplicate: TMenuItem;
    N1: TMenuItem;
    miColor: TMenuItem;
    miYellow: TMenuItem;
    miGreen: TMenuItem;
    miBlue: TMenuItem;
    miPink: TMenuItem;
    miPurple: TMenuItem;
    miOrange: TMenuItem;
    miWhite: TMenuItem;
    miGray: TMenuItem;
    N2: TMenuItem;
    miAlwaysOnTop: TMenuItem;
    miLock: TMenuItem;
    miCollapse: TMenuItem;
    N3: TMenuItem;
    miDelete: TMenuItem;
    miProperties: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure btnColorClick(Sender: TObject);
    procedure btnPinClick(Sender: TObject);
    procedure btnCollapseClick(Sender: TObject);
    procedure btnLockClick(Sender: TObject);
    procedure mmContentChange(Sender: TObject);
    procedure mmContentKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pmNotePopup(Sender: TObject);
    procedure ColorMenuItemClick(Sender: TObject);
    procedure miAlwaysOnTopClick(Sender: TObject);
    procedure miLockClick(Sender: TObject);
    procedure miCollapseClick(Sender: TObject);
    procedure miDeleteClick(Sender: TObject);
    procedure miDuplicateClick(Sender: TObject);
    procedure miPropertiesClick(Sender: TObject);
    procedure miNewNoteClick(Sender: TObject);
    procedure pnlHeaderMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pnlHeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pnlHeaderMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
  private
    FNote: TNote;
    FEditorContext: INoteEditorContext;
    FDragMode: Boolean;
    FDragOffset: TPoint;
    FCollapsedHeight: Integer;
    FIsClosing: Boolean;
    FOnClosed: TNotifyEvent;
    procedure LoadNote;
    procedure SaveNote;
    procedure ApplyColor;
    procedure UpdateUI;
    procedure ApplyTheme;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMGetMinMaxInfo(var Message: TWMGetMinMaxInfo); message WM_GETMINMAXINFO;
  public
    constructor CreateNote(AOwner: TComponent; ANote: TNote; const AContext: INoteEditorContext);
    // Lets an owning form (e.g. TTrayForm) close this note window without
    // triggering a re-save of a note that's already been deleted/is being
    // torn down in bulk, without reaching into the private FIsClosing field.
    procedure CloseWithoutSaving;
    procedure Save;  // Public wrapper for SaveNote
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
  MIN_WIDTH = 200;
  MIN_HEIGHT = 150;
  COLLAPSED_HEIGHT = 40;

{ TNoteForm }

constructor TNoteForm.CreateNote(AOwner: TComponent; ANote: TNote; const AContext: INoteEditorContext);
begin
  inherited Create(AOwner);
  FNote := ANote;
  FEditorContext := AContext;
  FCollapsedHeight := COLLAPSED_HEIGHT;
  FIsClosing := False;
end;

procedure TNoteForm.FormCreate(Sender: TObject);
begin
  TWindowUtils.EnableBorderlessWindow(Self);
  DoubleBuffered := True;
  
  // Header panel setup
  pnlHeader.Height := TWindowUtils.GetCaptionHeight;
  pnlHeader.Align := alTop;
  pnlHeader.BevelOuter := bvNone;
  pnlHeader.ParentBackground := False;
  
  // Buttons
  btnClose.Width := 28;
  btnClose.Height := 28;
  btnClose.Caption := '×';
  btnClose.Font.Size := 16;
  
  btnColor.Width := 28;
  btnColor.Height := 28;
  btnColor.Caption := '🎨';
  
  btnPin.Width := 28;
  btnPin.Height := 28;
  btnPin.Caption := '📌';
  
  btnCollapse.Width := 28;
  btnCollapse.Height := 28;
  btnCollapse.Caption := '□';
  
  btnLock.Width := 28;
  btnLock.Height := 28;
  btnLock.Caption := '🔓';
  
  // Content memo
  mmContent.Align := alClient;
  mmContent.BorderStyle := bsNone;
  mmContent.ScrollBars := ssVertical;
  mmContent.WordWrap := True;
  mmContent.Font.Name := 'Segoe UI';
  mmContent.Font.Size := 10;
  
  // Popup menu
  miYellow.Tag := Ord(ncYellow);
  miGreen.Tag := Ord(ncGreen);
  miBlue.Tag := Ord(ncBlue);
  miPink.Tag := Ord(ncPink);
  miPurple.Tag := Ord(ncPurple);
  miOrange.Tag := Ord(ncOrange);
  miWhite.Tag := Ord(ncWhite);
  miGray.Tag := Ord(ncGray);
  
  LoadNote;
  ApplyTheme;
end;

procedure TNoteForm.CloseWithoutSaving;
begin
  FIsClosing := True;
  Close;
end;

procedure TNoteForm.Save;
begin
  SaveNote;
end;

procedure TNoteForm.FormDestroy(Sender: TObject);
begin
  if not FIsClosing then
    SaveNote;
end;

procedure TNoteForm.FormShow(Sender: TObject);
var
  Desired: TRect;
  Clamped: TRect;
begin
  // Phase 4C: if the note's persisted position lies completely outside
  // every connected monitor's work area (e.g. monitor was disconnected,
  // resolution changed, or the note was saved on a now-removed display),
  // move it into the nearest monitor. Positions that are still visible
  // are left alone. The clamp preserves size and only nudges origin.
  Desired := Rect(FNote.Left, FNote.Top,
                  FNote.Left + FNote.Width, FNote.Top + FNote.Height);
  if TMonitorUtils.EnsureNoteRectVisible(Desired, Clamped) then
    SetBounds(FNote.Left, FNote.Top, FNote.Width, FNote.Height)
  else
  begin
    // Clamped position was changed; persist the new coordinates so the
    // note does not "drift back" to the inaccessible spot on the next
    // launch. (Phase 4E: the persist comment is now true - the corrected
    // coordinates are written through the editor context immediately.
    // Locked notes are included: position repair must work even when
    // content editing is locked. Only fires when clamping occurred.)
    FNote.Left := Clamped.Left;
    FNote.Top := Clamped.Top;
    SetBounds(Clamped.Left, Clamped.Top, FNote.Width, FNote.Height);
    FEditorContext.SaveNote(FNote);
  end;
  if FNote.AlwaysOnTop then
    FormStyle := fsStayOnTop;
  if FNote.Collapsed then
  begin
    Height := FCollapsedHeight;
    mmContent.Visible := False;
    btnCollapse.Caption := '▣';
  end;
  UpdateUI;
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

procedure TNoteForm.FormResize(Sender: TObject);
begin
  if not FNote.Collapsed then
  begin
    FNote.Width := Width;
    FNote.Height := Height;
  end;
  FNote.Left := Left;
  FNote.Top := Top;
end;

procedure TNoteForm.LoadNote;
begin
  Caption := FNote.Title;
  mmContent.Text := FNote.Content;
  Left := FNote.Left;
  Top := FNote.Top;
  Width := FNote.Width;
  Height := FNote.Height;
  ApplyColor;
  UpdateUI;
end;

procedure TNoteForm.SaveNote;
begin
  if FNote.Locked then Exit;
  
  FNote.Title := Caption;
  FNote.Content := mmContent.Text;
  FNote.Left := Left;
  FNote.Top := Top;
  if not FNote.Collapsed then
  begin
    FNote.Width := Width;
    FNote.Height := Height;
  end
  else
  begin
    FNote.Width := Width;
    FNote.Height := FCollapsedHeight;
  end;
  
  FEditorContext.SaveNote(FNote);
end;

procedure TNoteForm.ApplyColor;
var
  C: TColor;
begin
  C := FEditorContext.GetNoteColor(FNote.Color);
  Color := C;
  pnlHeader.Color := TColorUtils.DarkenColor(C, 20);
  mmContent.Color := C;
  mmContent.Font.Color := FEditorContext.GetNoteTextColor(FNote.Color);
  
  btnClose.Font.Color := mmContent.Font.Color;
  btnColor.Font.Color := mmContent.Font.Color;
  btnPin.Font.Color := mmContent.Font.Color;
  btnCollapse.Font.Color := mmContent.Font.Color;
  btnLock.Font.Color := mmContent.Font.Color;
end;

procedure TNoteForm.UpdateUI;
begin
  btnPin.Enabled := not FNote.Locked;
  btnCollapse.Enabled := not FNote.Locked;
  btnLock.Enabled := True;
  btnColor.Enabled := not FNote.Locked;
  
  miAlwaysOnTop.Checked := FNote.AlwaysOnTop;
  miLock.Checked := FNote.Locked;
  miCollapse.Checked := FNote.Collapsed;
  
  // Update color menu checks
  miYellow.Checked := FNote.Color = ncYellow;
  miGreen.Checked := FNote.Color = ncGreen;
  miBlue.Checked := FNote.Color = ncBlue;
  miPink.Checked := FNote.Color = ncPink;
  miPurple.Checked := FNote.Color = ncPurple;
  miOrange.Checked := FNote.Color = ncOrange;
  miWhite.Checked := FNote.Color = ncWhite;
  miGray.Checked := FNote.Color = ncGray;
  
  if FNote.Locked then
    btnLock.Caption := '🔒'
  else
    btnLock.Caption := '🔓';
    
  if FNote.Collapsed then
    btnCollapse.Caption := '▣'
  else
    btnCollapse.Caption := '□';
end;

procedure TNoteForm.ApplyTheme;
begin
  ApplyColor;
  UpdateUI;
end;

procedure TNoteForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TNoteForm.btnColorClick(Sender: TObject);
begin
  pmNote.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
end;

procedure TNoteForm.btnPinClick(Sender: TObject);
begin
  FNote.AlwaysOnTop := not FNote.AlwaysOnTop;
  if FNote.AlwaysOnTop then
    FormStyle := fsStayOnTop
  else
    FormStyle := fsNormal;
  SaveNote;
  UpdateUI;
end;

procedure TNoteForm.btnCollapseClick(Sender: TObject);
begin
  if FNote.Locked then Exit;
  
  FNote.Collapsed := not FNote.Collapsed;
  if FNote.Collapsed then
  begin
    Height := FCollapsedHeight;
    mmContent.Visible := False;
    btnCollapse.Caption := '▣';
  end
  else
  begin
    Height := FNote.Height;
    mmContent.Visible := True;
    btnCollapse.Caption := '□';
  end;
  SaveNote;
  UpdateUI;
end;

procedure TNoteForm.btnLockClick(Sender: TObject);
begin
  FNote.Locked := not FNote.Locked;
  mmContent.ReadOnly := FNote.Locked;
  SaveNote;
  UpdateUI;
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

procedure TNoteForm.pmNotePopup(Sender: TObject);
begin
  miDuplicate.Enabled := not FNote.Locked;
  miDelete.Enabled := not FNote.Locked;
  miProperties.Enabled := True;
  miColor.Enabled := not FNote.Locked;
  miAlwaysOnTop.Enabled := not FNote.Locked;
  miLock.Enabled := True;
  miCollapse.Enabled := not FNote.Locked;
  miNewNote.Enabled := True;
end;

procedure TNoteForm.ColorMenuItemClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  if FNote.Locked then Exit;
  
  Item := Sender as TMenuItem;
  FNote.Color := TNoteColor(Item.Tag);
  ApplyColor;
  SaveNote;
  UpdateUI;
end;

procedure TNoteForm.miAlwaysOnTopClick(Sender: TObject);
begin
  btnPinClick(Sender);
end;

procedure TNoteForm.miLockClick(Sender: TObject);
begin
  btnLockClick(Sender);
end;

procedure TNoteForm.miCollapseClick(Sender: TObject);
begin
  btnCollapseClick(Sender);
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

procedure TNoteForm.miDuplicateClick(Sender: TObject);
var
  NewNote: TNote;
begin
  if FNote.Locked then Exit;
  
  NewNote := FEditorContext.CreateNote(FNote.Title + ' (copy)', FNote.Content, FNote.Color);
  NewNote.Left := FNote.Left + 30;
  NewNote.Top := FNote.Top + 30;
  FEditorContext.SaveNote(NewNote);
end;

procedure TNoteForm.miPropertiesClick(Sender: TObject);
begin
  // Show properties dialog
  ShowMessage(Format('Note ID: %d'#13#10'Created: %s'#13#10'Modified: %s',
    [FNote.ID, DateTimeToStr(FNote.CreatedAt), DateTimeToStr(FNote.UpdatedAt)]));
end;

procedure TNoteForm.miNewNoteClick(Sender: TObject);
begin
  FEditorContext.CreateNote('', '', ncYellow);
end;

procedure TNoteForm.pnlHeaderMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (Y < TWindowUtils.GetCaptionHeight) and not FNote.Locked then
  begin
    FDragMode := True;
    FDragOffset := Point(X, Y);
  end;
end;

procedure TNoteForm.pnlHeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if FDragMode and (ssLeft in Shift) and not FNote.Locked then
  begin
    Left := Left + (X - FDragOffset.X);
    Top := Top + (Y - FDragOffset.Y);
    FNote.Left := Left;
    FNote.Top := Top;
    FEditorContext.ScheduleSave(FNote);
  end;
end;

procedure TNoteForm.pnlHeaderMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDragMode := False;
end;

procedure TNoteForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F4) and (ssAlt in Shift) then
    Close;
end;

procedure TNoteForm.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if ssCtrl in Shift then
  begin
    // Ctrl+Wheel to change font size
    mmContent.Font.Size := Max(8, Min(24, mmContent.Font.Size + WheelDelta div 120));
    Handled := True;
  end;
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

end.