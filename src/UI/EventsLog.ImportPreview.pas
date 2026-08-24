unit EventsLog.ImportPreview;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  EventsLog.Event, EventsLog.Json;

type
  TImportPreviewForm = class(TForm)
    LabelSummary: TLabel;
    PageControl: TPageControl;
    TabEvents: TTabSheet;
    ListViewEvents: TListView;
    TabProblems: TTabSheet;
    MemoProblems: TMemo;
    PanelButtons: TPanel;
    ButtonImport: TButton;
    ButtonCancel: TButton;
    procedure ListViewEventsData(Sender: TObject; Item: TListItem);
  private
    FEvents: TArray<TLogEvent>;
  end;

function ConfirmImport(const AFileName: string; const AReport: TImportReport;
  const AEvents: TArray<TLogEvent>): Boolean;

implementation

uses
  System.SysUtils, System.UITypes;

{$R *.dfm}

resourcestring
  SSummary = 'Read %s.' + sLineBreak +
    '%d events are ready to import, %d records were skipped.';
  STabEvents = 'Events to import (%d)';
  STabProblems = 'Problems (%d)';

procedure TImportPreviewForm.ListViewEventsData(Sender: TObject;
  Item: TListItem);
var
  Event: TLogEvent;
begin
  if (Item.Index < 0) or (Item.Index > High(FEvents)) then
    Exit;
  Event := FEvents[Item.Index];
  Item.Caption := TimeToText(Event.Time);
  Item.SubItems.Add(SeverityToStr(Event.Severity));
  Item.SubItems.Add(Event.Text);
end;

function ConfirmImport(const AFileName: string; const AReport: TImportReport;
  const AEvents: TArray<TLogEvent>): Boolean;
var
  Dialog: TImportPreviewForm;
begin
  Dialog := TImportPreviewForm.Create(Application);
  try
    Dialog.FEvents := AEvents;
    Dialog.LabelSummary.Caption := Format(SSummary,
      [AFileName, AReport.Accepted, AReport.Rejected]);
    Dialog.TabEvents.Caption := Format(STabEvents, [AReport.Accepted]);
    Dialog.TabProblems.Caption := Format(STabProblems, [AReport.Rejected]);
    Dialog.ListViewEvents.Items.Count := Length(AEvents);
    Dialog.MemoProblems.Lines.Text := string.Join(sLineBreak, AReport.Problems);
    Dialog.ButtonImport.Enabled := AReport.Accepted > 0;
    if AReport.Accepted = 0 then
      Dialog.PageControl.ActivePage := Dialog.TabProblems;
    Result := Dialog.ShowModal = mrOk;
  finally
    Dialog.Free;
  end;
end;

end.
