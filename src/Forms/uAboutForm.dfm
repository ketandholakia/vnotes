object AboutForm: TAboutForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'About V-Notes'
  ClientHeight = 380
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlHeader: TPanel
    Left = 0
    Top = 0
    Width = 400
    Height = 100
    Align = alTop
    BevelOuter = bvNone
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object imgIcon: TImage
      Left = 20
      Top = 20
      Width = 64
      Height = 64
    end
    object lblTitle: TLabel
      Left = 100
      Top = 24
      Width = 110
      Height = 25
      Caption = 'V-Notes'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -19
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblVersion: TLabel
      Left = 100
      Top = 52
      Width = 65
      Height = 15
      Caption = 'Version 1.0.0'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
  end
  object pnlBody: TPanel
    Left = 0
    Top = 100
    Width = 400
    Height = 230
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    object lblDescription: TLabel
      Left = 20
      Top = 16
      Width = 360
      Height = 150
      AutoSize = False
      Caption = 'A lightweight desktop sticky notes application for Windows.'
      WordWrap = True
    end
    object lblCopyright: TLabel
      Left = 20
      Top = 178
      Width = 98
      Height = 13
      Caption = 'Copyright '#194#169' 2026'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -11
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lblWebsite: TLabel
      Left = 20
      Top = 200
      Width = 157
      Height = 19
      Caption = 'github.com/ketandholakia/vnotes'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clBlue
      Font.Height = -11
      Font.Name = 'Segoe UI'
      Font.Style = [fsUnderline]
      ParentFont = False
      OnClick = lblWebsiteClick
      OnMouseEnter = lblWebsiteMouseEnter
      OnMouseLeave = lblWebsiteMouseLeave
    end
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 330
    Width = 400
    Height = 50
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object btnOK: TButton
      Left = 160
      Top = 12
      Width = 80
      Height = 25
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
  end
end
