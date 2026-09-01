object NoteForm: TNoteForm
  Left = 0
  Top = 0
  BorderStyle = bsNone
  Caption = 'Note'
  ClientHeight = 250
  ClientWidth = 300
  Color = clWindow
  DoubleBuffered = True
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poDesigned
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnMouseWheel = FormMouseWheel
  OnResize = FormResize
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 15
  object pnlHeader: TPanel
    Left = 0
    Top = 0
    Width = 300
    Height = 32
    Align = alTop
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 0
    OnMouseDown = pnlHeaderMouseDown
    OnMouseMove = pnlHeaderMouseMove
    OnMouseUp = pnlHeaderMouseUp
    object btnClose: TButton
      Left = 272
      Top = 2
      Width = 28
      Height = 28
      Caption = #215
      Flat = True
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
      OnClick = btnCloseClick
    end
    object btnLock: TButton
      Left = 240
      Top = 2
      Width = 28
      Height = 28
      Caption = #128275
      Flat = True
      TabOrder = 1
      OnClick = btnLockClick
    end
    object btnCollapse: TButton
      Left = 208
      Top = 2
      Width = 28
      Height = 28
      Caption = #9633
      Flat = True
      TabOrder = 2
      OnClick = btnCollapseClick
    end
    object btnPin: TButton
      Left = 176
      Top = 2
      Width = 28
      Height = 28
      Caption = #128204
      Flat = True
      TabOrder = 3
      OnClick = btnPinClick
    end
    object btnColor: TButton
      Left = 144
      Top = 2
      Width = 28
      Height = 28
      Caption = #127918
      Flat = True
      TabOrder = 4
      OnClick = btnColorClick
    end
  end
  object mmContent: TMemo
    Left = 0
    Top = 32
    Width = 300
    Height = 218
    Align = alClient
    BorderStyle = bsNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssVertical
    TabOrder = 1
    WordWrap = True
    OnChange = mmContentChange
    OnKeyDown = mmContentKeyDown
  end
  object pmNote: TPopupMenu
    OnPopup = pmNotePopup
    Left = 24
    Top = 64
    object miNewNote: TMenuItem
      Caption = '&New Note'
      OnClick = miNewNoteClick
    end
    object miDuplicate: TMenuItem
      Caption = '&Duplicate'
      OnClick = miDuplicateClick
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object miColor: TMenuItem
      Caption = '&Color'
      object miYellow: TMenuItem
        Caption = '&Yellow'
        Tag = 0
        OnClick = ColorMenuItemClick
      end
      object miGreen: TMenuItem
        Caption = '&Green'
        Tag = 1
        OnClick = ColorMenuItemClick
      end
      object miBlue: TMenuItem
        Caption = '&Blue'
        Tag = 2
        OnClick = ColorMenuItemClick
      end
      object miPink: TMenuItem
        Caption = '&Pink'
        Tag = 3
        OnClick = ColorMenuItemClick
      end
      object miPurple: TMenuItem
        Caption = 'P&urple'
        Tag = 4
        OnClick = ColorMenuItemClick
      end
      object miOrange: TMenuItem
        Caption = '&Orange'
        Tag = 5
        OnClick = ColorMenuItemClick
      end
      object miWhite: TMenuItem
        Caption = '&White'
        Tag = 6
        OnClick = ColorMenuItemClick
      end
      object miGray: TMenuItem
        Caption = '&Gray'
        Tag = 7
        OnClick = ColorMenuItemClick
      end
    end
    object N2: TMenuItem
      Caption = '-'
    end
    object miAlwaysOnTop: TMenuItem
      Caption = 'Always on &Top'
      OnClick = miAlwaysOnTopClick
    end
    object miLock: TMenuItem
      Caption = '&Lock'
      OnClick = miLockClick
    end
    object miCollapse: TMenuItem
      Caption = '&Collapse'
      OnClick = miCollapseClick
    end
    object N3: TMenuItem
      Caption = '-'
    end
    object miDelete: TMenuItem
      Caption = '&Delete'
      OnClick = miDeleteClick
    end
    object miProperties: TMenuItem
      Caption = '&Properties...'
      OnClick = miPropertiesClick
    end
  end
end