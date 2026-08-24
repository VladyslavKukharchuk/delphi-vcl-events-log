object ImportPreviewForm: TImportPreviewForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  Caption = 'Import preview'
  ClientHeight = 520
  ClientWidth = 860
  Color = clBtnFace
  Constraints.MinHeight = 340
  Constraints.MinWidth = 560
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object LabelSummary: TLabel
    AlignWithMargins = True
    Left = 12
    Top = 12
    Width = 836
    Height = 30
    Margins.Left = 12
    Margins.Top = 12
    Margins.Right = 12
    Margins.Bottom = 6
    Align = alTop
    Caption = 'LabelSummary'
    WordWrap = True
  end
  object PanelButtons: TPanel
    Left = 0
    Top = 468
    Width = 860
    Height = 52
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object ButtonImport: TButton
      Left = 658
      Top = 11
      Width = 91
      Height = 29
      Anchors = [akTop, akRight]
      Caption = 'Import'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object ButtonCancel: TButton
      Left = 757
      Top = 11
      Width = 91
      Height = 29
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
  object PageControl: TPageControl
    AlignWithMargins = True
    Left = 12
    Top = 48
    Width = 836
    Height = 414
    Margins.Left = 12
    Margins.Top = 0
    Margins.Right = 12
    Margins.Bottom = 6
    ActivePage = TabEvents
    Align = alClient
    TabOrder = 0
    object TabEvents: TTabSheet
      Caption = 'Events to import'
      object ListViewEvents: TListView
        Left = 0
        Top = 0
        Width = 828
        Height = 384
        Align = alClient
        Columns = <
          item
            Caption = 'Time'
            Width = 150
          end
          item
            Caption = 'Severity'
            Width = 90
          end
          item
            AutoSize = True
            Caption = 'Text'
          end>
        OwnerData = True
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnData = ListViewEventsData
      end
    end
    object TabProblems: TTabSheet
      Caption = 'Problems'
      ImageIndex = 1
      object MemoProblems: TMemo
        Left = 0
        Top = 0
        Width = 828
        Height = 384
        Align = alClient
        ReadOnly = True
        ScrollBars = ssVertical
        TabOrder = 0
      end
    end
  end
end
