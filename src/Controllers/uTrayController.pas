unit uTrayController;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Menus, Vcl.ExtCtrls,
  uNoteManager, uSettings;

type
  TTrayController = class
  private
    FTrayIcon: TTrayIcon;
    FPopupMenu: TPopupMenu;
    FNoteManager: TNoteManager;
    FSettings: TSettings;
    FOnNewNote: TNotifyEvent;
    FOnOpenNotesList: TNotifyEvent;
    FOnSettings: TNotifyEvent;
    FOnBackup: TNotifyEvent;
    FOnRestore: TNotifyEvent;
    FOnAbout: TNotifyEvent;
    FOnExit: TNotifyEvent;
    procedure CreateMenuItems;
    procedure OnMenuItemClick(Sender: TObject);
    procedure UpdateNotesMenu;
  public
    constructor Create(ANoteManager: TNoteManager; ASettings: TSettings);
    destructor Destroy; override;
    procedure ShowTrayIcon;
    procedure HideTrayIcon;
    procedure RefreshNotesMenu;
    property OnNewNote: TNotifyEvent read FOnNewNote write FOnNewNote;
    property OnOpenNotesList: TNotifyEvent read FOnOpenNotesList write FOnOpenNotesList;
    property OnSettings: TNotifyEvent read FOnSettings write FOnSettings;
    property OnBackup: TNotifyEvent read FOnBackup write FOnBackup;
    property OnRestore: TNotifyEvent read FOnRestore write FOnRestore;
    property OnAbout: TNotifyEvent read FOnAbout write FOnAbout;
    property OnExit: TNotifyEvent read FOnExit write FOnExit;
  end;

implementation

{ TTrayController }

constructor TTrayController.Create(ANoteManager: TNoteManager; ASettings: TSettings);
begin
  inherited Create;
  FNoteManager := ANoteManager;
  FSettings := ASettings;
  FTrayIcon := TTrayIcon.Create(nil);
  FPopupMenu := TPopupMenu.Create(nil);
  FTrayIcon.PopupMenu := FPopupMenu;
  FTrayIcon.Icon := Application.Icon;
  FTrayIcon.Hint := 'Sticky Notes';
  FTrayIcon.Visible := False;
  CreateMenuItems;
end;

destructor TTrayController.Destroy;
begin
  FTrayIcon.Visible := False;
  FTrayIcon.Free;
  FPopupMenu.Free;
  inherited;
end;

procedure TTrayController.CreateMenuItems;
var
  Item: TMenuItem;
begin
  // New Note
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '&New Note';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 1;
  FPopupMenu.Items.Add(Item);

  // Open Notes List
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '&Open Notes List';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 2;
  FPopupMenu.Items.Add(Item);

  FPopupMenu.Items.Add(TMenuItem.Create(FPopupMenu)); // Separator

  // Settings
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '&Settings...';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 3;
  FPopupMenu.Items.Add(Item);

  // Backup
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '&Backup...';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 4;
  FPopupMenu.Items.Add(Item);

  // Restore
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '&Restore...';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 5;
  FPopupMenu.Items.Add(Item);

  FPopupMenu.Items.Add(TMenuItem.Create(FPopupMenu)); // Separator

  // About
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '&About';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 6;
  FPopupMenu.Items.Add(Item);

  // Exit
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'E&xit';
  Item.OnClick := OnMenuItemClick;
  Item.Tag := 7;
  FPopupMenu.Items.Add(Item);
end;

procedure TTrayController.OnMenuItemClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  Item := Sender as TMenuItem;
  case Item.Tag of
    1: if Assigned(FOnNewNote) then FOnNewNote(Self);
    2: if Assigned(FOnOpenNotesList) then FOnOpenNotesList(Self);
    3: if Assigned(FOnSettings) then FOnSettings(Self);
    4: if Assigned(FOnBackup) then FOnBackup(Self);
    5: if Assigned(FOnRestore) then FOnRestore(Self);
    6: if Assigned(FOnAbout) then FOnAbout(Self);
    7: if Assigned(FOnExit) then FOnExit(Self);
  end;
end;

procedure TTrayController.UpdateNotesMenu;
begin
  // Will be expanded later to show recent notes in the menu
end;

procedure TTrayController.ShowTrayIcon;
begin
  FTrayIcon.Visible := True;
  FTrayIcon.Animate := True;
  FTrayIcon.ShowBalloonHint;
end;

procedure TTrayController.HideTrayIcon;
begin
  FTrayIcon.Visible := False;
end;

procedure TTrayController.RefreshNotesMenu;
begin
  UpdateNotesMenu;
end;

end.