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
  System.SysUtils, System.UITypes,
  EventsLog.ImportPreview;

resourcestring
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
  except
    on E: EEventImportError do
    begin
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;

  if not ConfirmImport(FOpenDialog.FileName, Report, Events) then
    Exit;
  FRepository.InsertMany(Events);
  DataChanged;
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
