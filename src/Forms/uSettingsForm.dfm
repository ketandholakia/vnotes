object SettingsForm: TSettingsForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Settings'
  ClientHeight = 450
  ClientWidth = 500
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 15
  object pcSettings: TPageControl
    Left = 8
    Top = 8
    Width = 484
    Height = 385
    ActivePage = tsGeneral
    TabOrder = 0
    object tsGeneral: TTabSheet
      Caption = 'General'
      object grpGeneral: TGroupBox
        Left = 16
        Top = 16
        Width = 441
        Height = 321
        Caption = 'General Settings'
        TabOrder = 0
        object chkAutoStart: TCheckBox
          Left = 16
          Top = 32
          Width = 200
          Height = 17
          Caption = 'Start with Windows'
          TabOrder = 0
        end
        object chkConfirmDelete: TCheckBox
          Left = 16
          Top = 56
          Width = 250
          Height = 17
          Caption = 'Confirm before deleting notes'
          TabOrder = 1
        end
        object lblAutosaveDelay: TLabel
          Left = 16
          Top = 88
          Width = 120
          Height = 15
          Caption = 'Auto-save delay (ms):'
        end
        object edtAutosaveDelay: TEdit
          Left = 152
          Top = 85
          Width = 80
          Height = 23
          TabOrder = 2
          Text = '1000'
        end
        object udAutosaveDelay: TUpDown
          Left = 232
          Top = 85
          Width = 17
          Height = 23
          Associate = edtAutosaveDelay
          TabOrder = 3
        end
        object lblDefaultSize: TLabel
          Left = 16
          Top = 120
          Width = 120
          Height = 15
          Caption = 'Default note size:'
        end
        object edtDefaultWidth: TEdit
          Left = 152
          Top = 117
          Width = 60
          Height = 23
          TabOrder = 4
          Text = '300'
        end
        object edtDefaultHeight: TEdit
          Left = 220
          Top = 117
          Width = 60
          Height = 23
          TabOrder = 5
          Text = '250'
        end
        object lblDefaultColor: TLabel
          Left = 16
          Top = 152
          Width = 100
          Height = 15
          Caption = 'Default color:'
        end
        object cbDefaultColor: TComboBox
          Left = 152
          Top = 149
          Width = 150
          Height = 23
          Style = csDropDownList
          TabOrder = 6
        end
        object chkDefaultAlwaysOnTop: TCheckBox
          Left = 16
          Top = 184
          Width = 200
          Height = 17
          Caption = 'New notes always on top'
          TabOrder = 7
        end
        object chkEnableHotkeys: TCheckBox
          Left = 16
          Top = 208
          Width = 250
          Height = 17
          Caption = 'Enable global hotkeys'
          TabOrder = 8
        end
      end
    end
    object tsAppearance: TTabSheet
      Caption = 'Appearance'
      ImageIndex = 1
      object grpTheme: TGroupBox
        Left = 16
        Top = 16
        Width = 441
        Height = 105
        Caption = 'Theme'
        TabOrder = 0
        object chkDarkTheme: TCheckBox
          Left = 16
          Top = 32
          Width = 200
          Height = 17
          Caption = 'Dark theme'
          TabOrder = 0
          OnClick = chkDarkThemeClick
        end
      end
    end
    object tsHotkeys: TTabSheet
      Caption = 'Hotkeys'
      ImageIndex = 2
      object grpHotkeys: TGroupBox
        Left = 16
        Top = 16
        Width = 441
        Height = 153
        Caption = 'Global Hotkeys'
        TabOrder = 0
        object lblHotkeyNewNote: TLabel
          Left = 16
          Top = 32
          Width = 100
          Height = 15
          Caption = 'New Note:'
        end
        object edtHotkeyNewNote: TEdit
          Left = 152
          Top = 29
          Width = 150
          Height = 23
          TabOrder = 0
          Text = 'Ctrl+Alt+N'
        end
        object lblHotkeySearch: TLabel
          Left = 16
          Top = 64
          Width = 100
          Height = 15
          Caption = 'Search Notes:'
        end
        object edtHotkeySearch: TEdit
          Left = 152
          Top = 61
          Width = 150
          Height = 23
          TabOrder = 1
          Text = 'Ctrl+Alt+F'
        end
      end
    end
    object tsBackup: TTabSheet
      Caption = 'Backup'
      ImageIndex = 3
      object grpBackup: TGroupBox
        Left = 16
        Top = 16
        Width = 441
        Height = 121
        Caption = 'Backup Settings'
        TabOrder = 0
        object chkBackupEnabled: TCheckBox
          Left = 16
          Top = 32
          Width = 200
          Height = 17
          Caption = 'Enable automatic backups'
          TabOrder = 0
        end
        object lblBackupInterval: TLabel
          Left = 16
          Top = 64
          Width = 120
          Height = 15
          Caption = 'Backup interval (days):'
        end
        object edtBackupInterval: TEdit
          Left = 152
          Top = 61
          Width = 60
          Height = 23
          TabOrder = 1
          Text = '1'
        end
        object udBackupInterval: TUpDown
          Left = 212
          Top = 61
          Width = 17
          Height = 23
          Associate = edtBackupInterval
          TabOrder = 2
        end
      end
    end
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 401
    Width = 500
    Height = 49
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnOK: TButton
      Left = 272
      Top = 12
      Width = 75
      Height = 25
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TButton
      Left = 353
      Top = 12
      Width = 75
      Height = 25
      Caption = 'Cancel'
      Cancel = True
      ModalResult = 2
      TabOrder = 1
      OnClick = btnCancelClick
    end
    object btnApply: TButton
      Left = 191
      Top = 12
      Width = 75
      Height = 25
      Caption = 'Apply'
      TabOrder = 2
      OnClick = btnApplyClick
    end
  end
end