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
  object lvNotes: TListView
    Left = 8
    Top = 37
    Width = 328
    Height = 328
    Anchors = [akLeft, akTop, akRight, akBottom]
    Columns = <
      item
        Caption = 'Title'
        Width = 210
      end
      item
        Caption = 'Modified'
        Width = 100
      end>
    HideSelection = False
    RowSelect = True
    TabOrder = 1
    ViewStyle = vsReport
    OnDblClick = lvNotesDblClick
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