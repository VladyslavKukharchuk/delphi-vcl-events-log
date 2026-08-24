object ImportProblemsForm: TImportProblemsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  Caption = 'Import problems'
  ClientHeight = 400
  ClientWidth = 640
  Color = clBtnFace
  Constraints.MinHeight = 260
  Constraints.MinWidth = 440
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
    Width = 616
    Height = 15
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
    Top = 348
    Width = 640
    Height = 52
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object ButtonClose: TButton
      Left = 537
      Top = 11
      Width = 91
      Height = 29
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
  end
  object MemoProblems: TMemo
    AlignWithMargins = True
    Left = 12
    Top = 33
    Width = 616
    Height = 309
    Margins.Left = 12
    Margins.Top = 0
    Margins.Right = 12
    Margins.Bottom = 6
    Align = alClient
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
end
