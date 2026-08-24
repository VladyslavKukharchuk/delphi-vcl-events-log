unit EventsLog.Actions;

interface

uses
  System.Classes, Vcl.Dialogs,
  EventsLog.Event, EventsLog.EventRepository, EventsLog.Json,
  EventsLog.GeneratorSession;

type
  { What the three buttons do. Each action that changed the stored history says
    so through OnDataChanged, and the form answers by refreshing the table: the
    actions never touch the table themselves, which is why they do not know it
    exists (ADR 0012).

    The import and clear dialogs live here rather than in the form, because the
    code that knows what happened is the code that has something to say about
    it. The generator's failure is the exception, and Poll says why. }
  TEventActions = class
  private
    FRepository: IEventRepository;
    FOpenDialog: TOpenDialog;
    FSession: TGeneratorSession;
    FOnDataChanged: TNotifyEvent;
    procedure ReportImport(const AFileName: string; const AReport: TImportReport);
    procedure DataChanged;
  public
    constructor Create(const ARepository: IEventRepository;
      AOpenDialog: TOpenDialog);
    destructor Destroy; override;
    procedure Import;
    procedure Clear;
    procedure ToggleGenerating;
    function IsGenerating: Boolean;
    { Called from the form's timer while generating. Returns True when the
      session has just been stopped by a failure, with AFailure holding the
      message for the user. The caller shows that message rather than this
      class, because it has to be shown after the timer is off: a modal dialog
      with the timer still running would be reached again from behind itself. }
    function Poll(out AFailure: string): Boolean;
    { The view has just been refreshed for somebody else's reason - an import, a
      clear, a change of filter - so a generated event waiting to be shown has
      been shown too, and the next tick has nothing left to do. }
    procedure ViewRefreshed;
    property OnDataChanged: TNotifyEvent read FOnDataChanged write FOnDataChanged;
  end;

implementation

uses
  System.SysUtils, System.UITypes;

resourcestring
  SImportedFrom = 'Imported %d events from %s.';
  SSkipped = '%d records were skipped. The first problem was: %s';
  SConfirmClear = 'Delete all %d stored events?' + sLineBreak +
    'This cannot be undone.';
  SGeneratorFailed = 'Generating was stopped, because the event could not be ' +
    'stored:' + sLineBreak + '%s';

constructor TEventActions.Create(const ARepository: IEventRepository;
  AOpenDialog: TOpenDialog);
begin
  inherited Create;
  FRepository := ARepository;
  FOpenDialog := AOpenDialog;
  FSession := TGeneratorSession.Create(ARepository);
end;

destructor TEventActions.Destroy;
begin
  { Freeing the session stops the generator, and that has to happen before the
    owner of the repository frees it: a queued event is stored on this thread
    and would otherwise reach a repository that is gone (ADR 0011). }
  FSession.Free;
  inherited;
end;

procedure TEventActions.DataChanged;
begin
  if Assigned(FOnDataChanged) then
    FOnDataChanged(Self);
end;

procedure TEventActions.Import;
var
  Events: TArray<TLogEvent>;
  Report: TImportReport;
begin
  if not FOpenDialog.Execute then
    Exit;
  try
    Events := LoadEventsFromFile(FOpenDialog.FileName, Report);
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
  DataChanged;
  ReportImport(FOpenDialog.FileName, Report);
end;

procedure TEventActions.ReportImport(const AFileName: string;
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

procedure TEventActions.Clear;
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
  DataChanged;
end;

procedure TEventActions.ToggleGenerating;
begin
  if not FSession.IsRunning then
  begin
    FSession.Start;
    Exit;
  end;
  FSession.Stop;
  { The timer stops with the session, so anything that arrived since its last
    tick would stay invisible until something else refreshed the window. }
  if FSession.TakeStale then
    DataChanged;
end;

procedure TEventActions.ViewRefreshed;
begin
  FSession.TakeStale;
end;

function TEventActions.IsGenerating: Boolean;
begin
  Result := FSession.IsRunning;
end;

function TEventActions.Poll(out AFailure: string): Boolean;
var
  Problem: string;
begin
  { Taking the problem also stops the session, so this cannot report twice. }
  Result := FSession.TakeProblem(Problem);
  if Result then
  begin
    AFailure := Format(SGeneratorFailed, [Problem]);
    Exit;
  end;
  if FSession.TakeStale then
    DataChanged;
end;

end.
