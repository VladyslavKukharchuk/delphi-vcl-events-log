unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.StdCtrls,
  EventsLog.Event, EventsLog.Filter, EventsLog.Database,
  EventsLog.EventRepository, EventsLog.Json, EventsLog.Generator;

type
  TMainForm = class(TForm)
    PanelTop: TPanel;
    ButtonImport: TButton;
    ButtonClear: TButton;
    ButtonGenerate: TButton;
    LabelSearch: TLabel;
    EditSearch: TEdit;
    LabelSeverity: TLabel;
    ComboSeverity: TComboBox;
    StatusBar: TStatusBar;
    ListViewEvents: TListView;
    OpenDialogJson: TOpenDialog;
    TimerRefresh: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ListViewEventsData(Sender: TObject; Item: TListItem);
    procedure ButtonImportClick(Sender: TObject);
    procedure ButtonClearClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure ButtonGenerateClick(Sender: TObject);
    procedure TimerRefreshTimer(Sender: TObject);
  private
    FDatabase: TEventsDatabase;
    FRepository: TEventRepository;
    FFilter: TEventFilter;
    { Nil exactly when the generator is off, so the button has no second copy
      of that state to keep in step. }
    FGenerator: TEventGenerator;
    { Set by an arriving event, cleared by the refresh that shows it. The
      refresh costs a query, so a burst is coalesced into one (ADR 0007). }
    FViewStale: Boolean;
    { Why the last generated event could not be stored, empty when nothing has
      failed. The timer reads it, because the callback that sets it cannot. }
    FGeneratorProblem: string;
    { The result of the current query. The list view is in virtual mode and
      reads this by index, so it is the only copy of what the user sees. }
    FVisible: TArray<TLogEvent>;
    procedure FillSeverities;
    function SelectedSeverities: TSeveritySet;
    function ViewSummary(AStored, AMatching: Int64): string;
    procedure RefreshView;
    procedure StartGenerating;
    procedure StopGenerating;
    procedure GeneratedEventArrived(const AEvent: TLogEvent);
    procedure ReportImport(const AFileName: string; const AReport: TImportReport);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

const
  { The entry in front of the severity names, standing for all of them. }
  SeverityAllIndex = 0;

resourcestring
  SDatabaseUnavailable = 'The event database is not available.';
  SStartGenerating = 'Start generating';
  SStopGenerating = 'Stop generating';
  SGeneratorFailed = 'Generating was stopped, because the event could not be ' +
    'stored:' + sLineBreak + '%s';
  SSeverityAll = 'All';
  SShowingSome = 'Showing the %d most recent of %d events';
  SShowingAll = '%d events';
  SMatchingSome = 'Showing the %d most recent of %d matching events, %d stored';
  SMatchingAll = '%d of %d events match the filter';
  SImportedFrom = 'Imported %d events from %s.';
  SSkipped = '%d records were skipped. The first problem was: %s';
  SConfirmClear = 'Delete all %d stored events?' + sLineBreak + 'This cannot be undone.';

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FFilter := TEventFilter.Unfiltered;
  FillSeverities;
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
      { Nothing can be stored, so there is nothing to generate either. }
      ButtonGenerate.Enabled := False;
      { Nothing can be queried, so there is nothing to search or filter. }
      EditSearch.Enabled := False;
      ComboSeverity.Enabled := False;
      StatusBar.SimpleText := SDatabaseUnavailable;
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshView;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { Before the repository, because a running generator still has events to hand
    over and they are stored on this thread. }
  StopGenerating;
  FRepository.Free;
  FDatabase.Free;
end;

procedure TMainForm.StartGenerating;
begin
  FGenerator := TEventGenerator.Create(GeneratedEventArrived);
  TimerRefresh.Enabled := True;
  ButtonGenerate.Caption := SStopGenerating;
end;

procedure TMainForm.StopGenerating;
begin
  if FGenerator = nil then
    Exit;
  { Freeing it is the whole of stopping: TThread.Destroy terminates the thread,
    waits for it, and drops the callback it had queued. }
  FreeAndNil(FGenerator);
  TimerRefresh.Enabled := False;
  ButtonGenerate.Caption := SStartGenerating;
  { The timer is off now, so anything that arrived since its last tick would
    stay invisible until something else refreshed the window. }
  if FViewStale then
    RefreshView;
end;

procedure TMainForm.ButtonGenerateClick(Sender: TObject);
begin
  if FGenerator = nil then
    StartGenerating
  else
    StopGenerating;
end;

{ Runs on the main thread: the generator queues it there, so this is the same
  thread that owns the connection and the array behind the table (ADR 0007). }
procedure TMainForm.GeneratedEventArrived(const AEvent: TLogEvent);
begin
  try
    FRepository.Insert(AEvent);
    FViewStale := True;
  except
    { Stopping here would run the thread's destructor from inside a callback of
      that same thread, and reporting here would put a dialog inside it. The
      timer is outside both, so it does the stopping and the talking. }
    on E: Exception do
      FGeneratorProblem := E.Message;
  end;
end;

procedure TMainForm.TimerRefreshTimer(Sender: TObject);
var
  Problem: string;
begin
  if FGeneratorProblem <> '' then
  begin
    { A failing insert fails again a second later, so the generator is stopped
      and the reason given once rather than every second. Stopping disables this
      timer, so the dialog cannot be reached twice. }
    Problem := FGeneratorProblem;
    FGeneratorProblem := '';
    StopGenerating;
    MessageDlg(Format(SGeneratorFailed, [Problem]), mtError, [mbOK], 0);
    Exit;
  end;
  if FViewStale then
    RefreshView;
end;

{ The names come from the model rather than from the form designer, so adding a
  severity level to the enumeration adds it to this list as well. }
procedure TMainForm.FillSeverities;
var
  Severity: TEventSeverity;
begin
  ComboSeverity.Items.BeginUpdate;
  try
    ComboSeverity.Items.Clear;
    ComboSeverity.Items.Add(SSeverityAll);
    for Severity := Low(TEventSeverity) to High(TEventSeverity) do
      ComboSeverity.Items.Add(SeverityToStr(Severity));
  finally
    ComboSeverity.Items.EndUpdate;
  end;
  ComboSeverity.ItemIndex := SeverityAllIndex;
end;

{ The list holds one severity per entry after the "All" one and in the order of
  the enumeration, which is what FillSeverities put there. }
function TMainForm.SelectedSeverities: TSeveritySet;
begin
  if ComboSeverity.ItemIndex <= SeverityAllIndex then
    Exit(AllSeverities);
  Result := [TEventSeverity(ComboSeverity.ItemIndex - 1)];
end;

procedure TMainForm.FilterChange(Sender: TObject);
begin
  FFilter := TEventFilter.Create(EditSearch.Text, SelectedSeverities);
  RefreshView;
end;

{ The query is capped, so the window has to say when it is showing less than
  what it could. Silence would read as "this is everything", and under a filter
  so would a bare count: zero matches and an empty database look the same. }
function TMainForm.ViewSummary(AStored, AMatching: Int64): string;
begin
  if FFilter.IsUnfiltered then
  begin
    if AStored > Length(FVisible) then
      Result := Format(SShowingSome, [Length(FVisible), AStored])
    else
      Result := Format(SShowingAll, [AStored]);
  end
  else if AMatching > Length(FVisible) then
    Result := Format(SMatchingSome, [Length(FVisible), AMatching, AStored])
  else
    Result := Format(SMatchingAll, [AMatching, AStored]);
end;

procedure TMainForm.RefreshView;
var
  Stored, Matching: Int64;
begin
  if FRepository = nil then
    Exit;
  FVisible := FRepository.Query(FFilter);
  ListViewEvents.Items.Count := Length(FVisible);
  ListViewEvents.Invalidate;

  Stored := FRepository.Count;
  { Counting twice would be counting the same rows twice when nothing is
    filtered out. }
  if FFilter.IsUnfiltered then
    Matching := Stored
  else
    Matching := FRepository.Count(FFilter);

  { Clearing an empty history is a question with one answer, so the button is
    not offered. This is the only place that decides, because it is the only
    place that knows the count. }
  ButtonClear.Enabled := Stored > 0;
  StatusBar.SimpleText := ViewSummary(Stored, Matching);
  FViewStale := False;
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

procedure TMainForm.ButtonClearClick(Sender: TObject);
var
  Stored: Int64;
begin
  { The button is disabled when the history is empty, so this only guards
    against a future path that mutates without refreshing. }
  Stored := FRepository.Count;
  if Stored = 0 then
    Exit;
  { Irreversible, so No is the default button rather than Yes. }
  if MessageDlg(Format(SConfirmClear, [Stored]), mtWarning, [mbYes, mbNo], 0,
    mbNo) <> mrYes then
    Exit;
  FRepository.DeleteAll;
  RefreshView;
end;

end.
