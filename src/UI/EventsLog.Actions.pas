unit EventsLog.Actions;

interface

uses
  System.Classes, Vcl.Dialogs,
  EventsLog.Event, EventsLog.EventRepository, EventsLog.Json,
  EventsLog.GeneratorSession;

type
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
    function Poll(out AFailure: string): Boolean;
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
  Stored := FRepository.Count;
  if Stored = 0 then
    Exit;
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
