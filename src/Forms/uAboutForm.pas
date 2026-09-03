unit uAboutForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Imaging.pngimage, Winapi.ShellAPI;

type
  TAboutForm = class(TForm)
    pnlHeader: TPanel;
    imgIcon: TImage;
    lblTitle: TLabel;
    lblVersion: TLabel;
    pnlBody: TPanel;
    lblDescription: TLabel;
    lblCopyright: TLabel;
    lblWebsite: TLabel;
    pnlButtons: TPanel;
    btnOK: TButton;
    procedure FormCreate(Sender: TObject);
    procedure lblWebsiteClick(Sender: TObject);
    procedure lblWebsiteMouseEnter(Sender: TObject);
    procedure lblWebsiteMouseLeave(Sender: TObject);
  private
  public
  end;

var
  AboutForm: TAboutForm;

implementation

{$R *.dfm}

procedure TAboutForm.FormCreate(Sender: TObject);
begin
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  Caption := 'About V-Notes';

  lblTitle.Caption := 'V-Notes';
  lblTitle.Font.Size := 18;
  lblTitle.Font.Style := [fsBold];
  
  lblVersion.Caption := 'Version 1.0.0';
  lblVersion.Font.Size := 10;
  lblVersion.Font.Color := clGrayText;
  
  lblDescription.Caption := 'A lightweight desktop sticky notes application for Windows.'#13#10 +
    'Built with Delphi using a clean, modular architecture.'#13#10#13#10 +
    'Features:'#13#10 +
    '• Colorful sticky notes'#13#10 +
    '• Always on top, collapse, lock'#13#10 +
    '• Global hotkeys (Ctrl+Alt+N for new note)'#13#10 +
    '• Auto-save with configurable delay'#13#10 +
    '• Dark/Light theme'#13#10 +
    '• Backup and restore'#13#10 +
    '• Multi-monitor support';
  lblDescription.WordWrap := True;
  
  lblCopyright.Caption := 'Copyright © 2026';
  lblCopyright.Font.Size := 9;
  lblCopyright.Font.Color := clGrayText;
  
  lblWebsite.Caption := 'github.com/ketandholakia/vnotes';
  lblWebsite.Font.Size := 9;
  lblWebsite.Font.Color := clBlue;
  lblWebsite.Font.Style := [fsUnderline];
  lblWebsite.Cursor := crHandPoint;
  
  btnOK.Caption := 'OK';
  btnOK.ModalResult := mrOk;
  btnOK.Default := True;
  btnOK.Cancel := True;
end;

procedure TAboutForm.lblWebsiteClick(Sender: TObject);
begin
  ShellExecute(Handle, 'open', 'https://github.com/ketandholakia/vnotes', nil, nil, SW_SHOWNORMAL);
end;

procedure TAboutForm.lblWebsiteMouseEnter(Sender: TObject);
begin
  lblWebsite.Font.Color := clHighlight;
end;

procedure TAboutForm.lblWebsiteMouseLeave(Sender: TObject);
begin
  lblWebsite.Font.Color := clBlue;
end;

end.