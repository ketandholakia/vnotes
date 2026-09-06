unit uNoteForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Variants,
  System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Menus, Vcl.ComCtrls, Vcl.Buttons,
  uNote, uNoteEditorContext, uEnums;

type
  TNoteForm = class(TForm)
    pnlHeader: TPanel;
    btnClose: TSpeedButton;
    btnColor: TSpeedButton;
    btnPin: TSpeedButton;
    btnFavorite: TSpeedButton;
    btnCollapse: TSpeedButton;
    btnLock: TSpeedButton;
    btnChecklist: TSpeedButton;
    edTitle: TEdit;
    mmContent: TMemo;
    pnlChecklist: TPanel;
    pnlChecklistItems: TPanel;
    pnlAddChecklist: TPanel;
    edAddChecklist: TEdit;
    pnlTagsFooter: TPanel;
    flwTags: TFlowPanel;
    edNewTag: TEdit;
    
    pnlMemoContainer: TPanel;
    pnlCustomScrollbar: TPanel;
    pnlThumb: TPanel;
    FTimerScroll: TTimer;
    btnAddTag: TButton;
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
    procedure btnFavoriteClick(Sender: TObject);
    procedure btnCollapseClick(Sender: TObject);
    procedure btnLockClick(Sender: TObject);
    procedure btnChecklistClick(Sender: TObject);
    procedure mmContentChange(Sender: TObject);
    procedure mmContentKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure edTitleChange(Sender: TObject);
    procedure btnAddTagClick(Sender: TObject);
    procedure edNewTagKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnAddChecklistClick(Sender: TObject);
    procedure edAddChecklistKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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
  protected
    // 6E.2 resize fix: see CreateParams comment.
    procedure CreateParams(var Params: TCreateParams); override;
    // 6E.2 resize fix: hook dynamically created windowed children (checklist
    // items, tag chips...) into the edge hit-test passthrough as they appear.
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  private
    FNote: TNote;
    FEditorContext: INoteEditorContext;
    FCollapsedHeight: Integer;
    FIsClosing: Boolean;
    FOnClosed: TNotifyEvent;
    FForcingChecklistMode: Boolean;
    FIsLoaded: Boolean;
    procedure LoadNote;
    procedure SaveNote;
    procedure ApplyColor;
    procedure UpdateUI;
    procedure UpdateFavoriteButton;
    procedure ApplyTheme;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMGetMinMaxInfo(var Message: TWMGetMinMaxInfo); message WM_GETMINMAXINFO;
    procedure WMExitSizeMove(var Message: TMessage); message WM_EXITSIZEMOVE;
    // Phase 6A Part 2: tag chip strip + checklist panel.
    procedure RefreshTagsFooter;
    procedure RefreshChecklistPanel;
    procedure UpdateContentMode;
    procedure ToggleChecklistMode;
    procedure HandleAddTagInput;
    procedure HandleAddChecklistInput;
    procedure ChecklistItemToggle(Sender: TObject);
    procedure ChecklistItemTextChange(Sender: TObject);
    procedure CreateTagChip(const ATag: string; AIndex: Integer);
    procedure RemoveTagChip(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MemoContainerResize(Sender: TObject);
    procedure OnScrollTimer(Sender: TObject);
  public
    constructor CreateNote(AOwner: TComponent; ANote: TNote; const AContext: INoteEditorContext);
    procedure CloseWithoutSaving;
    procedure Save;
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
  FForcingChecklistMode := False;
  FIsLoaded := False;
end;

procedure TNoteForm.FormCreate(Sender: TObject);
begin
  TWindowUtils.EnableBorderlessWindow(Self);
  TWindowUtils.EnableRoundedCorners(Self);
  edTitle.StyleElements := [];
  pnlTagsFooter.StyleElements := [];
  edNewTag.StyleElements := [];
  pnlChecklist.StyleElements := [];
  pnlAddChecklist.StyleElements := [];
  edAddChecklist.StyleElements := [];
  mmContent.StyleElements := [seBorder];
  flwTags.StyleElements := [];
  
  pnlTagsFooter.ParentBackground := False;
  pnlHeader.ParentBackground := False;
  pnlChecklist.ParentBackground := False;
  flwTags.ParentBackground := False;
  
  pnlMemoContainer := TPanel.Create(Self);
  pnlMemoContainer.Parent := Self;
  pnlMemoContainer.Align := alClient;
  pnlMemoContainer.BevelOuter := bvNone;
  pnlMemoContainer.ParentBackground := False;
  pnlMemoContainer.StyleElements := [];
  pnlMemoContainer.OnResize := MemoContainerResize;
  
  mmContent.Align := alNone;
  mmContent.Parent := pnlMemoContainer;
  mmContent.Anchors := [akLeft, akTop, akBottom];
  
  pnlCustomScrollbar := TPanel.Create(Self);
  pnlCustomScrollbar.Parent := Self;
  pnlCustomScrollbar.Align := alRight;
  pnlCustomScrollbar.Width := 8;
  pnlCustomScrollbar.BevelOuter := bvNone;
  pnlCustomScrollbar.ParentBackground := False;
  pnlCustomScrollbar.StyleElements := [];
  
  pnlThumb := TPanel.Create(Self);
  pnlThumb.Parent := pnlCustomScrollbar;
  pnlThumb.Width := 8;
  pnlThumb.Left := 0;
  pnlThumb.BevelOuter := bvNone;
  pnlThumb.ParentBackground := False;
  pnlThumb.StyleElements := [];
  
  FTimerScroll := TTimer.Create(Self);
  FTimerScroll.Interval := 30;
  FTimerScroll.OnTimer := OnScrollTimer;
  DoubleBuffered := True;
  KeyPreview := True;

  pnlHeader.Height := TWindowUtils.GetCaptionHeight;
  pnlHeader.Align := alTop;
  pnlHeader.BevelOuter := bvNone;
  pnlHeader.ParentBackground := False;

  btnClose.Width := 28;
  btnClose.Height := 28;
  btnClose.Caption := #$E8BB;
  btnClose.Font.Size := 12;
  btnClose.Font.Name := 'Segoe MDL2 Assets';

  btnColor.Width := 28;
  btnColor.Height := 28;
  btnColor.Caption := #$E2B1;
  btnColor.Font.Size := 12;
  btnColor.Font.Name := 'Segoe MDL2 Assets';

  btnPin.Width := 28;
  btnPin.Height := 28;
  btnPin.Caption := #$E718;
  btnPin.Font.Size := 12;
  btnPin.Font.Name := 'Segoe MDL2 Assets';

  btnCollapse.Width := 28;
  btnCollapse.Height := 28;
  btnCollapse.Caption := #$E738;
  btnCollapse.Font.Size := 12;
  btnCollapse.Font.Name := 'Segoe MDL2 Assets';

  btnLock.Width := 28;
  btnLock.Height := 28;
  btnLock.Caption := #$E785;
  btnLock.Font.Size := 12;
  btnLock.Font.Name := 'Segoe MDL2 Assets';

  btnChecklist.Width := 28;
  btnChecklist.Height := 28;
  btnChecklist.Caption := #$E73E;
  btnChecklist.Font.Size := 12;
  btnChecklist.Font.Name := 'Segoe MDL2 Assets';
  btnChecklist.Hint := 'Checklist';
  btnChecklist.ShowHint := True;
  
  btnFavorite.Width := 28;
  btnFavorite.Height := 28;
  btnFavorite.Caption := #$E113;
  btnFavorite.Font.Size := 12;
  btnFavorite.Font.Name := 'Segoe MDL2 Assets';

  edTitle.Align := alTop;
  edTitle.Height := 28;
  edTitle.BorderStyle := bsNone;
  edTitle.Font.Name := 'Segoe UI';
  edTitle.Font.Size := 11;
  edTitle.Font.Style := [fsBold];
  edTitle.ParentFont := False;

  mmContent.Align := alClient;
  mmContent.BorderStyle := bsNone;
  mmContent.ScrollBars := ssVertical;
  mmContent.WordWrap := True;
  mmContent.Font.Name := 'Segoe UI';
  mmContent.Font.Size := 10;

  miYellow.Tag := Ord(ncYellow);
  miGreen.Tag := Ord(ncGreen);
  miBlue.Tag := Ord(ncBlue);
  miPink.Tag := Ord(ncPink);
  miPurple.Tag := Ord(ncPurple);
  miOrange.Tag := Ord(ncOrange);
  miWhite.Tag := Ord(ncWhite);
  miGray.Tag := Ord(ncGray);

  pnlChecklist.Visible := False;

  LoadNote;
  ApplyTheme;

  TEdgeHitTestHook.Install(Self);
end;

procedure TNoteForm.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opInsert) and not (csLoading in ComponentState) and
     (AComponent is TWinControl) and (AComponent <> Self) and not (csDestroying in ComponentState) then
    TEdgeHitTestHook.InstallControl(Self, TWinControl(AComponent));
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
  Desired := Rect(FNote.Left, FNote.Top,
                  FNote.Left + FNote.Width, FNote.Top + FNote.Height);
  if TMonitorUtils.EnsureNoteRectVisible(Desired, Clamped) then
    SetBounds(FNote.Left, FNote.Top, FNote.Width, FNote.Height)
  else
  begin
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

procedure TNoteForm.FormResize(Sender: TObject);
begin
  if not FIsLoaded then Exit;
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
  edTitle.Text := FNote.Title;
  mmContent.Text := FNote.Content;
  Left := FNote.Left;
  Top := FNote.Top;
  Width := FNote.Width;
  Height := FNote.Height;
  ApplyColor;
  mmContent.ReadOnly := FNote.Locked;
  edTitle.ReadOnly := FNote.Locked;
  UpdateUI;

  RefreshTagsFooter;
  RefreshChecklistPanel;
end;

procedure TNoteForm.SaveNote;
begin
  if FNote.Locked then Exit;

  FNote.Title := edTitle.Text;
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
  C, FrameColor, ContentColor, TitleColor: TColor;
begin
  C := FEditorContext.GetNoteColor(FNote.Color);
  
  FrameColor := TColorUtils.AdjustBrightness(C, -15);
  TitleColor := C;
  ContentColor := TColorUtils.AdjustBrightness(C, 15);

  Color := FrameColor;
  
  pnlHeader.Color := FrameColor;
  pnlTagsFooter.Color := FrameColor;
  flwTags.Color := FrameColor;
  pnlCustomScrollbar.Color := FrameColor;
  pnlThumb.Color := TColorUtils.AdjustBrightness(ContentColor, -30);
  pnlMemoContainer.Color := ContentColor;
  
  mmContent.Color := ContentColor;
  mmContent.Font.Color := FEditorContext.GetNoteTextColor(FNote.Color);
  
  edTitle.Color := TitleColor;
  edTitle.Font.Color := mmContent.Font.Color;

  pnlChecklist.Color := ContentColor;
  pnlChecklistItems.Color := ContentColor;
  pnlAddChecklist.Color := ContentColor;
  edAddChecklist.Color := ContentColor;
  edAddChecklist.Font.Color := mmContent.Font.Color;

  edNewTag.Color := TitleColor;
  edNewTag.Font.Color := mmContent.Font.Color;

  btnClose.Font.Color := mmContent.Font.Color;
  btnColor.Font.Color := mmContent.Font.Color;
  btnPin.Font.Color := mmContent.Font.Color;
  btnCollapse.Font.Color := mmContent.Font.Color;
  btnLock.Font.Color := mmContent.Font.Color;
  btnFavorite.Font.Color := mmContent.Font.Color;
  btnChecklist.Font.Color := mmContent.Font.Color;
end;

procedure TNoteForm.UpdateUI;
begin
  btnPin.Enabled := not FNote.Locked;
  btnCollapse.Enabled := not FNote.Locked;
  btnLock.Enabled := True;
  btnColor.Enabled := not FNote.Locked;
  btnFavorite.Enabled := not FNote.Locked;
  UpdateFavoriteButton;

  miAlwaysOnTop.Checked := FNote.AlwaysOnTop;
  miLock.Checked := FNote.Locked;
  miCollapse.Checked := FNote.Collapsed;

  miYellow.Checked := FNote.Color = ncYellow;
  miGreen.Checked := FNote.Color = ncGreen;
  miBlue.Checked := FNote.Color = ncBlue;
  miPink.Checked := FNote.Color = ncPink;
  miPurple.Checked := FNote.Color = ncPurple;
  miOrange.Checked := FNote.Color = ncOrange;
  miWhite.Checked := FNote.Color = ncWhite;
  miGray.Checked := FNote.Color = ncGray;

  if FNote.Locked then
    btnLock.Caption := #$E72E
  else
    btnLock.Caption := #$E785;

  if FNote.Collapsed then
    btnCollapse.Caption := #$E73F
  else
    btnCollapse.Caption := #$E738;
end;

procedure TNoteForm.UpdateFavoriteButton;
begin
  if FNote.Favorite then
    btnFavorite.Caption := #$E734
  else
    btnFavorite.Caption := #$E113;
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

procedure TNoteForm.btnFavoriteClick(Sender: TObject);
begin
  if FNote.Locked then Exit;

  FNote.ToggleFavorite;
  UpdateFavoriteButton;
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.btnCollapseClick(Sender: TObject);
begin
  if FNote.Locked then Exit;

  FNote.Collapsed := not FNote.Collapsed;
  if FNote.Collapsed then
  begin
    Height := FCollapsedHeight;
    mmContent.Visible := False;
    edTitle.Visible := False;
    btnCollapse.Caption := '▣';
  end
  else
  begin
    Height := FNote.Height;
    mmContent.Visible := True;
    edTitle.Visible := True;
    btnCollapse.Caption := '□';
  end;
  SaveNote;
  UpdateUI;
end;

procedure TNoteForm.btnLockClick(Sender: TObject);
begin
  FNote.Locked := not FNote.Locked;
  mmContent.ReadOnly := FNote.Locked;
  edTitle.ReadOnly := FNote.Locked;
  SaveNote;
  UpdateUI;
end;

procedure TNoteForm.btnChecklistClick(Sender: TObject);
begin
  if FNote.Locked then
    Exit;

  ToggleChecklistMode;
end;

procedure TNoteForm.ToggleChecklistMode;
begin
  FForcingChecklistMode := not FForcingChecklistMode;

  if FForcingChecklistMode then
  begin
    RefreshChecklistPanel;
    pnlChecklist.Visible := True;
    mmContent.Visible := False;
  end
  else
  begin
    UpdateContentMode;
  end;
end;

procedure TNoteForm.mmContentChange(Sender: TObject);
begin
  if not FNote.Locked then
    FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.edTitleChange(Sender: TObject);
begin
  if FNote.Locked then
    Exit;

  FNote.Title := edTitle.Text;
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
begin
  if FNote.Locked then Exit;

  FEditorContext.CreateNote(FNote.Title + ' (copy)', FNote.Content, FNote.Color,
    FNote.Left + 30, FNote.Top + 30, FNote.Width, FNote.Height, FNote.AlwaysOnTop);
end;

procedure TNoteForm.miPropertiesClick(Sender: TObject);
begin
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
    ReleaseCapture;
    SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  end;
end;

procedure TNoteForm.pnlHeaderMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
end;

procedure TNoteForm.pnlHeaderMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
end;

procedure TNoteForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F4) and (ssAlt in Shift) then
    Close
  else if (ssCtrl in Shift) and not (ssAlt in Shift) and not (ssShift in Shift) then
  begin
    case Key of
      Ord('F'): 
        begin
          btnFavoriteClick(nil);
          Key := 0;
        end;
      Ord('P'): 
        begin
          btnPinClick(nil);
          Key := 0;
        end;
      Ord('M'): 
        begin
          btnCollapseClick(nil);
          Key := 0;
        end;
      Ord('L'): 
        begin
          btnLockClick(nil);
          Key := 0;
        end;
      Ord('K'): 
        begin
          btnChecklistClick(nil);
          Key := 0;
        end;
      Ord('D'): 
        begin
          miDeleteClick(nil);
          Key := 0;
        end;
    end;
  end;
end;

procedure TNoteForm.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if ssCtrl in Shift then
  begin
    mmContent.Font.Size := Max(8, Min(24, mmContent.Font.Size + WheelDelta div 120));
    Handled := True;
  end;
end;

procedure TNoteForm.WMNCHitTest(var Message: TWMNCHitTest);
begin
  TWindowUtils.HandleNCHitTest(Self, Message);
end;

procedure TNoteForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or WS_THICKFRAME;
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
    FNote.Width := Width;
    FNote.Height := Height;
  end;
  FNote.Left := Left;
  FNote.Top := Top;
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.RefreshTagsFooter;
var
  I: Integer;
  Tag: string;
begin
  while flwTags.ControlCount > 0 do
    flwTags.Controls[0].Free;

  for I := 0 to High(FNote.Tags) do
  begin
    Tag := FNote.Tags[I];
    CreateTagChip(Tag, I);
  end;
end;

procedure TNoteForm.CreateTagChip(const ATag: string; AIndex: Integer);
var
  pnlTag: TPanel;
  lblTag: TLabel;
  btnRemove: TButton;
  TagWidth: Integer;
begin
  pnlTag := TPanel.Create(Self);
  pnlTag.Parent := flwTags;
  pnlTag.BevelOuter := bvNone;
  pnlTag.Caption := '';
  pnlTag.Tag := AIndex;
  pnlTag.OnMouseDown := RemoveTagChip;
  pnlTag.Cursor := crHandPoint;
  pnlTag.Height := 22;
  pnlTag.Color := pnlTagsFooter.Color;

  lblTag := TLabel.Create(Self);
  lblTag.Parent := pnlTag;
  lblTag.Caption := ATag;
  lblTag.Align := alClient;
  lblTag.Alignment := taCenter;
  lblTag.Font.Color := mmContent.Font.Color;
  lblTag.Font.Style := [fsBold];
  lblTag.Visible := False;

  TagWidth := lblTag.Canvas.TextWidth(ATag) + 24;
  lblTag.Visible := True;
  pnlTag.Width := TagWidth;

  btnRemove := TButton.Create(Self);
  btnRemove.Parent := pnlTag;
  btnRemove.Caption := '×';
  btnRemove.Width := 16;
  btnRemove.Height := 16;
  btnRemove.Align := alRight;
  btnRemove.Font.Size := 10;
  btnRemove.Font.Color := mmContent.Font.Color;
  btnRemove.OnMouseDown := RemoveTagChip;
  btnRemove.Tag := AIndex;
  btnRemove.Cursor := crHandPoint;
end;

procedure TNoteForm.RemoveTagChip(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  if FNote.Locked then Exit;

  Index := TComponent(Sender).Tag;
  if (Index >= 0) and (Index < Length(FNote.Tags)) then
  begin
    if FNote.RemoveTag(FNote.Tags[Index]) then
    begin
      RefreshTagsFooter;
      FEditorContext.ScheduleSave(FNote);
    end;
  end;
end;

procedure TNoteForm.btnAddTagClick(Sender: TObject);
begin
  HandleAddTagInput;
end;

procedure TNoteForm.edNewTagKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    HandleAddTagInput;
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    edNewTag.Text := '';
    Key := 0;
  end;
end;

procedure TNoteForm.HandleAddTagInput;
var
  TagText: string;
begin
  if FNote.Locked then Exit;

  TagText := Trim(edNewTag.Text);
  if TagText <> '' then
  begin
    if FNote.AddTag(TagText) then
    begin
      RefreshTagsFooter;
      FEditorContext.ScheduleSave(FNote);
    end;
    edNewTag.Text := '';
  end;
end;

procedure TNoteForm.RefreshChecklistPanel;
var
  I: Integer;
  Item: TChecklistItem;
  pnlItem: TPanel;
  chkDone: TCheckBox;
  edtText: TEdit;
begin
  while pnlChecklistItems.ControlCount > 0 do
    pnlChecklistItems.Controls[0].Free;

  for I := 0 to High(FNote.ChecklistItems) do
  begin
    Item := FNote.ChecklistItems[I];

    pnlItem := TPanel.Create(Self);
    pnlItem.Parent := pnlChecklistItems;
    pnlItem.BevelOuter := bvNone;
    pnlItem.Caption := '';
    pnlItem.Height := 24;
    pnlItem.Tag := I;
    pnlItem.Top := I * 24;
    pnlItem.Left := 0;
    pnlItem.Width := pnlChecklistItems.ClientWidth;

    chkDone := TCheckBox.Create(Self);
    chkDone.Parent := pnlItem;
    chkDone.Checked := Item.Done;
    chkDone.Align := alLeft;
    chkDone.Width := 20;
    chkDone.OnClick := ChecklistItemToggle;
    chkDone.Tag := I;

    edtText := TEdit.Create(Self);
    edtText.Parent := pnlItem;
    edtText.Text := Item.Text;
    edtText.Align := alClient;
    edtText.BorderStyle := bsNone;
    edtText.Font.Color := mmContent.Font.Color;
    edtText.OnChange := ChecklistItemTextChange;
    edtText.Tag := I;
  end;

  pnlChecklist.Visible := Length(FNote.ChecklistItems) > 0;
  UpdateContentMode;
end;

procedure TNoteForm.btnAddChecklistClick(Sender: TObject);
begin
  HandleAddChecklistInput;
end;

procedure TNoteForm.edAddChecklistKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    HandleAddChecklistInput;
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    edAddChecklist.Text := '';
    Key := 0;
  end;
end;

procedure TNoteForm.HandleAddChecklistInput;
var
  ItemText: string;
begin
  if FNote.Locked then Exit;

  ItemText := Trim(edAddChecklist.Text);
  if ItemText <> '' then
  begin
    FNote.AddChecklistItem(ItemText);
    RefreshChecklistPanel;
    FEditorContext.ScheduleSave(FNote);
    edAddChecklist.Text := '';
  end;
end;

procedure TNoteForm.ChecklistItemToggle(Sender: TObject);
var
  Index: Integer;
begin
  if FNote.Locked then Exit;

  Index := TComponent(Sender).Tag;
  FNote.ToggleChecklistItem(Index);
  RefreshChecklistPanel;
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.ChecklistItemTextChange(Sender: TObject);
var
  Index: Integer;
  Text: string;
begin
  if FNote.Locked then Exit;

  Index := TComponent(Sender).Tag;
  Text := TEdit(Sender).Text;
  FNote.SetChecklistItemText(Index, Text);
  FEditorContext.ScheduleSave(FNote);
end;

procedure TNoteForm.UpdateContentMode;
begin
  if pnlChecklist.Visible and (Length(FNote.ChecklistItems) > 0) then
  begin
    mmContent.Visible := False;
    pnlChecklist.Visible := True;
  end
  else
  begin
    mmContent.Visible := True;
    pnlChecklist.Visible := False;
  end;
end;

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
  Result := pnlChecklist.Visible;
end;

procedure TNoteForm.MemoContainerResize(Sender: TObject);
begin
  if Assigned(mmContent) and Assigned(pnlMemoContainer) then
  begin
    mmContent.Height := pnlMemoContainer.Height;
    mmContent.Width := pnlMemoContainer.Width + 30; // Push native scrollbar completely out of view
  end;
end;

procedure TNoteForm.OnScrollTimer(Sender: TObject);
var
  SI: TScrollInfo;
  ThumbHeight: Integer;
begin
  if not Assigned(mmContent) or not mmContent.HandleAllocated then Exit;
  
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_ALL;
  if GetScrollInfo(mmContent.Handle, SB_VERT, SI) then
  begin
    if (SI.nMax = 0) or (SI.nPage >= Cardinal(SI.nMax)) then
    begin
      pnlThumb.Visible := False;
    end
    else
    begin
      pnlThumb.Visible := True;
      ThumbHeight := Max(20, Round(pnlCustomScrollbar.Height * (SI.nPage / (SI.nMax + 1))));
      pnlThumb.Height := ThumbHeight;
      pnlThumb.Top := Round((pnlCustomScrollbar.Height - ThumbHeight) * (SI.nPos / (SI.nMax - SI.nPage + 1)));
    end;
  end
  else
    pnlThumb.Visible := False;
end;

end.