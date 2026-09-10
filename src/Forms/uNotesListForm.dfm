object NotesListForm: TNotesListForm
  Left = 0
  Top = 0
  Caption = 'Notes'
  ClientHeight = 412
  ClientWidth = 344
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  PixelsPerInch = 96
  TextHeight = 15
  object edSearch: TEdit
    Left = 8
    Top = 8
    Width = 328
    Height = 23
    Anchors = [akLeft, akTop, akRight]
    TabOrder = 0
    TextHint = 'Search notes...'
    OnChange = edSearchChange
  end
  object cbTagFilter: TComboBox
    Left = 8
    Top = 37
    Width = 328
    Height = 23
    Style = csDropDownList
    Anchors = [akLeft, akTop, akRight]
    ItemIndex = 0
    TabOrder = 3
    Text = 'All Tags'
    OnChange = cbTagFilterChange
    Items.Strings = (
      'All Tags'
    )
  end
  object vstNotes: TVirtualStringTree
    Left = 8
    Top = 66
    Width = 328
    Height = 299
    Anchors = [akLeft, akTop, akRight, akBottom]
    Header.AutoSizeIndex = 0
    Header.Options = [hoColumnResize, hoDrag, hoShowSortGlyphs, hoVisible]
    TabOrder = 1
    TreeOptions.PaintOptions = [toShowButtons, toShowDropmark, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages]
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnBeforeCellPaint = vstNotesBeforeCellPaint
    OnDblClick = vstNotesDblClick
    OnFreeNode = vstNotesFreeNode
    OnGetText = vstNotesGetText
    OnGetNodeDataSize = vstNotesGetNodeDataSize
    OnInitNode = vstNotesInitNode
    Columns = <
      item
        Position = 0
        Text = 'Color/Folder'
        Width = 180
      end
      item
        Position = 1
        Text = 'Title'
        Width = 150
      end
      item
        Position = 2
        Text = 'Date Created'
        Width = 100
      end
      item
        Position = 3
        Text = 'Note Type'
        Width = 100
      end
      item
        Position = 4
        Text = 'Tags'
        Width = 150
      end
      item
        Position = 5
        Text = 'Color'
        Width = 50
      end>
  end
  object btnOpen: TButton
    Left = 236
    Top = 373
    Width = 100
    Height = 31
    Anchors = [akRight, akBottom]
    Caption = 'Open'
    TabOrder = 2
    OnClick = btnOpenClick
  end
end