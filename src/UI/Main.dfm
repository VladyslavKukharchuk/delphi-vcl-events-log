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
    Top = 0
    Width = 1000
    Height = 542
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
    TabOrder = 1
    ViewStyle = vsReport
    OnData = ListViewEventsData
  end
end
