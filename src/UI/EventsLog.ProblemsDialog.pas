unit EventsLog.ProblemsDialog;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TImportProblemsForm = class(TForm)
    LabelSummary: TLabel;
    PanelButtons: TPanel;
    ButtonClose: TButton;
    MemoProblems: TMemo;
  end;

procedure ShowImportProblems(const ASummary: string;
  const AProblems: TArray<string>);

implementation

uses
  System.SysUtils;

{$R *.dfm}

procedure ShowImportProblems(const ASummary: string;
  const AProblems: TArray<string>);
var
  Dialog: TImportProblemsForm;
begin
  Dialog := TImportProblemsForm.Create(Application);
  try
    Dialog.LabelSummary.Caption := ASummary;
    Dialog.MemoProblems.Lines.Text := string.Join(sLineBreak, AProblems);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

end.
