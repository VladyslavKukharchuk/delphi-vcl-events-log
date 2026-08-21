unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.StdCtrls,
  EventsLog.Event, EventsLog.Filter, EventsLog.Database,
  EventsLog.EventRepository, EventsLog.Json;

type
  TMainForm = class(TForm)
    PanelTop: TPanel;
    ButtonImport: TButton;
    StatusBar: TStatusBar;
    ListViewEvents: TListView;
    OpenDialogJson: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ListViewEventsData(Sender: TObject; Item: TListItem);
    procedure ButtonImportClick(Sender: TObject);
  private
    FDatabase: TEventsDatabase;
    FRepository: TEventRepository;
    FFilter: TEventFilter;
    { The result of the current query. The list view is in virtual mode and
      reads this by index, so it is the only copy of what the user sees. }
    FVisible: TArray<TLogEvent>;
    procedure RefreshView;
    procedure ReportImport(const AFileName: string; const AReport: TImportReport);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

resourcestring
  SDatabaseUnavailable = 'The event database is not available.';
  SShowingSome = 'Showing the %d most recent of %d events';
  SShowingAll = '%d events';
  SImportedFrom = 'Imported %d events from %s.';
  SSkipped = '%d records were skipped. The first problem was: %s';

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FFilter := TEventFilter.Unfiltered;
  try
    FDatabase := TEventsDatabase.Create;
    FRepository := TEventRepository.Create(FDatabase);
  except
    on E: Exception do
    begin
      { The repository and the database raise with the path in the message.
        Turning that into something the user reads is this form's job, and only
        this form's. }
      FreeAndNil(FRepository);
      FreeAndNil(FDatabase);
      ButtonImport.Enabled := False;
      StatusBar.SimpleText := SDatabaseUnavailable;
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshView;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FRepository.Free;
  FDatabase.Free;
end;

procedure TMainForm.RefreshView;
var
  Stored: Int64;
begin
  if FRepository = nil then
    Exit;
  FVisible := FRepository.Query(FFilter);
  ListViewEvents.Items.Count := Length(FVisible);
  ListViewEvents.Invalidate;

  { The query is capped, so the window has to say when it is showing less than
    the database holds. Silence would read as "this is everything". }
  Stored := FRepository.Count;
  if Stored > Length(FVisible) then
    StatusBar.SimpleText := Format(SShowingSome, [Length(FVisible), Stored])
  else
    StatusBar.SimpleText := Format(SShowingAll, [Stored]);
end;

procedure TMainForm.ListViewEventsData(Sender: TObject; Item: TListItem);
var
  Event: TLogEvent;
begin
  if (Item.Index < 0) or (Item.Index > High(FVisible)) then
    Exit;
  Event := FVisible[Item.Index];
  Item.Caption := GuidToText(Event.Id);
  Item.SubItems.Add(TimeToText(Event.Time));
  Item.SubItems.Add(SeverityToStr(Event.Severity));
  Item.SubItems.Add(Event.Text);
end;

procedure TMainForm.ReportImport(const AFileName: string;
  const AReport: TImportReport);
var
  Lines: TArray<string>;
  Kind: TMsgDlgType;
begin
  Lines := [Format(SImportedFrom, [AReport.Accepted, AFileName])];
  if AReport.Rejected > 0 then
    Lines := Lines + [Format(SSkipped, [AReport.Rejected, AReport.FirstProblem])];

  if (AReport.Rejected > 0) or (AReport.Accepted = 0) then
    Kind := mtWarning
  else
    Kind := mtInformation;
  MessageDlg(string.Join(sLineBreak, Lines), Kind, [mbOK], 0);
end;

procedure TMainForm.ButtonImportClick(Sender: TObject);
var
  Events: TArray<TLogEvent>;
  Report: TImportReport;
begin
  if not OpenDialogJson.Execute then
    Exit;
  try
    Events := LoadEventsFromFile(OpenDialogJson.FileName, Report);
    FRepository.InsertMany(Events);
  except
    { An unusable file is the user's problem to fix, so it is reported and the
      stored history is left as it was. }
    on E: EEventImportError do
    begin
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshView;
  ReportImport(OpenDialogJson.FileName, Report);
end;

end.
