object TrayForm: TTrayForm
  Left = 0
  Top = 0
  Caption = 'Sticky Notes Tray'
  ClientHeight = 100
  ClientWidth = 200
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDesigned
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object tiMain: TTrayIcon
    Hint = 'Sticky Notes'
    PopupMenu = pmTray
    Visible = True
    OnDblClick = tiMainDblClick
    Left = 48
    Top = 24
  end
  object pmTray: TPopupMenu
    Left = 112
    Top = 24
    object miNewNote: TMenuItem
      Caption = '&New Note'
      ShortCut = 16462
      OnClick = miNewNoteClick
    end
    object miOpenNotes: TMenuItem
      Caption = '&Open Notes List'
      OnClick = miOpenNotesClick
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object miSettings: TMenuItem
      Caption = '&Settings...'
      OnClick = miSettingsClick
    end
    object miBackup: TMenuItem
      Caption = '&Backup...'
      OnClick = miBackupClick
    end
    object miRestore: TMenuItem
      Caption = '&Restore...'
      OnClick = miRestoreClick
    end
    object N2: TMenuItem
      Caption = '-'
    end
    object miAbout: TMenuItem
      Caption = '&About'
      OnClick = miAboutClick
    end
    object miExit: TMenuItem
      Caption = 'E&xit'
      OnClick = miExitClick
    end
  end
end
