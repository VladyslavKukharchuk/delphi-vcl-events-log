unit EventsLog.GeneratorSession;

interface

uses
  EventsLog.Event, EventsLog.EventRepository, EventsLog.Generator;

type
  TGeneratorSession = class
  private
    FRepository: IEventRepository;
    FInterval: Cardinal;
    FGenerator: TEventGenerator;
    FStale: Boolean;
    FProblem: string;
    procedure EventArrived(const AEvent: TLogEvent);
  public
    constructor Create(const ARepository: IEventRepository;
      AInterval: Cardinal = DefaultInterval);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
    function TakeStale: Boolean;
    function TakeProblem(out AMessage: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

constructor TGeneratorSession.Create(const ARepository: IEventRepository;
  AInterval: Cardinal);
begin
  inherited Create;
  FRepository := ARepository;
  FInterval := AInterval;
end;

destructor TGeneratorSession.Destroy;
begin
  Stop;
  inherited;
end;

procedure TGeneratorSession.Start;
begin
  if FGenerator <> nil then
    Exit;
  { A problem belongs to the run that produced it. The window polls for one
    every 250 ms, so a stop inside that window leaves it unread, and carrying it
    into this run would report it against a healthy generator and stop it on its
    first tick. FStale is deliberately kept: it is a repaint still owed for an
    event that really was stored. }
  FProblem := '';
  FGenerator := TEventGenerator.Create(EventArrived, FInterval);
end;

procedure TGeneratorSession.Stop;
begin
  FreeAndNil(FGenerator);
end;

function TGeneratorSession.IsRunning: Boolean;
begin
  Result := FGenerator <> nil;
end;

procedure TGeneratorSession.EventArrived(const AEvent: TLogEvent);
begin
  try
    FRepository.Insert(AEvent);
    FStale := True;
  except
    on E: Exception do
      FProblem := E.Message;
  end;
end;

function TGeneratorSession.TakeStale: Boolean;
begin
  Result := FStale;
  FStale := False;
end;

function TGeneratorSession.TakeProblem(out AMessage: string): Boolean;
begin
  AMessage := FProblem;
  Result := FProblem <> '';
  FProblem := '';
  if Result then
    Stop;
end;

end.
