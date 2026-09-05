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
  object pnlHeader: TPanel
    Left = 0
    Top = 0
    Width = 300
    Height = 32
    StyleElements = [seBorder]
    Align = alTop
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 0
    OnMouseDown = pnlHeaderMouseDown
    OnMouseMove = pnlHeaderMouseMove
    OnMouseUp = pnlHeaderMouseUp
    object btnClose: TButton
      Left = 240
      Top = 2
      Width = 28
      Height = 28
      Caption = #215
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
      OnClick = btnCloseClick
    end
    object btnChecklist: TButton
      Left = 272
      Top = 2
      Width = 28
      Height = 28
      Caption = #9745
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 1
      OnClick = btnChecklistClick
    end
    object btnLock: TButton
      Left = 208
      Top = 2
      Width = 28
      Height = 28
      Caption = #62739
      TabOrder = 2
      OnClick = btnLockClick
    end
    object btnCollapse: TButton
      Left = 176
      Top = 2
      Width = 28
      Height = 28
      Caption = #9633
      TabOrder = 3
      OnClick = btnCollapseClick
    end
    object btnPin: TButton
      Left = 144
      Top = 2
      Width = 28
      Height = 28
      Caption = #62668
      TabOrder = 4
      OnClick = btnPinClick
    end
    object btnColor: TButton
      Left = 112
      Top = 2
      Width = 28
      Height = 28
      Caption = #62382
      TabOrder = 5
      OnClick = btnColorClick
    end
    object btnFavorite: TButton
      Left = 80
      Top = 2
      Width = 28
      Height = 28
      Caption = #9733
      TabOrder = 6
      OnClick = btnFavoriteClick
    end
  end
  object edTitle: TEdit
    Left = 0
    Top = 32
    Width = 300
    Height = 28
    Align = alTop
    BorderStyle = bsNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 1
    OnChange = edTitleChange
  end
  object sepTitle: TBevel
    Left = 0
    Top = 60
    Width = 300
    Height = 4
    Align = alTop
    Shape = bsBottomLine
    Style = bsLowered
  end
  object mmContent: TMemo
    Left = 0
    Top = 64
    Width = 300
    Height = 170
    StyleElements = [seBorder]
    Align = alClient
    BorderStyle = bsNone
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssVertical
    TabOrder = 2
    OnChange = mmContentChange
    OnKeyDown = mmContentKeyDown
  end
  object pnlChecklist: TPanel
    Left = 0
    Top = 56
    Width = 300
    Height = 170
    Align = alClient
    BevelOuter = bvNone
    BorderWidth = 4
    ParentBackground = False
    TabOrder = 3
    Visible = False
    object pnlChecklistItems: TPanel
      Left = 4
      Top = 4
      Width = 292
      Height = 166
      Align = alClient
      BevelOuter = bvNone
      ParentBackground = False
      TabOrder = 0
    end
    object pnlAddChecklist: TPanel
      Left = 4
      Top = 170
      Width = 292
      Height = 24
      Align = alBottom
      BevelOuter = bvNone
      ParentBackground = False
      TabOrder = 1
      object edAddChecklist: TEdit
        Left = 1
        Top = 1
        Width = 263
        Height = 22
        Align = alClient
        TabOrder = 0
        TextHint = '+ checklist item'
        OnKeyDown = edAddChecklistKeyDown
      end
      object btnAddChecklist: TButton
        Left = 264
        Top = 1
        Width = 28
        Height = 22
        Align = alRight
        Caption = '+'
        TabOrder = 1
        OnClick = btnAddChecklistClick
      end
    end
  end
  object pnlTagsFooter: TPanel
    Left = 0
    Top = 250
    Width = 300
    Height = 24
    Align = alBottom
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 4
    object flwTags: TFlowPanel
      Left = 1
      Top = 1
      Width = 218
      Height = 22
      Align = alClient
      BevelOuter = bvNone
      TabOrder = 0
    end
    object edNewTag: TEdit
      Left = 219
      Top = 1
      Width = 55
      Height = 22
      Align = alRight
      TabOrder = 1
      TextHint = '+ tag'
      OnKeyDown = edNewTagKeyDown
    end
    object btnAddTag: TButton
      Left = 274
      Top = 1
      Width = 25
      Height = 22
      Align = alRight
      Caption = '+'
      TabOrder = 2
      OnClick = btnAddTagClick
    end
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
        OnClick = ColorMenuItemClick
      end
      object miGreen: TMenuItem
        Tag = 1
        Caption = '&Green'
        OnClick = ColorMenuItemClick
      end
      object miBlue: TMenuItem
        Tag = 2
        Caption = '&Blue'
        OnClick = ColorMenuItemClick
      end
      object miPink: TMenuItem
        Tag = 3
        Caption = '&Pink'
        OnClick = ColorMenuItemClick
      end
      object miPurple: TMenuItem
        Tag = 4
        Caption = 'P&urple'
        OnClick = ColorMenuItemClick
      end
      object miOrange: TMenuItem
        Tag = 5
        Caption = '&Orange'
        OnClick = ColorMenuItemClick
      end
      object miWhite: TMenuItem
        Tag = 6
        Caption = '&White'
        OnClick = ColorMenuItemClick
      end
      object miGray: TMenuItem
        Tag = 7
        Caption = '&Gray'
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
