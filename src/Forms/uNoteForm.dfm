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
  TextHeight = 15
  object edTitle: TEdit
    Left = 0
    Top = 32
    Width = 300
    Height = 28
    Align = alTop
    AlignWithMargins = True
    Margins.Left = 10
    Margins.Top = 0
    Margins.Right = 10
    Margins.Bottom = 0
    BorderStyle = bsNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -18
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 0
    OnChange = edTitleChange
  end
  object mmContent: TMemo
    Left = 0
    Top = 60
    Width = 292
    Height = 162
    StyleElements = [seBorder]
    Align = alClient
    AlignWithMargins = True
    Margins.Left = 10
    Margins.Top = 5
    Margins.Right = 0
    Margins.Bottom = 5
    BorderStyle = bsNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssVertical
    TabOrder = 1
    OnChange = mmContentChange
    OnKeyDown = mmContentKeyDown
  end
  object pmNote: TPopupMenu
    OnPopup = pmNotePopup
    Left = 16
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
