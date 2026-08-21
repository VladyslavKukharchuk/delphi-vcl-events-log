object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Events Log'
  ClientHeight = 561
  ClientWidth = 1000
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 1000
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object ButtonImport: TButton
      Left = 8
      Top = 8
      Width = 130
      Height = 25
      Caption = 'Import JSON...'
      TabOrder = 0
      OnClick = ButtonImportClick
    end
    object ButtonClear: TButton
      Left = 146
      Top = 8
      Width = 130
      Height = 25
      Caption = 'Clear all events'
      Enabled = False
      TabOrder = 1
      OnClick = ButtonClearClick
    end
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 542
    Width = 1000
    Height = 19
    Panels = <>
    SimplePanel = True
  end
  object ListViewEvents: TListView
    Left = 0
    Top = 41
    Width = 1000
    Height = 501
    Align = alClient
    Columns = <
      item
        Caption = 'Id'
        Width = 250
      end
      item
        Caption = 'Time'
        Width = 150
      end
      item
        Caption = 'Severity'
        Width = 70
      end
      item
        AutoSize = True
        Caption = 'Text'
      end>
    OwnerData = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnData = ListViewEventsData
  end
  object OpenDialogJson: TOpenDialog
    Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    Options = [ofHideReadOnly, ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Title = 'Import events'
    Left = 8
    Top = 48
  end
end
