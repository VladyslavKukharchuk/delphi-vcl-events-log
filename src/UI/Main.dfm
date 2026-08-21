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
    Height = 76
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object LabelSearch: TLabel
      Left = 8
      Top = 48
      Width = 42
      Height = 15
      Caption = 'Search:'
      FocusControl = EditSearch
    end
    object LabelSeverity: TLabel
      Left = 480
      Top = 48
      Width = 48
      Height = 15
      Caption = 'Severity:'
      FocusControl = ComboSeverity
    end
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
    object EditSearch: TEdit
      Left = 60
      Top = 45
      Width = 400
      Height = 23
      TabOrder = 2
      TextHint = 'Part of the event text'
      OnChange = FilterChange
    end
    object ComboSeverity: TComboBox
      Left = 536
      Top = 45
      Width = 120
      Height = 23
      Style = csDropDownList
      TabOrder = 3
      OnChange = FilterChange
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
    Top = 76
    Width = 1000
    Height = 466
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
